#include "opts.h"

#include "args.h"
#include "conn.h"
#include "json.h"
#include "util.h"

#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- members ---- */

void opts_init(Opts *o) {
    memset(o, 0, sizeof *o);
    o->focus = -1;
}

void opts_set(Opts *o, const char *key, char *json) {
    for (int i = 0; i < o->nmembers; i++) {
        if (strcmp(o->members[i].key, key) == 0) {
            free(o->members[i].json);
            o->members[i].json = json;
            return;
        }
    }
    if (o->nmembers == MAX_MEMBERS) {
        usage_fail("too many options");
    }
    o->members[o->nmembers++] = (Member){key, json};
}

static void opts_set_buf(Opts *o, const char *key, Buf *b) {
    buf_reserve(b, 0);
    opts_set(o, key, b->data);
}

static void opts_set_raw(Opts *o, const char *key, const char *json) {
    Buf b = {0};
    buf_puts(&b, json);
    opts_set_buf(o, key, &b);
}

void opts_set_str(Opts *o, const char *key, const char *value) {
    Buf b = {0};
    json_cstr(&b, value);
    opts_set_buf(o, key, &b);
}

bool opts_has(const Opts *o, const char *key) {
    for (int i = 0; i < o->nmembers; i++) {
        if (strcmp(o->members[i].key, key) == 0) {
            return true;
        }
    }
    return false;
}

void opts_write(const Opts *o, Buf *b) {
    for (int i = 0; i < o->nmembers; i++) {
        json_key(b, o->members[i].key);
        buf_puts(b, o->members[i].json);
    }
}

/* ---- numbers ---- */

bool parse_number(const char *s, double *out) {
    if (s[0] == '\0' || strspn(s, "0123456789.eE+-") != strlen(s)) {
        return false;
    }
    char *end = NULL;
    errno = 0;
    double v = strtod(s, &end);
    if (*end != '\0' || errno != 0 || !isfinite(v)) {
        return false;
    }
    *out = v;
    return true;
}

static void format_fraction(double v, Buf *b) {
    char text[32] = "0";
    for (int precision = 1; precision <= 17; precision++) {
        (void)snprintf(text, sizeof text, "%.*g", precision, v);
        if (strtod(text, NULL) == v) {
            break;
        }
    }
    buf_puts(b, text);
}

void format_number(double v, Buf *b) {
    /* JSON parsers read "-0" as the integer 0; "-0.0" keeps the sign, which
       --at needs for flush right or bottom. */
    if (v == 0 && signbit(v)) {
        buf_puts(b, "-0.0");
        return;
    }
    if (fabs(v) >= 1e15 || v != floor(v)) {
        format_fraction(v, b);
        return;
    }
    char text[32] = "0";
    (void)snprintf(text, sizeof text, "%.0f", v);
    buf_puts(b, text);
}

static bool in_range(Range range, double v) {
    switch (range) {
    case RANGE_POSITIVE: return v > 0;
    case RANGE_NONNEG: return v >= 0;
    case RANGE_UNIT: return v >= 0 && v <= 1;
    default: return true;
    }
}

static const char *range_text(Range range) {
    switch (range) {
    case RANGE_POSITIVE: return "a positive number";
    case RANGE_NONNEG: return "a number >= 0";
    case RANGE_UNIT: return "a number from 0 to 1";
    default: return "a number";
    }
}

static double number_value(const Opt *spec, const char *text) {
    double v = 0;
    if (!parse_number(text, &v) || !in_range(spec->range, v)) {
        usage_fail("%s needs %s, got '%s'", spec->flag, range_text(spec->range), text);
    }
    return v;
}

/* A number, or with percent_ok "N%", which becomes the string "N%". */
static void put_measure(Buf *b, const Opt *spec, const char *text, bool percent_ok) {
    size_t n = strlen(text);
    if (!percent_ok || n == 0 || text[n - 1] != '%') {
        format_number(number_value(spec, text), b);
        return;
    }
    char num[64];
    if (n >= sizeof num) {
        usage_fail("%s value is too long: %s", spec->flag, text);
    }
    memcpy(num, text, n - 1);
    num[n - 1] = '\0';
    buf_putc(b, '"');
    format_number(number_value(spec, num), b);
    buf_puts(b, "%\"");
}

/* ---- generic appliers ---- */

static void apply_str(Opts *o, const Opt *spec, const char *value) { opts_set_str(o, spec->key, value); }

static bool choice_ok(const char *choices, const char *value) {
    size_t n = strlen(value);
    const char *p = choices;
    for (;;) {
        if (strncmp(p, value, n) == 0 && (p[n] == '|' || p[n] == '\0')) {
            return true;
        }
        p = strchr(p, '|');
        if (p == NULL) {
            return false;
        }
        p++;
    }
}

