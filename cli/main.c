#include "args.h"
#include "commands.h"
#include "trace.h"
#include "util.h"

#include <signal.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

typedef struct {
    const char *name;
    int (*run)(Args *a);
} Command;

static const Command commands[] = {
    {"show", cmd_show}, {"toggle", cmd_toggle}, {"update", cmd_update}, {"move", cmd_move},
    {"hide", cmd_hide}, {"list", cmd_list},     {"pub", cmd_pub},       {"sub", cmd_sub},
    {"get", cmd_get},   {"hotkeys", cmd_hotkeys}, {"ping", cmd_ping},   {"help", cmd_help},
    {"--help", cmd_help}, {"-h", cmd_help},
};

int main(int argc, char **argv) {
    trace_begin();
    /* Sockets use SO_NOSIGPIPE; a closed stdout shows up as EPIPE. */
    (void)signal(SIGPIPE, SIG_IGN);
    if (argc < 2) {
        help_write(STDERR_FILENO);
        return 64;
    }
    for (size_t i = 0; i < sizeof commands / sizeof commands[0]; i++) {
        if (strcmp(argv[1], commands[i].name) == 0) {
            Args a = {.argc = argc, .argv = argv, .i = 2};
            return commands[i].run(&a);
        }
    }
    usage_fail("unknown command: %s", argv[1]);
}
