#include "guide_app.h"

#include "bsp_audio.h"
#include "bsp_display.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "guide_adpcm.h"
#include "guide_ble.h"
#include "lvgl.h"
#include <stdio.h>
#include <string.h>

#define SAMPLE_RATE 16000
#define BLOCK_SAMPLES 320
#define BLOCK_BYTES 164
#define MAX_PACKET 513
#define TEXT_CAPACITY 768

enum {
    PKT_RECORD_START = 0x01,
    PKT_RECORD_AUDIO = 0x02,
    PKT_RECORD_END = 0x03,
    PKT_TRANSCRIPT = 0x10,
    PKT_ANSWER = 0x11,
    PKT_PLAY_START = 0x12,
    PKT_PLAY_AUDIO = 0x13,
    PKT_RESPONSE_END = 0x14,
    PKT_ERROR = 0x7f,
};

typedef struct {
    uint16_t length;
    uint8_t data[MAX_PACKET];
} rx_packet_t;

typedef enum {
    AUDIO_START_RECORD = 1,
    AUDIO_STOP_RECORD,
    AUDIO_PLAY_PACKET,
    AUDIO_STOP_PLAYBACK,
    AUDIO_END_PLAYBACK,
} audio_command_type_t;

typedef struct {
    audio_command_type_t type;
    uint16_t length;
    uint8_t data[BLOCK_BYTES];
} audio_command_t;

typedef enum {
    APP_HOLD_OK = 1,
    APP_RELEASE_OK,
    APP_STOP_AUDIO,
    APP_BLE_STATE,
} app_event_type_t;

typedef struct {
    app_event_type_t type;
    bool connected;
    bool ready;
    uint16_t mtu;
} app_event_t;

static QueueHandle_t s_rx_queue;
static QueueHandle_t s_audio_queue;
static QueueHandle_t s_event_queue;
static TaskHandle_t s_record_task;
static bool s_recording;
static bool s_playing;
static lv_obj_t *s_status;
static lv_obj_t *s_title;
static lv_obj_t *s_text;
static lv_obj_t *s_orb;
static char s_answer[TEXT_CAPACITY];
static size_t s_answer_length;
static bool s_receiving_answer;

static void set_ui(const char *title, const char *status, uint32_t color)
{
    if (!bsp_lvgl_lock(300)) return;
    if (s_title && title) lv_label_set_text(s_title, title);
    if (s_status && status) lv_label_set_text(s_status, status);
    if (s_orb) lv_obj_set_style_bg_color(s_orb, lv_color_hex(color), 0);
    bsp_lvgl_unlock();
}

static void set_text(const char *text)
{
    if (!bsp_lvgl_lock(300)) return;
    if (s_text) lv_label_set_text(s_text, text);
    bsp_lvgl_unlock();
}

static esp_err_t notify_retry(const uint8_t *data, size_t length)
{
    for (int retry = 0; retry < 8; ++retry) {
        esp_err_t err = guide_ble_notify(data, length);
        if (err == ESP_OK) return ESP_OK;
        if (err == ESP_ERR_INVALID_STATE || err == ESP_ERR_INVALID_SIZE) return err;
        vTaskDelay(pdMS_TO_TICKS(3));
    }
    return ESP_FAIL;
}

static void record_task(void *arg)
{
    (void)arg;
    uint8_t packet[1 + BLOCK_BYTES];
    int16_t pcm[BLOCK_SAMPLES];
    packet[0] = PKT_RECORD_AUDIO;
    while (s_recording && guide_ble_ready()) {
        if (bsp_audio_read(pcm, sizeof(pcm)) != ESP_OK) {
            set_ui("Audio error", "Could not read the microphone", 0xd4534b);
            break;
        }
        size_t encoded = guide_adpcm_encode_block(
            pcm, BLOCK_SAMPLES, packet + 1, BLOCK_BYTES);
        if (encoded != BLOCK_BYTES ||
            notify_retry(packet, encoded + 1) != ESP_OK) {
            set_ui("Link error", "Audio could not reach the phone", 0xd4534b);
            break;
        }
    }
    s_recording = false;
    const uint8_t end = PKT_RECORD_END;
    (void)notify_retry(&end, 1);
    set_ui("Thinking", "Phone is contacting your AI", 0x7c6ed1);
    s_record_task = NULL;
    vTaskDelete(NULL);
}

