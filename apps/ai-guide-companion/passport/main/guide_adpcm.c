#include "guide_adpcm.h"

#include <limits.h>

static const int s_step_table[89] = {
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
    34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130,
    143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449,
    494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411,
    1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026,
    4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442,
    11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623,
    27086, 29794, 32767,
};

static const int s_index_table[16] = {
    -1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8,
};

static int clamp_int(int value, int low, int high)
{
    if (value < low) return low;
    if (value > high) return high;
    return value;
}

static uint8_t encode_nibble(int sample, int *predictor, int *index)
{
    int step = s_step_table[*index];
    int diff = sample - *predictor;
    uint8_t code = 0;
    if (diff < 0) {
        code = 8;
        diff = -diff;
    }

    int delta = step >> 3;
    if (diff >= step) {
        code |= 4;
        diff -= step;
        delta += step;
    }
    step >>= 1;
    if (diff >= step) {
        code |= 2;
        diff -= step;
        delta += step;
    }
    step >>= 1;
    if (diff >= step) {
        code |= 1;
        delta += step;
    }

    *predictor += (code & 8) ? -delta : delta;
    *predictor = clamp_int(*predictor, INT16_MIN, INT16_MAX);
    *index = clamp_int(*index + s_index_table[code], 0, 88);
    return code;
}

static int16_t decode_nibble(uint8_t code, int *predictor, int *index)
{
    int step = s_step_table[*index];
    int delta = step >> 3;
    if (code & 4) delta += step;
    if (code & 2) delta += step >> 1;
    if (code & 1) delta += step >> 2;
    *predictor += (code & 8) ? -delta : delta;
    *predictor = clamp_int(*predictor, INT16_MIN, INT16_MAX);
    *index = clamp_int(*index + s_index_table[code & 0x0f], 0, 88);
    return (int16_t)*predictor;
}

size_t guide_adpcm_encoded_size(size_t sample_count)
{
    return sample_count == 0 ? 0 :
           GUIDE_ADPCM_HEADER_BYTES + (sample_count - 1 + 1) / 2;
}

size_t guide_adpcm_encode_block(const int16_t *pcm, size_t sample_count,
                                uint8_t *output, size_t output_capacity)
{
    size_t required = guide_adpcm_encoded_size(sample_count);
    if (!pcm || !output || sample_count == 0 || output_capacity < required) return 0;

    int predictor = pcm[0];
    int index = 0;
    output[0] = (uint8_t)(predictor & 0xff);
    output[1] = (uint8_t)(((uint16_t)predictor >> 8) & 0xff);
    output[2] = (uint8_t)index;
    output[3] = 0;

    uint8_t byte = 0;
    size_t out = GUIDE_ADPCM_HEADER_BYTES;
    for (size_t i = 1; i < sample_count; ++i) {
        uint8_t code = encode_nibble(pcm[i], &predictor, &index);
        if (i & 1U) {
            byte = code;
        } else {
            output[out++] = (uint8_t)(byte | (code << 4));
        }
    }
    if ((sample_count - 1) & 1U) output[out++] = byte;
    return out;
}

size_t guide_adpcm_decode_block(const uint8_t *input, size_t input_size,
                                int16_t *pcm, size_t pcm_capacity)
{
    if (!input || !pcm || input_size < GUIDE_ADPCM_HEADER_BYTES ||
        input[2] > 88) return 0;

    size_t samples = 1 + (input_size - GUIDE_ADPCM_HEADER_BYTES) * 2;
    if (pcm_capacity < samples) return 0;
    int predictor = (int16_t)((uint16_t)input[0] | ((uint16_t)input[1] << 8));
    int index = input[2];
    pcm[0] = (int16_t)predictor;
    size_t out = 1;
    for (size_t i = GUIDE_ADPCM_HEADER_BYTES; i < input_size; ++i) {
        pcm[out++] = decode_nibble(input[i] & 0x0f, &predictor, &index);
        pcm[out++] = decode_nibble(input[i] >> 4, &predictor, &index);
    }
    return out;
}
