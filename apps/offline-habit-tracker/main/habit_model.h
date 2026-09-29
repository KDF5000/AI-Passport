#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define HABIT_MODEL_VERSION 1U
#define HABIT_HISTORY_CAPACITY 366U

typedef struct {
    int year;
    int month;
    int day;
} habit_date_t;

typedef enum {
    HABIT_DATE_YEAR = 0,
    HABIT_DATE_MONTH,
    HABIT_DATE_DAY,
} habit_date_field_t;

typedef struct {
    uint32_t version;
    int32_t current_day;
    uint16_t checked_count;
    uint8_t date_set;
    uint8_t reserved;
    int32_t checked_days[HABIT_HISTORY_CAPACITY];
} habit_model_t;

bool habit_date_valid(habit_date_t date);
int32_t habit_date_to_day(habit_date_t date);
habit_date_t habit_day_to_date(int32_t day);
int habit_day_of_week(int32_t day);
habit_date_t habit_date_adjust(habit_date_t date, habit_date_field_t field, int delta);
bool habit_date_from_build(const char *build_date, habit_date_t *date);

void habit_model_init(habit_model_t *model, habit_date_t suggested_date);
bool habit_model_is_sane(const habit_model_t *model);
void habit_model_set_current_date(habit_model_t *model, habit_date_t date);
bool habit_model_is_checked(const habit_model_t *model, int32_t day);
bool habit_model_toggle(habit_model_t *model, int32_t day);
unsigned habit_model_streak(const habit_model_t *model);
int32_t habit_grid_start(int32_t anchor_day, unsigned weeks);
