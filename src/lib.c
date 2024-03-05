#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    void *ptr;
    size_t size;
    size_t ref_count;
} RC;

void rc_set_str(RC *rc, char *str, size_t size) {
    rc->ptr = malloc(sizeof(char) * (size + 1));
    memcpy(rc->ptr, str, size + 1);
}

void rc_take(RC *rc) {
    rc->ref_count++;
}

void rc_drop(RC *rc) {
    if (--rc->ref_count == 0) {
        free(rc->ptr);
        rc->ptr = (void *)0xdeadbeef;
        free(rc);
    }
}

int32_t array_first_integer(RC *rc) {
    if (rc->size == 0) {
        return 0; // FIXME
    }
    int32_t *ary = rc->ptr;
    return ary[0];
}

RC *array_first_pointer(RC *rc) {
    if (rc->size == 0) {
        return 0; // FIXME
    }
    RC **ary = rc->ptr;
    return ary[0];
}

int32_t array_last_integer(RC *rc) {
    if (rc->size == 0) {
        return 0; // FIXME
    }
    int32_t *ary = rc->ptr;
    return ary[rc->size - 1];
}

RC *array_last_pointer(RC *rc) {
    if (rc->size == 0) {
        return 0; // FIXME
    }
    RC **ary = rc->ptr;
    return ary[rc->size - 1];
}

int32_t puts_int(int32_t i) {
    return printf("%d\n", i);
}

int32_t puts_str(const RC *rc) {
    const char *str = rc->ptr;
    return printf("%s\n", str);
}
