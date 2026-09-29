#include "habit_store.h"

#include "habit_store_record.h"

#include <stdlib.h>

#include "esp_log.h"
#include "nvs.h"
#include "nvs_flash.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"

#define HABIT_NAMESPACE "habit"

typedef struct {
    habit_model_t model;
    uint32_t generation;
} save_request_t;

static const char *TAG = "habit_store";
static QueueHandle_t s_queue;
static uint32_t s_sequence;
static volatile uint32_t s_requested_generation;
static volatile uint32_t s_saved_generation;
static volatile bool s_error;

static bool read_slot(nvs_handle_t nvs, const char *key, habit_store_record_t *record)
{
    size_t length = sizeof(*record);
    esp_err_t error = nvs_get_blob(nvs, key, record, &length);
    return error == ESP_OK && habit_store_record_valid(record, length);
}

static void save_task(void *context)
{
    (void)context;
    save_request_t *request = malloc(sizeof(*request));
    habit_store_record_t *record = malloc(sizeof(*record));
    if (!request || !record) {
        free(request);
        free(record);
        s_error = true;
        ESP_LOGE(TAG, "save worker allocation failed");
        vTaskDelete(NULL);
        return;
    }

    for (;;) {
        if (xQueueReceive(s_queue, request, portMAX_DELAY) != pdTRUE) continue;

        habit_store_record_pack(record, &request->model, ++s_sequence);
        nvs_handle_t nvs;
        esp_err_t error = nvs_open(HABIT_NAMESPACE, NVS_READWRITE, &nvs);
        if (error == ESP_OK) {
            const char *key = (record->sequence & 1U) ? "slot_a" : "slot_b";
            error = nvs_set_blob(nvs, key, record, sizeof(*record));
            if (error == ESP_OK) error = nvs_commit(nvs);
            nvs_close(nvs);
        }
        if (error == ESP_OK) {
            s_saved_generation = request->generation;
            s_error = false;
            ESP_LOGI(TAG, "saved generation %lu to slot %c",
                     (unsigned long)request->generation,
                     (record->sequence & 1U) ? 'A' : 'B');
        } else {
            s_error = true;
            ESP_LOGE(TAG, "save failed: %s", esp_err_to_name(error));
        }
    }
}

bool habit_store_init(habit_model_t *model)
{
    if (!model) return false;
    if (s_queue) return true;

    esp_err_t error = nvs_flash_init();
    if (error != ESP_OK) {
        // This application shares the default NVS partition. Never erase other
        // namespaces just to recover this feature.
        ESP_LOGE(TAG, "NVS init failed without erase: %s", esp_err_to_name(error));
        s_error = true;
        return false;
    }

    nvs_handle_t nvs;
    error = nvs_open(HABIT_NAMESPACE, NVS_READONLY, &nvs);
    if (error == ESP_OK) {
        habit_store_record_t *slots = calloc(2, sizeof(*slots));
        if (!slots) {
            nvs_close(nvs);
            ESP_LOGE(TAG, "restore buffer allocation failed");
            s_error = true;
            return false;
        }
        bool a_valid = read_slot(nvs, "slot_a", &slots[0]);
        bool b_valid = read_slot(nvs, "slot_b", &slots[1]);
        nvs_close(nvs);
        const habit_store_record_t *newest =
            habit_store_record_newest(&slots[0], a_valid, &slots[1], b_valid);
        if (newest) {
            *model = newest->model;
            s_sequence = newest->sequence;
            ESP_LOGI(TAG, "restored %u check-ins from sequence %lu",
                     model->checked_count, (unsigned long)s_sequence);
        } else if (a_valid || b_valid) {
            ESP_LOGW(TAG, "no usable persistence slot");
        }
        free(slots);
    } else if (error != ESP_ERR_NVS_NOT_FOUND) {
        ESP_LOGW(TAG, "NVS read open failed: %s", esp_err_to_name(error));
    }

    s_queue = xQueueCreate(1, sizeof(save_request_t));
    if (!s_queue) {
        s_error = true;
        return false;
    }
    if (xTaskCreate(save_task, "habit_save", 4096, NULL, 3, NULL) != pdPASS) {
        vQueueDelete(s_queue);
        s_queue = NULL;
        s_error = true;
        return false;
    }
    s_error = false;
    return true;
}

bool habit_store_request_save(const habit_model_t *model)
{
    if (!s_queue || !model) return false;
    save_request_t request = {
        .model = *model,
        .generation = s_requested_generation + 1U,
    };
    s_requested_generation = request.generation;
    if (xQueueOverwrite(s_queue, &request) != pdPASS) {
        s_error = true;
        return false;
    }
    return true;
}

habit_store_state_t habit_store_state(void)
{
    if (!s_queue) return HABIT_STORE_UNAVAILABLE;
    if (s_error) return HABIT_STORE_ERROR;
    return s_saved_generation == s_requested_generation ? HABIT_STORE_SAVED
                                                        : HABIT_STORE_SAVING;
}
