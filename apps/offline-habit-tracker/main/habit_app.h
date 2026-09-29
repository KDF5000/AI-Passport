#pragma once

#include <stdbool.h>

#include "bsp_button.h"
#include "habit_model.h"

bool habit_app_start(habit_model_t *model, bool storage_available, int battery_soc);
void habit_app_button(bsp_btn_t button, bsp_btn_ev_t event);
