#include "habit_app.h"

#include <stdio.h>
#include <string.h>

#include "bsp_display.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "habit_photo_format.h"
#include "habit_photo_portal.h"
#include "habit_photo_store.h"
#include "habit_store.h"
#include "lvgl.h"

#define GRID_WEEKS 13
#define GRID_DAYS (GRID_WEEKS * 7)
#define GRID_STRIDE 15
#define GRID_CELL_SIZE 13
#define FOOTER_SLOT_WIDTH 80
#define FOOTER_TEXT_Y 286
#define INPUT_QUEUE_DEPTH 8
#define SCREENSAVER_DELAY_MS 3000
#define PHOTO_INTERVAL_MS 5000

#define COLOR_BG       0x08111F
#define COLOR_PANEL    0x101E2D
#define COLOR_BORDER   0x26384A
#define COLOR_TEXT     0xE8F1F5
#define COLOR_MUTED    0x8293A1
#define COLOR_EMPTY    0x1B2A38
#define COLOR_ACTIVE   0x39D98A
#define COLOR_FUTURE   0x0D1722
#define COLOR_ACCENT   0xFFCC66
#define COLOR_ERROR    0xFF6B6B

typedef enum {
    SCREEN_HEATMAP = 0,
    SCREEN_DATE,
    SCREEN_SAVER,
    SCREEN_UPLOAD,
} screen_t;

typedef struct {
    uint8_t button;
    uint8_t event;
} input_message_t;

static const char *TAG = "habit_app";
static habit_model_t *s_model;
static bool s_storage_available;
static bool s_photo_available;
static int s_battery_soc;
static screen_t s_screen_kind;
static int32_t s_selected_day;
static int32_t s_page_anchor;
static int32_t s_grid_start;
static habit_date_t s_draft_date;
static habit_date_field_t s_date_field;
static QueueHandle_t s_input_queue;
static TaskHandle_t s_input_task;
static volatile bool s_input_ready;
static lv_obj_t *s_screen;
static lv_obj_t *s_grid;
static lv_obj_t *s_streak_label;
static lv_obj_t *s_selected_label;
static lv_obj_t *s_date_values[3];
static lv_obj_t *s_upload_status;
static lv_obj_t *s_upload_progress;
static lv_timer_t *s_ui_timer;
static uint32_t s_last_activity;
static uint32_t s_last_photo;
static unsigned s_photo_slot;
static lv_image_dsc_t s_photo_image;
static bool s_ignore_wake_button;

static lv_obj_t *label(lv_obj_t *parent, const char *text, int x, int y,
                       const lv_font_t *font, uint32_t color)
{
    lv_obj_t *object = lv_label_create(parent);
    lv_label_set_text(object, text);
    lv_obj_set_pos(object, x, y);
    lv_obj_set_style_text_font(object, font, 0);
    lv_obj_set_style_text_color(object, lv_color_hex(color), 0);
    return object;
}

