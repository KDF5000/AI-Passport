#include "habit_model.h"

#include <limits.h>
#include <string.h>

static bool leap_year(int year)
{
    return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}

static int days_in_month(int year, int month)
{
    static const uint8_t lengths[] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (month < 1 || month > 12) return 0;
    return lengths[month - 1] + (month == 2 && leap_year(year));
}

bool habit_date_valid(habit_date_t date)
{
    return date.year >= 2000 && date.year <= 2099 &&
           date.month >= 1 && date.month <= 12 &&
           date.day >= 1 && date.day <= days_in_month(date.year, date.month);
}

// Howard Hinnant's civil-calendar conversion, with 1970-01-01 as day zero.
int32_t habit_date_to_day(habit_date_t date)
{
    int year = date.year - (date.month <= 2);
    int era = (year >= 0 ? year : year - 399) / 400;
    unsigned yoe = (unsigned)(year - era * 400);
    unsigned month = (unsigned)(date.month + (date.month > 2 ? -3 : 9));
    unsigned doy = (153U * month + 2U) / 5U + (unsigned)date.day - 1U;
    unsigned doe = yoe * 365U + yoe / 4U - yoe / 100U + doy;
    return (int32_t)(era * 146097 + (int)doe - 719468);
}

habit_date_t habit_day_to_date(int32_t day)
{
    int value = day + 719468;
    int era = (value >= 0 ? value : value - 146096) / 146097;
    unsigned doe = (unsigned)(value - era * 146097);
    unsigned yoe = (doe - doe / 1460U + doe / 36524U - doe / 146096U) / 365U;
    int year = (int)yoe + era * 400;
    unsigned doy = doe - (365U * yoe + yoe / 4U - yoe / 100U);
    unsigned mp = (5U * doy + 2U) / 153U;
    unsigned day_of_month = doy - (153U * mp + 2U) / 5U + 1U;
    unsigned month = mp + (mp < 10U ? 3U : (unsigned)-9);
    year += month <= 2U;
    return (habit_date_t){ year, (int)month, (int)day_of_month };
}

int habit_day_of_week(int32_t day)
{
    int weekday = (day + 4) % 7; // 1970-01-01 was Thursday; Sunday is zero.
    return weekday < 0 ? weekday + 7 : weekday;
}

habit_date_t habit_date_adjust(habit_date_t date, habit_date_field_t field, int delta)
{
    if (!habit_date_valid(date) || delta == 0) return date;
    if (field == HABIT_DATE_YEAR) {
        date.year += delta;
        if (date.year < 2000) date.year = 2099;
        if (date.year > 2099) date.year = 2000;
    } else if (field == HABIT_DATE_MONTH) {
        date.month = (date.month - 1 + delta) % 12;
        if (date.month < 0) date.month += 12;
        date.month += 1;
    } else {
        int maximum = days_in_month(date.year, date.month);
        date.day = (date.day - 1 + delta) % maximum;
        if (date.day < 0) date.day += maximum;
        date.day += 1;
        return date;
    }
    int maximum = days_in_month(date.year, date.month);
    if (date.day > maximum) date.day = maximum;
    return date;
}

bool habit_date_from_build(const char *build_date, habit_date_t *date)
{
    static const char *months[] = {
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    };
    if (!build_date || !date || strlen(build_date) != 11U) return false;
    int month = 0;
    for (int i = 0; i < 12; ++i) {
        if (memcmp(build_date, months[i], 3) == 0) {
            month = i + 1;
            break;
        }
    }
    if (!month) return false;
    int day = (build_date[4] == ' ' ? 0 : build_date[4] - '0') * 10 + build_date[5] - '0';
    int year = (build_date[7] - '0') * 1000 + (build_date[8] - '0') * 100 +
               (build_date[9] - '0') * 10 + build_date[10] - '0';
    habit_date_t parsed = { year, month, day };
    if (!habit_date_valid(parsed)) return false;
    *date = parsed;
    return true;
}

void habit_model_init(habit_model_t *model, habit_date_t suggested_date)
{
    memset(model, 0, sizeof(*model));
    model->version = HABIT_MODEL_VERSION;
    if (!habit_date_valid(suggested_date)) suggested_date = (habit_date_t){ 2026, 1, 1 };
    model->current_day = habit_date_to_day(suggested_date);
}

bool habit_model_is_sane(const habit_model_t *model)
{
    if (!model || model->version != HABIT_MODEL_VERSION ||
        model->date_set > 1U || model->checked_count > HABIT_HISTORY_CAPACITY) {
        return false;
    }
    habit_date_t current = habit_day_to_date(model->current_day);
    if (!habit_date_valid(current)) return false;
    for (uint16_t i = 0; i < model->checked_count; ++i) {
        if (i > 0 && model->checked_days[i - 1] >= model->checked_days[i]) return false;
    }
    return true;
}

void habit_model_set_current_date(habit_model_t *model, habit_date_t date)
{
    if (!model || !habit_date_valid(date)) return;
    model->current_day = habit_date_to_day(date);
    model->date_set = 1U;
}

static size_t lower_bound(const habit_model_t *model, int32_t day)
{
    size_t first = 0;
    size_t count = model->checked_count;
    while (count > 0) {
        size_t step = count / 2U;
        size_t middle = first + step;
        if (model->checked_days[middle] < day) {
            first = middle + 1U;
            count -= step + 1U;
        } else {
            count = step;
        }
    }
    return first;
}

bool habit_model_is_checked(const habit_model_t *model, int32_t day)
{
    if (!model) return false;
    size_t at = lower_bound(model, day);
    return at < model->checked_count && model->checked_days[at] == day;
}

bool habit_model_toggle(habit_model_t *model, int32_t day)
{
    if (!model || day > model->current_day) return false;
    size_t at = lower_bound(model, day);
    if (at < model->checked_count && model->checked_days[at] == day) {
        memmove(&model->checked_days[at], &model->checked_days[at + 1U],
                (model->checked_count - at - 1U) * sizeof(model->checked_days[0]));
        model->checked_count--;
        return true;
    }
    if (model->checked_count == HABIT_HISTORY_CAPACITY) {
        if (day < model->checked_days[0]) return false;
        memmove(&model->checked_days[0], &model->checked_days[1],
                (HABIT_HISTORY_CAPACITY - 1U) * sizeof(model->checked_days[0]));
        model->checked_count--;
        at = lower_bound(model, day);
    }
    memmove(&model->checked_days[at + 1U], &model->checked_days[at],
            (model->checked_count - at) * sizeof(model->checked_days[0]));
    model->checked_days[at] = day;
    model->checked_count++;
    return true;
}

unsigned habit_model_streak(const habit_model_t *model)
{
    if (!model || model->checked_count == 0) return 0;
    int32_t day = model->current_day;
    if (!habit_model_is_checked(model, day)) day--;
    unsigned streak = 0;
    while (habit_model_is_checked(model, day)) {
        streak++;
        if (day == INT32_MIN) break;
        day--;
    }
    return streak;
}

int32_t habit_grid_start(int32_t anchor_day, unsigned weeks)
{
    if (weeks == 0U) return anchor_day;
    int monday_offset = (habit_day_of_week(anchor_day) + 6) % 7;
    int32_t monday = anchor_day - monday_offset;
    return monday - (int32_t)((weeks - 1U) * 7U);
}
