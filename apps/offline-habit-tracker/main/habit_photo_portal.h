#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

typedef enum {
    HABIT_PHOTO_PORTAL_OFF = 0,
    HABIT_PHOTO_PORTAL_STARTING,
    HABIT_PHOTO_PORTAL_READY,
    HABIT_PHOTO_PORTAL_RECEIVING,
    HABIT_PHOTO_PORTAL_DELETING,
    HABIT_PHOTO_PORTAL_COMPLETE,
    HABIT_PHOTO_PORTAL_ERROR,
} habit_photo_portal_state_t;

typedef struct {
    habit_photo_portal_state_t state;
    uint32_t received;
    uint32_t total;
    unsigned photo_count;
    int error;
} habit_photo_portal_status_t;

esp_err_t habit_photo_portal_start(void);
esp_err_t habit_photo_portal_stop(void);
bool habit_photo_portal_is_running(void);
const char *habit_photo_portal_ssid(void);
const char *habit_photo_portal_password(void);
habit_photo_portal_status_t habit_photo_portal_status(void);
