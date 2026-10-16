#ifndef CANVAS_ARGS_H
#define CANVAS_ARGS_H

#include <stdbool.h>

typedef struct {
    int argc;
    char **argv;
    int i;
} Args;

/* The next argument, or NULL at the end. */
const char *args_next(Args *a);
/* The value after flag; a missing value is a usage error. */
const char *args_value(Args *a, const char *flag);
/* An option rather than a positional: starts with '-', but isn't "-" or a
   negative number. */
bool args_is_flag(const char *arg);

#endif
