#include "guide_playback_state.h"

bool guide_playback_queue_drained(bool playing, bool stream_ending)
{
    return playing && stream_ending;
}

void guide_playback_text_start(bool *receiving, size_t *length)
{
    if (receiving) *receiving = true;
    if (length) *length = 0;
}

void guide_playback_text_stop(bool *receiving)
{
    if (receiving) *receiving = false;
}