static void start_recording(void)
{
    if (s_recording || s_playing) return;
    if (!guide_ble_ready()) {
        set_ui("Phone not ready", "Open the app and connect first", 0xd99a45);
        return;
    }
    if (bsp_audio_set_format(SAMPLE_RATE, 16, 1) != ESP_OK) {
        set_ui("Audio error", "Microphone setup failed", 0xd4534b);
        return;
    }
    const uint8_t start[] = {PKT_RECORD_START, SAMPLE_RATE & 0xff, SAMPLE_RATE >> 8};
    if (notify_retry(start, sizeof(start)) != ESP_OK) return;
    s_recording = true;
    set_text("Speak naturally.\nRelease OK when finished.");
    set_ui("Listening", "Recording your question", 0xe26755);
    if (xTaskCreate(record_task, "guide_record", 4096, NULL, 5,
                    &s_record_task) != pdPASS) {
        s_recording = false;
        set_ui("Audio error", "Could not start recording", 0xd4534b);
    }
}

static void stop_recording(void)
{
    if (!s_recording) return;
    s_recording = false;
}

static void audio_worker(void *arg)
{
    (void)arg;
    audio_command_t command;
    int16_t pcm[BLOCK_SAMPLES + 1];
    for (;;) {
        if (xQueueReceive(s_audio_queue, &command, portMAX_DELAY) != pdTRUE) continue;
        if (command.type == AUDIO_STOP_PLAYBACK) {
            s_playing = false;
            xQueueReset(s_audio_queue);
            set_ui("Ready", "Hold OK to ask", 0x3fa77f);
        } else if (command.type == AUDIO_END_PLAYBACK) {
            s_playing = false;
            set_ui("Ready", "Hold OK to ask again", 0x3fa77f);
        } else if (command.type == AUDIO_PLAY_PACKET && s_playing) {
            size_t samples = guide_adpcm_decode_block(
                command.data, command.length, pcm, BLOCK_SAMPLES + 1);
            if (samples >= BLOCK_SAMPLES) {
                (void)bsp_audio_write(pcm, BLOCK_SAMPLES * sizeof(int16_t));
            }
        }
    }
}

static void append_answer(const uint8_t *data, size_t length)
{
    size_t available = sizeof(s_answer) - 1 - s_answer_length;
    if (length > available) length = available;
    memcpy(s_answer + s_answer_length, data, length);
    s_answer_length += length;
    s_answer[s_answer_length] = '\0';
    set_text(s_answer);
}

static void protocol_worker(void *arg)
{
    (void)arg;
    rx_packet_t packet;
    for (;;) {
        if (xQueueReceive(s_rx_queue, &packet, portMAX_DELAY) != pdTRUE ||
            packet.length == 0) continue;
        uint8_t type = packet.data[0];
        if (type == PKT_TRANSCRIPT) {
            set_ui("You asked", "Waiting for the guide", 0x7c6ed1);
        } else if (type == PKT_ANSWER) {
            if (!s_receiving_answer) {
                s_answer_length = 0;
                s_answer[0] = '\0';
                s_receiving_answer = true;
            }
            append_answer(packet.data + 1, packet.length - 1);
            set_ui("Your guide", "Answer received", 0x3fa77f);
        } else if (type == PKT_PLAY_START) {
            if (bsp_audio_set_format(SAMPLE_RATE, 16, 1) == ESP_OK) {
                bsp_audio_set_volume(75);
                s_playing = true;
                set_ui("Your guide", "OK stops playback", 0x3fa77f);
            }
        } else if (type == PKT_PLAY_AUDIO && packet.length == 1 + BLOCK_BYTES) {
            audio_command_t command = {
                .type = AUDIO_PLAY_PACKET,
                .length = BLOCK_BYTES,
            };
            memcpy(command.data, packet.data + 1, BLOCK_BYTES);
            if (xQueueSend(s_audio_queue, &command, pdMS_TO_TICKS(200)) != pdTRUE) {
                set_ui("Audio delayed", "Phone is sending too quickly", 0xd99a45);
            }
        } else if (type == PKT_RESPONSE_END) {
            s_receiving_answer = false;
            audio_command_t command = {.type = AUDIO_END_PLAYBACK};
            (void)xQueueSend(s_audio_queue, &command, pdMS_TO_TICKS(200));
        } else if (type == PKT_ERROR) {
            char error[160];
            size_t length = packet.length - 1;
            if (length >= sizeof(error)) length = sizeof(error) - 1;
            memcpy(error, packet.data + 1, length);
            error[length] = '\0';
            set_text(error);
            set_ui("Request failed", "Check the phone app", 0xd4534b);
        }
    }
}

