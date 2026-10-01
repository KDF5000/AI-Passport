#include "guide_app.h"

#include "bsp_audio.h"
#include "bsp_battery.h"
#include "bsp_display.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "guide_adpcm.h"
#include "guide_ble.h"
#include "guide_idle_state.h"
#include "guide_playback_state.h"
#include "guide_utf8.h"
#include "lvgl.h"
#include <stdio.h>
#include <string.h>

LV_FONT_DECLARE(guide_font_14);

#define SAMPLE_RATE 16000
#define BLOCK_SAMPLES 320
#define BLOCK_BYTES 164
#define PLAYBACK_BUFFER_BLOCKS 8
#define PLAYBACK_REBUFFER_BLOCKS 6
#define PLAYBACK_UNDERRUN_MS 30
#define VOLUME_DEFAULT 70
#define VOLUME_STEP 10
#define VOLUME_MIN 10
#define MAX_PACKET 513
#define ANSWER_TEXT_CAPACITY 2304
#define QUESTION_TEXT_CAPACITY 768
#define MAX_TRIP_STOPS 8
#define TRIP_TITLE_CAPACITY 64
#define STOP_NAME_CAPACITY 64
#define STOP_TIME_CAPACITY 12
#define STOP_SUMMARY_CAPACITY 192
#define OK_CLICK_SUPPRESS_MS 1000
#define DISPLAY_IDLE_TIMEOUT_MS 30000
#define IDLE_CHECK_INTERVAL_MS 250
#define BATTERY_REFRESH_MS 60000

static const char *TAG = "guide_app";

enum {
    PKT_RECORD_START = 0x01,
    PKT_RECORD_AUDIO = 0x02,
    PKT_RECORD_END = 0x03,
    PKT_TRANSCRIPT = 0x10,
    PKT_ANSWER = 0x11,
    PKT_PLAY_START = 0x12,
    PKT_PLAY_AUDIO = 0x13,
    PKT_RESPONSE_END = 0x14,
    PKT_TRIP_BEGIN = 0x20,
    PKT_TRIP_TITLE = 0x21,
    PKT_TRIP_STOP = 0x22,
    PKT_TRIP_COMMIT = 0x23,
    PKT_TRIP_SELECT = 0x30,
    PKT_TRIP_COMPLETION = 0x31,
    PKT_TRIP_PLAY_REQUEST = 0x32,
    PKT_TRIP_PLAY_CANCEL = 0x33,
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
    APP_BUTTON = 1,
    APP_ACTIVITY,
    APP_HOLD_OK,
    APP_RELEASE_OK,
    APP_STOP_AUDIO,
    APP_VOLUME_UP,
    APP_VOLUME_DOWN,
    APP_PREVIOUS_STOP,
    APP_NEXT_STOP,
    APP_PLAY_STOP,
    APP_TOGGLE_COMPLETE,
    APP_BLE_STATE,
} app_event_type_t;

typedef struct {
    app_event_type_t type;
    bool connected;
    bool ready;
    uint16_t mtu;
    bsp_btn_t button;
    bsp_btn_ev_t button_event;
} app_event_t;

typedef struct {
    char name[STOP_NAME_CAPACITY];
    char time[STOP_TIME_CAPACITY];
    char summary[STOP_SUMMARY_CAPACITY];
    uint16_t duration_minutes;
    bool completed;
} trip_stop_t;

typedef struct {
    char title[TRIP_TITLE_CAPACITY];
    trip_stop_t stops[MAX_TRIP_STOPS];
    uint8_t count;
    uint8_t current;
    uint16_t received_mask;
    bool ready;
} trip_plan_t;

static QueueHandle_t s_rx_queue;
static QueueHandle_t s_audio_queue;
static QueueHandle_t s_event_queue;
static TaskHandle_t s_record_task;
static bool s_recording;
static bool s_playing;
static bool s_playback_primed;
static bool s_playback_started;
static volatile bool s_playback_ending;
static volatile bool s_playback_stop_requested;
static bool s_playback_cancelled;
static uint8_t s_volume_percent = VOLUME_DEFAULT;
static lv_obj_t *s_route_view;
static lv_obj_t *s_qa_view;
static lv_obj_t *s_route_battery;
static lv_obj_t *s_route_battery_icon;
static lv_obj_t *s_route_title;
static lv_obj_t *s_route_index;
static lv_obj_t *s_route_stage;
static lv_obj_t *s_route_time;
static lv_obj_t *s_route_duration;
static lv_obj_t *s_route_name;
static lv_obj_t *s_route_summary;
static lv_obj_t *s_route_next;
static lv_obj_t *s_stamps[MAX_TRIP_STOPS];
static lv_obj_t *s_status;
static lv_obj_t *s_title;
static lv_obj_t *s_question;
static lv_obj_t *s_text;
static lv_obj_t *s_text_card;
static char s_answer[ANSWER_TEXT_CAPACITY];
static char s_question_text[QUESTION_TEXT_CAPACITY];
static size_t s_answer_length;
static bool s_receiving_answer;
static trip_plan_t s_trip;
static trip_plan_t s_trip_staging;
static int64_t s_suppress_ok_click_until_us;
static bool s_waiting_response;
static guide_idle_state_t s_idle;

#define COLOR_PAPER 0x151a18
#define COLOR_TICKET 0xe9eee9
#define COLOR_INK 0x18201d
#define COLOR_MUTED 0x53615b
#define COLOR_ACCENT 0x2fae78
#define COLOR_RULE 0xaab7b0
#define COLOR_HEADER 0xc7d3cc
#define COLOR_ERROR 0xffa08c

static void set_ui(const char *title, const char *status, uint32_t color);
static void set_text(const char *text);
static esp_err_t notify_retry(const uint8_t *data, size_t length);

static uint8_t completed_stop_count(void)
{
    uint8_t completed = 0;
    for (uint8_t i = 0; i < s_trip.count; ++i) {
        if (s_trip.stops[i].completed) completed++;
    }
    return completed;
}

