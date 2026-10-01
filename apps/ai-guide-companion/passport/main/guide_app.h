#pragma once

#include "bsp_button.h"
#include "esp_err.h"

esp_err_t guide_app_start(void);
void guide_app_button(bsp_btn_t button, bsp_btn_ev_t event);
