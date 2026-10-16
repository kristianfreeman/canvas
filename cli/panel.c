/* Commands on open panels: update, move, hide, list and ping. */
#include "args.h"
#include "commands.h"
#include "conn.h"
#include "events.h"
#include "json.h"
#include "opts.h"
#include "stream.h"
#include "text.h"
#include "util.h"

#include <stddef.h>
#include <string.h>
#include <stdint.h>

static const char server_timeout[] = "timed out waiting for the server";

static void begin(Buf *req, const char *cmd) {
    buf_puts(req, "{\"cmd\":\"");
    buf_puts(req, cmd);
    buf_putc(req, '"');
}

/* list and ping take no arguments except --emit. */
static void only_emit(Args *a, const char *command) {
    for (const char *arg = args_next(a); arg != NULL; arg = args_next(a)) {
        if (strcmp(arg, "--emit") != 0) {
            usage_fail("%s takes no arguments except --emit, got %s", command, arg);
        }
        conn_emit_only();
    }
}

static int await_one(LineReader *r, double seconds) {
    Flow f = {.deadline = deadline_after(seconds), .timeout_msg = server_timeout, .hide_id = NULL};
    return flow_await(&f, r);
}

int cmd_update(Args *a) {
    static const Opt *const tables[] = {update_opts, NULL};
    Opts o;
    opts_init(&o);
    opts_parse(&o, a, tables, false);
    if (o.id == NULL) {
        usage_fail("update needs --id");
    }
    if (o.data != NULL && o.stream) {
        usage_fail("give --data or --stream, not both");
    }
    if (o.data == NULL && !o.stream) {
        usage_fail("update needs --data or --stream");
    }
    if (o.stream && conn_emitting()) {
        usage_fail("--emit can't carry --stream");
    }
    Buf req = {0};
    begin(&req, "update");
    opts_write(&o, &req);
    if (o.data != NULL) {
        json_key(&req, "data");
        load_json_arg(o.data, "--data", &req);
    }
    buf_puts(&req, "}\n");
    LineReader r;
    (void)conn_request(&r, &req, true);
    if (!o.stream) {
        return await_one(&r, 10);
    }
    Flow f = {.deadline = 0, .timeout_msg = server_timeout, .hide_id = NULL, .stream = true};
    return stream_run(&r, &f, true);
}

int cmd_move(Args *a) {
    static const Opt *const tables[] = {id_opts, placement_opts, NULL};
    Opts o;
    opts_init(&o);
    opts_parse(&o, a, tables, false);
    if (o.id == NULL) {
        usage_fail("move needs --id");
    }
    Buf req = {0};
    begin(&req, "move");
    opts_write(&o, &req);
    buf_puts(&req, "}\n");
    LineReader r;
    if (!conn_request(&r, &req, false)) {
        fail("the canvas server is not running");
    }
    return await_one(&r, 10);
}

int cmd_hide(Args *a) {
    static const Opt *const tables[] = {hide_opts, NULL};
    Opts o;
    opts_init(&o);
    opts_parse(&o, a, tables, false);
    if (o.all && o.id != NULL) {
        usage_fail("give --id or --all, not both");
    }
    if (!o.all && o.id == NULL) {
        opts_set_str(&o, "id", "default");
    }
    Buf req = {0};
    begin(&req, "hide");
    opts_write(&o, &req);
    buf_puts(&req, "}\n");
    LineReader r;
    if (!conn_request(&r, &req, false)) {
        return 0;
    }
    return await_one(&r, 5);
}

int cmd_list(Args *a) {
    only_emit(a, "list");
    Buf req = {0};
    begin(&req, "list");
    buf_puts(&req, "}\n");
    LineReader r;
    if (!conn_request(&r, &req, false)) {
        return 0;
    }
    uint64_t deadline = deadline_after(5);
    for (;;) {
        Span line;
        LrStatus st = lr_next(&r, deadline, &line);
        if (st == LR_EOF) {
            return 0;
        }
        if (st == LR_TIMEOUT) {
            fail("%s", server_timeout);
        }
        out_line(line);
    }
}

int cmd_ping(Args *a) {
    only_emit(a, "ping");
    Buf req = {0};
    begin(&req, "ping");
    buf_puts(&req, "}\n");
    LineReader r;
    if (!conn_request(&r, &req, false)) {
        return 1;
    }
    return await_one(&r, 2);
}
