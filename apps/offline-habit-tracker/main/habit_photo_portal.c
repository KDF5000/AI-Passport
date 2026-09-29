#include "habit_photo_portal.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "esp_event.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "habit_photo_format.h"
#include "habit_photo_store.h"
#include "lwip/inet.h"
#include "lwip/sockets.h"

#define HTTP_BUFFER_BYTES 1024
#define HTTP_RECEIVE_RETRIES 5
#define DNS_STOP_WAIT_MS 1500
#define HABIT_AP_PASSWORD "12345678"

static const char *TAG = "habit_portal";
static const char *PORTAL_ADDRESS = "192.168.4.1";
static httpd_handle_t s_http;
static esp_netif_t *s_ap_netif;
static TaskHandle_t s_dns_task;
static bool s_netif_ready;
static bool s_event_loop_ready;
static bool s_wifi_initialized;
static bool s_running;
static volatile bool s_dns_running;
static char s_ssid[33];
static char s_password[17];
static portMUX_TYPE s_status_lock = portMUX_INITIALIZER_UNLOCKED;
static habit_photo_portal_status_t s_status;

typedef struct __attribute__((packed)) {
    uint16_t id;
    uint16_t flags;
    uint16_t questions;
    uint16_t answers;
    uint16_t authority;
    uint16_t additional;
} dns_header_t;

typedef struct __attribute__((packed)) {
    uint16_t pointer;
    uint16_t type;
    uint16_t class_value;
    uint32_t ttl;
    uint16_t length;
    uint32_t address;
} dns_answer_t;

