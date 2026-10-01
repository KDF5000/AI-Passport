#pragma once

#include <stddef.h>
#include <stdint.h>

size_t guide_utf8_complete_prefix(const uint8_t *text, size_t length);
size_t guide_utf8_sanitize(char *destination, size_t capacity,
                           const uint8_t *source, size_t length);
