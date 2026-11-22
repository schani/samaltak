#ifndef SAMALTAK_C4_PLATFORM_FILES_H
#define SAMALTAK_C4_PLATFORM_FILES_H

#include <errno.h>
#include <stdint.h>
#ifdef SAMALTAK_C4_PLATFORM_FILES
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

/* Open no device, pipe or socket, even if a path is replaced concurrently.
 * O_PATH takes a reference without invoking the file's open operation. If
 * creating, O_EXCL cannot open an existing inode. A racing create may fail. */
static inline int c4_platform_open_regular(const char *path, int flags, uint16_t mode)
{
#ifdef SAMALTAK_C4_PLATFORM_FILES
    int ref = open(path, O_PATH | O_CLOEXEC);
    if (ref < 0) {
        if (errno == ENOENT && (flags & O_CREAT))
            return open(path, flags | O_EXCL, mode);
        return -1;
    }

    struct stat st;
    int fd = -1;
    if (fstat(ref, &st) == 0) {
        if (S_ISREG(st.st_mode)) {
            char proc_path[64];
            snprintf(proc_path, sizeof(proc_path), "/proc/self/fd/%d", ref);
            fd = open(proc_path, flags & ~O_CREAT);
        } else {
            errno = EINVAL;
        }
    }
    int saved = errno;
    close(ref);
    errno = saved;
    return fd;
#else
    errno = ENOSYS;
    return -1;
#endif
}
#endif
