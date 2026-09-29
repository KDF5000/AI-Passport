#include <assert.h>
#include <string.h>

#include "habit_photo_format.h"

int main(void)
{
    static const char input[] = "123456789";
    assert(habit_photo_crc32(0, input, 9) == 0xcbf43926U);
    uint32_t first = habit_photo_crc32(0, input, 4);
    assert(habit_photo_crc32(first, input + 4, 5) == 0xcbf43926U);

    habit_photo_manifest_t a;
    habit_photo_manifest_t b;
    habit_photo_manifest_empty(&a);
    assert(habit_photo_manifest_count(&a) == 0);
    assert(habit_photo_manifest_first_free(&a) == 0);
    a.entries[0].valid = 1;
    a.entries[0].crc32 = 123;
    a.generation = 10;
    habit_photo_manifest_finalize(&a);
    assert(habit_photo_manifest_valid(&a));
    assert(habit_photo_manifest_count(&a) == 1);
    assert(habit_photo_manifest_first_free(&a) == 1);
    assert(!habit_photo_manifest_remove(&a, HABIT_PHOTO_MAX_COUNT));
    assert(!habit_photo_manifest_remove(&a, 1));
    assert(habit_photo_manifest_remove(&a, 0));
    assert(habit_photo_manifest_count(&a) == 0);
    assert(a.entries[0].crc32 == 0);
    assert(!habit_photo_manifest_clear(&a));
    a.entries[0].valid = 1;
    a.entries[1].valid = 1;
    assert(habit_photo_manifest_clear(&a));
    assert(habit_photo_manifest_count(&a) == 0);

    a.entries[0].valid = 1;
    a.entries[0].crc32 = 123;
    habit_photo_manifest_finalize(&a);
    b = a;
    b.generation = 11;
    b.entries[1].valid = 1;
    habit_photo_manifest_finalize(&b);
    assert(habit_photo_manifest_newest(&a, true, &b, true) == &b);
    assert(habit_photo_manifest_newest(&a, true, &b, false) == &a);
    b.entries[2].valid = 2;
    habit_photo_manifest_finalize(&b);
    assert(!habit_photo_manifest_valid(&b));

    memset(&a.entries, 0, sizeof(a.entries));
    for (unsigned i = 0; i < HABIT_PHOTO_MAX_COUNT; ++i) {
        a.entries[i].valid = 1;
    }
    habit_photo_manifest_finalize(&a);
    assert(habit_photo_manifest_count(&a) == HABIT_PHOTO_MAX_COUNT);
    assert(habit_photo_manifest_first_free(&a) == -1);
    return 0;
}
