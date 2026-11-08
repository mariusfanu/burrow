#include "cpty.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>

int cpty_spawn(const char *path,
               char *const argv[],
               char *const envp[],
               unsigned short rows,
               unsigned short cols,
               int *out_master,
               pid_t *out_pid) {
    struct winsize size;
    memset(&size, 0, sizeof(size));
    size.ws_row = rows;
    size.ws_col = cols;

    int master = -1;
    pid_t pid = forkpty(&master, NULL, NULL, &size);
    if (pid < 0) {
        return errno;
    }

    if (pid == 0) {
        // Only async-signal-safe calls between fork and exec.
        sigset_t empty;
        sigemptyset(&empty);
        sigprocmask(SIG_SETMASK, &empty, NULL);
        signal(SIGPIPE, SIG_DFL);
        signal(SIGINT, SIG_DFL);
        signal(SIGTERM, SIG_DFL);

        for (int fd = 3; fd < 1024; fd++) {
            close(fd);
        }
        execve(path, argv, envp);
        _exit(127);
    }

    fcntl(master, F_SETFD, FD_CLOEXEC);
    *out_master = master;
    *out_pid = pid;
    return 0;
}

int cpty_resize(int master, unsigned short rows, unsigned short cols) {
    struct winsize size;
    memset(&size, 0, sizeof(size));
    size.ws_row = rows;
    size.ws_col = cols;
    return ioctl(master, TIOCSWINSZ, &size) == 0 ? 0 : errno;
}

int cpipe_spawn(const char *path, char *const argv[], char *const envp[],
                int input, int output, int error, pid_t *out_pid) {
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    int result = posix_spawn_file_actions_init(&actions);
    if (result != 0) return result;
    result = posix_spawnattr_init(&attributes);
    if (result != 0) {
        posix_spawn_file_actions_destroy(&actions);
        return result;
    }

    sigset_t empty, defaults;
    sigemptyset(&empty);
    sigemptyset(&defaults);
    sigaddset(&defaults, SIGPIPE);
    sigaddset(&defaults, SIGINT);
    sigaddset(&defaults, SIGTERM);
    sigaddset(&defaults, SIGHUP);

    if ((result = posix_spawn_file_actions_adddup2(&actions, input, STDIN_FILENO)) == 0 &&
        (result = posix_spawn_file_actions_adddup2(&actions, output, STDOUT_FILENO)) == 0 &&
        (result = posix_spawn_file_actions_adddup2(&actions, error, STDERR_FILENO)) == 0 &&
        (result = posix_spawnattr_setpgroup(&attributes, 0)) == 0 &&
        (result = posix_spawnattr_setsigmask(&attributes, &empty)) == 0 &&
        (result = posix_spawnattr_setsigdefault(&attributes, &defaults)) == 0 &&
        (result = posix_spawnattr_setflags(&attributes,
            POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK |
            POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_CLOEXEC_DEFAULT)) == 0) {
        result = posix_spawn(out_pid, path, &actions, &attributes, argv, envp);
    }
    posix_spawnattr_destroy(&attributes);
    posix_spawn_file_actions_destroy(&actions);
    return result;
}
