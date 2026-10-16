#include "text.h"

#include "json.h"
#include "util.h"

#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

enum { READ_CHUNK = 65536 };

static Span read_fd(int fd, const char *label) {
    Buf b = {0};
    for (;;) {
        buf_reserve(&b, READ_CHUNK);
        ssize_t n = read(fd, b.data + b.len, READ_CHUNK);
        if (n > 0) {
            b.len += (size_t)n;
            continue;
        }
        if (n == 0) {
            break;
        }
        if (errno != EINTR) {
            fail("cannot read %s: %s", label, strerror(errno));
        }
    }
    return buf_span(&b);
}

static Span map_file(int fd, off_t size, const char *path) {
    if (size == 0) {
        return (Span){"", 0};
    }
    void *p = mmap(NULL, (size_t)size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (p == MAP_FAILED) {
        fail("cannot read %s: %s", path, strerror(errno));
    }
    return (Span){p, (size_t)size};
}

Span text_read_file(const char *path) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        fail("cannot read %s: %s", path, strerror(errno));
    }
    struct stat st;
    if (fstat(fd, &st) != 0) {
        fail("cannot read %s: %s", path, strerror(errno));
    }
    if (S_ISDIR(st.st_mode)) {
        fail("cannot read %s: %s", path, strerror(EISDIR));
    }
    Span text = S_ISREG(st.st_mode) ? map_file(fd, st.st_size, path) : read_fd(fd, path);
    (void)close(fd);
    return text;
}

Span text_read_stdin(void) { return read_fd(STDIN_FILENO, "stdin"); }

static bool looks_like_json(const char *s) {
    if (s[0] == '\0') {
        return false;
    }
    if (strchr("{[\"-", s[0]) != NULL || (s[0] >= '0' && s[0] <= '9')) {
        return true;
    }
    return strcmp(s, "true") == 0 || strcmp(s, "false") == 0 || strcmp(s, "null") == 0;
}

void load_json_arg(const char *arg, const char *label, Buf *out) {
    Span text;
    if (strcmp(arg, "-") == 0) {
        text = text_read_stdin();
    } else if (looks_like_json(arg)) {
        text = span_of(arg);
    } else {
        text = text_read_file(arg);
    }
    if (!json_minify(text, out)) {
        usage_fail("%s is not valid JSON", label);
    }
}