static lv_obj_t *panel(lv_obj_t *parent, int x, int y, int width, int height)
{
    lv_obj_t *object = lv_obj_create(parent);
    lv_obj_remove_flag(object, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_pos(object, x, y);
    lv_obj_set_size(object, width, height);
    lv_obj_set_style_pad_all(object, 0, 0);
    lv_obj_set_style_radius(object, 10, 0);
    lv_obj_set_style_border_width(object, 1, 0);
    lv_obj_set_style_border_color(object, lv_color_hex(COLOR_BORDER), 0);
    lv_obj_set_style_bg_color(object, lv_color_hex(COLOR_PANEL), 0);
    return object;
}

static lv_obj_t *base_screen(const char *title)
{
    lv_obj_t *screen = lv_obj_create(NULL);
    lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_pad_all(screen, 0, 0);
    lv_obj_set_style_border_width(screen, 0, 0);
    lv_obj_set_style_bg_color(screen, lv_color_hex(COLOR_BG), 0);
    label(screen, title, 14, 10, &lv_font_montserrat_20, COLOR_TEXT);
    if (s_battery_soc >= 0) {
        char battery[12];
        snprintf(battery, sizeof(battery), "%d%%", s_battery_soc);
        lv_obj_t *right = label(screen, battery, 0, 13,
                                &lv_font_montserrat_14, COLOR_MUTED);
        lv_obj_align(right, LV_ALIGN_TOP_RIGHT, -14, 13);
    }
    return screen;
}

static void load_screen(lv_obj_t *screen)
{
    lv_obj_t *old = s_screen;
    s_screen = screen;
    lv_screen_load(screen);
    if (old) lv_obj_delete(old);
}

static void date_text(char *buffer, size_t size, int32_t day)
{
    habit_date_t date = habit_day_to_date(day);
    snprintf(buffer, size, "%04d-%02d-%02d", date.year, date.month, date.day);
}

static void refresh_heatmap(void)
{
    s_grid_start = habit_grid_start(s_page_anchor, GRID_WEEKS);
    lv_obj_invalidate(s_grid);
    char text[40];
    snprintf(text, sizeof(text), "%u STREAK    %u TOTAL",
             habit_model_streak(s_model), s_model->checked_count);
    lv_label_set_text(s_streak_label, text);
    date_text(text, sizeof(text), s_selected_day);
    lv_label_set_text(s_selected_label, text);
}

static void grid_draw_event(lv_event_t *event)
{
    lv_obj_t *grid = lv_event_get_target_obj(event);
    lv_layer_t *layer = lv_event_get_layer(event);
    lv_area_t area;
    lv_obj_get_coords(grid, &area);

    for (int week = 0; week < GRID_WEEKS; ++week) {
        for (int weekday = 0; weekday < 7; ++weekday) {
            int32_t day = s_grid_start + week * 7 + weekday;
            uint32_t fill = habit_model_is_checked(s_model, day)
                ? COLOR_ACTIVE : COLOR_EMPTY;
            if (day > s_model->current_day) fill = COLOR_FUTURE;
            lv_area_t cell = {
                .x1 = area.x1 + week * GRID_STRIDE,
                .y1 = area.y1 + weekday * GRID_STRIDE,
                .x2 = area.x1 + week * GRID_STRIDE + GRID_CELL_SIZE - 1,
                .y2 = area.y1 + weekday * GRID_STRIDE + GRID_CELL_SIZE - 1,
            };
            lv_draw_rect_dsc_t draw;
            lv_draw_rect_dsc_init(&draw);
            draw.bg_opa = LV_OPA_COVER;
            draw.bg_color = lv_color_hex(fill);
            draw.radius = 3;
            if (day == s_selected_day) {
                draw.border_width = 2;
                draw.border_color = lv_color_hex(COLOR_ACCENT);
                draw.border_opa = LV_OPA_COVER;
            }
            lv_draw_rect(layer, &draw, &cell);
        }
    }
}

static void month_labels(lv_obj_t *parent)
{
    int previous = -1;
    for (int week = 0; week < GRID_WEEKS; ++week) {
        habit_date_t date = habit_day_to_date(s_grid_start + week * 7);
        if (date.month == previous) continue;
        static const char *names[] = {
            "", "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
            "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"
        };
        label(parent, names[date.month], 27 + week * GRID_STRIDE, 8,
              &lv_font_montserrat_12, COLOR_MUTED);
        previous = date.month;
    }
}

static void footer_hint(lv_obj_t *parent, const char *text, int slot,
                        uint32_t color)
{
    lv_obj_t *hint = label(parent, text, slot * FOOTER_SLOT_WIDTH,
                           FOOTER_TEXT_Y, &lv_font_montserrat_12, color);
    lv_obj_set_width(hint, FOOTER_SLOT_WIDTH);
    lv_obj_set_style_text_align(hint, LV_TEXT_ALIGN_CENTER, 0);
}

static void build_heatmap(void)
{
    s_screen_kind = SCREEN_HEATMAP;
    s_last_activity = lv_tick_get();
    s_grid_start = habit_grid_start(s_page_anchor, GRID_WEEKS);
    lv_obj_t *screen = base_screen("GLOW");
    s_selected_label = label(screen, "", 14, 43, &lv_font_montserrat_20, COLOR_TEXT);
    s_streak_label = label(screen, "", 14, 75, &lv_font_montserrat_14, COLOR_ACTIVE);

    lv_obj_t *card = panel(screen, 8, 105, 224, 160);
    month_labels(card);
    label(card, "M", 7, 37, &lv_font_montserrat_12, COLOR_MUTED);
    label(card, "W", 6, 67, &lv_font_montserrat_12, COLOR_MUTED);
    label(card, "F", 8, 97, &lv_font_montserrat_12, COLOR_MUTED);

    s_grid = lv_obj_create(card);
    lv_obj_remove_flag(s_grid, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_pos(s_grid, 24, 30);
    lv_obj_set_size(s_grid, 193, 103);
    lv_obj_set_style_pad_all(s_grid, 0, 0);
    lv_obj_set_style_border_width(s_grid, 0, 0);
    lv_obj_set_style_bg_opa(s_grid, LV_OPA_TRANSP, 0);
    lv_obj_add_event_cb(s_grid, grid_draw_event, LV_EVENT_DRAW_MAIN_END, NULL);
    label(card, "CHECKED DAYS", 24, 139, &lv_font_montserrat_12, COLOR_MUTED);
    lv_obj_t *range = label(card, "13 WEEKS", 0, 139,
                            &lv_font_montserrat_12, COLOR_MUTED);
    lv_obj_align(range, LV_ALIGN_TOP_RIGHT, -8, 139);

    footer_hint(screen, "UP PREV", 0, COLOR_MUTED);
    footer_hint(screen, "OK TOGGLE", 1, COLOR_TEXT);
    footer_hint(screen, "DOWN NEXT", 2, COLOR_MUTED);
    load_screen(screen);
    refresh_heatmap();
}

static void refresh_date_screen(void)
{
    char values[3][8];
    snprintf(values[0], sizeof(values[0]), "%04d", s_draft_date.year);
    snprintf(values[1], sizeof(values[1]), "%02d", s_draft_date.month);
    snprintf(values[2], sizeof(values[2]), "%02d", s_draft_date.day);
    for (int i = 0; i < 3; ++i) {
        lv_label_set_text(s_date_values[i], values[i]);
        lv_obj_set_style_text_color(s_date_values[i],
            lv_color_hex(i == (int)s_date_field ? COLOR_ACCENT : COLOR_TEXT), 0);
    }
}

static void build_date_screen(void)
{
    s_screen_kind = SCREEN_DATE;
    s_draft_date = habit_day_to_date(s_model->current_day);
    s_date_field = HABIT_DATE_YEAR;
    lv_obj_t *screen = base_screen("SET DATE");
    label(screen, s_model->date_set ? "ADJUST OFFLINE CALENDAR" : "CONFIRM DATE TO START",
          18, 57, &lv_font_montserrat_14,
          s_model->date_set ? COLOR_MUTED : COLOR_ACCENT);
    static const char *names[] = { "YEAR", "MONTH", "DAY" };
    for (int i = 0; i < 3; ++i) {
        lv_obj_t *box = panel(screen, 13 + i * 73, 101, 68, 89);
        label(box, names[i], 8, 10, &lv_font_montserrat_14, COLOR_MUTED);
        s_date_values[i] = label(box, "", 8, 42,
                                 &lv_font_montserrat_20, COLOR_TEXT);
    }
    label(screen, "UP/DOWN CHANGE", 13, 253, &lv_font_montserrat_14, COLOR_TEXT);
    label(screen, "OK NEXT / SAVE", 13, 278, &lv_font_montserrat_14, COLOR_ACCENT);
    load_screen(screen);
    refresh_date_screen();
}

static int next_photo_slot(unsigned after)
{
    for (unsigned step = 1; step <= HABIT_PHOTO_MAX_COUNT; ++step) {
        unsigned slot = (after + step) % HABIT_PHOTO_MAX_COUNT;
        if (habit_photo_store_slot_valid(slot)) return (int)slot;
    }
    return -1;
}

static bool show_photo(unsigned slot)
{
    const uint8_t *pixels = habit_photo_store_map(slot);
    if (!pixels) return false;
    memset(&s_photo_image, 0, sizeof(s_photo_image));
    s_photo_image.header.magic = LV_IMAGE_HEADER_MAGIC;
    s_photo_image.header.cf = LV_COLOR_FORMAT_RGB565;
    s_photo_image.header.w = HABIT_PHOTO_WIDTH;
    s_photo_image.header.h = HABIT_PHOTO_HEIGHT;
    s_photo_image.header.stride = HABIT_PHOTO_WIDTH * 2U;
    s_photo_image.data_size = HABIT_PHOTO_BYTES;
    s_photo_image.data = pixels;
    lv_obj_t *image = lv_image_create(s_screen);
    lv_image_set_src(image, &s_photo_image);
    lv_obj_center(image);
    return true;
}

static void build_saver(void)
{
    int first = next_photo_slot(HABIT_PHOTO_MAX_COUNT - 1U);
    if (first < 0) return;
    s_screen_kind = SCREEN_SAVER;
    s_photo_slot = (unsigned)first;
    lv_obj_t *screen = lv_obj_create(NULL);
    lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_pad_all(screen, 0, 0);
    lv_obj_set_style_border_width(screen, 0, 0);
    lv_obj_set_style_bg_color(screen, lv_color_black(), 0);
    load_screen(screen);
    (void)show_photo(s_photo_slot);
    s_last_photo = lv_tick_get();
}

static void advance_photo(void)
{
    int next = next_photo_slot(s_photo_slot);
    if (next < 0 || (unsigned)next == s_photo_slot) {
        s_last_photo = lv_tick_get();
        return;
    }
    lv_obj_clean(s_screen);
    habit_photo_store_unmap();
    s_photo_slot = (unsigned)next;
    (void)show_photo(s_photo_slot);
    s_last_photo = lv_tick_get();
}

static const char *portal_state_text(habit_photo_portal_status_t status)
{
    switch (status.state) {
    case HABIT_PHOTO_PORTAL_STARTING: return "STARTING HOTSPOT...";
    case HABIT_PHOTO_PORTAL_READY: return "READY FOR PHONE";
    case HABIT_PHOTO_PORTAL_RECEIVING: return "RECEIVING PHOTO";
    case HABIT_PHOTO_PORTAL_DELETING: return "DELETING PHOTO";
    case HABIT_PHOTO_PORTAL_COMPLETE: return "PHOTO SAVED";
    case HABIT_PHOTO_PORTAL_ERROR: return "UPLOAD ERROR";
    default: return "HOTSPOT OFF";
    }
}

static void refresh_upload(void)
{
    if (!s_upload_status || !s_upload_progress) return;
    habit_photo_portal_status_t status = habit_photo_portal_status();
    char text[96];
    if (status.state == HABIT_PHOTO_PORTAL_RECEIVING && status.total) {
        unsigned percent = (unsigned)((uint64_t)status.received * 100U / status.total);
        snprintf(text, sizeof(text), "%s  %u%%", portal_state_text(status),
                 percent);
        lv_bar_set_value(s_upload_progress, (int32_t)percent, LV_ANIM_OFF);
    } else {
        snprintf(text, sizeof(text), "%s  %u / %u",
                 portal_state_text(status), status.photo_count,
                 HABIT_PHOTO_MAX_COUNT);
        lv_bar_set_value(s_upload_progress,
                         status.state == HABIT_PHOTO_PORTAL_COMPLETE ? 100 : 0,
                         LV_ANIM_OFF);
    }
    lv_label_set_text(s_upload_status, text);
    lv_obj_set_style_text_color(
        s_upload_status,
        lv_color_hex(status.state == HABIT_PHOTO_PORTAL_ERROR
                     ? COLOR_ERROR : COLOR_TEXT), 0);
}

static void build_upload(void)
{
    s_screen_kind = SCREEN_UPLOAD;
    lv_obj_t *screen = base_screen("ADD PHOTOS");
    char payload[128];
    snprintf(payload, sizeof(payload), "WIFI:T:WPA;S:%s;P:%s;;",
             habit_photo_portal_ssid(), habit_photo_portal_password());
    lv_obj_t *qr = lv_qrcode_create(screen);
    lv_qrcode_set_size(qr, 132);
    lv_qrcode_set_dark_color(qr, lv_color_hex(COLOR_BG));
    lv_qrcode_set_light_color(qr, lv_color_hex(COLOR_TEXT));
    lv_qrcode_set_quiet_zone(qr, true);
    lv_qrcode_set_data(qr, payload);
    lv_obj_set_pos(qr, 54, 43);

    char text[64];
    snprintf(text, sizeof(text), "WIFI  %s", habit_photo_portal_ssid());
    label(screen, text, 14, 186, &lv_font_montserrat_14, COLOR_ACTIVE);
    snprintf(text, sizeof(text), "PASS  %s", habit_photo_portal_password());
    label(screen, text, 14, 209, &lv_font_montserrat_14, COLOR_TEXT);
    label(screen, "OPEN  192.168.4.1", 14, 232,
          &lv_font_montserrat_14, COLOR_MUTED);

    s_upload_status = label(screen, "", 14, 260,
                            &lv_font_montserrat_12, COLOR_TEXT);
    s_upload_progress = lv_bar_create(screen);
    lv_obj_set_pos(s_upload_progress, 14, 279);
    lv_obj_set_size(s_upload_progress, 212, 6);
    lv_bar_set_range(s_upload_progress, 0, 100);
    lv_obj_set_style_bg_color(s_upload_progress, lv_color_hex(COLOR_EMPTY),
                              LV_PART_MAIN);
    lv_obj_set_style_bg_color(s_upload_progress, lv_color_hex(COLOR_ACTIVE),
                              LV_PART_INDICATOR);
    lv_obj_t *exit = label(screen, "HOLD UP TO EXIT", 0, 295,
                           &lv_font_montserrat_12, COLOR_ACCENT);
    lv_obj_set_width(exit, 240);
    lv_obj_set_style_text_align(exit, LV_TEXT_ALIGN_CENTER, 0);
    load_screen(screen);
    refresh_upload();
}

static void ui_timer(lv_timer_t *timer)
{
    (void)timer;
    if (s_screen_kind == SCREEN_HEATMAP && s_photo_available &&
        lv_tick_elaps(s_last_activity) >= SCREENSAVER_DELAY_MS) {
        build_saver();
    } else if (s_screen_kind == SCREEN_SAVER &&
               lv_tick_elaps(s_last_photo) >= PHOTO_INTERVAL_MS) {
        advance_photo();
    } else if (s_screen_kind == SCREEN_UPLOAD) {
        refresh_upload();
    }
}

static void move_selection(int delta)
{
    int32_t next = s_selected_day + delta;
    if (next > s_model->current_day) return;
    s_selected_day = next;
    int32_t end = s_grid_start + GRID_DAYS - 1;
    if (next < s_grid_start || next > end) {
        s_page_anchor = next;
        build_heatmap();
    } else {
        refresh_heatmap();
    }
}

static void move_page(int direction)
{
    int32_t anchor = s_page_anchor + direction * GRID_DAYS;
    if (anchor > s_model->current_day) anchor = s_model->current_day;
    s_page_anchor = anchor;
    int32_t start = habit_grid_start(anchor, GRID_WEEKS);
    int32_t end = start + GRID_DAYS - 1;
    s_selected_day = direction < 0 ? end : start;
    if (s_selected_day > s_model->current_day) s_selected_day = s_model->current_day;
    build_heatmap();
}

static void save_date(void)
{
    habit_model_set_current_date(s_model, s_draft_date);
    s_selected_day = s_model->current_day;
    s_page_anchor = s_model->current_day;
    if (s_storage_available) habit_store_request_save(s_model);
    build_heatmap();
}

static void process_input(const input_message_t *input)
{
    bsp_btn_t button = (bsp_btn_t)input->button;
    bsp_btn_ev_t event = (bsp_btn_ev_t)input->event;
    if (!bsp_lvgl_lock(500)) return;

    if (s_screen_kind == SCREEN_SAVER) {
        s_ignore_wake_button = event == BSP_BTN_PRESS;
        build_heatmap();
        habit_photo_store_unmap();
        bsp_lvgl_unlock();
        return;
    }
    if (s_ignore_wake_button) {
        if (event == BSP_BTN_CLICK || event == BSP_BTN_LONG) {
            s_ignore_wake_button = false;
        }
        bsp_lvgl_unlock();
        return;
    }
    if (s_screen_kind == SCREEN_UPLOAD) {
        if (event == BSP_BTN_LONG && button == BSP_BTN_UP) {
            bsp_lvgl_unlock();
            esp_err_t err = habit_photo_portal_stop();
            if (err != ESP_OK) {
                ESP_LOGW(TAG, "photo portal stop deferred: %s",
                         esp_err_to_name(err));
                return;
            }
            if (!bsp_lvgl_lock(500)) return;
            s_photo_available = habit_photo_store_count() > 0;
            s_upload_status = NULL;
            s_upload_progress = NULL;
            build_heatmap();
        }
        bsp_lvgl_unlock();
        return;
    }
    if (s_screen_kind == SCREEN_DATE) {
        if (event == BSP_BTN_CLICK && (button == BSP_BTN_UP || button == BSP_BTN_DOWN)) {
            int delta = button == BSP_BTN_UP ? 1 : -1;
            s_draft_date = habit_date_adjust(s_draft_date, s_date_field, delta);
            refresh_date_screen();
        } else if (event == BSP_BTN_CLICK && button == BSP_BTN_OK) {
            if (s_date_field == HABIT_DATE_DAY) save_date();
            else {
                s_date_field = (habit_date_field_t)((int)s_date_field + 1);
                refresh_date_screen();
            }
        } else if (event == BSP_BTN_LONG && button == BSP_BTN_OK) {
            save_date();
        }
        bsp_lvgl_unlock();
        return;
    }

    s_last_activity = lv_tick_get();
    if (event == BSP_BTN_CLICK && button == BSP_BTN_UP) {
        move_selection(-1);
    } else if (event == BSP_BTN_CLICK && button == BSP_BTN_DOWN) {
        move_selection(1);
    } else if (event == BSP_BTN_CLICK && button == BSP_BTN_OK) {
        if (habit_model_toggle(s_model, s_selected_day)) {
            if (s_storage_available) habit_store_request_save(s_model);
            refresh_heatmap();
        }
    } else if (event == BSP_BTN_LONG && button == BSP_BTN_UP) {
        bsp_lvgl_unlock();
        esp_err_t err = habit_photo_portal_start();
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "photo portal start failed: %s",
                     esp_err_to_name(err));
            return;
        }
        if (!bsp_lvgl_lock(500)) {
            (void)habit_photo_portal_stop();
            return;
        }
        build_upload();
    } else if (event == BSP_BTN_LONG && button == BSP_BTN_DOWN) {
        move_page(-1);
    } else if (event == BSP_BTN_LONG && button == BSP_BTN_OK) {
        build_date_screen();
    }
    bsp_lvgl_unlock();
}