static void post_activity(void)
{
    if (!s_event_queue) return;
    app_event_t activity = {.type = APP_ACTIVITY};
    (void)xQueueSend(s_event_queue, &activity, 0);
}

static uint32_t uptime_ms(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}

static bool interaction_active(void)
{
    return s_recording || s_playing || s_waiting_response ||
           s_receiving_answer;
}

static esp_err_t set_display_awake(bool awake)
{
    if (!bsp_lvgl_lock(300)) return ESP_ERR_TIMEOUT;
    esp_err_t result = bsp_display_set_awake(awake);
    bsp_lvgl_unlock();
    return result;
}

static void set_battery_text(int soc)
{
    char value[12];
    uint32_t icon_color = COLOR_MUTED;
    uint32_t text_color = COLOR_HEADER;
    if (soc >= 0 && soc <= 100) {
        snprintf(value, sizeof(value), "%d%%", soc);
        icon_color = soc < 20 ? COLOR_ERROR : COLOR_ACCENT;
        if (soc < 20) text_color = COLOR_ERROR;
    } else {
        snprintf(value, sizeof(value), "--%%");
    }
    if (!bsp_lvgl_lock(300)) return;
    if (s_route_battery) {
        lv_label_set_text(s_route_battery, value);
        lv_obj_set_style_text_color(
            s_route_battery, lv_color_hex(text_color), 0);
    }
    if (s_route_battery_icon) {
        lv_obj_set_style_text_color(
            s_route_battery_icon, lv_color_hex(icon_color), 0);
    }
    bsp_lvgl_unlock();
}

static void battery_worker(void *arg)
{
    (void)arg;
    esp_err_t error = bsp_battery_init();
    if (error != ESP_OK) {
        ESP_LOGW(TAG, "battery gauge unavailable: %s", esp_err_to_name(error));
        set_battery_text(-1);
        vTaskDelete(NULL);
        return;
    }
    for (;;) {
        set_battery_text(bsp_battery_soc());
        vTaskDelay(pdMS_TO_TICKS(BATTERY_REFRESH_MS));
    }
}

