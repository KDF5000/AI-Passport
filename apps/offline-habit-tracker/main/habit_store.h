#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "habit_model.h"

typedef enum {
    HABIT_STORE_UNAVAILABLE = 0,
    HABIT_STORE_SAVED,
    HABIT_STORE_SAVING,
    HABIT_STORE_ERROR,
} habit_store_state_t;

// Initializes NVS without erasing other namespaces. A valid newest slot replaces
// the supplied default model. Saves run on a worker task and alternate CRC slots.
bool habit_store_init(habit_model_t *model);
bool habit_store_request_save(const habit_model_t *model);
habit_store_state_t habit_store_state(void);
