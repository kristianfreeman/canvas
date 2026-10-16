#include "args.h"

#include "util.h"

#include <stddef.h>

const char *args_next(Args *a) {
    if (a->i >= a->argc) {
        return NULL;
    }
    return a->argv[a->i++];
}

const char *args_value(Args *a, const char *flag) {
    const char *value = args_next(a);
    if (value == NULL) {
        usage_fail("%s needs a value", flag);
    }
    return value;
}

bool args_is_flag(const char *arg) {
    if (arg[0] != '-' || arg[1] == '\0') {
        return false;
    }
    return !(arg[1] >= '0' && arg[1] <= '9');
}
