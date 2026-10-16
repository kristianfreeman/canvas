#include "util.h"

#include <errno.h>
#include <poll.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void buf_reserve(Buf *b, size_t extra) {
    if (extra > SIZE_MAX / 2 - b->len) {
        fail("out of memory");
    }
    size_t need = b->len + extra + 1;
    if (need <= b->cap) {
        return;
    }
    size_t cap = b->cap < 256 ? 256 : b->cap;
    while (cap < need) {
        cap *= 2;
    }
    char *data = realloc(b->data, cap);
    if (data == NULL) {
        fail("out of memory");
    }
    b->data = data;
    b->cap = cap;
}

void buf_put(Buf *b, const void *src, size_t n) {
    buf_reserve(b, n);
    if (n > 0) {
        memcpy(b->data + b->len, src, n);
    }
    b->len += n;
    b->data[b->len] = '\0';
}

void buf_puts(Buf *b, const char *s) { buf_put(b, s, strlen(s)); }

void buf_putc(Buf *b, char c) { buf_put(b, &c, 1); }

void buf_putspan(Buf *b, Span s) { buf_put(b, s.ptr, s.len); }

void buf_free(Buf *b) {
    free(b->data);
    b->data = NULL;
    b->len = 0;
    b->cap = 0;
}

Span buf_span(const Buf *b) { return (Span){b->data, b->len}; }

Span span_of(const char *s) { return (Span){s, strlen(s)}; }

bool span_eq(Span s, const char *lit) {
    size_t n = strlen(lit);
    return s.len == n && memcmp(s.ptr, lit, n) == 0;
}

bool span_blank(Span s) {
    for (size_t i = 0; i < s.len; i++) {
        if (strchr(" \t\r\n", s.ptr[i]) == NULL) {
            return false;
        }
    }
    return true;
}

/* A fixed buffer, not a Buf: buf_reserve reports out of memory through
   here. */
static void vmessage(const char *fmt, va_list ap) {
    static const char prefix[] = "canvas: ";
    char text[2048];
    memcpy(text, prefix, sizeof prefix - 1);
    size_t room = sizeof text - sizeof prefix;
    int n = vsnprintf(text + sizeof prefix - 1, room, fmt, ap);
    if (n < 0) {
        return;
    }
    size_t len = sizeof prefix - 1 + ((size_t)n < room ? (size_t)n : room - 1);
    text[len] = '\n';
    (void)write_all(STDERR_FILENO, text, len + 1);
}

void usage_fail(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vmessage(fmt, ap);
    va_end(ap);
    static const char hint[] = "run `canvas help` for usage\n";
    (void)write_all(STDERR_FILENO, hint, sizeof hint - 1);
    exit(64);
}

void fail(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vmessage(fmt, ap);
    va_end(ap);
    exit(1);
}

void warn(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vmessage(fmt, ap);
    va_end(ap);
}

/* Blocks until fd is writable again after EAGAIN. */
static bool retry_write(int fd) {
    if (errno == EINTR) {
        return true;
    }
    if (errno != EAGAIN) {
        return false;
    }
    struct pollfd p = {.fd = fd, .events = POLLOUT, .revents = 0};
    return poll(&p, 1, -1) >= 0 || errno == EINTR;
}

bool write_all(int fd, const void *src, size_t n) {
    const char *at = src;
    while (n > 0) {
        ssize_t written = write(fd, at, n);
        if (written < 0 && !retry_write(fd)) {
            return false;
        }
        if (written > 0) {
            at += written;
            n -= (size_t)written;
        }
    }
    return true;
}

void out_line(Span s) {
    static Buf line;
    line.len = 0;
    buf_putspan(&line, s);
    buf_putc(&line, '\n');
    if (!write_all(STDOUT_FILENO, line.data, line.len)) {
        exit(errno == EPIPE ? 0 : 1);
    }
}
