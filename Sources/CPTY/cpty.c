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

    // Prepare the Darwin exec attributes before forking. SETEXEC preserves the session
    // forkpty creates, while CLOEXEC_DEFAULT closes every descriptor we did not inherit.
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

    int master = -1;
    pid_t pid = -1;
    if ((result = posix_spawn_file_actions_addinherit_np(&actions, STDIN_FILENO)) == 0 &&
        (result = posix_spawn_file_actions_addinherit_np(&actions, STDOUT_FILENO)) == 0 &&
        (result = posix_spawn_file_actions_addinherit_np(&actions, STDERR_FILENO)) == 0 &&
        (result = posix_spawnattr_setsigmask(&attributes, &empty)) == 0 &&
        (result = posix_spawnattr_setsigdefault(&attributes, &defaults)) == 0 &&
        (result = posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETEXEC |
            POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_CLOEXEC_DEFAULT)) == 0) {
        pid = forkpty(&master, NULL, NULL, &size);
        if (pid < 0) result = errno;
    }
    if (pid == 0) {
        // Darwin's wrapper passes the prebuilt attributes straight to the kernel.
        posix_spawn(NULL, path, &actions, &attributes, argv, envp);
        _exit(127);
    }
    posix_spawnattr_destroy(&attributes);
    posix_spawn_file_actions_destroy(&actions);
    if (result != 0) return result;

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
