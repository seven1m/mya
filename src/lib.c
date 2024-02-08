#include <stdint.h>
#include <stdio.h>

int32_t puts_int(int32_t a) {
  printf("%d\n", a);
  return a;
}

const char *puts_str(const char *a) {
  printf("%s\n", a);
  return a;
}
