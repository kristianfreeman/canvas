#include "args.h"
#include "commands.h"
#include "conn.h"
#include "events.h"
#include "json.h"
#include "util.h"

#include <string.h>

static void emit(Span channel, Span value, bool multi) {
    static Buf line;
    if (!multi) {
        out_line(value);
        return;
    }
    line.len = 0;
    buf_puts(&line, "{\"channel\":");
    buf_putspan(&line, channel);
    buf_puts(&line, ",\"value\":");
    buf_putspan(&line, value);
    buf_putc(&line, '}');
    out_line(buf_span(&line));
}

static Span channel_of(Span event) {
    Span channel;
    return json_member(event, "channel", &channel) ? channel : span_of("\"\"");
}

static void print_message(Span event, bool multi) {
    Span value;
    if (json_member(event, "value", &value)) {
        emit(channel_of(event), value, multi);
    }
}

static void print_history(Span event, bool multi) {
    Span values;
    Span value;
    JIter it;
    if (!json_member(event, "values", &values) || !jiter_begin(&it, values, '[')) {
        return;
    }
    Span channel = channel_of(event);
    while (jiter_element(&it, &value) == 1) {
        emit(channel, value, multi);
    }
}

static int sub_event(Span event, bool multi) {
    Span name;
    if (!json_string_member(event, "event", &name)) {
        fail("bad response from the server");
    }
    if (span_eq(name, "message")) {
        print_message(event, multi);
    } else if (span_eq(name, "history")) {
        print_history(event, multi);
    } else if (span_eq(name, "error")) {
        print_error_event(event);
        return 1;
    }
    return GO_ON;
}

static int sub_loop(LineReader *r, bool multi) {
    Span line;
    while (lr_next(r, 0, &line) == LR_LINE) {
        int code = span_blank(line) ? GO_ON : sub_event(line, multi);
        if (code != GO_ON) {
            return code;
        }
    }
    return 0;
}

static void add_channel(Buf *channels, const char *name, int *count) {
    if (!channel_valid(name)) {
        usage_fail("bad channel name '%s': use dot-separated [a-z0-9_-] segments", name);
    }
    if (*count > 0) {
        buf_putc(channels, ',');
    }
    json_cstr(channels, name);
    (*count)++;
}

int cmd_sub(Args *a) {
    Buf channels = {0};
    int count = 0;
    bool history = false;
    for (const char *arg = args_next(a); arg != NULL; arg = args_next(a)) {
        if (strcmp(arg, "--history") == 0) {
            history = true;
        } else if (args_is_flag(arg)) {
            usage_fail("unknown option: %s", arg);
        } else {
            add_channel(&channels, arg, &count);
        }
    }
    if (count == 0) {
        usage_fail("sub needs at least one CHANNEL");
    }
    Buf req = {0};
    buf_puts(&req, "{\"cmd\":\"sub\",\"channels\":[");
    buf_putspan(&req, buf_span(&channels));
    buf_puts(&req, history ? "],\"history\":true}\n" : "],\"history\":false}\n");
    LineReader r;
    if (!conn_request(&r, &req, false)) {
        fail("the canvas server is not running");
    }
    return sub_loop(&r, count > 1);
}
