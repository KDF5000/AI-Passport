#include "bsp_battery.h"
#include "bsp_button.h"
#include "bsp_display.h"
#include "bsp_pins.h"
#include "esp_log.h"
#include "habit_app.h"
#include "habit_model.h"
#include "habit_store.h"

static const char *TAG = "habit_main";
static habit_model_t s_model;

static void on_button(bsp_btn_t button, bsp_btn_ev_t event, void *context)
{
    (void)context;
    habit_app_button(button, event);
}
void app_main(void)
{
    ESP_LOGI(TAG, "starting offline habit tracker");

    habit_date_t suggested = { 2026, 1, 1 };
    (void)habit_date_from_build(__DATE__, &suggested);
    habit_model_init(&s_model, suggested);
    bool storage_available = habit_store_init(&s_model);

    if (bsp_display_init() != ESP_OK || !bsp_lvgl_init()) {
        ESP_LOGE(TAG, "display/LVGL init failed (MOSI=%d SCLK=%d CS=%d DC=%d BL=%d)",
                 BSP_LCD_MOSI, BSP_LCD_SCLK, BSP_LCD_CS, BSP_LCD_DC, BSP_LCD_BL);
        return;
    }
    bsp_display_backlight(85);

    int battery = -1;
    if (bsp_battery_init() == ESP_OK) battery = bsp_battery_soc();

    if (!habit_app_start(&s_model, storage_available, battery)) {
        ESP_LOGE(TAG, "application UI/task startup failed");
        return;
    }
    esp_err_t button_error = bsp_button_init(on_button, NULL);
    if (button_error != ESP_OK) {
        ESP_LOGE(TAG, "button init failed: %s", esp_err_to_name(button_error));
        return;
    }

    ESP_LOGI(TAG, "ready: storage=%d battery=%d date_set=%u check_ins=%u",
             storage_available, battery, s_model.date_set, s_model.checked_count);
}
