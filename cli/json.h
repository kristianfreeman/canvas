#ifndef CANVAS_JSON_H
#define CANVAS_JSON_H

#include "util.h"

#include <stdbool.h>

/* Append s as a quoted JSON string. Malformed UTF-8 becomes U+FFFD, so the
   output is always valid JSON. */
void json_str(Buf *b, const char *s, size_t n);
void json_cstr(Buf *b, const char *s);
/* Append `,"key":`. Requests always start with "cmd", so every later
   member needs the comma. */
void json_key(Buf *b, const char *key);

/* Validate a single JSON value with optional surrounding whitespace and
   append it to out without insignificant whitespace, so it fits on one
   NDJSON line. On failure out may hold a partial value. */
bool json_minify(Span in, Buf *out);

/* Iterates the members of an object or the elements of an array. The
   spans point into the input; keys are the raw text between the quotes. */
typedef struct {
    const char *p;
    const char *end;
    char close;
    bool first;
} JIter;

bool jiter_begin(JIter *it, Span s, char open);
/* 1: an item was read, 0: end of the container, -1: malformed. */
int jiter_member(JIter *it, Span *key, Span *val);
int jiter_element(JIter *it, Span *val);

/* The raw text of a top-level member of the object in obj. */
bool json_member(Span obj, const char *key, Span *val);
/* Like json_member, but the value must be a string; returns the raw text
   between its quotes. */
bool json_string_member(Span obj, const char *key, Span *content);
/* Decode a quoted JSON string (escapes included) into UTF-8. */
bool json_decode_string(Span quoted, Buf *out);

#endif
