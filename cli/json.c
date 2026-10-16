#include "json.h"

#include "utf8.h"
#include "util.h"

#include <stdio.h>
#include <string.h>

/* ---- writer ---- */

static bool plain_byte(unsigned char c) { return c >= 0x20 && c < 0x80 && c != '"' && c != '\\'; }

static void put_escape(Buf *b, unsigned char c) {
    static const char raw[] = "\"\\\n\t\r\b\f";
    static const char letters[] = "\"\\ntrbf";
    const char *hit = memchr(raw, c, sizeof raw - 1);
    if (hit != NULL) {
        buf_putc(b, '\\');
        buf_putc(b, letters[hit - raw]);
        return;
    }
    char hex[8];
    (void)snprintf(hex, sizeof hex, "\\u%04x", (unsigned)c);
    buf_puts(b, hex);
}

static const unsigned char *put_special(Buf *b, const unsigned char *p, const unsigned char *end) {
    if (*p < 0x80) {
        put_escape(b, *p);
        return p + 1;
    }
    size_t len = utf8_seq(p, (size_t)(end - p));
    if (len == 0) {
        buf_puts(b, "\xEF\xBF\xBD");
        return p + 1;
    }
    buf_put(b, p, len);
    return p + len;
}

void json_str(Buf *b, const char *s, size_t n) {
    buf_reserve(b, n + 2);
    buf_putc(b, '"');
    const unsigned char *p = (const unsigned char *)s;
    const unsigned char *end = p + n;
    while (p < end) {
        const unsigned char *run = p;
        while (p < end && plain_byte(*p)) {
            p++;
        }
        buf_put(b, run, (size_t)(p - run));
        if (p < end) {
            p = put_special(b, p, end);
        }
    }
    buf_putc(b, '"');
}

void json_cstr(Buf *b, const char *s) { json_str(b, s, strlen(s)); }

void json_key(Buf *b, const char *key) {
    buf_puts(b, ",\"");
    buf_puts(b, key);
    buf_puts(b, "\":");
}

/* ---- tokens ---- */

static bool is_digit(char c) { return c >= '0' && c <= '9'; }

static bool is_ws(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; }

static const char *skip_ws(const char *p, const char *end) {
    while (p < end && is_ws(*p)) {
        p++;
    }
    return p;
}

