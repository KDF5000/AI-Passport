#pragma once

#include <stddef.h>
#include <stdint.h>

// Independent IMA-ADPCM blocks. Header:
// predictor int16 little-endian, step index uint8, reserved uint8.
#define GUIDE_ADPCM_HEADER_BYTES 4

size_t guide_adpcm_encoded_size(size_t sample_count);

// Returns encoded bytes, or 0 when output is too small or input is invalid.
size_t guide_adpcm_encode_block(const int16_t *pcm, size_t sample_count,
                                uint8_t *output, size_t output_capacity);

// Returns decoded sample count, or 0 for a malformed block / small output.
size_t guide_adpcm_decode_block(const uint8_t *input, size_t input_size,
                                int16_t *pcm, size_t pcm_capacity);