static const char PAGE_HTML[] =
"<!doctype html><html lang=zh-CN><head><meta charset=utf-8>"
"<meta name=viewport content='width=device-width,initial-scale=1,viewport-fit=cover'>"
"<title>FoloHabit 照片上传</title><style>"
":root{color-scheme:dark;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}"
"*{box-sizing:border-box}body{margin:0;background:#08111f;color:#e8f1f5}"
"main{width:min(560px,calc(100% - 28px));margin:24px auto 48px}"
"h1,h2{margin:0 0 8px}h1{font-size:28px}h2{font-size:20px}p{color:#91a1ae;line-height:1.55}"
".card{padding:18px;border:1px solid #26384a;border-radius:18px;background:#101e2d}"
".preview{display:block;width:180px;height:240px;margin:auto;border-radius:12px;background:#050a11}"
".row{display:flex;flex-wrap:wrap;gap:10px;margin:16px 0}"
"button,label{border:1px solid #385166;border-radius:999px;padding:11px 16px;"
"background:#172637;color:#e8f1f5;cursor:pointer;font:inherit}"
"button.primary{background:#1d6f50;border-color:#39d98a}.danger{color:#ff9e9e;border-color:#71383f}"
"button:disabled{opacity:.45}.manage{margin-top:16px}.photos{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:14px}"
".photo{padding:8px;border-radius:12px;background:#08111f}.photo canvas{display:block;width:100%;aspect-ratio:3/4;border-radius:7px}"
".photo button{width:100%;margin-top:8px;padding:7px 4px;font-size:13px}"
"input{display:none}progress{width:100%;accent-color:#39d98a}"
"#status{min-height:48px;color:#ffcc66;white-space:pre-line}</style></head><body><main>"
"<h1>FoloHabit 照片上传</h1>"
"<p>照片只会通过当前设备热点直接写入 Passport，不经过互联网。</p><section class=card>"
"<canvas id=preview class=preview width=240 height=320></canvas><div class=row>"
"<label for=file>选择照片</label><input id=file type=file accept='image/*'>"
"<button id=upload class=primary disabled>上传到 Passport</button></div>"
"<progress id=progress max=100 value=0></progress>"
"<p id=status>请选择一张照片。浏览器会居中裁剪为 240×320。</p></section>"
"<section class='card manage'><h2>管理设备照片</h2><p id=count>正在读取…</p>"
"<div id=photos class=photos></div><div class=row>"
"<button id=clear class=danger disabled>删除全部照片</button></div></section>"
"<p>最多保存 13 张。上传完成后，可继续选择下一张；完成全部上传后，在设备上长按 UP 返回首页。</p>"
"</main><script>"
"const BYTES=240*320*2,$=q=>document.querySelector(q),c=$('#preview'),x=c.getContext('2d',{alpha:false});"
"let rgb=null;const say=t=>$('#status').textContent=t;"
"function crc32(a){let c=0xffffffff;for(const b of a){c^=b;for(let i=0;i<8;i++)c=(c>>>1)^((c&1)?0xedb88320:0)}return(~c)>>>0}"
"function convert(){let p=x.getImageData(0,0,240,320).data,o=new Uint8Array(BYTES);"
"for(let i=0,j=0;i<p.length;i+=4,j+=2){let v=((p[i]>>3)<<11)|((p[i+1]>>2)<<5)|(p[i+2]>>3);o[j]=v&255;o[j+1]=v>>8}return o}"
"function draw565(canvas,a){let g=canvas.getContext('2d'),im=g.createImageData(240,320),p=im.data;"
"for(let i=0,j=0;i<a.length;i+=2,j+=4){let v=a[i]|(a[i+1]<<8);p[j]=((v>>11)&31)*255/31;p[j+1]=((v>>5)&63)*255/63;p[j+2]=(v&31)*255/31;p[j+3]=255}g.putImageData(im,0,0)}"
"async function remove(url,button){button.disabled=true;$('#count').textContent='正在删除，请稍候…';"
"try{let r=await fetch(url,{method:'POST'});if(!r.ok)throw new Error(await r.text()||('HTTP '+r.status));"
"await refresh();$('#count').textContent+=' · 删除完成'}catch(e){$('#count').textContent='删除失败：'+e.message;button.disabled=false}}"
"async function refresh(){let s=await (await fetch('/status',{cache:'no-store'})).json(),box=$('#photos');box.textContent='';"
"$('#count').textContent='设备现有 '+s.count+' / 13 张照片';$('#clear').disabled=!s.count;"
"for(let n=0;n<13;n++)if(s.mask&(1<<n)){let d=document.createElement('div'),v=document.createElement('canvas'),b=document.createElement('button');"
"d.className='photo';v.width=240;v.height=320;b.className='danger';b.textContent='删除照片 '+(n+1);d.append(v,b);box.append(d);"
"fetch('/photo?slot='+n).then(r=>r.arrayBuffer()).then(a=>draw565(v,new Uint8Array(a)));"
"b.onclick=()=>{if(b.dataset.confirm!=='yes'){b.dataset.confirm='yes';b.textContent='再次点按确认';"
"setTimeout(()=>{if(b.isConnected){b.dataset.confirm='';b.textContent='删除照片 '+(n+1)}},4000);return}"
"remove('/delete?slot='+n,b)}}}"
"$('#file').onchange=async e=>{let f=e.target.files[0];if(!f)return;try{let b=await createImageBitmap(f),"
"s=Math.max(240/b.width,320/b.height),w=b.width*s,h=b.height*s;x.fillStyle='#000';x.fillRect(0,0,240,320);"
"x.drawImage(b,(240-w)/2,(320-h)/2,w,h);b.close();rgb=convert();$('#progress').value=0;"
"$('#upload').disabled=false;say('已准备 '+f.name+'\\n设备数据：'+rgb.length+' 字节')}catch(e){say('无法读取照片：'+e.message)}};"
"$('#upload').onclick=async()=>{if(!rgb)return;let b=$('#upload');b.disabled=true;try{"
"say('正在上传，请保持手机连接设备热点…');let r=await fetch('/photo',{method:'POST',"
"headers:{'Content-Type':'application/octet-stream','X-Photo-CRC32':crc32(rgb).toString(16)},body:rgb});"
"if(!r.ok)throw new Error(await r.text()||('HTTP '+r.status));let j=await r.json();"
"$('#progress').value=100;say('上传完成。设备现有 '+j.count+' 张照片。');await refresh()}catch(e){"
"say('上传失败：'+e.message+'\\n请确认手机仍连接 FoloHabit 热点。')}finally{b.disabled=!rgb}};"
"$('#clear').onclick=()=>{let b=$('#clear');if(b.dataset.confirm!=='yes'){b.dataset.confirm='yes';"
"b.textContent='再次点按，删除全部';setTimeout(()=>{if(b.isConnected){b.dataset.confirm='';"
"b.textContent='删除全部照片'}},4000);return}remove('/clear',b)};"
"refresh().catch(e=>$('#count').textContent='读取照片失败：'+e.message);"
"</script></body></html>";