static void apply_enum(Opts *o, const Opt *spec, const char *value) {
    if (value[0] == '\0' || !choice_ok(spec->choices, value)) {
        usage_fail("%s must be one of %s, got '%s'", spec->flag, spec->choices, value);
    }
    opts_set_str(o, spec->key, value);
}

static void apply_number(Opts *o, const Opt *spec, const char *value) {
    Buf b = {0};
    put_measure(&b, spec, value, false);
    opts_set_buf(o, spec->key, &b);
}

static void apply_measure(Opts *o, const Opt *spec, const char *value) {
    Buf b = {0};
    put_measure(&b, spec, value, true);
    opts_set_buf(o, spec->key, &b);
}

static void apply_at(Opts *o, const Opt *spec, const char *value) {
    const char *comma = strchr(value, ',');
    char left[64];
    size_t n = comma != NULL ? (size_t)(comma - value) : 0;
    if (comma == NULL || strchr(comma + 1, ',') != NULL || n >= sizeof left) {
        usage_fail("--at needs X,Y, got '%s'", value);
    }
    memcpy(left, value, n);
    left[n] = '\0';
    Buf b = {0};
    buf_puts(&b, "{\"x\":");
    put_measure(&b, spec, left, true);
    buf_puts(&b, ",\"y\":");
    put_measure(&b, spec, comma + 1, true);
    buf_putc(&b, '}');
    opts_set_buf(o, spec->key, &b);
}

static void apply_true(Opts *o, const Opt *spec, const char *value) {
    (void)value;
    opts_set_raw(o, spec->key, "true");
}

static void apply_false(Opts *o, const Opt *spec, const char *value) {
    (void)value;
    opts_set_raw(o, spec->key, "false");
}

/* ---- options with client-side effects ---- */

static void apply_id(Opts *o, const Opt *spec, const char *value) {
    o->id = value;
    opts_set_str(o, spec->key, value);
}

static void apply_kind(Opts *o, const Opt *spec, const char *value) {
    (void)spec;
    if (strcmp(value, "md") == 0 || strcmp(value, "markdown") == 0) {
        o->kind = "markdown";
    } else if (strcmp(value, "tsx") == 0 || strcmp(value, "jsx") == 0) {
        o->kind = "tsx";
    } else {
        usage_fail("--kind must be one of md, markdown, tsx, jsx, got '%s'", value);
    }
}

static void apply_data(Opts *o, const Opt *spec, const char *value) {
    (void)spec;
    o->data = value;
}

static void apply_stream(Opts *o, const Opt *spec, const char *value) {
    o->stream = true;
    apply_true(o, spec, value);
}

static void apply_wait(Opts *o, const Opt *spec, const char *value) {
    o->wait = true;
    apply_true(o, spec, value);
}

static void apply_trace(Opts *o, const Opt *spec, const char *value) {
    o->trace = true;
    apply_true(o, spec, value);
}

static void apply_all(Opts *o, const Opt *spec, const char *value) {
    o->all = true;
    apply_true(o, spec, value);
}

static void apply_emit(Opts *o, const Opt *spec, const char *value) {
    (void)o;
    (void)spec;
    (void)value;
    conn_emit_only();
}

static void apply_focus(Opts *o, const Opt *spec, const char *value) {
    (void)value;
    o->focus = strcmp(spec->flag, "--focus") == 0 ? 1 : 0;
}

static void apply_timeout(Opts *o, const Opt *spec, const char *value) {
    o->timeout = number_value(spec, value);
    o->has_timeout = true;
}

static Span trimmed(const char *p, size_t n) {
    while (n > 0 && (*p == ' ' || *p == '\t')) {
        p++;
        n--;
    }
    while (n > 0 && (p[n - 1] == ' ' || p[n - 1] == '\t')) {
        n--;
    }
    return (Span){p, n};
}

static void put_label(Buf *b, Span label, int *count) {
    if (label.len == 0) {
        return;
    }
    if (*count > 0) {
        buf_putc(b, ',');
    }
    json_str(b, label.ptr, label.len);
    (*count)++;
}

static void apply_buttons(Opts *o, const Opt *spec, const char *value) {
    Buf b = {0};
    int count = 0;
    buf_putc(&b, '[');
    const char *p = value;
    for (const char *comma = strchr(p, ','); comma != NULL; comma = strchr(p, ',')) {
        put_label(&b, trimmed(p, (size_t)(comma - p)), &count);
        p = comma + 1;
    }
    put_label(&b, trimmed(p, strlen(p)), &count);
    if (count == 0) {
        usage_fail("--buttons needs at least one label");
    }
    buf_putc(&b, ']');
    opts_set_buf(o, spec->key, &b);
}

