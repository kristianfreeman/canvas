#ifndef CANVAS_UTF8_H
#define CANVAS_UTF8_H

#include <stdbool.h>
#include <stddef.h>

/* Length of the well-formed UTF-8 sequence at p (1 to 4), or 0 if it is
   malformed, overlong, a surrogate, above U+10FFFF or truncated. */
size_t utf8_seq(const unsigned char *p, size_t n);

bool utf8_valid(const char *p, size_t n);

/* Append the UTF-8 encoding of a code point (at most 4 bytes) to out and
   return its length. */
size_t utf8_encode(unsigned long cp, unsigned char out[4]);

#endif