static void set_status(habit_photo_portal_state_t state, uint32_t received,
                       uint32_t total, int error)
{
    unsigned photo_count = habit_photo_store_count();
    portENTER_CRITICAL(&s_status_lock);
    s_status.state = state;
    s_status.received = received;
    s_status.total = total;
    s_status.photo_count = photo_count;
    s_status.error = error;
    portEXIT_CRITICAL(&s_status_lock);
}

habit_photo_portal_status_t habit_photo_portal_status(void)
{
    habit_photo_portal_status_t status;
    portENTER_CRITICAL(&s_status_lock);
    status = s_status;
    portEXIT_CRITICAL(&s_status_lock);
    return status;
}

static size_t dns_question_end(const uint8_t *packet, size_t length)
{
    size_t index = sizeof(dns_header_t);
    while (index < length && packet[index] != 0) {
        size_t label = packet[index];
        if (label > 63 || index + label + 1 >= length) return 0;
        index += label + 1;
    }
    return index + 5 <= length ? index + 5 : 0;
}

static void dns_task(void *context)
{
    (void)context;
    int fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_IP);
    struct sockaddr_in address = {
        .sin_family = AF_INET,
        .sin_port = htons(53),
        .sin_addr.s_addr = htonl(INADDR_ANY),
    };
    struct timeval timeout = {.tv_sec = 1};
    uint8_t packet[320];
    if (fd < 0 || bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        if (fd >= 0) close(fd);
        s_dns_task = NULL;
        vTaskDelete(NULL);
        return;
    }
    (void)setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    while (s_dns_running) {
        struct sockaddr_in source;
        socklen_t source_length = sizeof(source);
        int length = recvfrom(fd, packet,
                              sizeof(packet) - sizeof(dns_answer_t), 0,
                              (struct sockaddr *)&source, &source_length);
        if (length <= 0) continue;
        size_t end = dns_question_end(packet, (size_t)length);
        dns_header_t *header = (dns_header_t *)packet;
        if (end == 0 || ntohs(header->questions) != 1) continue;
        header->flags = htons(0x8180);
        header->answers = htons(1);
        dns_answer_t *answer = (dns_answer_t *)(packet + length);
        answer->pointer = htons(0xC00C);
        answer->type = htons(1);
        answer->class_value = htons(1);
        answer->ttl = htonl(30);
        answer->length = htons(4);
        answer->address = inet_addr(PORTAL_ADDRESS);
        (void)sendto(fd, packet, length + sizeof(*answer), 0,
                     (struct sockaddr *)&source, source_length);
    }
    close(fd);
    s_dns_task = NULL;
    vTaskDelete(NULL);
}

static esp_err_t root_get(httpd_req_t *request)
{
    httpd_resp_set_type(request, "text/html; charset=utf-8");
    httpd_resp_set_hdr(request, "Cache-Control", "no-store");
    return httpd_resp_send(request, PAGE_HTML, HTTPD_RESP_USE_STRLEN);
}

static esp_err_t status_get(httpd_req_t *request)
{
    habit_photo_portal_status_t status = habit_photo_portal_status();
    char json[176];
    snprintf(json, sizeof(json),
             "{\"state\":%u,\"received\":%lu,\"total\":%lu,\"count\":%u,"
             "\"mask\":%u,\"error\":%d}",
             (unsigned)status.state, (unsigned long)status.received,
             (unsigned long)status.total, status.photo_count,
             habit_photo_store_valid_mask(), status.error);
    httpd_resp_set_type(request, "application/json");
    httpd_resp_set_hdr(request, "Cache-Control", "no-store");
    return httpd_resp_sendstr(request, json);
}

