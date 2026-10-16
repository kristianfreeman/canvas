#ifndef CANVAS_PROC_H
#define CANVAS_PROC_H

#include <stdbool.h>
#include <sys/types.h>

typedef struct {
    /* Replaces the child's stdout when >= 0. */
    int stdout_fd;
    /* New session, stdio on /dev/null: for the server, which outlives us. */
    bool detach;
    /* Look argv[0] up on PATH. */
    bool search;
} SpawnOpts;

/* Spawn argv with signals reset to their defaults and every descriptor
   except stdio closed. Returns -1 with errno set on failure. */
pid_t proc_spawn(char *const argv[], const SpawnOpts *opts);
/* The exit status, 128 + the signal number if killed, or -1. */
int proc_wait(pid_t pid);

#endif
