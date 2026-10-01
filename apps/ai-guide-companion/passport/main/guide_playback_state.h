#pragma once

#include <stdbool.h>
#include <stddef.h>

// A queue receive timeout means every queued audio packet has been consumed.
// Finish only after the protocol has also announced the end of the stream.
bool guide_playback_queue_drained(bool playing, bool stream_ending);
void guide_playback_text_start(bool *receiving, size_t *length);
void guide_playback_text_stop(bool *receiving);
void guide_playback_cancel(bool *cancelled, bool *receiving);
void guide_playback_restart(bool *cancelled);
bool guide_playback_accept_stream(bool cancelled);
