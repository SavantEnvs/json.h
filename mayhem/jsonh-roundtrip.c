/* json.h round-trip harness: json_parse_ex() under an input-chosen flag set, then both writers
 * (json_write_minified / json_write_pretty), json_extract_value(), and a re-parse of the minified text.
 *
 * Input layout: bytes 0-1 (little endian) select the json_parse_flags_e bitset (masked to the defined
 * bits 0x1..0x2000); the remaining bytes are the JSON / JSON5 / simplified-JSON text, copied into an
 * exact-size heap buffer with no trailing NUL so ASan sees any read past the end.
 *
 * Every json.h result (DOM, written text, extracted copy) is a single malloc block, freed with free().
 * No state is kept across inputs. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "../json.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  size_t flags;
  size_t len;
  char *src;
  struct json_parse_result_s result;
  struct json_value_s *value;

  if (size < 2) {
    return -1;
  }
  flags = ((size_t)data[0] | ((size_t)data[1] << 8)) & 0x3fff;
  len = size - 2;

  /* malloc(0) may return NULL; keep a valid pointer so json.h gets a real (empty) buffer. */
  src = (char *)malloc(len ? len : 1);
  if (!src) {
    return 0;
  }
  if (len) {
    memcpy(src, data + 2, len);
  }

  value = json_parse_ex(src, len, flags, 0, 0, &result);
  if (value) {
    size_t min_size = 0, pretty_size = 0;
    void *minified = json_write_minified(value, &min_size);
    void *pretty = json_write_pretty(value, "  ", "\n", &pretty_size);
    struct json_value_s *copy = json_extract_value(value);

    if (minified && min_size > 0) {
      /* The writer's size includes the NUL terminator; re-parse just the text, same flags. */
      struct json_value_s *again = json_parse_ex(minified, min_size - 1, flags, 0, 0, 0);
      free(again);
    }
    if (copy) {
      void *copy_text = json_write_minified(copy, 0);
      free(copy_text);
    }
    free(copy);
    free(pretty);
    free(minified);
    free(value);
  }
  free(src);
  return 0;
}