static void app_worker(void *arg)
{
    (void)arg;
    app_event_t event;
    for (;;) {
        if (xQueueReceive(s_event_queue, &event, portMAX_DELAY) != pdTRUE) continue;
        if (event.type == APP_HOLD_OK) {
            start_recording();
        } else if (event.type == APP_RELEASE_OK) {
            stop_recording();
        } else if (event.type == APP_STOP_AUDIO) {
            audio_command_t stop = {.type = AUDIO_STOP_PLAYBACK};
            (void)xQueueSend(s_audio_queue, &stop, 0);
        } else if (event.type == APP_BLE_STATE) {
            if (!event.connected) {
                s_recording = false;
                s_playing = false;
                set_text("Open Passport Guide on your phone,\nthen scan and connect.");
                set_ui("Waiting for phone", "Bluetooth is advertising", 0xd99a45);
            } else if (!event.ready) {
                char detail[64];
                snprintf(detail, sizeof(detail), "Connected · MTU %u (need 168)",
                         event.mtu);
                set_ui("Link not ready", detail, 0xd4534b);
            } else {
                set_text("Hold OK and ask a question.\nRelease OK to send it.");
                set_ui("Ready", "Phone connected · hold OK", 0x3fa77f);
            }
        }
    }
}

static void ble_rx(const uint8_t *data, size_t length, void *user)
{
    (void)user;
    if (!s_rx_queue || !data || length == 0 || length > MAX_PACKET) return;
    rx_packet_t packet = {.length = (uint16_t)length};
    memcpy(packet.data, data, length);
    (void)xQueueSend(s_rx_queue, &packet, 0);
}

static void ble_state(bool connected, bool ready, uint16_t mtu, void *user)
{
    (void)user;
    if (!s_event_queue) return;
    app_event_t event = {
        .type = APP_BLE_STATE,
        .connected = connected,
        .ready = ready,
        .mtu = mtu,
    };
    (void)xQueueSend(s_event_queue, &event, 0);
}

