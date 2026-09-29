#include "habit_photo_store.h"

#include <string.h>

#include "esp_log.h"
#include "esp_partition.h"

#define PHOTO_PARTITION_LABEL "photos"
#define MANIFEST_A_OFFSET 0U
#define MANIFEST_B_OFFSET 4096U
#define PHOTO_DATA_OFFSET 8192U
#define PHOTO_SLOT_BYTES ((HABIT_PHOTO_BYTES + 4095U) & ~4095U)

static const char *TAG = "habit_photos";
static const esp_partition_t *s_partition;
static habit_photo_manifest_t s_manifest;
static unsigned s_manifest_copy;
static int s_upload_slot = -1;
static size_t s_upload_offset;
static uint32_t s_upload_crc;
static const uint8_t *s_mapped;
static esp_partition_mmap_handle_t s_map_handle;

static size_t slot_offset(unsigned slot)
{
    return PHOTO_DATA_OFFSET + slot * PHOTO_SLOT_BYTES;
}

static esp_err_t read_manifest(size_t offset, habit_photo_manifest_t *manifest)
{
    return esp_partition_read(s_partition, offset, manifest, sizeof(*manifest));
}

static esp_err_t save_manifest(void)
{
    unsigned next = s_manifest_copy ^ 1U;
    size_t offset = next ? MANIFEST_B_OFFSET : MANIFEST_A_OFFSET;
    s_manifest.generation++;
    habit_photo_manifest_finalize(&s_manifest);
    esp_err_t err = esp_partition_erase_range(s_partition, offset, 4096U);
    if (err == ESP_OK) {
        err = esp_partition_write(s_partition, offset, &s_manifest, sizeof(s_manifest));
    }
    if (err == ESP_OK) s_manifest_copy = next;
    return err;
}

bool habit_photo_store_init(void)
{
    s_partition = esp_partition_find_first(
        ESP_PARTITION_TYPE_DATA, ESP_PARTITION_SUBTYPE_ANY, PHOTO_PARTITION_LABEL);
    if (!s_partition ||
        s_partition->size < PHOTO_DATA_OFFSET +
                            HABIT_PHOTO_MAX_COUNT * PHOTO_SLOT_BYTES) {
        ESP_LOGE(TAG, "photo partition missing or too small");
        return false;
    }

    habit_photo_manifest_t a;
    habit_photo_manifest_t b;
    bool a_valid = read_manifest(MANIFEST_A_OFFSET, &a) == ESP_OK &&
                   habit_photo_manifest_valid(&a);
    bool b_valid = read_manifest(MANIFEST_B_OFFSET, &b) == ESP_OK &&
                   habit_photo_manifest_valid(&b);
    const habit_photo_manifest_t *newest =
        habit_photo_manifest_newest(&a, a_valid, &b, b_valid);
    if (newest) {
        s_manifest = *newest;
        s_manifest_copy = newest == &b ? 1U : 0U;
    } else {
        habit_photo_manifest_empty(&s_manifest);
        s_manifest_copy = 1U;
        if (save_manifest() != ESP_OK) {
            ESP_LOGE(TAG, "failed to initialize photo manifest");
            return false;
        }
    }
    ESP_LOGI(TAG, "ready: %u photos", habit_photo_manifest_count(&s_manifest));
    return true;
}

unsigned habit_photo_store_count(void)
{
    return s_partition ? habit_photo_manifest_count(&s_manifest) : 0U;
}

int habit_photo_store_first_free(void)
{
    return s_partition ? habit_photo_manifest_first_free(&s_manifest) : -1;
}

bool habit_photo_store_slot_valid(unsigned slot)
{
    return s_partition && slot < HABIT_PHOTO_MAX_COUNT &&
           s_manifest.entries[slot].valid;
}

uint16_t habit_photo_store_valid_mask(void)
{
    uint16_t mask = 0;
    if (!s_partition) return 0;
    for (unsigned slot = 0; slot < HABIT_PHOTO_MAX_COUNT; ++slot) {
        if (s_manifest.entries[slot].valid) mask |= (uint16_t)(1U << slot);
    }
    return mask;
}

esp_err_t habit_photo_store_begin(unsigned slot)
{
    if (!s_partition || slot >= HABIT_PHOTO_MAX_COUNT) return ESP_ERR_INVALID_ARG;
    habit_photo_store_unmap();
    esp_err_t err = esp_partition_erase_range(
        s_partition, slot_offset(slot), PHOTO_SLOT_BYTES);
    if (err != ESP_OK) return err;
    s_upload_slot = (int)slot;
    s_upload_offset = 0;
    s_upload_crc = 0;
    return ESP_OK;
}

