#ifndef CPTY_H
#define CPTY_H

#include <sys/types.h>

/// Starts `path` attached to a new pseudo-terminal that becomes its controlling
/// terminal, so `/dev/tty`, `sudo` and `read` behave as they do in Terminal.app.
/// Returns 0 and fills the out parameters, or returns an errno value.
int cpty_spawn(const char *path,
               char *const argv[],
               char *const envp[],
               unsigned short rows,
               unsigned short cols,
               int *out_master,
               pid_t *out_pid);

/// Resizes the terminal, which delivers SIGWINCH to the foreground job.
int cpty_resize(int master, unsigned short rows, unsigned short cols);

/// Starts a piped command in its own process group. Only the three explicitly
/// supplied descriptors are inherited. Returns a posix_spawn error code.
int cpipe_spawn(const char *path, char *const argv[], char *const envp[],
                int input, int output, int error, pid_t *out_pid);

#endif
