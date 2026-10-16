#ifndef CANVAS_EVENTS_H
#define CANVAS_EVENTS_H

#include "conn.h"
#include "util.h"

#include <stdbool.h>
#include <stdint.h>

/* Outcomes besides an exit code. */
enum { GO_ON = -1, START_STREAM = -2 };

/* How a command reacts to the server's events. */
typedef struct {
    /* Absolute deadline for the next event; 0 waits forever. */
    uint64_t deadline;
    /* Printed (exit 1) when the deadline passes and hide_id is NULL. */
    const char *timeout_msg;
    /* With --wait --timeout: hide this panel and exit 3 on the deadline. */
    const char *hide_id;
    bool wait;
    bool stream;
    bool streaming;
    bool trace;
    bool traced;
} Flow;

/* Map one event line to an exit code, GO_ON or START_STREAM, printing
   results, frames and errors on the way. Exits 1 on a malformed line. */
int flow_event(Flow *f, Span line);
/* Read events until one decides the outcome. */
int flow_await(Flow *f, LineReader *r);
/* The deadline passed: exit 1 with the message, or hide and return 3. */
int flow_timeout(const Flow *f);

/* `canvas: <message>` on stderr for an error event. */
void print_error_event(Span line);

#endif
