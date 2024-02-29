#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    void *ptr;
    size_t ref_count;
} RC;

RC *rc_new() {
    RC *rc = malloc(sizeof(RC));
    rc->ptr = NULL;
    rc->ref_count = 1;
    return rc;
}

void rc_set_str(RC *rc, char *str) {
    rc->ptr = malloc(sizeof(char) * (strlen(str) + 1));
    strcpy(rc->ptr, str);
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

int32_t puts_int(int32_t i) {
    printf("%d\n", i);
    return i;
}

const RC *puts_str(const RC *rc) {
    const char *str = rc->ptr;
    printf("[%s]\n", str);
    return rc;
}
