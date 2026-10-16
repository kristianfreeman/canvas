#ifndef CANVAS_UTIL_H
#define CANVAS_UTIL_H

#include <stdbool.h>
#include <stddef.h>

/* A growable byte buffer. data is always NUL-terminated once allocated. */
typedef struct {
    char *data;
    size_t len;
    size_t cap;
} Buf;

/* A borrowed byte range. */
typedef struct {
    const char *ptr;
    size_t len;
} Span;

void buf_reserve(Buf *b, size_t extra);
void buf_put(Buf *b, const void *src, size_t n);
void buf_puts(Buf *b, const char *s);
void buf_putc(Buf *b, char c);
void buf_putspan(Buf *b, Span s);
void buf_free(Buf *b);
Span buf_span(const Buf *b);

Span span_of(const char *s);
bool span_eq(Span s, const char *lit);
bool span_blank(Span s);

/* Exit 64 with `canvas: <problem>` and a pointer to `canvas help`. */
_Noreturn void usage_fail(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
/* Exit 1 with `canvas: <problem>`. */
_Noreturn void fail(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
/* Print `canvas: <problem>` to stderr and carry on. */
void warn(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

/* Write everything, retrying on EINTR and short writes. */
bool write_all(int fd, const void *src, size_t n);
/* Write a line to stdout. A closed stdout (EPIPE) exits 0 quietly. */
void out_line(Span s);

#endif