static bool request_slot(httpd_req_t *request, unsigned *slot)
{
    char query[24] = {0};
    char value[5] = {0};
    if (httpd_req_get_url_query_str(request, query, sizeof(query)) != ESP_OK ||
        httpd_query_key_value(query, "slot", value, sizeof(value)) != ESP_OK) {
        return false;
    }
    errno = 0;
    char *end = NULL;
    unsigned long parsed = strtoul(value, &end, 10);
    if (errno || !end || *end != '\0' || parsed >= HABIT_PHOTO_MAX_COUNT) {
        return false;
    }
    *slot = (unsigned)parsed;
    return true;
}

static esp_err_t photo_get(httpd_req_t *request)
{
    unsigned slot = 0;
    if (!request_slot(request, &slot) ||
        !habit_photo_store_slot_valid(slot)) {
        return httpd_resp_send_err(request, HTTPD_404_NOT_FOUND,
                                   "照片不存在");
    }
    const uint8_t *photo = habit_photo_store_map(slot);
    if (!photo) {
        return httpd_resp_send_err(request, HTTPD_500_INTERNAL_SERVER_ERROR,
                                   "无法读取照片");
    }
    httpd_resp_set_type(request, "application/octet-stream");
    httpd_resp_set_hdr(request, "Cache-Control", "no-store");
    esp_err_t err = httpd_resp_send(
        request, (const char *)photo, HABIT_PHOTO_BYTES);
    habit_photo_store_unmap();
    return err;
}

static esp_err_t photo_delete(httpd_req_t *request)
{
    unsigned slot = 0;
    if (!request_slot(request, &slot)) {
        return httpd_resp_send_err(request, HTTPD_400_BAD_REQUEST,
                                   "照片编号无效");
    }
    set_status(HABIT_PHOTO_PORTAL_DELETING, 0, 0, 0);
    esp_err_t err = habit_photo_store_delete(slot);
    if (err != ESP_OK) {
        set_status(HABIT_PHOTO_PORTAL_ERROR, 0, 0, err);
        return httpd_resp_send_err(
            request, err == ESP_ERR_NOT_FOUND ? HTTPD_404_NOT_FOUND
                                               : HTTPD_500_INTERNAL_SERVER_ERROR,
            "删除照片失败");
    }
    set_status(HABIT_PHOTO_PORTAL_READY, 0, 0, 0);
    return httpd_resp_sendstr(request, "{\"ok\":true}");
}

static esp_err_t photos_delete(httpd_req_t *request)
{
    set_status(HABIT_PHOTO_PORTAL_DELETING, 0, 0, 0);
    esp_err_t err = habit_photo_store_clear();
    if (err != ESP_OK) {
        set_status(HABIT_PHOTO_PORTAL_ERROR, 0, 0, err);
        return httpd_resp_send_err(request, HTTPD_500_INTERNAL_SERVER_ERROR,
                                   "清空照片失败");
    }
    set_status(HABIT_PHOTO_PORTAL_READY, 0, 0, 0);
    return httpd_resp_sendstr(request, "{\"ok\":true}");
}

static bool request_crc(httpd_req_t *request, uint32_t *crc)
{
    char text[12] = {0};
    size_t length = httpd_req_get_hdr_value_len(request, "X-Photo-CRC32");
    if (length == 0 || length >= sizeof(text) ||
        httpd_req_get_hdr_value_str(request, "X-Photo-CRC32", text,
                                    sizeof(text)) != ESP_OK) {
        return false;
    }
    errno = 0;
    char *end = NULL;
    unsigned long value = strtoul(text, &end, 16);
    if (errno != 0 || !end || *end != '\0' || value > UINT32_MAX) return false;
    *crc = (uint32_t)value;
    return true;
}