static void show_view(lv_obj_t *view)
{
    if (s_route_view) {
        if (view == s_route_view) {
            lv_obj_clear_flag(s_route_view, LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_add_flag(s_route_view, LV_OBJ_FLAG_HIDDEN);
        }
    }
    if (s_qa_view) {
        if (view == s_qa_view) {
            lv_obj_clear_flag(s_qa_view, LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_add_flag(s_qa_view, LV_OBJ_FLAG_HIDDEN);
        }
    }
}

static void copy_packet_text(char *destination, size_t capacity,
                             const uint8_t *source, size_t length)
{
    if (!destination || capacity == 0) return;
    guide_utf8_sanitize(destination, capacity, source, length);
}

static void show_current_stop(void)
{
    if (!bsp_lvgl_lock(300)) return;
    show_view(s_route_view);
    if (!s_trip.ready || s_trip.count == 0 || s_trip.current >= s_trip.count) {
        lv_label_set_text(s_route_title, "PASSPORT GUIDE");
        lv_label_set_text(s_route_index, "--/--");
        lv_label_set_text(s_route_stage, "等待路线");
        lv_label_set_text(s_route_time, "--:--");
        lv_label_set_text(s_route_duration, "PHONE");
        lv_label_set_text(s_route_name, "今日行程");
        lv_label_set_text(s_route_summary, "连接手机，同步今日路线。");
        lv_label_set_text(s_route_next, "长按 OK 问 AI");
        for (size_t i = 0; i < MAX_TRIP_STOPS; ++i) {
            if (s_stamps[i]) lv_obj_add_flag(s_stamps[i], LV_OBJ_FLAG_HIDDEN);
        }
        bsp_lvgl_unlock();
        return;
    }
    const trip_stop_t *stop = &s_trip.stops[s_trip.current];
    char value[96];
    lv_label_set_text(s_route_title,
                      s_trip.title[0] ? s_trip.title : "今日行程");
    snprintf(value, sizeof(value), "%u/%u",
             (unsigned)completed_stop_count(), (unsigned)s_trip.count);
    lv_label_set_text(s_route_index, value);
    snprintf(value, sizeof(value), "第 %u 站",
             (unsigned)(s_trip.current + 1));
    lv_label_set_text(s_route_stage, value);
    lv_label_set_text(s_route_time, stop->time[0] ? stop->time : "--:--");
    snprintf(value, sizeof(value), "%u MIN",
             (unsigned)stop->duration_minutes);
    lv_label_set_text(s_route_duration, value);
    lv_label_set_text(s_route_name, stop->name);
    lv_label_set_text(s_route_summary, stop->summary);
    if (s_trip.current + 1 < s_trip.count) {
        const trip_stop_t *next = &s_trip.stops[s_trip.current + 1];
        snprintf(value, sizeof(value), "下一站  %s  %s",
                 next->name, next->time);
        value[guide_utf8_complete_prefix((const uint8_t *)value,
                                         strlen(value))] = '\0';
    } else {
        snprintf(value, sizeof(value), "%s",
                 stop->completed ? "今日行程已完成" : "双击 OK 标记完成");
    }
    lv_label_set_text(s_route_next, value);
    for (size_t i = 0; i < MAX_TRIP_STOPS; ++i) {
        if (!s_stamps[i]) continue;
        if (i >= s_trip.count) {
            lv_obj_add_flag(s_stamps[i], LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        lv_obj_clear_flag(s_stamps[i], LV_OBJ_FLAG_HIDDEN);
        lv_obj_set_style_bg_color(
            s_stamps[i],
            lv_color_hex(i == s_trip.current ? COLOR_ACCENT : COLOR_TICKET), 0);
        lv_obj_set_style_text_color(
            s_stamps[i],
            lv_color_hex(i == s_trip.current ? COLOR_TICKET :
                         (s_trip.stops[i].completed ? COLOR_ACCENT : COLOR_MUTED)), 0);
        lv_obj_set_style_border_color(
            s_stamps[i],
            lv_color_hex(i <= s_trip.current ? COLOR_ACCENT : COLOR_RULE), 0);
        if (s_trip.stops[i].completed) {
            lv_label_set_text(lv_obj_get_child(s_stamps[i], 0), "完");
        } else {
            snprintf(value, sizeof(value), "%u", (unsigned)(i + 1));
            lv_label_set_text(lv_obj_get_child(s_stamps[i], 0), value);
        }
    }
    bsp_lvgl_unlock();
}

static void notify_trip_state(uint8_t type)
{
    if (!s_trip.ready || s_trip.current >= s_trip.count) return;
    uint8_t packet[] = {
        type,
        s_trip.current,
        s_trip.stops[s_trip.current].completed ? 1 : 0,
    };
    size_t length = type == PKT_TRIP_SELECT ? 2 : sizeof(packet);
    if (notify_retry(packet, length) != ESP_OK) {
        set_ui(NULL, "Phone update delayed", 0xd99a45);
    }
}

static void set_ui(const char *title, const char *status, uint32_t color)
{
    if (!bsp_lvgl_lock(300)) return;
    if (s_title && title) {
        show_view(s_qa_view);
        lv_label_set_text(s_title, title);
    }
    if (s_status && status) lv_label_set_text(s_status, status);
    if (s_status) {
        uint32_t readable = color == 0xd4534b ? COLOR_ERROR : COLOR_HEADER;
        lv_obj_set_style_text_color(s_status, lv_color_hex(readable), 0);
    }
    bsp_lvgl_unlock();
}

static void set_text(const char *text)
{
    if (!bsp_lvgl_lock(300)) return;
    if (s_text) {
        show_view(s_qa_view);
        lv_label_set_text(s_text, text);
        lv_obj_update_layout(s_text_card);
        lv_obj_scroll_to_y(s_text_card, 0, LV_ANIM_OFF);
    }
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
    s_waiting_response = true;
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
    guide_playback_restart(&s_playback_cancelled);
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
        TickType_t wait = s_playing && s_playback_primed
            ? pdMS_TO_TICKS(PLAYBACK_UNDERRUN_MS)
            : portMAX_DELAY;
        if (xQueueReceive(s_audio_queue, &command, wait) != pdTRUE) {
            if (guide_playback_queue_drained(s_playing, s_playback_ending)) {
                s_playing = false;
                s_playback_primed = false;
                s_playback_started = false;
                s_playback_ending = false;
                s_playback_stop_requested = false;
                ESP_LOGI(TAG, "playback finished after audio queue drained");
                show_current_stop();
                post_activity();
                continue;
            }
            /*
             * The speaker consumes one packet every 20 ms. If BLE or the next
             * TTS phrase arrives late, stop consuming until a small reservoir
             * has formed again instead of repeatedly starving the I2S stream.
             */
            if (s_playing && !s_playback_ending) s_playback_primed = false;
            continue;
        }
        if (command.type == AUDIO_STOP_PLAYBACK) {
            s_playing = false;
            s_playback_primed = false;
            s_playback_started = false;
            s_playback_ending = false;
            s_playback_stop_requested = false;
            xQueueReset(s_audio_queue);
            show_current_stop();
            post_activity();
        } else if (command.type == AUDIO_END_PLAYBACK) {
            s_playing = false;
            s_playback_primed = false;
            s_playback_started = false;
            s_playback_ending = false;
            show_current_stop();
            post_activity();
        } else if (command.type == AUDIO_PLAY_PACKET && s_playing) {
            if (!s_playback_primed) {
                UBaseType_t target = s_playback_started
                    ? PLAYBACK_REBUFFER_BLOCKS
                    : PLAYBACK_BUFFER_BLOCKS;
                while (!s_playback_ending && !s_playback_stop_requested &&
                       uxQueueMessagesWaiting(s_audio_queue) + 1 < target) {
                    vTaskDelay(pdMS_TO_TICKS(10));
                    if (!s_playing) break;
                }
                if (!s_playing || s_playback_stop_requested) {
                    s_playing = false;
                    s_playback_primed = false;
                    s_playback_started = false;
                    s_playback_ending = false;
                    s_playback_stop_requested = false;
                    xQueueReset(s_audio_queue);
                    show_current_stop();
                    post_activity();
                    continue;
                }
                s_playback_primed = true;
                s_playback_started = true;
            }
            size_t samples = guide_adpcm_decode_block(
                command.data, command.length, pcm, BLOCK_SAMPLES + 1);
            if (samples >= BLOCK_SAMPLES) {
                if (bsp_audio_write(pcm, BLOCK_SAMPLES * sizeof(int16_t)) != ESP_OK) {
                    s_playing = false;
                    s_playback_primed = false;
                    set_ui("Audio error", "Speaker playback failed", 0xd4534b);
                }
            }
        }
    }
}

static void append_answer(const uint8_t *data, size_t length)
{
    char sanitized[MAX_PACKET];
    length = guide_utf8_sanitize(sanitized, sizeof(sanitized), data, length);
    size_t available = sizeof(s_answer) - 1 - s_answer_length;
    if (length > available) length = available;
    length = guide_utf8_complete_prefix((const uint8_t *)sanitized, length);
    memcpy(s_answer + s_answer_length, sanitized, length);
    s_answer_length += length;
    s_answer[s_answer_length] = '\0';
    size_t display_length =
        guide_utf8_complete_prefix((const uint8_t *)s_answer, s_answer_length);
    char saved = s_answer[display_length];
    s_answer[display_length] = '\0';
    if (!bsp_lvgl_lock(300)) {
        s_answer[display_length] = saved;
        return;
    }
    if (s_text) {
        lv_label_set_text(s_text, s_answer);
        lv_obj_update_layout(s_text_card);
        lv_obj_scroll_to_y(s_text_card, LV_COORD_MAX, LV_ANIM_OFF);
    }
    bsp_lvgl_unlock();
    s_answer[display_length] = saved;
}

static void protocol_worker(void *arg)
{
    (void)arg;
    rx_packet_t packet;
    for (;;) {
        if (xQueueReceive(s_rx_queue, &packet, portMAX_DELAY) != pdTRUE ||
            packet.length == 0) continue;
        uint8_t type = packet.data[0];
        if (type != PKT_PLAY_AUDIO) post_activity();
        if (type == PKT_TRANSCRIPT) {
            copy_packet_text(s_question_text, sizeof(s_question_text),
                             packet.data + 1, packet.length - 1);
            if (bsp_lvgl_lock(300)) {
                show_view(s_qa_view);
                if (s_question) lv_label_set_text(s_question, s_question_text);
                bsp_lvgl_unlock();
            }
            set_ui("You asked", "Waiting for the guide", 0x7c6ed1);
        } else if (type == PKT_ANSWER) {
            if (!guide_playback_accept_stream(s_playback_cancelled)) continue;
            s_waiting_response = false;
            if (!s_receiving_answer) {
                s_answer_length = 0;
                s_answer[0] = '\0';
                s_receiving_answer = true;
            }
            append_answer(packet.data + 1, packet.length - 1);
            set_ui("Your guide", "Answer received", 0x3fa77f);
        } else if (type == PKT_PLAY_START) {
            s_waiting_response = false;
            if (bsp_audio_set_format(SAMPLE_RATE, 16, 1) == ESP_OK) {
                bsp_audio_set_volume(s_volume_percent);
                /*
                 * The user action that requested this operation already
                 * reopened stream acceptance. Reset the text view here when
                 * audio for that accepted operation begins.
                 */
                guide_playback_text_start(&s_receiving_answer,
                                           &s_answer_length);
                s_answer[0] = '\0';
                set_text("");
                s_playing = true;
                s_playback_primed = false;
                s_playback_started = false;
                s_playback_ending = false;
                s_playback_stop_requested = false;
                set_ui("Your guide", "OK stops playback", 0x3fa77f);
            }
        } else if (type == PKT_PLAY_AUDIO && packet.length == 1 + BLOCK_BYTES) {
            if (!guide_playback_accept_stream(s_playback_cancelled)) continue;
            audio_command_t command = {
                .type = AUDIO_PLAY_PACKET,
                .length = BLOCK_BYTES,
            };
            memcpy(command.data, packet.data + 1, BLOCK_BYTES);
            if (xQueueSend(s_audio_queue, &command, pdMS_TO_TICKS(200)) != pdTRUE) {
                set_ui("Audio delayed", "Phone is sending too quickly", 0xd99a45);
            }
        } else if (type == PKT_RESPONSE_END) {
            if (!guide_playback_accept_stream(s_playback_cancelled)) continue;
            s_waiting_response = false;
            s_answer_length =
                guide_utf8_complete_prefix((const uint8_t *)s_answer,
                                           s_answer_length);
            s_answer[s_answer_length] = '\0';
            guide_playback_text_stop(&s_receiving_answer);
            s_playback_ending = true;
            audio_command_t command = {.type = AUDIO_END_PLAYBACK};
            if (xQueueSend(s_audio_queue, &command,
                           pdMS_TO_TICKS(200)) != pdTRUE) {
                /*
                 * A full queue contains audio that still needs to play. The
                 * audio task will finish when it drains the queue and observes
                 * s_playback_ending, so a dropped sentinel cannot leave
                 * s_playing stuck forever.
                 */
                ESP_LOGW(TAG, "playback end sentinel deferred until queue drain");
            }
        } else if (type == PKT_TRIP_BEGIN && packet.length >= 3) {
            uint8_t count = packet.data[1];
            uint8_t current = packet.data[2];
            memset(&s_trip_staging, 0, sizeof(s_trip_staging));
            if (count > 0 && count <= MAX_TRIP_STOPS && current < count) {
                s_trip_staging.count = count;
                s_trip_staging.current = current;
            }
        } else if (type == PKT_TRIP_TITLE &&
                   s_trip_staging.count > 0) {
            copy_packet_text(s_trip_staging.title,
                             sizeof(s_trip_staging.title),
                             packet.data + 1, packet.length - 1);
        } else if (type == PKT_TRIP_STOP && packet.length >= 7 &&
                   s_trip_staging.count > 0) {
            uint8_t index = packet.data[1];
            uint8_t time_length = packet.data[5];
            uint8_t name_length = packet.data[6];
            size_t header_length = 7;
            size_t fixed_length = header_length + time_length + name_length;
            if (index < s_trip_staging.count &&
                index < MAX_TRIP_STOPS &&
                fixed_length <= packet.length) {
                trip_stop_t *stop = &s_trip_staging.stops[index];
                stop->completed = packet.data[2] != 0;
                stop->duration_minutes =
                    (uint16_t)packet.data[3] |
                    ((uint16_t)packet.data[4] << 8);
                copy_packet_text(stop->time, sizeof(stop->time),
                                 packet.data + header_length, time_length);
                copy_packet_text(stop->name, sizeof(stop->name),
                                 packet.data + header_length + time_length,
                                 name_length);
                copy_packet_text(stop->summary, sizeof(stop->summary),
                                 packet.data + fixed_length,
                                 packet.length - fixed_length);
                s_trip_staging.received_mask |= (uint16_t)(1U << index);
            }
        } else if (type == PKT_TRIP_COMMIT &&
                   s_trip_staging.count > 0) {
            uint16_t expected =
                (uint16_t)((1U << s_trip_staging.count) - 1U);
            if (s_trip_staging.received_mask == expected) {
                s_trip = s_trip_staging;
                s_trip.ready = true;
                show_current_stop();
            } else {
                set_ui("Route incomplete", "Reconnect phone to retry",
                       0xd4534b);
            }
        } else if (type == PKT_ERROR) {
            s_waiting_response = false;
            s_receiving_answer = false;
            if (s_playing) {
                audio_command_t stop = {.type = AUDIO_STOP_PLAYBACK};
                (void)xQueueSend(s_audio_queue, &stop, 0);
            }
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

static app_event_type_t translate_button(bsp_btn_t button,
                                         bsp_btn_ev_t event)
{
    if (button == BSP_BTN_UP && event == BSP_BTN_CLICK) {
        return s_playing ? APP_VOLUME_UP : APP_PREVIOUS_STOP;
    }
    if (button == BSP_BTN_DOWN && event == BSP_BTN_CLICK) {
        return s_playing ? APP_VOLUME_DOWN : APP_NEXT_STOP;
    }
    if (button == BSP_BTN_OK && event == BSP_BTN_LONG) {
        return APP_HOLD_OK;
    }
    if (button == BSP_BTN_OK && event == BSP_BTN_RELEASE) {
        return APP_RELEASE_OK;
    }
    if (button == BSP_BTN_OK && event == BSP_BTN_PRESS && s_playing) {
        s_suppress_ok_click_until_us =
            esp_timer_get_time() + (int64_t)OK_CLICK_SUPPRESS_MS * 1000;
        return APP_STOP_AUDIO;
    }
    if (button == BSP_BTN_OK && event == BSP_BTN_DOUBLE &&
        !s_playing && !s_recording) {
        return APP_TOGGLE_COMPLETE;
    }
    if (button == BSP_BTN_OK && event == BSP_BTN_CLICK &&
        !s_playing && !s_recording) {
        int64_t now_us = esp_timer_get_time();
        if (s_suppress_ok_click_until_us > now_us) {
            s_suppress_ok_click_until_us = 0;
            ESP_LOGI(TAG, "ignored click paired with playback stop");
            return 0;
        }
        s_suppress_ok_click_until_us = 0;
        return APP_PLAY_STOP;
    }
    return 0;
}

static void app_worker(void *arg)
{
    (void)arg;
    app_event_t event;
    guide_idle_init(&s_idle, uptime_ms(), DISPLAY_IDLE_TIMEOUT_MS);
    for (;;) {
        if (xQueueReceive(s_event_queue, &event,
                          pdMS_TO_TICKS(IDLE_CHECK_INTERVAL_MS)) != pdTRUE) {
            if (guide_idle_should_sleep(&s_idle, uptime_ms(),
                                        interaction_active())) {
                if (set_display_awake(false) != ESP_OK) {
                    guide_idle_mark_activity(&s_idle, uptime_ms());
                    s_idle.awake = true;
                }
            }
            continue;
        }
        if (event.type == APP_ACTIVITY) {
            guide_idle_mark_activity(&s_idle, uptime_ms());
            if (!s_idle.awake) {
                if (set_display_awake(true) == ESP_OK) {
                    s_idle.awake = true;
                }
            }
            continue;
        }
        if (event.type == APP_BUTTON) {
            guide_idle_button_result_t result = guide_idle_handle_button(
                &s_idle, uptime_ms(), event.button,
                (guide_idle_button_event_t)event.button_event);
            if (result == GUIDE_IDLE_BUTTON_WAKE) {
                if (set_display_awake(true) != ESP_OK) {
                    ESP_LOGW(TAG, "display wake failed");
                    s_idle.awake = false;
                }
                continue;
            }
            if (result == GUIDE_IDLE_BUTTON_CONSUME) continue;
            event.type = translate_button(event.button, event.button_event);
            if (!event.type) continue;
        } else {
            guide_idle_mark_activity(&s_idle, uptime_ms());
            if (!s_idle.awake && set_display_awake(true) == ESP_OK) {
                s_idle.awake = true;
            }
        }
        if (event.type == APP_HOLD_OK) {
            start_recording();
        } else if (event.type == APP_RELEASE_OK) {
            stop_recording();
        } else if (event.type == APP_STOP_AUDIO) {
            s_playback_stop_requested = true;
            s_waiting_response = false;
            guide_playback_cancel(&s_playback_cancelled, &s_receiving_answer);
            const uint8_t cancel = PKT_TRIP_PLAY_CANCEL;
            if (notify_retry(&cancel, 1) != ESP_OK) {
                ESP_LOGW(TAG, "phone did not acknowledge playback cancellation");
            }
            audio_command_t stop = {.type = AUDIO_STOP_PLAYBACK};
            xQueueReset(s_audio_queue);
            if (xQueueSendToFront(s_audio_queue, &stop, 0) != pdTRUE) {
                ESP_LOGE(TAG, "failed to queue playback stop");
            }
        } else if (event.type == APP_VOLUME_UP ||
                   event.type == APP_VOLUME_DOWN) {
            if (event.type == APP_VOLUME_UP) {
                if (s_volume_percent <= 100 - VOLUME_STEP) {
                    s_volume_percent += VOLUME_STEP;
                } else {
                    s_volume_percent = 100;
                }
            } else if (s_volume_percent >= VOLUME_MIN + VOLUME_STEP) {
                s_volume_percent -= VOLUME_STEP;
            } else {
                s_volume_percent = VOLUME_MIN;
            }
            bsp_audio_set_volume(s_volume_percent);
            char detail[32];
            snprintf(detail, sizeof(detail), "Volume %u%%", s_volume_percent);
            set_ui(NULL, detail, 0x3fa77f);
        } else if (event.type == APP_PREVIOUS_STOP ||
                   event.type == APP_NEXT_STOP) {
            if (!s_trip.ready || s_trip.count == 0) {
                show_current_stop();
                continue;
            }
            if (event.type == APP_PREVIOUS_STOP && s_trip.current > 0) {
                s_trip.current--;
            } else if (event.type == APP_NEXT_STOP &&
                       s_trip.current + 1 < s_trip.count) {
                s_trip.current++;
            }
            show_current_stop();
            notify_trip_state(PKT_TRIP_SELECT);
        } else if (event.type == APP_PLAY_STOP) {
            if (!s_trip.ready) {
                set_ui(NULL, "Sync a route from the phone first", 0xd4534b);
                ESP_LOGW(TAG, "offline playback ignored: route not ready");
                continue;
            }
            if (!guide_ble_ready()) {
                set_ui(NULL, "Reconnect the phone to play", 0xd4534b);
                ESP_LOGW(TAG, "offline playback ignored: BLE not ready");
                continue;
            }
            uint8_t packet[] = {PKT_TRIP_PLAY_REQUEST, s_trip.current};
            if (notify_retry(packet, sizeof(packet)) == ESP_OK) {
                guide_playback_restart(&s_playback_cancelled);
                s_waiting_response = true;
                set_ui(NULL, "Loading offline guide...", 0x7c6ed1);
                ESP_LOGI(TAG, "offline playback requested for stop %u",
                         s_trip.current);
            } else {
                set_ui(NULL, "Phone not ready", 0xd4534b);
                ESP_LOGW(TAG, "offline playback request failed for stop %u",
                         s_trip.current);
            }
        } else if (event.type == APP_TOGGLE_COMPLETE) {
            if (!s_trip.ready || s_trip.current >= s_trip.count) continue;
            trip_stop_t *stop = &s_trip.stops[s_trip.current];
            stop->completed = !stop->completed;
            show_current_stop();
            notify_trip_state(PKT_TRIP_COMPLETION);
        } else if (event.type == APP_BLE_STATE) {
            if (!event.connected) {
                s_recording = false;
                s_playing = false;
                s_waiting_response = false;
                set_text("Open Passport Guide on your phone,\nthen scan and connect.");
                set_ui("Waiting for phone", "Bluetooth is advertising", 0xd99a45);
            } else if (!event.ready) {
                char detail[64];
                snprintf(detail, sizeof(detail), "Connected | MTU %u (need 168)",
                         event.mtu);
                set_ui("Link not ready", detail, 0xd4534b);
            } else {
                if (s_trip.ready) {
                    show_current_stop();
                } else {
                    set_text("Syncing today's route from your phone...");
                    set_ui("Phone connected", "Waiting for route",
                           0x3fa77f);
                }
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

static lv_obj_t *create_footer_label(lv_obj_t *parent, const char *text,
                                     lv_coord_t x, uint32_t color)
{
    lv_obj_t *label = lv_label_create(parent);
    lv_label_set_text(label, text);
    lv_obj_set_size(label, 68, 18);
    lv_label_set_long_mode(label, LV_LABEL_LONG_CLIP);
    lv_obj_set_style_text_align(label, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_font(label, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_color(label, lv_color_hex(color), 0);
    lv_obj_set_pos(label, x, 296);
    return label;
}

static void create_ui(void)
{
    lv_obj_t *screen = lv_obj_create(NULL);
    lv_obj_set_style_bg_color(screen, lv_color_hex(COLOR_PAPER), 0);
    lv_obj_set_style_border_width(screen, 0, 0);
    lv_obj_set_style_pad_all(screen, 0, 0);
    lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE);

    s_route_view = lv_obj_create(screen);
    lv_obj_set_size(s_route_view, 240, 320);
    lv_obj_set_pos(s_route_view, 0, 0);
    lv_obj_set_style_bg_opa(s_route_view, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(s_route_view, 0, 0);
    lv_obj_set_style_pad_all(s_route_view, 0, 0);
    lv_obj_remove_flag(s_route_view, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *brand = lv_label_create(s_route_view);
    lv_label_set_text(brand, "TODAY'S JOURNEY");
    lv_obj_set_style_text_font(brand, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_color(brand, lv_color_hex(COLOR_HEADER), 0);
    lv_obj_set_pos(brand, 18, 9);

    lv_obj_t *battery_group = lv_obj_create(s_route_view);
    lv_obj_set_size(battery_group, 50, 20);
    lv_obj_set_pos(battery_group, 172, 7);
    lv_obj_set_style_bg_opa(battery_group, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(battery_group, 0, 0);
    lv_obj_set_style_pad_all(battery_group, 0, 0);
    lv_obj_set_style_pad_column(battery_group, 2, 0);
    lv_obj_set_flex_flow(battery_group, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(
        battery_group, LV_FLEX_ALIGN_END, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_remove_flag(battery_group, LV_OBJ_FLAG_SCROLLABLE);

    s_route_battery_icon = lv_label_create(battery_group);
    lv_label_set_text(s_route_battery_icon, LV_SYMBOL_CHARGE);
    lv_obj_set_size(s_route_battery_icon, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_style_text_font(
        s_route_battery_icon, &lv_font_montserrat_10, 0);
    lv_obj_set_style_text_color(
        s_route_battery_icon, lv_color_hex(COLOR_MUTED), 0);

    s_route_battery = lv_label_create(battery_group);
    lv_label_set_text(s_route_battery, "--%");
    lv_obj_set_size(s_route_battery, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_style_text_font(s_route_battery, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_color(s_route_battery, lv_color_hex(COLOR_HEADER), 0);

    s_route_title = lv_label_create(s_route_view);
    lv_obj_set_size(s_route_title, 154, 27);
    lv_label_set_long_mode(s_route_title, LV_LABEL_LONG_DOT);
    lv_obj_set_style_text_font(s_route_title, &guide_font_14, 0);
    lv_obj_set_style_text_color(s_route_title, lv_color_hex(COLOR_TICKET), 0);
    lv_obj_set_pos(s_route_title, 18, 24);

    s_route_index = lv_label_create(s_route_view);
    lv_label_set_text(s_route_index, "--/--");
    lv_obj_set_size(s_route_index, 44, 27);
    lv_label_set_long_mode(s_route_index, LV_LABEL_LONG_CLIP);
    lv_obj_set_style_text_align(s_route_index, LV_TEXT_ALIGN_RIGHT, 0);
    lv_obj_set_style_text_font(s_route_index, &guide_font_14, 0);
    lv_obj_set_style_text_color(s_route_index, lv_color_hex(COLOR_TICKET), 0);
    lv_obj_set_pos(s_route_index, 178, 24);

    lv_obj_t *ticket = lv_obj_create(s_route_view);
    lv_obj_set_size(ticket, 208, 184);
    lv_obj_set_pos(ticket, 16, 54);
    lv_obj_set_style_radius(ticket, 16, 0);
    lv_obj_set_style_bg_color(ticket, lv_color_hex(COLOR_TICKET), 0);
    lv_obj_set_style_border_width(ticket, 0, 0);
    lv_obj_set_style_pad_all(ticket, 0, 0);
    lv_obj_remove_flag(ticket, LV_OBJ_FLAG_SCROLLABLE);

    s_route_stage = lv_label_create(ticket);
    lv_label_set_text(s_route_stage, "等待路线");
    lv_obj_set_size(s_route_stage, 106, 27);
    lv_label_set_long_mode(s_route_stage, LV_LABEL_LONG_DOT);
    lv_obj_set_style_text_font(s_route_stage, &guide_font_14, 0);
    lv_obj_set_style_text_color(s_route_stage, lv_color_hex(COLOR_ACCENT), 0);
    lv_obj_set_pos(s_route_stage, 14, 4);

    s_route_duration = lv_label_create(ticket);
    lv_label_set_text(s_route_duration, "PHONE");
    lv_obj_set_size(s_route_duration, 72, 18);
    lv_label_set_long_mode(s_route_duration, LV_LABEL_LONG_CLIP);
    lv_obj_set_style_text_align(s_route_duration, LV_TEXT_ALIGN_RIGHT, 0);
    lv_obj_set_style_text_font(s_route_duration, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_color(s_route_duration, lv_color_hex(COLOR_MUTED), 0);
    lv_obj_set_pos(s_route_duration, 122, 10);

    s_route_time = lv_label_create(ticket);
    lv_label_set_text(s_route_time, "--:--");
    lv_obj_set_style_text_font(s_route_time, &lv_font_montserrat_20, 0);
    lv_obj_set_style_text_color(s_route_time, lv_color_hex(COLOR_ACCENT), 0);
    lv_obj_set_pos(s_route_time, 14, 34);

    s_route_name = lv_label_create(ticket);
    lv_label_set_text(s_route_name, "今日行程");
    lv_obj_set_size(s_route_name, 180, 27);
    lv_label_set_long_mode(s_route_name, LV_LABEL_LONG_DOT);
    lv_obj_set_style_text_font(s_route_name, &guide_font_14, 0);
    lv_obj_set_style_text_color(s_route_name, lv_color_hex(COLOR_INK), 0);
    lv_obj_set_pos(s_route_name, 14, 57);

    lv_obj_t *accent = lv_obj_create(ticket);
    lv_obj_set_size(accent, 34, 3);
    lv_obj_set_pos(accent, 14, 84);
    lv_obj_set_style_radius(accent, 0, 0);
    lv_obj_set_style_border_width(accent, 0, 0);
    lv_obj_set_style_bg_color(accent, lv_color_hex(COLOR_ACCENT), 0);

    s_route_summary = lv_label_create(ticket);
    lv_label_set_text(s_route_summary, "连接手机，同步今日路线。");
    lv_obj_set_size(s_route_summary, 180, 48);
    lv_label_set_long_mode(s_route_summary, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_font(s_route_summary, &guide_font_14, 0);
    lv_obj_set_style_text_color(s_route_summary, lv_color_hex(COLOR_MUTED), 0);
    lv_obj_set_style_text_line_space(s_route_summary, -7, 0);
    lv_obj_set_pos(s_route_summary, 14, 92);

    lv_obj_t *dash = lv_obj_create(ticket);
    lv_obj_set_size(dash, 180, 2);
    lv_obj_set_pos(dash, 14, 143);
    lv_obj_set_style_border_width(dash, 0, 0);
    lv_obj_set_style_bg_color(dash, lv_color_hex(COLOR_RULE), 0);

    s_route_next = lv_label_create(ticket);
    lv_label_set_text(s_route_next, "长按 OK 问 AI");
    lv_obj_set_size(s_route_next, 180, 27);
    lv_label_set_long_mode(s_route_next, LV_LABEL_LONG_DOT);
    lv_obj_set_style_text_font(s_route_next, &guide_font_14, 0);
    lv_obj_set_style_text_color(s_route_next, lv_color_hex(COLOR_ACCENT), 0);
    lv_obj_set_pos(s_route_next, 14, 151);

    for (int side = 0; side < 2; ++side) {
        lv_obj_t *cutout = lv_obj_create(s_route_view);
        lv_obj_set_size(cutout, 14, 14);
        lv_obj_set_style_radius(cutout, LV_RADIUS_CIRCLE, 0);
        lv_obj_set_style_border_width(cutout, 0, 0);
        lv_obj_set_style_bg_color(cutout, lv_color_hex(COLOR_PAPER), 0);
        lv_obj_set_pos(cutout, side == 0 ? 9 : 217, 194);
    }

    lv_obj_t *stamp_row = lv_obj_create(s_route_view);
    lv_obj_set_size(stamp_row, 208, 27);
    lv_obj_set_pos(stamp_row, 16, 242);
    lv_obj_set_flex_flow(stamp_row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(stamp_row, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(stamp_row, 3, 0);
    lv_obj_set_style_pad_all(stamp_row, 0, 0);
    lv_obj_set_style_bg_opa(stamp_row, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(stamp_row, 0, 0);
    lv_obj_remove_flag(stamp_row, LV_OBJ_FLAG_SCROLLABLE);
    for (size_t i = 0; i < MAX_TRIP_STOPS; ++i) {
        s_stamps[i] = lv_obj_create(stamp_row);
        lv_obj_set_size(s_stamps[i], 22, 22);
        lv_obj_set_style_radius(s_stamps[i], LV_RADIUS_CIRCLE, 0);
        lv_obj_set_style_bg_color(s_stamps[i], lv_color_hex(COLOR_TICKET), 0);
        lv_obj_set_style_border_width(s_stamps[i], 1, 0);
        lv_obj_set_style_border_color(s_stamps[i], lv_color_hex(COLOR_RULE), 0);
        lv_obj_set_style_pad_all(s_stamps[i], 0, 0);
        lv_obj_remove_flag(s_stamps[i], LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_t *number = lv_label_create(s_stamps[i]);
        char value[4];
        snprintf(value, sizeof(value), "%u", (unsigned)(i + 1));
        lv_label_set_text(number, value);
        lv_obj_set_style_text_font(number, &guide_font_14, 0);
        lv_obj_set_style_text_color(number, lv_color_hex(COLOR_MUTED), 0);
        lv_obj_center(number);
        lv_obj_add_flag(s_stamps[i], LV_OBJ_FLAG_HIDDEN);
    }

    lv_obj_t *ask_hint = lv_label_create(s_route_view);
    lv_label_set_text(ask_hint, "HOLD OK  ASK AI");
    lv_obj_set_size(ask_hint, 180, 18);
    lv_label_set_long_mode(ask_hint, LV_LABEL_LONG_CLIP);
    lv_obj_set_style_text_align(ask_hint, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_font(ask_hint, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_color(ask_hint, lv_color_hex(COLOR_HEADER), 0);
    lv_obj_set_pos(ask_hint, 30, 273);

    create_footer_label(s_route_view, "UP PREV", 10, COLOR_HEADER);
    create_footer_label(s_route_view, "OK PLAY", 86, COLOR_TICKET);
    create_footer_label(s_route_view, "DOWN NEXT", 162, COLOR_HEADER);

    s_qa_view = lv_obj_create(screen);
    lv_obj_set_size(s_qa_view, 240, 320);
    lv_obj_set_pos(s_qa_view, 0, 0);
    lv_obj_set_style_bg_opa(s_qa_view, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(s_qa_view, 0, 0);
    lv_obj_set_style_pad_all(s_qa_view, 0, 0);
    lv_obj_remove_flag(s_qa_view, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(s_qa_view, LV_OBJ_FLAG_HIDDEN);

    lv_obj_t *qa_brand = lv_label_create(s_qa_view);
    lv_label_set_text(qa_brand, "AI GUIDE");
    lv_obj_set_style_text_font(qa_brand, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_color(qa_brand, lv_color_hex(COLOR_HEADER), 0);
    lv_obj_set_pos(qa_brand, 18, 9);

    s_title = lv_label_create(s_qa_view);
    lv_label_set_text(s_title, "Waiting for phone");
    lv_obj_set_size(s_title, 135, 27);
    lv_label_set_long_mode(s_title, LV_LABEL_LONG_DOT);
    lv_obj_set_style_text_font(s_title, &guide_font_14, 0);
    lv_obj_set_style_text_color(s_title, lv_color_hex(COLOR_TICKET), 0);
    lv_obj_set_pos(s_title, 18, 24);

    s_status = lv_label_create(s_qa_view);
    lv_label_set_text(s_status, "Bluetooth");
    lv_obj_set_size(s_status, 80, 18);
    lv_label_set_long_mode(s_status, LV_LABEL_LONG_DOT);
    lv_obj_set_style_text_align(s_status, LV_TEXT_ALIGN_RIGHT, 0);
    lv_obj_set_style_text_font(s_status, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_color(s_status, lv_color_hex(COLOR_HEADER), 0);
    lv_obj_align(s_status, LV_ALIGN_TOP_RIGHT, -18, 15);

    s_question = lv_label_create(s_qa_view);
    lv_label_set_text(s_question, "长按 OK 后说出你的问题");
    lv_obj_set_size(s_question, 208, 27);
    lv_label_set_long_mode(s_question, LV_LABEL_LONG_DOT);
    lv_obj_set_style_text_font(s_question, &guide_font_14, 0);
    lv_obj_set_style_text_color(s_question, lv_color_hex(COLOR_HEADER), 0);
    lv_obj_set_pos(s_question, 16, 52);

    s_text_card = lv_obj_create(s_qa_view);
    lv_obj_set_size(s_text_card, 208, 196);
    lv_obj_set_pos(s_text_card, 16, 80);
    lv_obj_set_style_radius(s_text_card, 16, 0);
    lv_obj_set_style_bg_color(s_text_card, lv_color_hex(COLOR_TICKET), 0);
    lv_obj_set_style_border_width(s_text_card, 0, 0);
    lv_obj_set_style_pad_all(s_text_card, 14, 0);
    lv_obj_set_scroll_dir(s_text_card, LV_DIR_VER);
    lv_obj_set_scrollbar_mode(s_text_card, LV_SCROLLBAR_MODE_OFF);

    lv_obj_t *answer_tag = lv_label_create(s_text_card);
    lv_label_set_text(answer_tag, "导游回答");
    lv_obj_set_style_text_font(answer_tag, &guide_font_14, 0);
    lv_obj_set_style_text_color(answer_tag, lv_color_hex(COLOR_ACCENT), 0);

    s_text = lv_label_create(s_text_card);
    lv_obj_set_width(s_text, 176);
    lv_obj_set_height(s_text, LV_SIZE_CONTENT);
    lv_label_set_long_mode(s_text, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_color(s_text, lv_color_hex(COLOR_INK), 0);
    lv_obj_set_style_text_font(s_text, &guide_font_14, 0);
    lv_obj_set_style_text_line_space(s_text, -5, 0);
    lv_obj_set_pos(s_text, 0, 29);
    lv_label_set_text(s_text, "按住 OK 说话，松开后发送。");

    create_footer_label(s_qa_view, "UP VOL+", 10, COLOR_HEADER);
    create_footer_label(s_qa_view, "OK STOP", 86, COLOR_TICKET);
    create_footer_label(s_qa_view, "DOWN VOL-", 162, COLOR_HEADER);

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
    if (xTaskCreate(battery_worker, "guide_battery", 3072, NULL, 2, NULL) !=
        pdPASS) {
        ESP_LOGW(TAG, "battery UI worker could not start");
    }
    return guide_ble_start(ble_rx, ble_state, NULL);
}

void guide_app_button(bsp_btn_t button, bsp_btn_ev_t event)
{
    if (!s_event_queue) return;
    app_event_t app_event = {
        .type = APP_BUTTON,
        .button = button,
        .button_event = event,
    };
    (void)xQueueSend(s_event_queue, &app_event, 0);
}
