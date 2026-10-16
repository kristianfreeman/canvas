#ifndef CANVAS_CONN_H
#define CANVAS_CONN_H

#include "util.h"

#include <stdbool.h>
#include <stdint.h>

/* Splits a file descriptor's input into lines. */
typedef struct {
    int fd;
    Buf buf;
    size_t pos;
    bool eof;
} LineReader;

typedef enum { LR_LINE, LR_EOF, LR_TIMEOUT } LrStatus;

void lr_init(LineReader *r, int fd);
/* One read(). Read errors count as end of input. Returns false at EOF. */
bool lr_fill(LineReader *r);
/* Take a buffered line without the newline. At EOF the unterminated tail
   counts as a line. The span is valid until the next lr_fill. */
bool lr_take(LineReader *r, Span *line);
/* Block for the next line until deadline (0 waits forever). */
LrStatus lr_next(LineReader *r, uint64_t deadline, Span *line);

/* An absolute clock_ns() deadline. */
uint64_t deadline_after(double seconds);
/* poll() timeout in ms for a deadline; -1 for none. */
int poll_timeout(uint64_t deadline);

/* Connect to the server socket. With autostart, a missing server is
   started and awaited (failing exits 1); without it, returns -1. */
int conn_open(bool autostart);
/* Connect, write the request, record the `sent` trace stage and set up a
   reader on the connection. Returns false if there's no server and
   autostart is off. After conn_emit_only it prints the request line to
   stdout and exits 0 instead. */
bool conn_request(LineReader *r, const Buf *req, bool autostart);
/* --emit: build requests but print them rather than send them. */
void conn_emit_only(void);
bool conn_emitting(void);

#endif
