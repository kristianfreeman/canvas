/* `canvas pub CHANNEL --every DUR -- CMD ARGS...` */
#include "commands.h"
#include "conn.h"
#include "events.h"
#include "json.h"
#include "opts.h"
#include "proc.h"
#include "trace.h"
#include "util.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static volatile sig_atomic_t stopping;

static void on_stop(int sig) {
    (void)sig;
    stopping = 1;
}

static double unit_scale(const char *unit) {
    if (strcmp(unit, "ms") == 0) {
        return 1e6;
    }
    if (strcmp(unit, "s") == 0) {
        return 1e9;
    }
    return strcmp(unit, "m") == 0 ? 60e9 : 0;
}

uint64_t parse_duration(const char *text) {
    size_t n = strspn(text, "0123456789.");
    double scale = unit_scale(text + n);
    char num[32];
    double value = 0;
    if (n > 0 && n < sizeof num && scale > 0) {
        memcpy(num, text, n);
        num[n] = '\0';
        if (parse_number(num, &value) && value * scale >= 1e6 && value * scale <= 1e15) {
            return (uint64_t)(value * scale);
        }
    }
    usage_fail("--every needs a duration like 500ms, 1s or 2.5m (at least 1ms), got '%s'", text);
}

static void install_handlers(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_stop;
    (void)sigemptyset(&sa.sa_mask);
    (void)sigaction(SIGINT, &sa, NULL);
    (void)sigaction(SIGTERM, &sa, NULL);
}

static void read_child(int fd, pid_t pid, Buf *raw) {
    enum { CHUNK = 16384 };
    raw->len = 0;
    for (;;) {
        buf_reserve(raw, CHUNK);
        ssize_t n = read(fd, raw->data + raw->len, CHUNK);
        if (n > 0) {
            raw->len += (size_t)n;
            continue;
        }
        if (n == 0 || errno != EINTR) {
            return;
        }
        if (stopping != 0) {
            (void)kill(pid, SIGTERM);
        }
    }
}

/* Run cmd with stdout captured into raw; returns its exit status. */
static int capture(char **cmd, Buf *raw) {
    int fds[2];
    if (pipe(fds) != 0) {
        fail("cannot create a pipe: %s", strerror(errno));
    }
    (void)fcntl(fds[0], F_SETFD, FD_CLOEXEC);
    (void)fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    SpawnOpts opts = {.stdout_fd = fds[1], .detach = false, .search = true};
    pid_t pid = proc_spawn(cmd, &opts);
    int err = errno;
    (void)close(fds[1]);
    if (pid < 0) {
        fail("cannot run %s: %s", cmd[0], strerror(err));
    }
    read_child(fds[0], pid, raw);
    (void)close(fds[0]);
    return proc_wait(pid);
}

/* One run's output, minified into out. False if the run is skipped. */
static bool run_once(char **cmd, Buf *out) {
    static Buf raw;
    int status = capture(cmd, &raw);
    if (stopping != 0) {
        return false;
    }
    if (status != 0) {
        warn("%s exited with status %d; skipping this run", cmd[0], status);
        return false;
    }
    if (!json_minify(buf_span(&raw), out)) {
        warn("%s printed invalid JSON; skipping this run", cmd[0]);
        return false;
    }
    return true;
}

static int publish(char **cmd, LineReader *r, Flow *f, Buf *out) {
    out->len = 0;
    if (!run_once(cmd, out)) {
        return GO_ON;
    }
    buf_putc(out, '\n');
    if (write_all(r->fd, out->data, out->len)) {
        return GO_ON;
    }
    f->deadline = deadline_after(2);
    f->timeout_msg = "lost the connection to the server";
    return flow_await(f, r);
}

static int read_events(LineReader *r, Flow *f) {
    (void)lr_fill(r);
    Span line;
    while (lr_take(r, &line)) {
        int code = span_blank(line) ? GO_ON : flow_event(f, line);
        if (code != GO_ON) {
            return code;
        }
    }
    if (r->eof) {
        fail("lost the connection to the server");
    }
    return GO_ON;
}

/* Sleep until next while watching the connection for an error. */
static int wait_until(LineReader *r, Flow *f, uint64_t next) {
    while (stopping == 0) {
        struct pollfd p = {.fd = r->fd, .events = POLLIN, .revents = 0};
        int n = poll(&p, 1, poll_timeout(next));
        if (n == 0) {
            return GO_ON;
        }
        int code = n > 0 ? read_events(r, f) : GO_ON;
        if (code != GO_ON) {
            return code;
        }
    }
    return GO_ON;
}

/* Ctrl-C: end the stream so the server takes the last value, then exit 0. */
static int finish(LineReader *r, Flow *f) {
    (void)shutdown(r->fd, SHUT_WR);
    uint64_t deadline = deadline_after(1);
    Span line;
    while (lr_next(r, deadline, &line) == LR_LINE) {
        if (!span_blank(line) && flow_event(f, line) != GO_ON) {
            break;
        }
    }
    return 0;
}

int pub_every(Buf *req, char **cmd, uint64_t period_ns) {
    install_handlers();
    json_key(req, "stream");
    buf_puts(req, "true}\n");
    LineReader r;
    (void)conn_request(&r, req, true);
    Flow f = {.deadline = 0, .timeout_msg = "lost the connection to the server", .hide_id = NULL};
    f.stream = true;
    f.streaming = true;
    Buf out = {0};
    while (stopping == 0) {
        uint64_t next = clock_ns() + period_ns;
        int code = publish(cmd, &r, &f, &out);
        if (code == GO_ON) {
            code = wait_until(&r, &f, next);
        }
        if (code != GO_ON) {
            return code;
        }
    }
    return finish(&r, &f);
}
