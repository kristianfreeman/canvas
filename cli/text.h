#ifndef CANVAS_TEXT_H
#define CANVAS_TEXT_H

#include "util.h"

/* A whole file, mapped when it's a regular file. Exits 1 with
   `cannot read <path>: <reason>` on failure. */
Span text_read_file(const char *path);
/* All of stdin. */
Span text_read_stdin(void);

/* Append the minified JSON named by an argument that follows the --data
   rule: `-` reads stdin; text starting with `{`, `[`, `"`, a digit or `-`,
   or exactly true, false or null, is JSON; anything else is a file path.
   Invalid JSON is a usage error: `<label> is not valid JSON`. */
void load_json_arg(const char *arg, const char *label, Buf *out);

#endif
