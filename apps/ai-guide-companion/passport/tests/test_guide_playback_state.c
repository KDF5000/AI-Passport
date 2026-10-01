#include "../main/guide_playback_state.c"
#include <assert.h>
#include <stdio.h>

int main(void)
{
    assert(!guide_playback_queue_drained(false, false));
    assert(!guide_playback_queue_drained(true, false));
    assert(!guide_playback_queue_drained(false, true));
    assert(guide_playback_queue_drained(true, true));

    bool receiving = false;
    size_t length = 42;
    guide_playback_text_start(&receiving, &length);
    assert(receiving);
    assert(length == 0);
    guide_playback_text_stop(&receiving);
    assert(!receiving);

    bool cancelled = false;
    receiving = true;
    guide_playback_cancel(&cancelled, &receiving);
    assert(cancelled);
    assert(!receiving);
    assert(!guide_playback_accept_stream(cancelled));
    guide_playback_restart(&cancelled);
    assert(!cancelled);
    assert(guide_playback_accept_stream(cancelled));

    puts("Guide playback completion tests: PASS");
    return 0;
}