static void create_ui(void)
{
    lv_obj_t *screen = lv_obj_create(NULL);
    lv_obj_set_style_bg_color(screen, lv_color_hex(0x101b28), 0);
    lv_obj_set_style_bg_grad_color(screen, lv_color_hex(0x203b42), 0);
    lv_obj_set_style_bg_grad_dir(screen, LV_GRAD_DIR_VER, 0);
    lv_obj_set_style_border_width(screen, 0, 0);
    lv_obj_set_style_pad_all(screen, 0, 0);

    lv_obj_t *eyebrow = lv_label_create(screen);
    lv_label_set_text(eyebrow, "PASSPORT GUIDE");
    lv_obj_set_style_text_color(eyebrow, lv_color_hex(0x8fc9bc), 0);
    lv_obj_set_style_text_font(eyebrow, &lv_font_montserrat_12, 0);
    lv_obj_align(eyebrow, LV_ALIGN_TOP_LEFT, 22, 24);

    s_orb = lv_obj_create(screen);
    lv_obj_set_size(s_orb, 54, 54);
    lv_obj_set_style_radius(s_orb, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_border_width(s_orb, 4, 0);
    lv_obj_set_style_border_color(s_orb, lv_color_hex(0xe8dfca), 0);
    lv_obj_set_style_bg_color(s_orb, lv_color_hex(0xd99a45), 0);
    lv_obj_align(s_orb, LV_ALIGN_TOP_RIGHT, -22, 22);

    s_title = lv_label_create(screen);
    lv_label_set_text(s_title, "Waiting for phone");
    lv_obj_set_width(s_title, 190);
    lv_label_set_long_mode(s_title, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_font(s_title, &lv_font_montserrat_20, 0);
    lv_obj_set_style_text_color(s_title, lv_color_hex(0xf6f0df), 0);
    lv_obj_align(s_title, LV_ALIGN_TOP_LEFT, 22, 61);

    lv_obj_t *card = lv_obj_create(screen);
    lv_obj_set_size(card, 204, 144);
    lv_obj_set_style_radius(card, 20, 0);
    lv_obj_set_style_bg_color(card, lv_color_hex(0xf6f0df), 0);
    lv_obj_set_style_border_width(card, 0, 0);
    lv_obj_set_style_pad_all(card, 16, 0);
    lv_obj_align(card, LV_ALIGN_CENTER, 0, 23);

    s_text = lv_label_create(card);
    lv_obj_set_width(s_text, 172);
    lv_obj_set_height(s_text, 112);
    lv_label_set_long_mode(s_text, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_color(s_text, lv_color_hex(0x23323b), 0);
    lv_obj_set_style_text_font(s_text, &lv_font_source_han_sans_sc_14_cjk, 0);
    lv_label_set_text(s_text,
                      "Open Passport Guide on your phone,\nthen scan and connect.");

    s_status = lv_label_create(screen);
    lv_obj_set_width(s_status, 204);
    lv_obj_set_style_text_align(s_status, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_color(s_status, lv_color_hex(0xb8ccc7), 0);
    lv_obj_set_style_text_font(s_status, &lv_font_montserrat_12, 0);
    lv_label_set_text(s_status, "Bluetooth is advertising");
    lv_obj_align(s_status, LV_ALIGN_BOTTOM_MID, 0, -23);
    lv_screen_load(screen);
}

esp_err_t guide_app_start(void)
{
    s_rx_queue = xQueueCreate(24, sizeof(rx_packet_t));
    s_audio_queue = xQueueCreate(24, sizeof(audio_command_t));
    s_event_queue = xQueueCreate(8, sizeof(app_event_t));
    if (!s_rx_queue || !s_audio_queue || !s_event_queue) return ESP_ERR_NO_MEM;
    if (!bsp_lvgl_lock(1000)) return ESP_ERR_TIMEOUT;
    create_ui();
    bsp_lvgl_unlock();
    if (xTaskCreate(protocol_worker, "guide_protocol", 4608, NULL, 4, NULL) != pdPASS ||
        xTaskCreate(audio_worker, "guide_audio", 4096, NULL, 5, NULL) != pdPASS ||
        xTaskCreate(app_worker, "guide_events", 3584, NULL, 4, NULL) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    return guide_ble_start(ble_rx, ble_state, NULL);
}

void guide_app_button(bsp_btn_t button, bsp_btn_ev_t event)
{
    if (button != BSP_BTN_OK || !s_event_queue) return;
    app_event_t app_event = {0};
    if (event == BSP_BTN_LONG) {
        app_event.type = APP_HOLD_OK;
    } else if (event == BSP_BTN_RELEASE) {
        app_event.type = APP_RELEASE_OK;
    } else if (event == BSP_BTN_PRESS && s_playing) {
        app_event.type = APP_STOP_AUDIO;
    }
    if (app_event.type) (void)xQueueSend(s_event_queue, &app_event, 0);
}
