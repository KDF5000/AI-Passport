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

void guide_playback_cancel(bool *cancelled, bool *receiving)
{
    if (cancelled) *cancelled = true;
    if (receiving) *receiving = false;
}

void guide_playback_restart(bool *cancelled)
{
    if (cancelled) *cancelled = false;
}

bool guide_playback_accept_stream(bool cancelled)
{
    return !cancelled;
}
