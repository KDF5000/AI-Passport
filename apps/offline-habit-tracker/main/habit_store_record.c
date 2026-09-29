#include "habit_store_record.h"

#include <stddef.h>
#include <string.h>

uint32_t habit_store_crc32(const void *data, size_t length)
{
    const uint8_t *bytes = data;
    uint32_t crc = 0xFFFFFFFFU;
    for (size_t i = 0; i < length; ++i) {
        crc ^= bytes[i];
        for (unsigned bit = 0; bit < 8U; ++bit) {
            crc = (crc >> 1) ^ (0xEDB88320U & (uint32_t)-(int32_t)(crc & 1U));
        }
    }
    return ~crc;
}

void habit_store_record_pack(habit_store_record_t *record,
                             const habit_model_t *model, uint32_t sequence)
{
    memset(record, 0, sizeof(*record));
    record->magic = HABIT_STORE_MAGIC;
    record->schema = HABIT_STORE_SCHEMA;
    record->size = sizeof(*record);
    record->sequence = sequence;
    record->model = *model;
    record->crc32 = habit_store_crc32(record, offsetof(habit_store_record_t, crc32));
}

bool habit_store_record_valid(const habit_store_record_t *record, size_t length)
{
    return record && length == sizeof(*record) &&
           record->magic == HABIT_STORE_MAGIC &&
           record->schema == HABIT_STORE_SCHEMA &&
           record->size == sizeof(*record) &&
           record->crc32 == habit_store_crc32(record, offsetof(habit_store_record_t, crc32)) &&
           habit_model_is_sane(&record->model);
}

const habit_store_record_t *habit_store_record_newest(const habit_store_record_t *a,
                                                       bool a_valid,
                                                       const habit_store_record_t *b,
                                                       bool b_valid)
{
    if (!a_valid) return b_valid ? b : NULL;
    if (!b_valid) return a;
    return (int32_t)(a->sequence - b->sequence) > 0 ? a : b;
}
