#include <assert.h>
#include <string.h>

#include "habit_model.h"
#include "habit_store_record.h"

static void expect_date(int32_t day, int year, int month, int date)
{
    habit_date_t actual = habit_day_to_date(day);
    assert(actual.year == year);
    assert(actual.month == month);
    assert(actual.day == date);
    assert(habit_date_to_day(actual) == day);
}

int main(void)
{
    habit_date_t leap_day = { 2024, 2, 29 };
    assert(habit_date_valid(leap_day));
    assert(!habit_date_valid((habit_date_t){ 2023, 2, 29 }));
    expect_date(0, 1970, 1, 1);
    expect_date(habit_date_to_day(leap_day), 2024, 2, 29);
    assert(habit_day_of_week(0) == 4);

    habit_date_t build_date;
    assert(habit_date_from_build("Sep 28 2026", &build_date));
    assert(build_date.year == 2026 && build_date.month == 9 && build_date.day == 28);
    assert(!habit_date_from_build("not a date", &build_date));
    habit_date_t adjusted = habit_date_adjust((habit_date_t){ 2024, 2, 29 },
                                              HABIT_DATE_YEAR, -1);
    assert(adjusted.year == 2023 && adjusted.month == 2 && adjusted.day == 28);

    habit_model_t model;
    habit_model_init(&model, (habit_date_t){ 2026, 9, 28 });
    assert(!model.date_set);
    habit_model_set_current_date(&model, (habit_date_t){ 2026, 9, 28 });
    assert(model.date_set);
    assert(habit_model_toggle(&model, model.current_day - 2));
    assert(habit_model_toggle(&model, model.current_day - 1));
    assert(habit_model_streak(&model) == 2);
    assert(habit_model_toggle(&model, model.current_day));
    assert(habit_model_streak(&model) == 3);
    assert(!habit_model_toggle(&model, model.current_day + 1));
    assert(habit_model_toggle(&model, model.current_day - 1));
    assert(!habit_model_is_checked(&model, model.current_day - 1));
    assert(habit_model_streak(&model) == 1);
    assert(habit_model_is_sane(&model));

    int32_t grid_start = habit_grid_start(model.current_day, 14);
    assert(habit_day_of_week(grid_start) == 1);
    assert(grid_start <= model.current_day);
    assert(grid_start + 98 > model.current_day);

    habit_store_record_t first;
    habit_store_record_t second;
    habit_store_record_pack(&first, &model, 10);
    assert(habit_store_record_valid(&first, sizeof(first)));
    second = first;
    second.sequence = 11;
    second.crc32 = habit_store_crc32(&second,
                                     offsetof(habit_store_record_t, crc32));
    assert(habit_store_record_newest(&first, true, &second, true) == &second);
    first.model.current_day++;
    assert(!habit_store_record_valid(&first, sizeof(first)));
    assert(habit_store_record_newest(&first, false, &second, true) == &second);

    habit_model_init(&model, (habit_date_t){ 2026, 9, 28 });
    habit_model_set_current_date(&model, (habit_date_t){ 2026, 9, 28 });
    for (unsigned i = 0; i < HABIT_HISTORY_CAPACITY; ++i) {
        assert(habit_model_toggle(&model, model.current_day - (int32_t)i));
    }
    assert(model.checked_count == HABIT_HISTORY_CAPACITY);
    int32_t previous_oldest = model.checked_days[0];
    assert(!habit_model_toggle(&model, model.current_day - 500));
    assert(model.checked_count == HABIT_HISTORY_CAPACITY);
    assert(model.checked_days[0] == previous_oldest);
    habit_model_set_current_date(&model, (habit_date_t){ 2026, 9, 29 });
    assert(habit_model_toggle(&model, model.current_day));
    assert(model.checked_count == HABIT_HISTORY_CAPACITY);
    assert(model.checked_days[0] == previous_oldest + 1);
    assert(habit_model_is_sane(&model));
    return 0;
}
