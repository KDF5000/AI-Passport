#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define HABIT_PHOTO_WIDTH 240U
#define HABIT_PHOTO_HEIGHT 320U
#define HABIT_PHOTO_BYTES (HABIT_PHOTO_WIDTH * HABIT_PHOTO_HEIGHT * 2U)
#define HABIT_PHOTO_MAX_COUNT 13U
#define HABIT_PHOTO_MAGIC 0x4850484FU
#define HABIT_PHOTO_SCHEMA 1U

typedef struct {
    uint32_t crc32;
    uint8_t valid;
    uint8_t reserved[3];
} habit_photo_entry_t;

typedef struct {
    uint32_t magic;
    uint16_t schema;
    uint16_t size;
    uint32_t generation;
    habit_photo_entry_t entries[HABIT_PHOTO_MAX_COUNT];
    uint32_t crc32;
} habit_photo_manifest_t;

uint32_t habit_photo_crc32(uint32_t seed, const void *data, size_t length);
void habit_photo_manifest_empty(habit_photo_manifest_t *manifest);
void habit_photo_manifest_finalize(habit_photo_manifest_t *manifest);
bool habit_photo_manifest_valid(const habit_photo_manifest_t *manifest);
const habit_photo_manifest_t *habit_photo_manifest_newest(
    const habit_photo_manifest_t *a, bool a_valid,
    const habit_photo_manifest_t *b, bool b_valid);
unsigned habit_photo_manifest_count(const habit_photo_manifest_t *manifest);
int habit_photo_manifest_first_free(const habit_photo_manifest_t *manifest);
bool habit_photo_manifest_remove(habit_photo_manifest_t *manifest,
                                 unsigned slot);
bool habit_photo_manifest_clear(habit_photo_manifest_t *manifest);
