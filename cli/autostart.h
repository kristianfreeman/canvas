#ifndef CANVAS_AUTOSTART_H
#define CANVAS_AUTOSTART_H

#include <sys/types.h>

/* Start the server: `open -g` on the bundle that contains this binary
   (returns 0 once open is done), or spawn $CANVAS_SERVER or a dev build's
   canvas-server with `serve`, detached (returns its pid). Exits 1 if no
   server can be found or started, or without trying when
   CANVAS_NO_AUTOSTART=1. */
pid_t server_start(void);

/* Exit 1 early if the spawned server already died with a failure. Sets
   *pid to 0 once it has been reaped. */
void server_check(pid_t *pid);

#endif