static esp_err_t photo_post(httpd_req_t *request)
{
    habit_photo_portal_status_t current = habit_photo_portal_status();
    if (current.state == HABIT_PHOTO_PORTAL_RECEIVING) {
        httpd_resp_set_status(request, "409 Conflict");
        return httpd_resp_sendstr(request, "已有照片正在上传");
    }
    int slot = habit_photo_store_first_free();
    uint32_t expected_crc = 0;
    if (slot < 0) {
        httpd_resp_set_status(request, "409 Conflict");
        return httpd_resp_sendstr(request, "设备已存满 13 张照片");
    }
    if (request->content_len != (int)HABIT_PHOTO_BYTES ||
        !request_crc(request, &expected_crc)) {
        return httpd_resp_send_err(request, HTTPD_400_BAD_REQUEST,
                                   "照片长度或 CRC 无效");
    }

    esp_err_t err = habit_photo_store_begin((unsigned)slot);
    if (err != ESP_OK) {
        set_status(HABIT_PHOTO_PORTAL_ERROR, 0, HABIT_PHOTO_BYTES, err);
        return httpd_resp_send_err(request, HTTPD_500_INTERNAL_SERVER_ERROR,
                                   "无法准备照片存储");
    }

    uint8_t buffer[HTTP_BUFFER_BYTES];
    size_t received = 0;
    unsigned retries = 0;
    set_status(HABIT_PHOTO_PORTAL_RECEIVING, 0, HABIT_PHOTO_BYTES, 0);
    while (received < HABIT_PHOTO_BYTES) {
        size_t remaining = HABIT_PHOTO_BYTES - received;
        int count = httpd_req_recv(
            request, (char *)buffer,
            remaining < sizeof(buffer) ? remaining : sizeof(buffer));
        if (count == HTTPD_SOCK_ERR_TIMEOUT && retries++ < HTTP_RECEIVE_RETRIES) {
            continue;
        }
        if (count <= 0) {
            err = ESP_ERR_TIMEOUT;
            break;
        }
        retries = 0;
        err = habit_photo_store_write((unsigned)slot, received, buffer,
                                      (size_t)count);
        if (err != ESP_OK) break;
        received += (size_t)count;
        set_status(HABIT_PHOTO_PORTAL_RECEIVING, (uint32_t)received,
                   HABIT_PHOTO_BYTES, 0);
    }
    if (err == ESP_OK) {
        err = habit_photo_store_commit((unsigned)slot, expected_crc);
    }
    if (err != ESP_OK) {
        habit_photo_store_abort();
        set_status(HABIT_PHOTO_PORTAL_ERROR, (uint32_t)received,
                   HABIT_PHOTO_BYTES, err);
        return httpd_resp_send_err(request, HTTPD_500_INTERNAL_SERVER_ERROR,
                                   "照片写入或校验失败");
    }

    set_status(HABIT_PHOTO_PORTAL_COMPLETE, HABIT_PHOTO_BYTES,
               HABIT_PHOTO_BYTES, 0);
    char json[48];
    snprintf(json, sizeof(json), "{\"ok\":true,\"count\":%u}",
             habit_photo_store_count());
    httpd_resp_set_type(request, "application/json");
    return httpd_resp_sendstr(request, json);
}

static esp_err_t redirect_404(httpd_req_t *request, httpd_err_code_t error)
{
    (void)error;
    return root_get(request);
}

static esp_err_t register_uri(const char *uri, httpd_method_t method,
                              esp_err_t (*handler)(httpd_req_t *))
{
    httpd_uri_t route = {
        .uri = uri,
        .method = method,
        .handler = handler,
        .user_ctx = NULL,
    };
    return httpd_register_uri_handler(s_http, &route);
}

static void make_credentials(void)
{
    uint8_t mac[6] = {0};
    (void)esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
    snprintf(s_ssid, sizeof(s_ssid), "FoloHabit-%02X%02X", mac[4], mac[5]);
    snprintf(s_password, sizeof(s_password), "%s", HABIT_AP_PASSWORD);
}

