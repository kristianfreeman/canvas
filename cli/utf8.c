#include "utf8.h"

#include <stddef.h>

/* For a lead byte: the sequence length and the allowed range of the second
   byte. The narrowed ranges reject overlongs, surrogates and > U+10FFFF. */
typedef struct {
    unsigned char lo;
    unsigned char hi;
    unsigned char len;
} Lead;

static Lead lead_info(unsigned char c) {
    if (c >= 0xC2 && c <= 0xDF) {
        return (Lead){0x80, 0xBF, 2};
    }
    if (c == 0xE0) {
        return (Lead){0xA0, 0xBF, 3};
    }
    if (c == 0xED) {
        return (Lead){0x80, 0x9F, 3};
    }
    if (c >= 0xE1 && c <= 0xEF) {
        return (Lead){0x80, 0xBF, 3};
    }
    if (c == 0xF0) {
        return (Lead){0x90, 0xBF, 4};
    }
    if (c >= 0xF1 && c <= 0xF3) {
        return (Lead){0x80, 0xBF, 4};
    }
    if (c == 0xF4) {
        return (Lead){0x80, 0x8F, 4};
    }
    return (Lead){0, 0, 0};
}

static bool continuation(unsigned char c) { return (c & 0xC0U) == 0x80U; }

size_t utf8_seq(const unsigned char *p, size_t n) {
    if (n == 0) {
        return 0;
    }
    if (p[0] < 0x80) {
        return 1;
    }
    Lead lead = lead_info(p[0]);
    if (lead.len == 0 || n < lead.len || p[1] < lead.lo || p[1] > lead.hi) {
        return 0;
    }
    for (size_t i = 2; i < lead.len; i++) {
        if (!continuation(p[i])) {
            return 0;
        }
    }
    return lead.len;
}

bool utf8_valid(const char *p, size_t n) {
    const unsigned char *at = (const unsigned char *)p;
    const unsigned char *end = at + n;
    while (at < end) {
        if (*at < 0x80) {
            at++;
            continue;
        }
        size_t len = utf8_seq(at, (size_t)(end - at));
        if (len == 0) {
            return false;
        }
        at += len;
    }
    return true;
}

static unsigned char tail(unsigned long cp, unsigned shift) {
    return (unsigned char)(0x80U | ((cp >> shift) & 0x3FU));
}

size_t utf8_encode(unsigned long cp, unsigned char out[4]) {
    if (cp < 0x80) {
        out[0] = (unsigned char)cp;
        return 1;
    }
    if (cp < 0x800) {
        out[0] = (unsigned char)(0xC0U | (cp >> 6U));
        out[1] = tail(cp, 0);
        return 2;
    }
    if (cp < 0x10000) {
        out[0] = (unsigned char)(0xE0U | (cp >> 12U));
        out[1] = tail(cp, 6);
        out[2] = tail(cp, 0);
        return 3;
    }
    out[0] = (unsigned char)(0xF0U | (cp >> 18U));
    out[1] = tail(cp, 12);
    out[2] = tail(cp, 6);
    out[3] = tail(cp, 0);
    return 4;
}