static bool is_hex(char c) { return is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'); }

static size_t escape_len(const char *p, const char *end) {
    if (end - p < 2) {
        return 0;
    }
    if (p[1] != 'u') {
        return p[1] != '\0' && strchr("\"\\/bfnrt", p[1]) != NULL ? 2 : 0;
    }
    if (end - p < 6) {
        return 0;
    }
    for (int i = 2; i < 6; i++) {
        if (!is_hex(p[i])) {
            return 0;
        }
    }
    return 6;
}

static size_t string_char_len(const char *p, const char *end) {
    unsigned char c = (unsigned char)*p;
    if (c == '\\') {
        return escape_len(p, end);
    }
    return c < 0x20 ? 0 : 1;
}

/* p is at the opening quote. Returns the end of the string or NULL. */
static const char *string_end(const char *p, const char *end) {
    p++;
    while (p < end) {
        if (*p == '"') {
            return p + 1;
        }
        size_t step = string_char_len(p, end);
        if (step == 0) {
            return NULL;
        }
        p += step;
    }
    return NULL;
}

static const char *some_digits(const char *p, const char *end) {
    const char *start = p;
    while (p < end && is_digit(*p)) {
        p++;
    }
    return p == start ? NULL : p;
}

static const char *int_part(const char *p, const char *end) {
    if (p < end && *p == '-') {
        p++;
    }
    if (p < end && *p == '0') {
        return p + 1;
    }
    return some_digits(p, end);
}

static const char *frac_part(const char *p, const char *end) {
    if (p == NULL || p >= end || *p != '.') {
        return p;
    }
    return some_digits(p + 1, end);
}

static const char *exp_part(const char *p, const char *end) {
    if (p == NULL || p >= end || (*p != 'e' && *p != 'E')) {
        return p;
    }
    p++;
    if (p < end && (*p == '+' || *p == '-')) {
        p++;
    }
    return some_digits(p, end);
}

static const char *number_end(const char *p, const char *end) {
    return exp_part(frac_part(int_part(p, end), end), end);
}

static const char *literal_end(const char *p, const char *end) {
    static const char *const words[] = {"true", "false", "null"};
    for (size_t i = 0; i < sizeof words / sizeof words[0]; i++) {
        size_t n = strlen(words[i]);
        if ((size_t)(end - p) >= n && memcmp(p, words[i], n) == 0) {
            return p + n;
        }
    }
    return NULL;
}

static const char *scalar_end(const char *p, const char *end) {
    if (*p == '"') {
        return string_end(p, end);
    }
    if (*p == '-' || is_digit(*p)) {
        return number_end(p, end);
    }
    return literal_end(p, end);
}

/* ---- value scanner: an explicit-stack state machine, so deep input can't
   overflow the C stack ---- */

enum { MAX_DEPTH = 512 };

typedef enum { WANT_VALUE, WANT_FIRST_VALUE, WANT_KEY, WANT_FIRST_KEY, WANT_COLON, WANT_SEP, DONE, FAILED } State;

typedef struct {
    const char *p;
    const char *end;
    Buf *out;
    int depth;
    State state;
    char stack[MAX_DEPTH];
} Scan;

static void take(Scan *s, const char *stop) {
    if (s->out != NULL) {
        buf_put(s->out, s->p, (size_t)(stop - s->p));
    }
    s->p = stop;
}

static void finish_value(Scan *s) { s->state = s->depth == 0 ? DONE : WANT_SEP; }

static void open_container(Scan *s, char c) {
    if (s->depth == MAX_DEPTH) {
        s->state = FAILED;
        return;
    }
    s->stack[s->depth++] = c;
    take(s, s->p + 1);
    s->state = c == '{' ? WANT_FIRST_KEY : WANT_FIRST_VALUE;
}

static void close_container(Scan *s, char c) {
    char open = c == '}' ? '{' : '[';
    if ((c != '}' && c != ']') || s->depth == 0 || s->stack[s->depth - 1] != open) {
        s->state = FAILED;
        return;
    }
    s->depth--;
    take(s, s->p + 1);
    finish_value(s);
}

static void step_value(Scan *s) {
    char c = *s->p;
    if (c == '{' || c == '[') {
        open_container(s, c);
        return;
    }
    const char *stop = scalar_end(s->p, s->end);
    if (stop == NULL) {
        s->state = FAILED;
        return;
    }
    take(s, stop);
    finish_value(s);
}

static void step_key(Scan *s) {
    const char *stop = *s->p == '"' ? string_end(s->p, s->end) : NULL;
    if (stop == NULL) {
        s->state = FAILED;
        return;
    }
    take(s, stop);
    s->state = WANT_COLON;
}

static void step_punct(Scan *s, char want, State next) {
    if (*s->p != want) {
        s->state = FAILED;
        return;
    }
    take(s, s->p + 1);
    s->state = next;
}

static void step_sep(Scan *s) {
    if (*s->p != ',') {
        close_container(s, *s->p);
        return;
    }
    step_punct(s, ',', s->stack[s->depth - 1] == '{' ? WANT_KEY : WANT_VALUE);
}

static void step_first(Scan *s, char close, void (*item)(Scan *)) {
    if (*s->p == close) {
        close_container(s, close);
        return;
    }
    item(s);
}

static void step(Scan *s) {
    s->p = skip_ws(s->p, s->end);
    if (s->p >= s->end) {
        s->state = FAILED;
        return;
    }
    switch (s->state) {
    case WANT_VALUE: step_value(s); break;
    case WANT_FIRST_VALUE: step_first(s, ']', step_value); break;
    case WANT_FIRST_KEY: step_first(s, '}', step_key); break;
    case WANT_KEY: step_key(s); break;
    case WANT_COLON: step_punct(s, ':', WANT_VALUE); break;
    case WANT_SEP: step_sep(s); break;
    default: s->state = FAILED; break;
    }
}

/* Scan one value starting at *pp (leading whitespace allowed). */
static bool scan_value(const char **cursor, const char *end, Buf *out) {
    Scan s = {.p = *cursor, .end = end, .out = out, .depth = 0, .state = WANT_VALUE, .stack = {0}};
    while (s.state != DONE && s.state != FAILED) {
        step(&s);
    }
    *cursor = s.p;
    return s.state == DONE;
}

bool json_minify(Span in, Buf *out) {
    if (!utf8_valid(in.ptr, in.len)) {
        return false;
    }
    const char *p = in.ptr;
    const char *end = p + in.len;
    if (!scan_value(&p, end, out)) {
        return false;
    }
    return skip_ws(p, end) == end;
}

/* ---- iteration ---- */

bool jiter_begin(JIter *it, Span s, char open) {
    it->end = s.ptr + s.len;
    it->p = skip_ws(s.ptr, it->end);
    it->close = open == '{' ? '}' : ']';
    it->first = true;
    if (it->p >= it->end || *it->p != open) {
        return false;
    }
    it->p++;
    return true;
}

/* Moves past the separator before the next item. */
static int jiter_advance(JIter *it) {
    it->p = skip_ws(it->p, it->end);
    if (it->p >= it->end) {
        return -1;
    }
    if (*it->p == it->close) {
        it->p++;
        return 0;
    }
    if (!it->first) {
        if (*it->p != ',') {
            return -1;
        }
        it->p++;
    }
    it->first = false;
    return 1;
}

static int jiter_value(JIter *it, Span *val) {
    it->p = skip_ws(it->p, it->end);
    const char *start = it->p;
    if (!scan_value(&it->p, it->end, NULL)) {
        return -1;
    }
    *val = (Span){start, (size_t)(it->p - start)};
    return 1;
}

int jiter_element(JIter *it, Span *val) {
    int st = jiter_advance(it);
    return st == 1 ? jiter_value(it, val) : st;
}

int jiter_member(JIter *it, Span *key, Span *val) {
    int st = jiter_advance(it);
    if (st != 1) {
        return st;
    }
    it->p = skip_ws(it->p, it->end);
    const char *kend = it->p < it->end && *it->p == '"' ? string_end(it->p, it->end) : NULL;
    if (kend == NULL) {
        return -1;
    }
    *key = (Span){it->p + 1, (size_t)(kend - it->p) - 2};
    it->p = skip_ws(kend, it->end);
    if (it->p >= it->end || *it->p != ':') {
        return -1;
    }
    it->p++;
    return jiter_value(it, val);
}

bool json_member(Span obj, const char *key, Span *val) {
    JIter it;
    Span name;
    if (!jiter_begin(&it, obj, '{')) {
        return false;
    }
    while (jiter_member(&it, &name, val) == 1) {
        if (span_eq(name, key)) {
            return true;
        }
    }
    return false;
}

bool json_string_member(Span obj, const char *key, Span *content) {
    Span val;
    if (!json_member(obj, key, &val) || val.len < 2 || val.ptr[0] != '"') {
        return false;
    }
    *content = (Span){val.ptr + 1, val.len - 2};
    return true;
}

/* ---- string decoding ---- */

static unsigned long hex_value(char c) {
    if (is_digit(c)) {
        return (unsigned long)(c - '0');
    }
    return (unsigned long)(((unsigned char)c | 0x20U) - 'a') + 10;
}

static bool hex4(const char *p, const char *end, unsigned long *v) {
    if (end - p < 4) {
        return false;
    }
    unsigned long value = 0;
    for (int i = 0; i < 4; i++) {
        if (!is_hex(p[i])) {
            return false;
        }
        value = (value * 16) + hex_value(p[i]);
    }
    *v = value;
    return true;
}

static bool in_range(unsigned long v, unsigned long lo, unsigned long hi) { return v >= lo && v <= hi; }

static const char *low_surrogate(const char *p, const char *end, unsigned long *cp) {
    unsigned long lo = 0;
    if (end - p >= 6 && p[0] == '\\' && p[1] == 'u' && hex4(p + 2, end, &lo) && in_range(lo, 0xDC00, 0xDFFF)) {
        *cp = 0x10000 + ((*cp - 0xD800) << 10U) + (lo - 0xDC00);
        return p + 6;
    }
    *cp = 0xFFFD;
    return p;
}

static const char *decode_unicode(const char *p, const char *end, Buf *out) {
    unsigned long cp = 0;
    if (!hex4(p + 2, end, &cp)) {
        return NULL;
    }
    p += 6;
    if (in_range(cp, 0xD800, 0xDBFF)) {
        p = low_surrogate(p, end, &cp);
    } else if (in_range(cp, 0xDC00, 0xDFFF)) {
        cp = 0xFFFD;
    }
    unsigned char bytes[4];
    buf_put(out, bytes, utf8_encode(cp, bytes));
    return p;
}

static const char *decode_escape(const char *p, const char *end, Buf *out) {
    if (end - p < 2) {
        return NULL;
    }
    if (p[1] == 'u') {
        return decode_unicode(p, end, out);
    }
    static const char letters[] = "\"\\/bfnrt";
    static const char raw[] = "\"\\/\b\f\n\r\t";
    const char *hit = memchr(letters, p[1], sizeof letters - 1);
    if (hit == NULL) {
        return NULL;
    }
    buf_putc(out, raw[hit - letters]);
    return p + 2;
}

bool json_decode_string(Span quoted, Buf *out) {
    if (quoted.len < 2 || quoted.ptr[0] != '"') {
        return false;
    }
    const char *p = quoted.ptr + 1;
    const char *end = quoted.ptr + quoted.len - 1;
    while (p != NULL && p < end) {
        if (*p != '\\') {
            buf_putc(out, *p++);
            continue;
        }
        p = decode_escape(p, end, out);
    }
    return p != NULL;
}
