#include "guide_ble.h"

#include "esp_log.h"
#include "host/ble_att.h"
#include "host/ble_gap.h"
#include "host/ble_gatt.h"
#include "host/ble_hs.h"
#include "host/ble_hs_mbuf.h"
#include "host/ble_uuid.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"
#include <string.h>

static const char *TAG = "guide_ble";
static const char *DEVICE_NAME = "Passport Guide";
static const ble_uuid128_t SERVICE_UUID = BLE_UUID128_INIT(
    0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0,
    0x93, 0xf3, 0xa3, 0xb5, 0x01, 0x00, 0x40, 0x6e);
static const ble_uuid128_t RX_UUID = BLE_UUID128_INIT(
    0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0,
    0x93, 0xf3, 0xa3, 0xb5, 0x02, 0x00, 0x40, 0x6e);
static const ble_uuid128_t TX_UUID = BLE_UUID128_INIT(
    0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0,
    0x93, 0xf3, 0xa3, 0xb5, 0x03, 0x00, 0x40, 0x6e);

static uint8_t s_addr_type;
static uint16_t s_conn = BLE_HS_CONN_HANDLE_NONE;
static uint16_t s_tx_handle;
static bool s_subscribed;
static guide_ble_rx_cb_t s_rx;
static guide_ble_state_cb_t s_state;
static void *s_user;

static void report(void)
{
    uint16_t mtu = s_conn == BLE_HS_CONN_HANDLE_NONE ? 23 : ble_att_mtu(s_conn);
    if (s_state) s_state(s_conn != BLE_HS_CONN_HANDLE_NONE,
                         s_subscribed && mtu >= 168, mtu, s_user);
}

static int access_cb(uint16_t conn, uint16_t attr,
                     struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)attr;
    (void)arg;
    if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR) return BLE_ATT_ERR_UNLIKELY;
    uint16_t length = OS_MBUF_PKTLEN(ctxt->om);
    if (length == 0 || length > 512) return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    uint8_t buffer[512];
    uint16_t copied = 0;
    if (ble_hs_mbuf_to_flat(ctxt->om, buffer, sizeof(buffer), &copied) != 0) {
        return BLE_ATT_ERR_UNLIKELY;
    }
    if (s_rx) s_rx(buffer, copied, s_user);
    s_conn = conn;
    return 0;
}

static const struct ble_gatt_svc_def SERVICES[] = {{
    .type = BLE_GATT_SVC_TYPE_PRIMARY,
    .uuid = &SERVICE_UUID.u,
    .characteristics = (struct ble_gatt_chr_def[]) {{
        .uuid = &RX_UUID.u,
        .access_cb = access_cb,
        .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_NO_RSP,
    }, {
        .uuid = &TX_UUID.u,
        .access_cb = access_cb,
        .flags = BLE_GATT_CHR_F_NOTIFY,
        .val_handle = &s_tx_handle,
    }, {0}},
}, {0}};

static int gap_event(struct ble_gap_event *event, void *arg);

static int advertise(void)
{
    struct ble_hs_adv_fields fields = {0};
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.uuids128 = (ble_uuid128_t *)&SERVICE_UUID;
    fields.num_uuids128 = 1;
    fields.uuids128_is_complete = 1;
    int rc = ble_gap_adv_set_fields(&fields);
    if (rc) return rc;
    struct ble_hs_adv_fields response = {0};
    response.name = (const uint8_t *)DEVICE_NAME;
    response.name_len = strlen(DEVICE_NAME);
    response.name_is_complete = 1;
    rc = ble_gap_adv_rsp_set_fields(&response);
    if (rc) return rc;
    struct ble_gap_adv_params params = {0};
    params.conn_mode = BLE_GAP_CONN_MODE_UND;
    params.disc_mode = BLE_GAP_DISC_MODE_GEN;
    return ble_gap_adv_start(s_addr_type, NULL, BLE_HS_FOREVER, &params,
                             gap_event, NULL);
}

static int gap_event(struct ble_gap_event *event, void *arg)
{
    (void)arg;
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status == 0) s_conn = event->connect.conn_handle;
        else (void)advertise();
        report();
        return 0;
    case BLE_GAP_EVENT_DISCONNECT:
        s_conn = BLE_HS_CONN_HANDLE_NONE;
        s_subscribed = false;
        report();
        (void)advertise();
        return 0;
    case BLE_GAP_EVENT_SUBSCRIBE:
        if (event->subscribe.attr_handle == s_tx_handle) {
            s_subscribed = event->subscribe.cur_notify;
            report();
        }
        return 0;
    case BLE_GAP_EVENT_MTU:
        report();
        return 0;
    case BLE_GAP_EVENT_ADV_COMPLETE:
        (void)advertise();
        return 0;
    default:
        return 0;
    }
}

static void on_sync(void)
{
    int rc = ble_hs_util_ensure_addr(0);
    if (!rc) rc = ble_hs_id_infer_auto(0, &s_addr_type);
    if (!rc) rc = advertise();
    if (rc) ESP_LOGE(TAG, "BLE sync/advertise failed: %d", rc);
}

static void on_reset(int reason)
{
    ESP_LOGE(TAG, "NimBLE reset: %d", reason);
    s_conn = BLE_HS_CONN_HANDLE_NONE;
    s_subscribed = false;
    report();
}

static void host_task(void *arg)
{
    (void)arg;
    nimble_port_run();
    vTaskDelete(NULL);
}

esp_err_t guide_ble_start(guide_ble_rx_cb_t rx, guide_ble_state_cb_t state, void *user)
{
    s_rx = rx;
    s_state = state;
    s_user = user;
    esp_err_t err = nimble_port_init();
    if (err != ESP_OK) return err;
    ble_svc_gap_init();
    ble_svc_gatt_init();
    if (ble_svc_gap_device_name_set(DEVICE_NAME) != 0 ||
        ble_gatts_count_cfg(SERVICES) != 0 ||
        ble_gatts_add_svcs(SERVICES) != 0) return ESP_FAIL;
    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.reset_cb = on_reset;
    if (xTaskCreate(host_task, "guide_ble", NIMBLE_HS_STACK_SIZE, NULL,
                    configMAX_PRIORITIES - 4, NULL) != pdPASS) return ESP_ERR_NO_MEM;
    return ESP_OK;
}

bool guide_ble_ready(void)
{
    return s_conn != BLE_HS_CONN_HANDLE_NONE && s_subscribed &&
           ble_att_mtu(s_conn) >= 168;
}

esp_err_t guide_ble_notify(const uint8_t *data, size_t length)
{
    if (!guide_ble_ready()) return ESP_ERR_INVALID_STATE;
    if (!data || length == 0 || length > ble_att_mtu(s_conn) - 3) {
        return ESP_ERR_INVALID_SIZE;
    }
    struct os_mbuf *om = ble_hs_mbuf_from_flat(data, (uint16_t)length);
    if (!om) return ESP_ERR_NO_MEM;
    int rc = ble_gatts_notify_custom(s_conn, s_tx_handle, om);
    return rc == 0 ? ESP_OK : ESP_FAIL;
}
