#include "events.h"

#include "conn.h"
#include "json.h"
#include "trace.h"
#include "util.h"

#include <stddef.h>
#include <unistd.h>

typedef enum { EV_OTHER, EV_RENDERED, EV_ERROR, EV_RESULT, EV_MOVED, EV_CLOSED, EV_DONE } EventKind;

static EventKind event_kind(Span name) {
    static const struct {
        const char *name;
        EventKind kind;
    } kinds[] = {
        {"rendered", EV_RENDERED}, {"error", EV_ERROR},   {"result", EV_RESULT}, {"moved", EV_MOVED},
        {"closed", EV_CLOSED},     {"replaced", EV_CLOSED}, {"hidden", EV_DONE},   {"updated", EV_DONE},
        {"ok", EV_DONE},           {"pong", EV_DONE},
    };
    for (size_t i = 0; i < sizeof kinds / sizeof kinds[0]; i++) {
        if (span_eq(name, kinds[i].name)) {
            return kinds[i].kind;
        }
    }
    return EV_OTHER;
}

void print_error_event(Span line) {
    Span message;
    Buf text = {0};
    buf_reserve(&text, 0);
    if (!json_member(line, "message", &message) || !json_decode_string(message, &text)) {
        text.len = 0;
        buf_puts(&text, "the server reported an error");
    }
    warn("%s", text.data);
    buf_free(&text);
}

static void print_member(Span line, const char *key) {
    Span value;
    if (!json_member(line, key, &value)) {
        value = span_of("null");
    }
    out_line(value);
}

static int rendered_outcome(const Flow *f) {
    if (f->streaming || (f->wait && !f->stream)) {
        return GO_ON;
    }
    return f->stream ? START_STREAM : 0;
}

int flow_event(Flow *f, Span line) {
    Span name;
    if (!json_string_member(line, "event", &name)) {
        fail("bad response from the server: %.*s", line.len > 200 ? 200 : (int)line.len, line.ptr);
    }
    if (f->trace && !f->traced) {
        f->traced = true;
        trace_report(line);
    }
    switch (event_kind(name)) {
    case EV_RENDERED: return rendered_outcome(f);
    case EV_ERROR: print_error_event(line); return 1;
    case EV_RESULT: print_member(line, "value"); return 0;
    case EV_MOVED: print_member(line, "frame"); return 0;
    case EV_CLOSED: return 2;
    case EV_DONE: return 0;
    default: return GO_ON;
    }
}

static void hide_panel(const char *id) {
    int fd = conn_open(false);
    if (fd < 0) {
        return;
    }
    Buf req = {0};
    buf_puts(&req, "{\"cmd\":\"hide\"");
    json_key(&req, "id");
    json_cstr(&req, id);
    buf_puts(&req, "}\n");
    if (write_all(fd, req.data, req.len)) {
        LineReader r;
        Span line;
        lr_init(&r, fd);
        (void)lr_next(&r, deadline_after(2), &line);
    }
    (void)close(fd);
    buf_free(&req);
}

int flow_timeout(const Flow *f) {
    if (f->hide_id == NULL) {
        fail("%s", f->timeout_msg);
    }
    hide_panel(f->hide_id);
    return 3;
}

int flow_await(Flow *f, LineReader *r) {
    for (;;) {
        Span line;
        LrStatus st = lr_next(r, f->deadline, &line);
        if (st == LR_TIMEOUT) {
            return flow_timeout(f);
        }
        if (st == LR_EOF) {
            fail("lost the connection to the server");
        }
        int code = span_blank(line) ? GO_ON : flow_event(f, line);
        if (code != GO_ON) {
            return code;
        }
    }
}
