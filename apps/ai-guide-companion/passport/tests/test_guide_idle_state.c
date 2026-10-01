#include "../main/guide_idle_state.c"
#include <assert.h>
#include <stdio.h>

int main(void)
{
    guide_idle_state_t state;
    guide_idle_init(&state, 1000, 30000);
    assert(state.awake);
    assert(!guide_idle_should_sleep(&state, 30999, false));
    assert(guide_idle_should_sleep(&state, 31000, false));
    assert(!state.awake);

    assert(guide_idle_handle_button(&state, 32000, 2,
                                    GUIDE_IDLE_BUTTON_PRESS) ==
           GUIDE_IDLE_BUTTON_WAKE);
    assert(state.awake);
    assert(guide_idle_handle_button(&state, 32100, 2,
                                    GUIDE_IDLE_BUTTON_RELEASE) ==
           GUIDE_IDLE_BUTTON_CONSUME);
    assert(guide_idle_handle_button(&state, 32110, 2,
                                    GUIDE_IDLE_BUTTON_CLICK) ==
           GUIDE_IDLE_BUTTON_CONSUME);
    assert(guide_idle_handle_button(&state, 33000, 2,
                                    GUIDE_IDLE_BUTTON_PRESS) ==
           GUIDE_IDLE_BUTTON_DELIVER);
    assert(guide_idle_handle_button(&state, 33100, 2,
                                    GUIDE_IDLE_BUTTON_CLICK) ==
           GUIDE_IDLE_BUTTON_DELIVER);

    guide_idle_mark_activity(&state, 40000);
    assert(!guide_idle_should_sleep(&state, 69999, false));
    assert(guide_idle_should_sleep(&state, 70000, false));

    guide_idle_init(&state, 0, 30000);
    assert(!guide_idle_should_sleep(&state, 60000, true));
    assert(state.awake);
    assert(guide_idle_should_sleep(&state, 60000, false));

    guide_idle_init(&state, UINT32_MAX - 1000U, 30000);
    assert(!guide_idle_should_sleep(&state, 28998, false));
    assert(guide_idle_should_sleep(&state, 28999, false));

    guide_idle_init(&state, 0, 30000);
    assert(guide_idle_should_sleep(&state, 30000, false));
    assert(guide_idle_handle_button(&state, 30100, 0,
                                    GUIDE_IDLE_BUTTON_PRESS) ==
           GUIDE_IDLE_BUTTON_WAKE);
    assert(guide_idle_handle_button(&state, 31000, 0,
                                    GUIDE_IDLE_BUTTON_LONG) ==
           GUIDE_IDLE_BUTTON_CONSUME);
    assert(guide_idle_handle_button(&state, 31100, 0,
                                    GUIDE_IDLE_BUTTON_RELEASE) ==
           GUIDE_IDLE_BUTTON_CONSUME);
    assert(guide_idle_handle_button(&state, 32000, 0,
                                    GUIDE_IDLE_BUTTON_PRESS) ==
           GUIDE_IDLE_BUTTON_DELIVER);

    puts("Guide idle screen tests: PASS");
    return 0;
}
