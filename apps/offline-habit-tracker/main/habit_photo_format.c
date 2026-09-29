#include "habit_photo_format.h"

#include <stddef.h>
#include <string.h>

uint32_t habit_photo_crc32(uint32_t seed, const void *data, size_t length)
{
    const uint8_t *bytes = data;
    uint32_t crc = ~seed;
    for (size_t i = 0; i < length; ++i) {
        crc ^= bytes[i];
        for (unsigned bit = 0; bit < 8U; ++bit) {
            crc = (crc >> 1) ^ (0xEDB88320U & (uint32_t)-(int32_t)(crc & 1U));
        }
    }
    return ~crc;
}

void habit_photo_manifest_empty(habit_photo_manifest_t *manifest)
{
    memset(manifest, 0, sizeof(*manifest));
    manifest->magic = HABIT_PHOTO_MAGIC;
    manifest->schema = HABIT_PHOTO_SCHEMA;
    manifest->size = sizeof(*manifest);
}

void habit_photo_manifest_finalize(habit_photo_manifest_t *manifest)
{
    manifest->magic = HABIT_PHOTO_MAGIC;
    manifest->schema = HABIT_PHOTO_SCHEMA;
    manifest->size = sizeof(*manifest);
    manifest->crc32 = habit_photo_crc32(
        0, manifest, offsetof(habit_photo_manifest_t, crc32));
}

bool habit_photo_manifest_valid(const habit_photo_manifest_t *manifest)
{
    if (!manifest || manifest->magic != HABIT_PHOTO_MAGIC ||
        manifest->schema != HABIT_PHOTO_SCHEMA ||
        manifest->size != sizeof(*manifest) ||
        manifest->crc32 != habit_photo_crc32(
            0, manifest, offsetof(habit_photo_manifest_t, crc32))) {
        return false;
    }
    for (unsigned i = 0; i < HABIT_PHOTO_MAX_COUNT; ++i) {
        if (manifest->entries[i].valid > 1U) return false;
    }
    return true;
}

const habit_photo_manifest_t *habit_photo_manifest_newest(
    const habit_photo_manifest_t *a, bool a_valid,
    const habit_photo_manifest_t *b, bool b_valid)
{
    if (!a_valid) return b_valid ? b : NULL;
    if (!b_valid) return a;
    return (int32_t)(a->generation - b->generation) > 0 ? a : b;
}

unsigned habit_photo_manifest_count(const habit_photo_manifest_t *manifest)
{
    unsigned count = 0;
    if (!manifest) return 0;
    for (unsigned i = 0; i < HABIT_PHOTO_MAX_COUNT; ++i) {
        if (manifest->entries[i].valid) count++;
    }
    return count;
}

int habit_photo_manifest_first_free(const habit_photo_manifest_t *manifest)
{
    if (!manifest) return -1;
    for (unsigned i = 0; i < HABIT_PHOTO_MAX_COUNT; ++i) {
        if (!manifest->entries[i].valid) return (int)i;
    }
    return -1;
}

bool habit_photo_manifest_remove(habit_photo_manifest_t *manifest,
                                 unsigned slot)
{
    if (!manifest || slot >= HABIT_PHOTO_MAX_COUNT ||
        !manifest->entries[slot].valid) {
        return false;
    }
    memset(&manifest->entries[slot], 0, sizeof(manifest->entries[slot]));
    return true;
}

bool habit_photo_manifest_clear(habit_photo_manifest_t *manifest)
{
    if (!manifest || habit_photo_manifest_count(manifest) == 0) return false;
    memset(manifest->entries, 0, sizeof(manifest->entries));
    return true;
}
