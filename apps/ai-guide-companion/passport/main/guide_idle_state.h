#pragma once

#include <stdbool.h>
#include <stdint.h>

typedef enum {
    GUIDE_IDLE_BUTTON_PRESS = 0,
    GUIDE_IDLE_BUTTON_RELEASE,
    GUIDE_IDLE_BUTTON_CLICK,
    GUIDE_IDLE_BUTTON_DOUBLE,
    GUIDE_IDLE_BUTTON_LONG,
} guide_idle_button_event_t;

typedef enum {
    GUIDE_IDLE_BUTTON_DELIVER = 0,
    GUIDE_IDLE_BUTTON_CONSUME,
    GUIDE_IDLE_BUTTON_WAKE,
} guide_idle_button_result_t;

typedef struct {
    uint32_t timeout_ms;
    uint32_t last_activity_ms;
    int8_t wake_button;
    bool awake;
    bool wake_button_was_long;
} guide_idle_state_t;

void guide_idle_init(guide_idle_state_t *state, uint32_t now_ms,
                     uint32_t timeout_ms);
void guide_idle_mark_activity(guide_idle_state_t *state, uint32_t now_ms);
bool guide_idle_should_sleep(guide_idle_state_t *state, uint32_t now_ms,
                             bool interaction_active);
guide_idle_button_result_t guide_idle_handle_button(
    guide_idle_state_t *state, uint32_t now_ms, int button,
    guide_idle_button_event_t event);
