// Mac unit tests for ensure_token() in byte-brain-launcher.c. Run: brain/test.sh
#define BYTE_LAUNCHER_NO_MAIN
#include "byte-brain-launcher.c"
static char token_path[1024];
static int ensure(uid_t owner) { return ensure_token(token_path, owner); }

static int failures = 0, count = 0;
#define CHECK(cond, name) do { count++; if (!(cond)) { failures++; printf("FAIL %s (line %d)\n", name, __LINE__); } } while (0)

static void write_file(const char *s, mode_t mode) {
    unlink(token_path);
    int fd = open(token_path, O_WRONLY | O_CREAT | O_TRUNC, mode);
    if (write(fd, s, strlen(s)) < 0) perror("write");
    close(fd); chmod(token_path, mode);
}
static mode_t mode_of(void) { struct stat st; stat(token_path, &st); return st.st_mode & 0777; }
static ssize_t read_all(char *buf, size_t n) { int fd = open(token_path, O_RDONLY); ssize_t r = read(fd, buf, n); close(fd); return r; }

int main(void) {
    char dir[] = "/tmp/byte-token-test-XXXXXX";
    if (!mkdtemp(dir)) { perror("mkdtemp"); return 1; }
    snprintf(token_path, sizeof token_path, "%s/brain.token", dir);
    uid_t me = getuid();
    char buf[256], first[256];

    // new token
    CHECK(ensure(me) == 0, "creates a missing token");
    CHECK(mode_of() == 0600, "new token is mode 600");
    ssize_t n = read_all(buf, sizeof buf); buf[n > 0 ? n : 0] = 0;
    CHECK(n == 65 && buf[64] == '\n', "new token is 64 chars + newline");
    int hex = 1; for (int i = 0; i < 64; i++) if (!strchr("0123456789abcdef", buf[i])) hex = 0;
    CHECK(hex, "new token is lowercase hex");
    memcpy(first, buf, sizeof first);

    // existing valid token is kept
    CHECK(ensure(me) == 0, "existing valid token accepted");
    n = read_all(buf, sizeof buf); buf[n > 0 ? n : 0] = 0;
    CHECK(strcmp(buf, first) == 0, "existing token not regenerated");

    // a second token is different (randomness)
    unlink(token_path); ensure(me);
    n = read_all(buf, sizeof buf); buf[n > 0 ? n : 0] = 0;
    CHECK(strcmp(buf, first) != 0, "new tokens differ");

    // loose permissions are tightened
    chmod(token_path, 0644);
    CHECK(ensure(me) == 0 && mode_of() == 0600, "mode 644 tightened to 600");

    // malformed contents are refused
    write_file("short\n", 0600);
    CHECK(ensure(me) != 0, "short token refused");
    write_file("ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ\n", 0600);
    CHECK(ensure(me) != 0, "non-hex token refused");
    write_file("", 0600);
    CHECK(ensure(me) != 0, "empty token refused");

    // wrong owner is refused
    unlink(token_path); ensure(me);
    CHECK(ensure(me + 1) != 0, "token owned by someone else refused");

    // a symlink is never followed (an attacker can't point it at another file)
    unlink(token_path);
    char target[1100]; snprintf(target, sizeof target, "%s/elsewhere", dir);
    int fd = open(target, O_WRONLY | O_CREAT, 0644); close(fd);
    if (symlink(target, token_path) != 0) perror("symlink");
    CHECK(ensure(me) != 0, "symlinked token refused");
    struct stat st; stat(target, &st);
    CHECK(st.st_size == 0, "symlink target left untouched");

    // a directory in its place is refused
    unlink(token_path); mkdir(token_path, 0700);
    CHECK(ensure(me) != 0, "directory refused");
    rmdir(token_path); unlink(target);

    // two token files (brain and events) are independent: different secrets, neither touches the other
    char brain[1100], events[1100], b1[256] = {0}, e1[256] = {0}, b2[256] = {0};
    snprintf(brain, sizeof brain, "%s/brain.token", dir);
    snprintf(events, sizeof events, "%s/events.token", dir);
    CHECK(ensure_token(brain, me) == 0 && ensure_token(events, me) == 0, "brain and events tokens both created");
    fd = open(brain, O_RDONLY); if (read(fd, b1, 65) < 0) perror("read"); close(fd);
    fd = open(events, O_RDONLY); if (read(fd, e1, 65) < 0) perror("read"); close(fd);
    CHECK(strlen(b1) == 65 && strlen(e1) == 65 && strcmp(b1, e1) != 0, "brain and events tokens differ");
    unlink(events);
    CHECK(ensure_token(events, me) == 0, "events token recreated on its own");
    fd = open(brain, O_RDONLY); if (read(fd, b2, 65) < 0) perror("read"); close(fd);
    CHECK(strcmp(b1, b2) == 0, "recreating the events token leaves the brain token alone");
    unlink(brain); unlink(events); rmdir(dir);

    printf(failures ? "%d of %d launcher checks FAILED\n" : "OK: %d launcher checks passed\n", failures ? failures : count, count);
    return failures != 0;
}
