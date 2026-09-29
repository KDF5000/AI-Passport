#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"
#include "habit_photo_format.h"

bool habit_photo_store_init(void);
unsigned habit_photo_store_count(void);
int habit_photo_store_first_free(void);
bool habit_photo_store_slot_valid(unsigned slot);
uint16_t habit_photo_store_valid_mask(void);

esp_err_t habit_photo_store_begin(unsigned slot);
esp_err_t habit_photo_store_write(unsigned slot, size_t offset,
                                  const void *data, size_t length);
esp_err_t habit_photo_store_commit(unsigned slot, uint32_t expected_crc);
void habit_photo_store_abort(void);
esp_err_t habit_photo_store_delete(unsigned slot);
esp_err_t habit_photo_store_clear(void);

const uint8_t *habit_photo_store_map(unsigned slot);
void habit_photo_store_unmap(void);
