#ifndef CANVAS_COMMANDS_H
#define CANVAS_COMMANDS_H

#include "args.h"
#include "util.h"

#include <stdbool.h>
#include <stdint.h>

/* Each command parses the arguments after its name and returns the exit
   code. Usage errors and failures exit directly. */
int cmd_show(Args *a);
int cmd_toggle(Args *a);
int cmd_update(Args *a);
int cmd_move(Args *a);
int cmd_hide(Args *a);
int cmd_list(Args *a);
int cmd_ping(Args *a);
int cmd_pub(Args *a);
int cmd_sub(Args *a);
int cmd_help(Args *a);

/* The help text to fd. */
void help_write(int fd);

/* Dot-separated [a-z0-9_-] segments. */
bool channel_valid(const char *name);
/* "500ms", "1s", "2.5m" in nanoseconds; a usage error otherwise. */
uint64_t parse_duration(const char *text);
/* `pub --every`: req is the pub request without its closing brace. */
int pub_every(Buf *req, char **cmd, uint64_t period_ns);

#endif
