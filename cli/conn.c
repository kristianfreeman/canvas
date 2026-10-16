#include "conn.h"

#include "autostart.h"
#include "trace.h"
#include "util.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <stdint.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

enum { READ_CHUNK = 65536 };

void lr_init(LineReader *r, int fd) { *r = (LineReader){.fd = fd, .buf = {0}, .pos = 0, .eof = false}; }

static void lr_compact(LineReader *r) {
    if (r->pos == 0) {
        return;
    }
    size_t rest = r->buf.len - r->pos;
    memmove(r->buf.data, r->buf.data + r->pos, rest);
    r->buf.len = rest;
    r->pos = 0;
}

bool lr_fill(LineReader *r) {
    lr_compact(r);
    buf_reserve(&r->buf, READ_CHUNK);
    for (;;) {
        ssize_t n = read(r->fd, r->buf.data + r->buf.len, READ_CHUNK);
        if (n > 0) {
            r->buf.len += (size_t)n;
            r->buf.data[r->buf.len] = '\0';
            return true;
        }
        if (n == 0 || errno != EINTR) {
            r->eof = true;
            return false;
        }
    }
}

bool lr_take(LineReader *r, Span *line) {
    size_t avail = r->buf.len - r->pos;
    if (avail == 0) {
        return false;
    }
    const char *start = r->buf.data + r->pos;
    const char *newline = memchr(start, '\n', avail);
    if (newline == NULL) {
        if (!r->eof) {
            return false;
        }
        *line = (Span){start, avail};
        r->pos = r->buf.len;
        return true;
    }
    *line = (Span){start, (size_t)(newline - start)};
    r->pos += line->len + 1;
    return true;
}

uint64_t deadline_after(double seconds) { return clock_ns() + (uint64_t)(seconds * 1e9); }

int poll_timeout(uint64_t deadline) {
    if (deadline == 0) {
        return -1;
    }
    uint64_t now = clock_ns();
    if (now >= deadline) {
        return 0;
    }
    uint64_t ms = (deadline - now + 999999) / 1000000;
    return ms > INT_MAX ? INT_MAX : (int)ms;
}

/* False once the deadline passes. Poll errors other than EINTR return
   true so the following read reports them. */
static bool wait_readable(int fd, uint64_t deadline) {
    for (;;) {
        struct pollfd p = {.fd = fd, .events = POLLIN, .revents = 0};
        int n = poll(&p, 1, poll_timeout(deadline));
        if (n > 0 || (n < 0 && errno != EINTR)) {
            return true;
        }
        if (n == 0 && poll_timeout(deadline) == 0) {
            return false;
        }
    }
}

LrStatus lr_next(LineReader *r, uint64_t deadline, Span *line) {
    while (!lr_take(r, line)) {
        if (r->eof) {
            return LR_EOF;
        }
        if (!wait_readable(r->fd, deadline)) {
            return LR_TIMEOUT;
        }
        (void)lr_fill(r);
    }
    return LR_LINE;
}

static void home_dir(char *out, size_t cap) {
    const char *home = getenv("CANVAS_HOME");
    if (home != NULL && home[0] != '\0') {
        (void)snprintf(out, cap, "%s", home);
        return;
    }
    const char *user = getenv("HOME");
    if (user == NULL || user[0] == '\0') {
        const struct passwd *entry = getpwuid(getuid());
        user = entry != NULL ? entry->pw_dir : "/";
    }
    (void)snprintf(out, cap, "%s/Library/Application Support/Canvas", user);
}

static void socket_addr(struct sockaddr_un *addr) {
    char dir[PATH_MAX];
    home_dir(dir, sizeof dir);
    *addr = (struct sockaddr_un){.sun_family = AF_UNIX};
    int n = snprintf(addr->sun_path, sizeof addr->sun_path, "%s/canvas.sock", dir);
    if (n < 0 || (size_t)n >= sizeof addr->sun_path) {
        fail("socket path is too long: %s/canvas.sock", dir);
    }
}

/* A connected socket, or -errno. */
static int try_connect(const struct sockaddr_un *addr) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        fail("cannot create a socket: %s", strerror(errno));
    }
    (void)fcntl(fd, F_SETFD, FD_CLOEXEC);
    int one = 1;
    (void)setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
    if (connect(fd, (const struct sockaddr *)addr, sizeof *addr) == 0) {
        return fd;
    }
    int err = errno;
    (void)close(fd);
    return -err;
}

static void sleep_ms(long ms) {
    struct timespec ts = {.tv_sec = 0, .tv_nsec = ms * 1000000L};
    (void)nanosleep(&ts, NULL);
}

static int await_server(const struct sockaddr_un *addr, pid_t pid) {
    uint64_t deadline = deadline_after(5);
    while (clock_ns() < deadline) {
        sleep_ms(20);
        int fd = try_connect(addr);
        if (fd >= 0) {
            return fd;
        }
        server_check(&pid);
    }
    fail("the canvas server did not start within 5 s (socket %s)", addr->sun_path);
}

int conn_open(bool autostart) {
    struct sockaddr_un addr;
    socket_addr(&addr);
    int fd = try_connect(&addr);
    if (fd >= 0 || !autostart) {
        return fd >= 0 ? fd : -1;
    }
    if (fd != -ENOENT && fd != -ECONNREFUSED) {
        fail("cannot connect to %s: %s", addr.sun_path, strerror(-fd));
    }
    return await_server(&addr, server_start());
}

static bool emit_only;

void conn_emit_only(void) { emit_only = true; }

bool conn_emitting(void) { return emit_only; }

bool conn_request(LineReader *r, const Buf *req, bool autostart) {
    if (emit_only) {
        exit(write_all(STDOUT_FILENO, req->data, req->len) ? 0 : 1);
    }
    int fd = conn_open(autostart);
    if (fd < 0) {
        return false;
    }
    if (!write_all(fd, req->data, req->len)) {
        fail("lost the connection to the server: %s", strerror(errno));
    }
    trace_sent();
    lr_init(r, fd);
    return true;
}
