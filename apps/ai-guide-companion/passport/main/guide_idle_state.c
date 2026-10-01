#include "guide_idle_state.h"

#include <stddef.h>

void guide_idle_init(guide_idle_state_t *state, uint32_t now_ms,
                     uint32_t timeout_ms)
{
    if (!state) return;
    state->timeout_ms = timeout_ms;
    state->last_activity_ms = now_ms;
    state->wake_button = -1;
    state->awake = true;
    state->wake_button_was_long = false;
}

void guide_idle_mark_activity(guide_idle_state_t *state, uint32_t now_ms)
{
    if (!state) return;
    state->last_activity_ms = now_ms;
}

bool guide_idle_should_sleep(guide_idle_state_t *state, uint32_t now_ms,
                             bool interaction_active)
{
    if (!state || !state->awake || interaction_active ||
        state->timeout_ms == 0) {
        return false;
    }
    if ((uint32_t)(now_ms - state->last_activity_ms) < state->timeout_ms) {
        return false;
    }
    state->awake = false;
    state->wake_button = -1;
    state->wake_button_was_long = false;
    return true;
}

guide_idle_button_result_t guide_idle_handle_button(
    guide_idle_state_t *state, uint32_t now_ms, int button,
    guide_idle_button_event_t event)
{
    if (!state) return GUIDE_IDLE_BUTTON_DELIVER;
    state->last_activity_ms = now_ms;

    if (!state->awake) {
        state->awake = true;
        state->wake_button = (int8_t)button;
        state->wake_button_was_long = false;
        return GUIDE_IDLE_BUTTON_WAKE;
    }

    if (state->wake_button != button) return GUIDE_IDLE_BUTTON_DELIVER;

    if (event == GUIDE_IDLE_BUTTON_LONG) {
        state->wake_button_was_long = true;
        return GUIDE_IDLE_BUTTON_CONSUME;
    }
    if (event == GUIDE_IDLE_BUTTON_RELEASE) {
        if (state->wake_button_was_long) state->wake_button = -1;
        return GUIDE_IDLE_BUTTON_CONSUME;
    }
    if (event == GUIDE_IDLE_BUTTON_CLICK ||
        event == GUIDE_IDLE_BUTTON_DOUBLE) {
        state->wake_button = -1;
        return GUIDE_IDLE_BUTTON_CONSUME;
    }
    return GUIDE_IDLE_BUTTON_CONSUME;
}
