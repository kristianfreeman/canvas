#include "proc.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static void setup_attr(posix_spawnattr_t *attr, bool detach) {
    sigset_t none;
    sigset_t defaults;
    (void)sigemptyset(&none);
    (void)sigemptyset(&defaults);
    (void)sigaddset(&defaults, SIGPIPE);
    (void)sigaddset(&defaults, SIGINT);
    (void)sigaddset(&defaults, SIGTERM);
    (void)sigaddset(&defaults, SIGHUP);
    (void)posix_spawnattr_setsigmask(attr, &none);
    (void)posix_spawnattr_setsigdefault(attr, &defaults);
    unsigned flags = (unsigned)POSIX_SPAWN_CLOEXEC_DEFAULT | (unsigned)POSIX_SPAWN_SETSIGMASK |
                     (unsigned)POSIX_SPAWN_SETSIGDEF;
    if (detach) {
        flags |= (unsigned)POSIX_SPAWN_SETSID;
    }
    (void)posix_spawnattr_setflags(attr, (short)flags);
}

static void setup_io(posix_spawn_file_actions_t *actions, const SpawnOpts *opts) {
    if (opts->detach) {
        (void)posix_spawn_file_actions_addopen(actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
        (void)posix_spawn_file_actions_addopen(actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
        (void)posix_spawn_file_actions_addopen(actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
        return;
    }
    (void)posix_spawn_file_actions_addinherit_np(actions, STDIN_FILENO);
    (void)posix_spawn_file_actions_addinherit_np(actions, STDERR_FILENO);
    if (opts->stdout_fd >= 0) {
        (void)posix_spawn_file_actions_adddup2(actions, opts->stdout_fd, STDOUT_FILENO);
    } else {
        (void)posix_spawn_file_actions_addinherit_np(actions, STDOUT_FILENO);
    }
}

pid_t proc_spawn(char *const argv[], const SpawnOpts *opts) {
    posix_spawnattr_t attr;
    posix_spawn_file_actions_t actions;
    (void)posix_spawnattr_init(&attr);
    (void)posix_spawn_file_actions_init(&actions);
    setup_attr(&attr, opts->detach);
    setup_io(&actions, opts);
    pid_t pid = -1;
    int err = opts->search ? posix_spawnp(&pid, argv[0], &actions, &attr, argv, environ)
                           : posix_spawn(&pid, argv[0], &actions, &attr, argv, environ);
    (void)posix_spawn_file_actions_destroy(&actions);
    (void)posix_spawnattr_destroy(&attr);
    if (err != 0) {
        errno = err;
        return -1;
    }
    return pid;
}

int proc_wait(pid_t pid) {
    int status = 0;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) {
            return -1;
        }
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return 128 + WTERMSIG(status);
}
