#include "args.h"
#include "commands.h"
#include "conn.h"
#include "events.h"
#include "json.h"
#include "stream.h"
#include "text.h"
#include "util.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const char *channel;
    const char *value;
    char **cmd;
    uint64_t every_ns;
    unsigned long keep;
    bool has_keep;
    bool merge;
    bool persist;
    bool clear;
    bool has_every;
} Pub;

static bool channel_char(char c) {
    return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-';
}

/* A dot may only end a non-empty segment. */
static bool fits_channel(char c, bool segment_empty) {
    if (c == '.') {
        return !segment_empty;
    }
    return channel_char(c);
}

bool channel_valid(const char *name) {
    bool segment_empty = true;
    for (const char *p = name; *p != '\0'; p++) {
        if (!fits_channel(*p, segment_empty)) {
            return false;
        }
        segment_empty = *p == '.';
    }
    return !segment_empty;
}

static unsigned long keep_value(const char *text) {
    size_t n = strlen(text);
    if (n == 0 || n > 9 || strspn(text, "0123456789") != n) {
        usage_fail("--keep needs a whole number >= 0, got '%s'", text);
    }
    return strtoul(text, NULL, 10);
}

static void pub_flag(Pub *p, Args *a, const char *arg) {
    if (strcmp(arg, "--merge") == 0) {
        p->merge = true;
    } else if (strcmp(arg, "--persist") == 0) {
        p->persist = true;
    } else if (strcmp(arg, "--clear") == 0) {
        p->clear = true;
    } else if (strcmp(arg, "--emit") == 0) {
        conn_emit_only();
    } else if (strcmp(arg, "--keep") == 0) {
        p->keep = keep_value(args_value(a, arg));
        p->has_keep = true;
    } else if (strcmp(arg, "--every") == 0) {
        p->every_ns = parse_duration(args_value(a, arg));
        p->has_every = true;
    } else {
        usage_fail("unknown option: %s", arg);
    }
}

static void pub_positional(Pub *p, const char *arg) {
    if (p->channel == NULL) {
        p->channel = arg;
    } else if (p->value == NULL) {
        p->value = arg;
    } else {
        usage_fail("unexpected argument: %s", arg);
    }
}

static void parse_pub(Pub *p, Args *a) {
    for (const char *arg = args_next(a); arg != NULL; arg = args_next(a)) {
        if (strcmp(arg, "--") == 0) {
            p->cmd = a->argv + a->i;
            a->i = a->argc;
        } else if (args_is_flag(arg)) {
            pub_flag(p, a, arg);
        } else {
            pub_positional(p, arg);
        }
    }
}

static void check_channel(const char *channel) {
    if (channel == NULL) {
        usage_fail("pub needs a CHANNEL");
    }
    if (!channel_valid(channel)) {
        usage_fail("bad channel name '%s': use dot-separated [a-z0-9_-] segments", channel);
    }
    if (strncmp(channel, "canvas.", 7) == 0) {
        usage_fail("channels starting with canvas. are reserved");
    }
}

static void check_clear(const Pub *p) {
    if (p->value != NULL || p->has_every || p->cmd != NULL || p->merge || p->persist || p->has_keep) {
        usage_fail("--clear takes only a CHANNEL");
    }
}

static void check_pub(const Pub *p) {
    check_channel(p->channel);
    if (p->clear) {
        check_clear(p);
        return;
    }
    if (!p->has_every && p->cmd != NULL) {
        usage_fail("a command after -- needs --every");
    }
    if (p->has_every && p->value != NULL) {
        usage_fail("give a VALUE or --every, not both");
    }
    if (!p->has_every && p->value == NULL) {
        usage_fail("pub needs a VALUE, - or --every DUR -- CMD");
    }
    if (p->has_every && (p->cmd == NULL || p->cmd[0] == NULL)) {
        usage_fail("--every needs a command after --");
    }
}

static bool streams(const Pub *p) { return p->has_every || (p->value != NULL && strcmp(p->value, "-") == 0); }

static void pub_header(const Pub *p, Buf *req) {
    buf_puts(req, "{\"cmd\":\"pub\"");
    json_key(req, "channel");
    json_cstr(req, p->channel);
    if (p->merge || p->clear) {
        json_key(req, "op");
        buf_puts(req, p->clear ? "\"clear\"" : "\"merge\"");
    }
    if (p->persist) {
        json_key(req, "persist");
        buf_puts(req, "true");
    }
    if (p->has_keep) {
        char num[24];
        (void)snprintf(num, sizeof num, "%lu", p->keep);
        json_key(req, "keep");
        buf_puts(req, num);
    }
}

static int pub_once(Buf *req, const char *value) {
    if (value != NULL) {
        json_key(req, "value");
        load_json_arg(value, "VALUE", req);
    }
    buf_puts(req, "}\n");
    LineReader r;
    (void)conn_request(&r, req, true);
    Flow f = {.deadline = deadline_after(10), .timeout_msg = "timed out waiting for the server", .hide_id = NULL};
    return flow_await(&f, &r);
}

static int pub_stream(Buf *req) {
    json_key(req, "stream");
    buf_puts(req, "true}\n");
    LineReader r;
    (void)conn_request(&r, req, true);
    Flow f = {.deadline = 0, .timeout_msg = "timed out waiting for the server", .hide_id = NULL, .stream = true};
    return stream_run(&r, &f, false);
}

int cmd_pub(Args *a) {
    Pub p;
    memset(&p, 0, sizeof p);
    parse_pub(&p, a);
    check_pub(&p);
    if (conn_emitting() && streams(&p)) {
        usage_fail("--emit works only with a single VALUE");
    }
    Buf req = {0};
    pub_header(&p, &req);
    if (p.has_every) {
        return pub_every(&req, p.cmd, p.every_ns);
    }
    if (streams(&p)) {
        return pub_stream(&req);
    }
    return pub_once(&req, p.value);
}
