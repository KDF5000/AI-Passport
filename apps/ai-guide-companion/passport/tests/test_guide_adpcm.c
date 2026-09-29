#include "../main/guide_adpcm.c"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    int16_t input[321];
    for (size_t i = 0; i < 321; ++i) {
        int period = (int)(i % 64);
        input[i] = (int16_t)((period < 32 ? period : 63 - period) * 500 - 8000);
    }

    uint8_t encoded[GUIDE_ADPCM_HEADER_BYTES + 160];
    int16_t decoded[321];
    size_t bytes = guide_adpcm_encode_block(input, 320, encoded, sizeof(encoded));
    assert(bytes == 164);
    size_t samples = guide_adpcm_decode_block(encoded, bytes, decoded, 321);
    assert(samples == 321); // A padded final nibble is decoded by design.
    assert(decoded[0] == input[0]);

    long total_error = 0;
    for (size_t i = 0; i < 320; ++i) total_error += labs((long)input[i] - decoded[i]);
    assert(total_error / 320 < 700);
    assert(guide_adpcm_encode_block(NULL, 1, encoded, sizeof(encoded)) == 0);
    assert(guide_adpcm_decode_block(encoded, 3, decoded, 321) == 0);
    puts("Guide IMA-ADPCM tests: PASS");
    return 0;
}
