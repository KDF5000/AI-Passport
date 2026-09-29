#pragma once

#include "esp_err.h"
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef void (*guide_ble_rx_cb_t)(const uint8_t *data, size_t length, void *user);
typedef void (*guide_ble_state_cb_t)(bool connected, bool ready, uint16_t mtu, void *user);

esp_err_t guide_ble_start(guide_ble_rx_cb_t rx, guide_ble_state_cb_t state, void *user);
esp_err_t guide_ble_notify(const uint8_t *data, size_t length);
bool guide_ble_ready(void);
