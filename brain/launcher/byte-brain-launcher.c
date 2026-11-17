// byte-brain-launcher: started by launchd as root, it
//   1. lifts the 6 MB jetsam limit iOS 15 gives third-party launch daemons (for this process only),
//   2. drops to the unprivileged `mobile` user for good,
//   3. makes sure the token files exist (created as mobile, mode 600): the brain's API key, and the
//      separate key the Mac uses for push events (step 5, decision 2A),
//   4. execs llama-server with the given arguments plus --api-key-file (the jetsam limit stays across exec).
// Usage: byte-brain-launcher /path/to/llama-server [llama-server args...]
// Decision 2026-11-16 (BUILD_LOG.md, step 4, option 1A).

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <grp.h>
#include <pwd.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

// Private XNU API (sys/kern_memorystatus.h), stable since iOS 10.
#define MEMORYSTATUS_CMD_SET_MEMLIMIT_PROPERTIES 7
#define MEMORYSTATUS_CMD_GET_MEMLIMIT_PROPERTIES 8
typedef struct {
    int32_t memlimit_active;       // MB, -1 = no limit
    uint32_t memlimit_active_attr;
    int32_t memlimit_inactive;     // MB, -1 = no limit
    uint32_t memlimit_inactive_attr;
} memorystatus_memlimit_properties_t;
extern int memorystatus_control(uint32_t command, int32_t pid, uint32_t flags, void *buffer, size_t buffersize);

static const char *RUN_AS = "mobile";
// Shared secret between llama-server and the Byte app, so web pages on the device can't use the brain.
static const char *BRAIN_TOKEN_FILE = "/var/jb/var/mobile/byte/brain.token";
// Shared secret between the Mac's `git shipit` and the app's event listener (port 7420). Separate from the
// brain's, so a leaked Mac token can only make Byte dance.
static const char *EVENTS_TOKEN_FILE = "/var/jb/var/mobile/byte/events.token";
enum { TOKEN_BYTES = 32, TOKEN_HEX = TOKEN_BYTES * 2 };

static void log_line(const char *msg) { fprintf(stderr, "byte-brain-launcher: %s\n", msg); }

static void log_path(const char *path, const char *msg) { fprintf(stderr, "byte-brain-launcher: %s: %s\n", path, msg); }

// Creates the token file at `path` if missing (64 hex chars + newline, mode 600). If it exists, it must be
// ours, regular, and well formed; loose permissions are tightened. Runs as mobile. Returns 0 on success.
static int ensure_token(const char *path, uid_t owner) {
    int fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (fd >= 0) {
        unsigned char raw[TOKEN_BYTES];
        char hex[TOKEN_HEX + 2];
        arc4random_buf(raw, sizeof raw);
        for (int i = 0; i < TOKEN_BYTES; i++) snprintf(hex + i * 2, 3, "%02x", raw[i]);
        hex[TOKEN_HEX] = '\n'; hex[TOKEN_HEX + 1] = '\0';
        int ok = write(fd, hex, TOKEN_HEX + 1) == TOKEN_HEX + 1 && fsync(fd) == 0;
        close(fd);
        if (!ok) { unlink(path); log_path(path, "could not write token file"); return -1; }
        log_path(path, "created a new token");
        return 0;
    }
    if (errno != EEXIST) { log_path(path, strerror(errno)); return -1; }

    fd = open(path, O_RDONLY | O_NOFOLLOW);
    struct stat st;
    if (fd < 0 || fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_uid != owner) {
        if (fd >= 0) close(fd);
        log_path(path, "not a regular file owned by mobile; refusing to start");
        return -1;
    }
    if ((st.st_mode & 0077) != 0 && fchmod(fd, 0600) != 0) { close(fd); log_path(path, "could not tighten permissions"); return -1; }
    char buf[TOKEN_HEX + 2] = {0};
    ssize_t n = read(fd, buf, sizeof buf - 1);
    close(fd);
    if (n < TOKEN_HEX) { log_path(path, "malformed; delete it to regenerate"); return -1; }
    for (int i = 0; i < TOKEN_HEX; i++) {
        char c = buf[i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) { log_path(path, "malformed; delete it to regenerate"); return -1; }
    }
    return 0;
}

#ifndef BYTE_LAUNCHER_NO_MAIN
int main(int argc, char *argv[]) {
    if (argc < 2) { log_line("usage: byte-brain-launcher /path/to/llama-server [args...]"); return 64; }
    if (getuid() != 0) { log_line("must be started as root by launchd"); return 77; }

    // 1. No per-process memory cap for this process. iOS's normal memory-pressure order still
    //    applies: this daemon stays in a low jetsam band, so it is killed before the foreground app.
    memorystatus_memlimit_properties_t limits = { -1, 0, -1, 0 };
    if (memorystatus_control(MEMORYSTATUS_CMD_SET_MEMLIMIT_PROPERTIES, getpid(), 0, &limits, sizeof limits) != 0) {
        fprintf(stderr, "byte-brain-launcher: could not lift memory limit: %s\n", strerror(errno));
        return 71; // without this, llama-server would be killed at 6 MB anyway
    }
    memorystatus_memlimit_properties_t now = {0};
    if (memorystatus_control(MEMORYSTATUS_CMD_GET_MEMLIMIT_PROPERTIES, getpid(), 0, &now, sizeof now) == 0) {
        fprintf(stderr, "byte-brain-launcher: memory limit now active=%d inactive=%d MB (-1 = none)\n",
                now.memlimit_active, now.memlimit_inactive);
    }

    // 2. Drop root permanently: groups, then gid, then uid; then prove root can't come back.
    struct passwd *pw = getpwnam(RUN_AS);
    if (!pw) { log_line("user mobile not found"); return 67; }
    if (initgroups(pw->pw_name, (int)pw->pw_gid) != 0 || setgid(pw->pw_gid) != 0 || setuid(pw->pw_uid) != 0) {
        fprintf(stderr, "byte-brain-launcher: dropping to %s failed: %s\n", RUN_AS, strerror(errno));
        return 71;
    }
    if (setuid(0) == 0 || getuid() == 0 || geteuid() == 0) { log_line("still root after dropping; refusing to run"); return 71; }

    // 3. The tokens, created as mobile so only mobile (and root) can read them. The brain needs its own;
    //    a bad events token only disables push celebrations, so it is logged but doesn't stop the brain.
    if (ensure_token(BRAIN_TOKEN_FILE, pw->pw_uid) != 0) return 78;
    if (ensure_token(EVENTS_TOKEN_FILE, pw->pw_uid) != 0) log_line("push events stay off until the events token is fixed");

    // 4. Become llama-server, adding --api-key-file so the key never appears in `ps`.
    char **args = calloc((size_t)argc + 2, sizeof *args);
    if (!args) { log_line("out of memory"); return 71; }
    for (int i = 1; i < argc; i++) args[i - 1] = argv[i];
    args[argc - 1] = "--api-key-file";
    args[argc] = (char *)BRAIN_TOKEN_FILE;
    args[argc + 1] = NULL;
    execv(args[0], args);
    fprintf(stderr, "byte-brain-launcher: exec %s failed: %s\n", argv[1], strerror(errno));
    return 126;
}
#endif
