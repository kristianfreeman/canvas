#include "autostart.h"

#include "proc.h"
#include "util.h"

#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <signal.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

/* The directory holding this binary, symlinks resolved: the CLI is usually
   reached through ~/.local/bin/canvas. */
static void exe_dir(char out[PATH_MAX]) {
    char raw[PATH_MAX];
    uint32_t size = sizeof raw;
    if (_NSGetExecutablePath(raw, &size) != 0 || realpath(raw, out) == NULL) {
        fail("cannot find the canvas executable");
    }
    char *slash = strrchr(out, '/');
    if (slash != NULL) {
        *slash = '\0';
    }
}

static bool ends_with(const char *s, size_t n, const char *suffix) {
    size_t k = strlen(suffix);
    return n >= k && memcmp(s + n - k, suffix, k) == 0;
}

/* X.app when dir is X.app/Contents/MacOS. */
static bool bundle_of(const char *dir, char out[PATH_MAX]) {
    static const char inner[] = "/Contents/MacOS";
    size_t n = strlen(dir);
    if (!ends_with(dir, n, inner)) {
        return false;
    }
    n -= sizeof inner - 1;
    if (!ends_with(dir, n, ".app")) {
        return false;
    }
    memcpy(out, dir, n);
    out[n] = '\0';
    return true;
}

static bool find_dev_server(const char *dir, char out[PATH_MAX]) {
    static const char *const candidates[] = {"canvas-server", "../debug/canvas-server", "../release/canvas-server"};
    for (size_t i = 0; i < sizeof candidates / sizeof candidates[0]; i++) {
        int n = snprintf(out, PATH_MAX, "%s/%s", dir, candidates[i]);
        if (n > 0 && n < PATH_MAX && access(out, X_OK) == 0) {
            return true;
        }
    }
    return false;
}

static void run_open(const char *bundle) {
    char open_path[] = "/usr/bin/open";
    char flag[] = "-g";
    char path[PATH_MAX];
    (void)snprintf(path, sizeof path, "%s", bundle);
    char *argv[] = {open_path, flag, path, NULL};
    SpawnOpts opts = {.stdout_fd = -1, .detach = false, .search = false};
    pid_t pid = proc_spawn(argv, &opts);
    if (pid < 0 || proc_wait(pid) != 0) {
        fail("could not start %s with open -g", bundle);
    }
}

typedef int (*DisclaimFn)(posix_spawnattr_t *attr, int disclaim);

/* Makes the server its own responsible process, as it is when launched by
   launchd or open, instead of inheriting the terminal: macOS attributes the
   server's WebKit processes and privacy prompts to the responsible process.
   The call is private, so it's looked up at run time. */
static void disclaim_responsibility(posix_spawnattr_t *attr) {
    void *symbol = dlsym(RTLD_DEFAULT, "responsibility_spawnattrs_setdisclaim");
    if (symbol == NULL) {
        return;
    }
    DisclaimFn disclaim = NULL;
    _Static_assert(sizeof disclaim == sizeof symbol, "function and data pointers differ in size");
    memcpy((void *)&disclaim, (const void *)&symbol, sizeof disclaim);
    (void)disclaim(attr, 1);
}

/* A new session with default signals, stdio on /dev/null and every other
   descriptor closed, so the server outlives us and never holds the caller's
   pipes open. */
static void server_attr(posix_spawnattr_t *attr) {
    sigset_t none;
    sigset_t defaults;
    (void)sigemptyset(&none);
    (void)sigfillset(&defaults);
    (void)posix_spawnattr_setsigmask(attr, &none);
    (void)posix_spawnattr_setsigdefault(attr, &defaults);
    unsigned flags = (unsigned)POSIX_SPAWN_SETSID | (unsigned)POSIX_SPAWN_CLOEXEC_DEFAULT |
                     (unsigned)POSIX_SPAWN_SETSIGMASK | (unsigned)POSIX_SPAWN_SETSIGDEF;
    (void)posix_spawnattr_setflags(attr, (short)flags);
    disclaim_responsibility(attr);
}

/* With CANVAS_DEBUG=1 and a CANVAS_HOME, the server's stderr goes to
   server.log there; otherwise to /dev/null. */
static void server_log(char out[PATH_MAX]) {
    const char *debug = getenv("CANVAS_DEBUG");
    const char *home = getenv("CANVAS_HOME");
    bool wanted = debug != NULL && strcmp(debug, "1") == 0 && home != NULL && home[0] != '\0';
    int n = wanted ? snprintf(out, PATH_MAX, "%s/server.log", home) : -1;
    if (n < 0 || n >= PATH_MAX) {
        (void)snprintf(out, PATH_MAX, "/dev/null");
    }
}

static pid_t spawn_server(const char *server) {
    char path[PATH_MAX];
    char log[PATH_MAX];
    char serve[] = "serve";
    (void)snprintf(path, sizeof path, "%s", server);
    server_log(log);
    char *argv[] = {path, serve, NULL};
    posix_spawnattr_t attr;
    posix_spawn_file_actions_t actions;
    (void)posix_spawnattr_init(&attr);
    (void)posix_spawn_file_actions_init(&actions);
    server_attr(&attr);
    (void)posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    (void)posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    (void)posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, log, O_WRONLY | O_CREAT | O_APPEND, 0600);
    pid_t pid = -1;
    int err = posix_spawn(&pid, path, &actions, &attr, argv, environ);
    (void)posix_spawn_file_actions_destroy(&actions);
    (void)posix_spawnattr_destroy(&attr);
    if (err != 0) {
        fail("cannot start %s: %s", server, strerror(err));
    }
    return pid;
}

pid_t server_start(void) {
    const char *off = getenv("CANVAS_NO_AUTOSTART");
    if (off != NULL && strcmp(off, "1") == 0) {
        fail("the canvas server is not running (CANVAS_NO_AUTOSTART=1)");
    }
    const char *env = getenv("CANVAS_SERVER");
    if (env != NULL && env[0] != '\0') {
        return spawn_server(env);
    }
    char dir[PATH_MAX];
    char path[PATH_MAX];
    exe_dir(dir);
    if (bundle_of(dir, path)) {
        run_open(path);
        return 0;
    }
    if (!find_dev_server(dir, path)) {
        fail("cannot find canvas-server next to %s; set CANVAS_SERVER", dir);
    }
    return spawn_server(path);
}

void server_check(pid_t *pid) {
    int status = 0;
    if (*pid <= 0 || waitpid(*pid, &status, WNOHANG) != *pid) {
        return;
    }
    *pid = 0;
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fail("the canvas server exited before it was ready");
    }
}
