#include "bsp_audio.h"
#include "bsp_button.h"
#include "bsp_display.h"
#include "bsp_pins.h"
#include "esp_log.h"
#include "guide_app.h"
#include "nvs_flash.h"

static const char *TAG = "guide_main";

static void on_button(bsp_btn_t button, bsp_btn_ev_t event, void *context)
{
    (void)context;
    guide_app_button(button, event);
}
void app_main(void)
{
    ESP_LOGI(TAG, "starting BLE AI guide companion");
    esp_err_t nvs_error = nvs_flash_init();
    if (nvs_error != ESP_OK) {
        ESP_LOGE(TAG, "NVS init failed without erasing stored data: %s",
                 esp_err_to_name(nvs_error));
        return;
    }

    if (bsp_display_init() != ESP_OK || !bsp_lvgl_init()) {
        ESP_LOGE(TAG, "display/LVGL init failed (MOSI=%d SCLK=%d CS=%d DC=%d BL=%d)",
                 BSP_LCD_MOSI, BSP_LCD_SCLK, BSP_LCD_CS, BSP_LCD_DC, BSP_LCD_BL);
        return;
    }
    bsp_display_backlight(85);

    if (bsp_audio_init() != ESP_OK) {
        ESP_LOGE(TAG, "audio init failed");
        return;
    }
    if (guide_app_start() != ESP_OK) {
        ESP_LOGE(TAG, "guide application startup failed");
        return;
    }
    esp_err_t button_error = bsp_button_init(on_button, NULL);
    if (button_error != ESP_OK) {
        ESP_LOGE(TAG, "button init failed: %s", esp_err_to_name(button_error));
        return;
    }

    ESP_LOGI(TAG, "ready; connect with Passport Guide mobile app");
}
