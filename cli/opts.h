#ifndef CANVAS_OPTS_H
#define CANVAS_OPTS_H

#include "args.h"
#include "util.h"

#include <stdbool.h>

typedef struct Opts Opts;
typedef struct Opt Opt;

typedef enum { RANGE_ANY, RANGE_POSITIVE, RANGE_NONNEG, RANGE_UNIT } Range;

typedef void (*ApplyFn)(Opts *o, const Opt *spec, const char *value);

/* One command-line option. Tables end with a zeroed entry. */
struct Opt {
    const char *flag;
    /* The request member it sets, if any. */
    const char *key;
    ApplyFn apply;
    /* For enums: the allowed values, separated by '|'. */
    const char *choices;
    Range range;
    bool has_value;
};

enum { MAX_MEMBERS = 48 };

typedef struct {
    const char *key;
    char *json;
} Member;

/* Parsed options. Request members are kept as rendered JSON in the order
   first given; giving an option again replaces its value. */
struct Opts {
    Member members[MAX_MEMBERS];
    int nmembers;
    const char *file;
    const char *id;
    const char *kind;
    const char *data;
    double timeout;
    int focus; /* -1 unset, 0 off, 1 on */
    bool wait;
    bool stream;
    bool trace;
    bool all;
    bool has_timeout;
};

extern const Opt content_opts[];
extern const Opt placement_opts[];
extern const Opt id_opts[];
extern const Opt update_opts[];
extern const Opt hide_opts[];

void opts_init(Opts *o);
/* Parse the remaining arguments against a NULL-terminated list of tables.
   With allow_file, one positional argument becomes o->file. */
void opts_parse(Opts *o, Args *a, const Opt *const *tables, bool allow_file);
void opts_set(Opts *o, const char *key, char *json);
void opts_set_str(Opts *o, const char *key, const char *value);
bool opts_has(const Opts *o, const char *key);
/* Append every member as `,"key":value`. */
void opts_write(const Opts *o, Buf *b);

/* A finite decimal number: digits, '.', exponent, sign. */
bool parse_number(const char *s, double *out);
/* The shortest text that reads back as v. */
void format_number(double v, Buf *b);

#endif