static void input_task(void *context)
{
    (void)context;
    input_message_t input;
    for (;;) {
        if (xQueueReceive(s_input_queue, &input, portMAX_DELAY) == pdTRUE) {
            process_input(&input);
        }
    }
}

bool habit_app_start(habit_model_t *model, bool storage_available, int battery_soc)
{
    if (!model || s_input_queue) return false;
    s_model = model;
    s_storage_available = storage_available;
    s_battery_soc = battery_soc;
    s_photo_available = habit_photo_store_init();
    s_photo_available = s_photo_available && habit_photo_store_count() > 0;
    s_selected_day = model->current_day;
    s_page_anchor = model->current_day;
    s_input_queue = xQueueCreate(INPUT_QUEUE_DEPTH, sizeof(input_message_t));
    if (!s_input_queue) return false;
    if (xTaskCreate(input_task, "habit_input", 4096, NULL, 5,
                    &s_input_task) != pdPASS) {
        vQueueDelete(s_input_queue);
        s_input_queue = NULL;
        return false;
    }
    if (!bsp_lvgl_lock(1000)) {
        vTaskDelete(s_input_task);
        s_input_task = NULL;
        vQueueDelete(s_input_queue);
        s_input_queue = NULL;
        return false;
    }
    if (model->date_set) build_heatmap();
    else build_date_screen();
    s_ui_timer = lv_timer_create(ui_timer, 100, NULL);
    bsp_lvgl_unlock();
    s_input_ready = true;
    return true;
}

void habit_app_button(bsp_btn_t button, bsp_btn_ev_t event)
{
    if (!s_input_ready || !s_input_queue) return;
    input_message_t input = { .button = (uint8_t)button, .event = (uint8_t)event };
    (void)xQueueSend(s_input_queue, &input, 0);
}
