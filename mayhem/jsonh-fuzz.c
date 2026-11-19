/* Ported from the legacy mayhemheroes/json.h fuzz/jsonh-fuzz.c: json_parse() with the default flags.
 * The parsed DOM is one malloc block (json.h contract), so it is released with a single free(). */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../json.h"

int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size)
{
    struct json_value_s *v = json_parse(Data, Size);
    free(v);
    return 0;
}
