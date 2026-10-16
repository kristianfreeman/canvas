#include "trace.h"

#include "json.h"
#include "util.h"

#include <mach/mach_time.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static uint64_t cli_start;
static uint64_t sent_at;

uint64_t clock_ns(void) {
    static mach_timebase_info_data_t base;
    if (base.denom == 0) {
        (void)mach_timebase_info(&base);
    }
    uint64_t t = mach_continuous_time();
    /* Split to avoid overflowing t * numer. */
    return ((t / base.denom) * base.numer) + ((t % base.denom) * base.numer / base.denom);
}

void trace_begin(void) { cli_start = clock_ns(); }

void trace_sent(void) { sent_at = clock_ns(); }

enum { MAX_STAGES = 32 };

typedef struct {
    Span name;
    double ms;
} Stage;

typedef struct {
    Stage items[MAX_STAGES];
    int n;
} Stages;

static double ms_since_start(double ns) { return (ns - (double)cli_start) / 1e6; }

static void add_stage(Stages *s, Span name, double ms) {
    if (s->n < MAX_STAGES) {
        s->items[s->n++] = (Stage){name, ms};
    }
}

static bool parse_ns(Span text, double *ns) {
    char num[64];
    if (text.len == 0 || text.len >= sizeof num) {
        return false;
    }
    memcpy(num, text.ptr, text.len);
    num[text.len] = '\0';
    char *end = NULL;
    *ns = strtod(num, &end);
    return *end == '\0';
}

static void add_server_stages(Stages *s, Span trace) {
    JIter it;
    Span key;
    Span val;
    if (!jiter_begin(&it, trace, '{')) {
        return;
    }
    while (jiter_member(&it, &key, &val) == 1) {
        double ns = 0;
        if (parse_ns(val, &ns)) {
            add_stage(s, key, ms_since_start(ns));
        }
    }
}

static void sort_stages(Stages *s) {
    for (int i = 1; i < s->n; i++) {
        Stage cur = s->items[i];
        int j = i - 1;
        while (j >= 0 && s->items[j].ms > cur.ms) {
            s->items[j + 1] = s->items[j];
            j--;
        }
        s->items[j + 1] = cur;
    }
}

static void put_ms(Buf *b, double ms) {
    char text[32];
    (void)snprintf(text, sizeof text, "%.2f", ms);
    buf_puts(b, text);
}

static void write_report(const Stages *s, double total) {
    Buf b = {0};
    buf_puts(&b, "{\"total_ms\":");
    put_ms(&b, total);
    buf_puts(&b, ",\"stages\":{");
    for (int i = 0; i < s->n; i++) {
        buf_puts(&b, i == 0 ? "\"" : ",\"");
        buf_putspan(&b, s->items[i].name);
        buf_puts(&b, "\":");
        put_ms(&b, s->items[i].ms);
    }
    buf_puts(&b, "}}\n");
    (void)write_all(STDERR_FILENO, b.data, b.len);
    buf_free(&b);
}

void trace_report(Span event_line) {
    double received = ms_since_start((double)clock_ns());
    Stages s = {.n = 0};
    add_stage(&s, span_of("cliStart"), 0);
    add_stage(&s, span_of("sent"), ms_since_start((double)sent_at));
    add_stage(&s, span_of("received"), received);
    Span trace;
    if (json_member(event_line, "trace", &trace)) {
        add_server_stages(&s, trace);
    }
    sort_stages(&s);
    write_report(&s, received);
}
