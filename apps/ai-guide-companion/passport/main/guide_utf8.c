#include "guide_utf8.h"

#include <stdbool.h>
#include <string.h>

size_t guide_utf8_complete_prefix(const uint8_t *text, size_t length)
{
    size_t offset = 0;
    if (!text) return 0;
    while (offset < length) {
        uint8_t first = text[offset];
        size_t sequence_length;
        if (first < 0x80) {
            sequence_length = 1;
        } else if (first >= 0xc2 && first <= 0xdf) {
            sequence_length = 2;
        } else if (first >= 0xe0 && first <= 0xef) {
            sequence_length = 3;
        } else if (first >= 0xf0 && first <= 0xf4) {
            sequence_length = 4;
        } else {
            return offset;
        }
        if (sequence_length > length - offset) return offset;
        for (size_t i = 1; i < sequence_length; ++i) {
            if ((text[offset + i] & 0xc0) != 0x80) return offset;
        }
        offset += sequence_length;
    }
    return offset;
}

static size_t decode_codepoint(const uint8_t *text, size_t length,
                               uint32_t *codepoint)
{
    uint8_t first = text[0];
    size_t count = first < 0x80 ? 1 :
                   first <= 0xdf ? 2 :
                   first <= 0xef ? 3 : 4;
    if (count > length) return 0;
    uint32_t value = first & (count == 1 ? 0x7f :
                              count == 2 ? 0x1f :
                              count == 3 ? 0x0f : 0x07);
    for (size_t i = 1; i < count; ++i) {
        value = (value << 6) | (text[i] & 0x3f);
    }
    *codepoint = value;
    return count;
}

static bool supported_codepoint(uint32_t codepoint)
{
    return codepoint == '\n' || codepoint == '\r' || codepoint == '\t' ||
           (codepoint >= 0x20 && codepoint <= 0x7e) ||
           (codepoint >= 0xa0 && codepoint <= 0xff) ||
           (codepoint >= 0x2000 && codepoint <= 0x206f) ||
           (codepoint >= 0x3000 && codepoint <= 0x303f) ||
           (codepoint >= 0x4e00 && codepoint <= 0x9fff) ||
           (codepoint >= 0xff00 && codepoint <= 0xffef);
}

size_t guide_utf8_sanitize(char *destination, size_t capacity,
                           const uint8_t *source, size_t length)
{
    if (!destination || capacity == 0) return 0;
    size_t source_offset = 0;
    size_t destination_offset = 0;
    size_t complete = guide_utf8_complete_prefix(source, length);
    while (source_offset < complete) {
        uint32_t codepoint;
        size_t count = decode_codepoint(source + source_offset,
                                        complete - source_offset, &codepoint);
        if (count == 0) break;
        source_offset += count;
        if (codepoint >= 0xfe00 && codepoint <= 0xfe0f) continue;
        if (!supported_codepoint(codepoint)) {
            if (destination_offset > 0 &&
                destination[destination_offset - 1] == '?') {
                continue;
            }
            if (destination_offset + 1 >= capacity) break;
            destination[destination_offset++] = '?';
            continue;
        }
        if (destination_offset + count >= capacity) break;
        memcpy(destination + destination_offset,
               source + source_offset - count, count);
        destination_offset += count;
    }
    destination[destination_offset] = '\0';
    return destination_offset;
}
