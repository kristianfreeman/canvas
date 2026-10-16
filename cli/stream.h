#ifndef CANVAS_STREAM_H
#define CANVAS_STREAM_H

#include "conn.h"
#include "events.h"

#include <stdbool.h>

/* Forward stdin to the connection, one JSON value per line (wrapped as
   {"data":V} with wrap), while watching the connection for events. Invalid
   lines are skipped with a warning. On stdin EOF the write side is shut
   down and the final event decides the exit code. */
int stream_run(LineReader *sock, Flow *f, bool wrap);

#endif
