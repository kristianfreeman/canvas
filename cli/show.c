#include "args.h"
#include "commands.h"
#include "conn.h"
#include "events.h"
#include "json.h"
#include "opts.h"
#include "stream.h"
#include "text.h"
#include "utf8.h"
#include "util.h"

#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

static bool source_is_stdin(const Opts *o) { return o->file == NULL || strcmp(o->file, "-") == 0; }

static bool data_is_stdin(const Opts *o) { return o->data != NULL && strcmp(o->data, "-") == 0; }

static void check_show(const Opts *o) {
    if (o->file == NULL && isatty(STDIN_FILENO) != 0) {
        usage_fail("give a FILE, or pipe the source to stdin");
    }
    if (o->stream && source_is_stdin(o)) {
        usage_fail("--stream needs a FILE, since it reads data from stdin");
    }
    if (data_is_stdin(o) && (source_is_stdin(o) || o->stream)) {
        usage_fail("--data - needs stdin, which is already taken");
    }
    if (o->has_timeout && !o->wait) {
        usage_fail("--timeout needs --wait");
    }
}

static void check_emit(const Opts *o) {
    if (conn_emitting() && (o->stream || o->has_timeout)) {
        usage_fail("--emit can't carry --stream or --timeout, which work in the CLI");
    }
}

static const char *base_name(const char *path) {
    const char *slash = strrchr(path, '/');
    return slash != NULL ? slash + 1 : path;
}

static const char *ext_kind(const char *path) {
    static const char *const tsx_exts[] = {".tsx", ".jsx", ".ts"};
    const char *dot = strrchr(base_name(path), '.');
    for (size_t i = 0; dot != NULL && i < sizeof tsx_exts / sizeof tsx_exts[0]; i++) {
        if (strcasecmp(dot, tsx_exts[i]) == 0) {
            return "tsx";
        }
    }
    return "markdown";
}

static const char *source_kind(const Opts *o, Span text) {
    static const char marker[] = "export default";
    if (o->kind != NULL) {
        return o->kind;
    }
    if (!source_is_stdin(o)) {
        return ext_kind(o->file);
    }
    return memmem(text.ptr, text.len, marker, sizeof marker - 1) != NULL ? "tsx" : "markdown";
}

static void add_path(const Opts *o, Buf *req) {
    char abs[PATH_MAX];
    if (realpath(o->file, abs) == NULL) {
        fail("cannot read %s: %s", o->file, strerror(errno));
    }
    json_key(req, "path");
    json_cstr(req, abs);
    if (!opts_has(o, "title")) {
        json_key(req, "title");
        json_cstr(req, base_name(o->file));
    }
}

static void add_source(const Opts *o, Buf *req) {
    bool from_stdin = source_is_stdin(o);
    const char *label = from_stdin ? "stdin" : o->file;
    Span text = from_stdin ? text_read_stdin() : text_read_file(o->file);
    if (!utf8_valid(text.ptr, text.len)) {
        fail("cannot read %s as UTF-8", label);
    }
    json_key(req, "source");
    json_str(req, text.ptr, text.len);
    json_key(req, "kind");
    json_cstr(req, source_kind(o, text));
    if (!from_stdin) {
        add_path(o, req);
    }
}

static bool focus_value(const Opts *o, const char *cmd) {
    if (o->focus >= 0) {
        return o->focus == 1;
    }
    return o->wait || strcmp(cmd, "toggle") == 0;
}

static void build_show(const Opts *o, const char *cmd, Buf *req) {
    buf_puts(req, "{\"cmd\":\"");
    buf_puts(req, cmd);
    buf_putc(req, '"');
    add_source(o, req);
    if (o->data != NULL) {
        json_key(req, "data");
        load_json_arg(o->data, "--data", req);
    }
    json_key(req, "focus");
    buf_puts(req, focus_value(o, cmd) ? "true" : "false");
    opts_write(o, req);
    buf_puts(req, "}\n");
}

static Flow show_flow(const Opts *o) {
    Flow f = {.deadline = 0, .timeout_msg = "timed out waiting for render", .hide_id = NULL};
    f.wait = o->wait;
    f.stream = o->stream;
    f.trace = o->trace;
    if (!o->wait) {
        f.deadline = deadline_after(10);
    } else if (o->has_timeout) {
        f.deadline = deadline_after(o->timeout);
        f.hide_id = o->id != NULL ? o->id : "default";
    }
    return f;
}

static int show_like(const char *cmd, Args *a) {
    static const Opt *const tables[] = {content_opts, placement_opts, NULL};
    Opts o;
    opts_init(&o);
    opts_parse(&o, a, tables, true);
    check_show(&o);
    check_emit(&o);
    Buf req = {0};
    build_show(&o, cmd, &req);
    LineReader r;
    (void)conn_request(&r, &req, true);
    buf_free(&req);
    Flow f = show_flow(&o);
    int code = flow_await(&f, &r);
    if (code != START_STREAM) {
        return code;
    }
    if (!o.wait) {
        f.deadline = 0;
    }
    return stream_run(&r, &f, true);
}

int cmd_show(Args *a) { return show_like("show", a); }

static bool asks_all(const Args *a) {
    for (int i = a->i; i < a->argc; i++) {
        if (strcmp(a->argv[i], "--all") == 0) {
            return true;
        }
    }
    return false;
}

int cmd_toggle(Args *a) { return asks_all(a) ? toggle_all(a) : show_like("toggle", a); }