/* The server parses the key names; only an empty value is caught here. */
static void apply_hotkey(Opts *o, const Opt *spec, const char *value) {
    if (value[0] == '\0') {
        usage_fail("--hotkey needs keys like ctrl+opt+t, or none");
    }
    opts_set_str(o, spec->key, value);
}

/* ---- tables ---- */

#define VALUE(flag, key, fn) {flag, key, fn, NULL, RANGE_ANY, true}
#define RANGED(flag, key, fn, range) {flag, key, fn, NULL, range, true}
#define CHOICE(flag, key, choices) {flag, key, apply_enum, choices, RANGE_ANY, true}
#define SWITCH(flag, key, fn) {flag, key, fn, NULL, RANGE_ANY, false}
#define END {NULL, NULL, NULL, NULL, RANGE_ANY, false}

const Opt content_opts[] = {
    VALUE("--id", "id", apply_id),
    VALUE("--kind", NULL, apply_kind),
    VALUE("--title", "title", apply_str),
    VALUE("--data", NULL, apply_data),
    SWITCH("--stream", "stream", apply_stream),
    CHOICE("--theme", "theme", "auto|dark|light"),
    VALUE("--accent", "accent", apply_str),
    SWITCH("--wait", "wait", apply_wait),
    VALUE("--buttons", "buttons", apply_buttons),
    SWITCH("--focus", NULL, apply_focus),
    SWITCH("--no-focus", NULL, apply_focus),
    RANGED("--timeout", NULL, apply_timeout, RANGE_POSITIVE),
    SWITCH("--trace", "trace", apply_trace),
    VALUE("--hotkey", "hotkey", apply_hotkey),
    SWITCH("--emit", NULL, apply_emit),
    END,
};

const Opt placement_opts[] = {
    CHOICE("--position", "position",
           "center|top|bottom|left|right|top-left|top-right|bottom-left|bottom-right|mouse"),
    VALUE("--at", "at", apply_at),
    VALUE("--screen", "screen", apply_str),
    RANGED("--margin", "margin", apply_number, RANGE_NONNEG),
    RANGED("--width", "width", apply_measure, RANGE_POSITIVE),
    RANGED("--height", "height", apply_measure, RANGE_POSITIVE),
    RANGED("--min-height", "minHeight", apply_measure, RANGE_POSITIVE),
    RANGED("--max-height", "maxHeight", apply_measure, RANGE_POSITIVE),
    SWITCH("--resizable", "resizable", apply_true),
    SWITCH("--no-resizable", "resizable", apply_false),
    CHOICE("--level", "level", "normal|floating|top"),
    CHOICE("--spaces", "spaces", "all|current"),
    SWITCH("--pin", "pin", apply_true),
    SWITCH("--click-through", "clickThrough", apply_true),
    RANGED("--opacity", "opacity", apply_number, RANGE_UNIT),
    VALUE("--stack", "stack", apply_str),
    SWITCH("--forget", "forget", apply_true),
    END,
};

const Opt id_opts[] = {
    VALUE("--id", "id", apply_id),
    SWITCH("--emit", NULL, apply_emit),
    END,
};

const Opt update_opts[] = {
    VALUE("--id", "id", apply_id),
    VALUE("--data", NULL, apply_data),
    SWITCH("--stream", "stream", apply_stream),
    SWITCH("--emit", NULL, apply_emit),
    END,
};

const Opt hide_opts[] = {
    VALUE("--id", "id", apply_id),
    SWITCH("--all", "all", apply_all),
    SWITCH("--emit", NULL, apply_emit),
    END,
};

/* ---- parsing ---- */

static const Opt *find_in_table(const Opt *table, const char *flag) {
    for (const Opt *opt = table; opt->flag != NULL; opt++) {
        if (strcmp(opt->flag, flag) == 0) {
            return opt;
        }
    }
    return NULL;
}

static const Opt *find_opt(const Opt *const *tables, const char *flag) {
    for (; *tables != NULL; tables++) {
        const Opt *opt = find_in_table(*tables, flag);
        if (opt != NULL) {
            return opt;
        }
    }
    return NULL;
}

static void take_file(Opts *o, const char *arg, bool allow_file) {
    if (!allow_file || o->file != NULL) {
        usage_fail("unexpected argument: %s", arg);
    }
    o->file = arg;
}

void opts_parse(Opts *o, Args *a, const Opt *const *tables, bool allow_file) {
    for (const char *arg = args_next(a); arg != NULL; arg = args_next(a)) {
        if (!args_is_flag(arg)) {
            take_file(o, arg, allow_file);
            continue;
        }
        const Opt *spec = find_opt(tables, arg);
        if (spec == NULL) {
            usage_fail("unknown option: %s", arg);
        }
        spec->apply(o, spec, spec->has_value ? args_value(a, arg) : NULL);
    }
}
