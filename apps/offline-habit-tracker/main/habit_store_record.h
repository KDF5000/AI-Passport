#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "habit_model.h"

#define HABIT_STORE_MAGIC 0x48414254U
#define HABIT_STORE_SCHEMA 1U

typedef struct {
    uint32_t magic;
    uint16_t schema;
    uint16_t size;
    uint32_t sequence;
    habit_model_t model;
    uint32_t crc32;
} habit_store_record_t;

uint32_t habit_store_crc32(const void *data, size_t length);
void habit_store_record_pack(habit_store_record_t *record,
                             const habit_model_t *model, uint32_t sequence);
bool habit_store_record_valid(const habit_store_record_t *record, size_t length);
const habit_store_record_t *habit_store_record_newest(const habit_store_record_t *a,
                                                       bool a_valid,
                                                       const habit_store_record_t *b,
                                                       bool b_valid);