esp_err_t habit_photo_portal_start(void)
{
    if (s_running) return ESP_ERR_INVALID_STATE;
    set_status(HABIT_PHOTO_PORTAL_STARTING, 0, 0, 0);
    make_credentials();

    if (!s_netif_ready) {
        esp_err_t err = esp_netif_init();
        if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) goto failed;
        s_netif_ready = true;
    }
    if (!s_event_loop_ready) {
        esp_err_t err = esp_event_loop_create_default();
        if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) goto failed;
        s_event_loop_ready = true;
    }
    s_ap_netif = esp_netif_create_default_wifi_ap();
    if (!s_ap_netif) goto failed;

    wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
    esp_err_t err = esp_wifi_init(&init);
    if (err != ESP_OK) goto failed;
    s_wifi_initialized = true;
    (void)esp_wifi_set_storage(WIFI_STORAGE_RAM);
    wifi_config_t config = {0};
    strncpy((char *)config.ap.ssid, s_ssid, sizeof(config.ap.ssid) - 1);
    strncpy((char *)config.ap.password, s_password,
            sizeof(config.ap.password) - 1);
    config.ap.ssid_len = strlen(s_ssid);
    config.ap.channel = 1;
    config.ap.max_connection = 1;
    config.ap.authmode = WIFI_AUTH_WPA2_PSK;
    if (esp_wifi_set_mode(WIFI_MODE_AP) != ESP_OK ||
        esp_wifi_set_config(WIFI_IF_AP, &config) != ESP_OK ||
        esp_wifi_start() != ESP_OK) {
        goto failed;
    }

    httpd_config_t http_config = HTTPD_DEFAULT_CONFIG();
    http_config.max_uri_handlers = 8;
    http_config.max_open_sockets = 3;
    http_config.backlog_conn = 2;
    http_config.stack_size = 6144;
    http_config.lru_purge_enable = true;
    if (httpd_start(&s_http, &http_config) != ESP_OK ||
        register_uri("/", HTTP_GET, root_get) != ESP_OK ||
        register_uri("/status", HTTP_GET, status_get) != ESP_OK ||
        register_uri("/photo", HTTP_GET, photo_get) != ESP_OK ||
        register_uri("/photo", HTTP_POST, photo_post) != ESP_OK ||
        register_uri("/delete", HTTP_POST, photo_delete) != ESP_OK ||
        register_uri("/clear", HTTP_POST, photos_delete) != ESP_OK ||
        httpd_register_err_handler(s_http, HTTPD_404_NOT_FOUND,
                                   redirect_404) != ESP_OK) {
        goto failed;
    }

    s_dns_running = true;
    if (xTaskCreate(dns_task, "habit_dns", 3072, NULL, 3,
                    &s_dns_task) != pdPASS) {
        s_dns_running = false;
        goto failed;
    }
    s_running = true;
    set_status(HABIT_PHOTO_PORTAL_READY, 0, 0, 0);
    ESP_LOGI(TAG, "photo portal ready: ssid=%s address=%s", s_ssid,
             PORTAL_ADDRESS);
    return ESP_OK;

failed:
    (void)habit_photo_portal_stop();
    set_status(HABIT_PHOTO_PORTAL_ERROR, 0, 0, ESP_FAIL);
    return ESP_FAIL;
}

esp_err_t habit_photo_portal_stop(void)
{
    habit_photo_portal_status_t status = habit_photo_portal_status();
    if (status.state == HABIT_PHOTO_PORTAL_RECEIVING ||
        status.state == HABIT_PHOTO_PORTAL_DELETING) {
        return ESP_ERR_INVALID_STATE;
    }
    s_dns_running = false;
    for (unsigned elapsed = 0; s_dns_task && elapsed < DNS_STOP_WAIT_MS;
         elapsed += 100) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    if (s_dns_task) return ESP_ERR_TIMEOUT;
    if (s_http) {
        (void)httpd_stop(s_http);
        s_http = NULL;
    }
    if (s_wifi_initialized) {
        (void)esp_wifi_stop();
        (void)esp_wifi_deinit();
        s_wifi_initialized = false;
    }
    if (s_ap_netif) {
        esp_netif_destroy_default_wifi(s_ap_netif);
        s_ap_netif = NULL;
    }
    s_running = false;
    habit_photo_store_abort();
    set_status(HABIT_PHOTO_PORTAL_OFF, 0, 0, 0);
    ESP_LOGI(TAG, "photo portal stopped");
    return ESP_OK;
}

bool habit_photo_portal_is_running(void)
{
    return s_running;
}

const char *habit_photo_portal_ssid(void)
{
    return s_ssid;
}

const char *habit_photo_portal_password(void)
{
    return s_password;
}
