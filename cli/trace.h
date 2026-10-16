#ifndef CANVAS_TRACE_H
#define CANVAS_TRACE_H

#include "util.h"

#include <stdint.h>

/* mach_continuous_time() in nanoseconds; the server uses the same clock. */
uint64_t clock_ns(void);

/* Record cliStart. Call first thing in main. */
void trace_begin(void);
/* Record `sent` (the request was written). */
void trace_sent(void);
/* Record `received`, merge the CLI stages with the event's "trace" object,
   and print `{"total_ms":..,"stages":{..}}` to stderr. */
void trace_report(Span event_line);

#endif
