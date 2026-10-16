#include "stream.h"

#include "conn.h"
#include "events.h"
#include "json.h"
#include "util.h"

#include <errno.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

typedef struct {
    LineReader *sock;
    LineReader in;
    Flow *flow;
    Buf msg;
    unsigned long lineno;
    bool wrap;
    bool shut;
} Stream;

static int socket_closed(const Stream *s) {
    if (!s->shut) {
        fail("lost the connection to the server");
    }
    return 0;
}

/* Handle the complete event lines already buffered. */
static int drain_socket(Stream *s) {
    Span line;
    while (lr_take(s->sock, &line)) {
        int code = span_blank(line) ? GO_ON : flow_event(s->flow, line);
        if (code != GO_ON) {
            return code;
        }
    }
    return s->sock->eof ? socket_closed(s) : GO_ON;
}

static bool forward(Stream *s, Span line) {
    s->lineno++;
    if (span_blank(line)) {
        return true;
    }
    s->msg.len = 0;
    if (s->wrap) {
        buf_puts(&s->msg, "{\"data\":");
    }
    if (!json_minify(line, &s->msg)) {
        warn("skipping line %lu of stdin: not valid JSON", s->lineno);
        return true;
    }
    buf_puts(&s->msg, s->wrap ? "}\n" : "\n");
    return write_all(s->sock->fd, s->msg.data, s->msg.len);
}

/* The server stopped reading, usually because the panel closed. Its last
   event says why. */
static int send_failed(Stream *s) {
    s->shut = true;
    s->flow->deadline = deadline_after(2);
    s->flow->hide_id = NULL;
    s->flow->timeout_msg = "lost the connection to the server";
    return flow_await(s->flow, s->sock);
}

static int read_stdin(Stream *s) {
    (void)lr_fill(&s->in);
    Span line;
    while (lr_take(&s->in, &line)) {
        if (!forward(s, line)) {
            return send_failed(s);
        }
    }
    if (s->in.eof) {
        (void)shutdown(s->sock->fd, SHUT_WR);
        s->shut = true;
    }
    return GO_ON;
}

static int stream_step(Stream *s) {
    struct pollfd p[2] = {
        {.fd = s->sock->fd, .events = POLLIN, .revents = 0},
        {.fd = STDIN_FILENO, .events = POLLIN, .revents = 0},
    };
    int n = poll(p, s->shut ? 1 : 2, poll_timeout(s->flow->deadline));
    if (n == 0) {
        return flow_timeout(s->flow);
    }
    if (n < 0) {
        return errno == EINTR ? GO_ON : socket_closed(s);
    }
    if (p[0].revents != 0) {
        (void)lr_fill(s->sock);
        int code = drain_socket(s);
        if (code != GO_ON) {
            return code;
        }
    }
    return !s->shut && p[1].revents != 0 ? read_stdin(s) : GO_ON;
}

int stream_run(LineReader *sock, Flow *f, bool wrap) {
    Stream s = {.sock = sock, .flow = f, .msg = {0}, .lineno = 0, .wrap = wrap, .shut = false};
    lr_init(&s.in, STDIN_FILENO);
    f->streaming = true;
    int code = drain_socket(&s);
    while (code == GO_ON) {
        code = stream_step(&s);
    }
    return code;
}