esp_err_t habit_photo_store_write(unsigned slot, size_t offset,
                                  const void *data, size_t length)
{
    if (s_upload_slot != (int)slot || offset != s_upload_offset || !data ||
        length == 0 || offset + length > HABIT_PHOTO_BYTES) {
        return ESP_ERR_INVALID_ARG;
    }
    esp_err_t err = esp_partition_write(
        s_partition, slot_offset(slot) + offset, data, length);
    if (err == ESP_OK) {
        s_upload_crc = habit_photo_crc32(s_upload_crc, data, length);
        s_upload_offset += length;
    }
    return err;
}

esp_err_t habit_photo_store_commit(unsigned slot, uint32_t expected_crc)
{
    if (s_upload_slot != (int)slot || s_upload_offset != HABIT_PHOTO_BYTES ||
        s_upload_crc != expected_crc) {
        return ESP_ERR_INVALID_CRC;
    }
    uint8_t verify[512];
    uint32_t flash_crc = 0;
    for (size_t offset = 0; offset < HABIT_PHOTO_BYTES;
         offset += sizeof(verify)) {
        size_t length = HABIT_PHOTO_BYTES - offset;
        if (length > sizeof(verify)) length = sizeof(verify);
        esp_err_t read_err = esp_partition_read(
            s_partition, slot_offset(slot) + offset, verify, length);
        if (read_err != ESP_OK) return read_err;
        flash_crc = habit_photo_crc32(flash_crc, verify, length);
    }
    if (flash_crc != expected_crc) return ESP_ERR_INVALID_CRC;
    s_manifest.entries[slot].crc32 = expected_crc;
    s_manifest.entries[slot].valid = 1;
    esp_err_t err = save_manifest();
    if (err == ESP_OK) {
        ESP_LOGI(TAG, "photo %u committed crc=%08lx", slot,
                 (unsigned long)expected_crc);
        habit_photo_store_abort();
    }
    return err;
}

void habit_photo_store_abort(void)
{
    s_upload_slot = -1;
    s_upload_offset = 0;
    s_upload_crc = 0;
}

esp_err_t habit_photo_store_delete(unsigned slot)
{
    if (!s_partition || slot >= HABIT_PHOTO_MAX_COUNT) {
        return ESP_ERR_INVALID_ARG;
    }
    if (s_upload_slot >= 0) return ESP_ERR_INVALID_STATE;
    if (!s_manifest.entries[slot].valid) return ESP_ERR_NOT_FOUND;

    habit_photo_store_unmap();
    habit_photo_manifest_t previous = s_manifest;
    (void)habit_photo_manifest_remove(&s_manifest, slot);
    esp_err_t err = save_manifest();
    if (err != ESP_OK) {
        s_manifest = previous;
        return err;
    }

    err = esp_partition_erase_range(
        s_partition, slot_offset(slot), PHOTO_SLOT_BYTES);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "photo %u removed from manifest; slot erase failed: %s",
                 slot, esp_err_to_name(err));
    } else {
        ESP_LOGI(TAG, "photo %u deleted", slot);
    }
    return ESP_OK;
}

esp_err_t habit_photo_store_clear(void)
{
    if (!s_partition) return ESP_ERR_INVALID_STATE;
    if (s_upload_slot >= 0) return ESP_ERR_INVALID_STATE;
    if (habit_photo_store_count() == 0) return ESP_OK;

    habit_photo_store_unmap();
    habit_photo_manifest_t previous = s_manifest;
    (void)habit_photo_manifest_clear(&s_manifest);
    esp_err_t err = save_manifest();
    if (err != ESP_OK) {
        s_manifest = previous;
        return err;
    }

    err = esp_partition_erase_range(
        s_partition, PHOTO_DATA_OFFSET,
        HABIT_PHOTO_MAX_COUNT * PHOTO_SLOT_BYTES);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "photos removed from manifest; data erase failed: %s",
                 esp_err_to_name(err));
    } else {
        ESP_LOGI(TAG, "all photos deleted");
    }
    return ESP_OK;
}

const uint8_t *habit_photo_store_map(unsigned slot)
{
    if (!habit_photo_store_slot_valid(slot)) return NULL;
    habit_photo_store_unmap();
    const void *pointer = NULL;
    esp_err_t err = esp_partition_mmap(
        s_partition, slot_offset(slot), HABIT_PHOTO_BYTES,
        ESP_PARTITION_MMAP_DATA, &pointer, &s_map_handle);
    if (err != ESP_OK) return NULL;
    s_mapped = pointer;
    return s_mapped;
}

void habit_photo_store_unmap(void)
{
    if (s_mapped) {
        esp_partition_munmap(s_map_handle);
        s_mapped = NULL;
        s_map_handle = 0;
    }
}
