<p align="right">
  <a href="habit-tracker.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Glow Journal

The habit tracker is a standalone 240 × 320 application. It replaces the
hardware-test menu with a GitHub-style 13-week daily heatmap and stores both
check-ins and user photos across power loss.

## Controls

| Screen | UP | DOWN | OK |
| --- | --- | --- | --- |
| Heatmap | Previous day | Next day | Toggle the selected day |
| Heatmap, hold | Open photo upload | Previous 13 weeks | Set the offline date |
| Date setup | Increase field | Decrease field | Next field; save on day |
| Photo upload | Hold to stop the local hotspot and return | No action | No action |
| Photo screensaver | Any key wakes the heatmap without applying that key's normal action | | |

When at least one photo is stored, the heatmap enters the photo screensaver
after three seconds without input. Photos advance every five seconds. The local
Wi-Fi hotspot is enabled only while the photo-upload screen is open.

## Upload photos from a phone

The device hosts a temporary WPA2 Wi-Fi hotspot and an upload page. Android and
iPhone browsers can use it without Web Bluetooth, an app, or internet access.

1. On the device heatmap, hold **UP** to show `ADD PHOTOS`.
2. Scan the Wi-Fi QR code shown on the Passport. If the phone cannot scan it,
   connect manually using the displayed `FoloHabit-XXXX` SSID and the fixed
   password `12345678`. The hotspot is intentionally available only while the
   photo-upload screen is open.
3. Open `http://192.168.4.1` in the phone browser. Some phones may open the
   local upload page automatically after joining the hotspot.
4. Choose and upload a photo. Keep the phone connected to the Passport hotspot
   until the page confirms completion; repeat to add more photos.
   The photo-management section shows thumbnails of every stored photo. Each
   photo has an inline two-tap delete button; deleting all photos also requires
   a second tap within four seconds. This works in phone captive-portal windows
   that suppress browser confirmation dialogs. The management page remains
   available when all 13 slots are full.
5. Hold **UP** on the device to stop the hotspot and return to the heatmap.

The browser center-crops each image to 240 × 320 and converts it to RGB565
before transfer. The firmware accepts at most 13 photos. Each upload is written
to an erased slot, read back, CRC-checked, and then committed to a redundant
manifest; an interrupted or corrupt upload is not added to the rotation.
Deletion commits the redundant manifest before reclaiming the image slot, so a
power interruption cannot restore a photo that the manifest already removed.

## Persistent layout and flashing

This application uses the following 8 MB Flash layout:

| Partition | Offset | Size | Contents |
| --- | ---: | ---: | --- |
| `nvs` | `0x9000` | 24 KiB | Habit check-ins and ESP-IDF data |
| `phy_init` | `0xF000` | 4 KiB | PHY initialization |
| `factory` | `0x10000` | 6080 KiB | Application firmware |
| `photos` | `0x600000` | 2048 KiB | Up to 13 RGB565 photos and redundant metadata |

For a development update that must retain existing check-ins and photos, flash
only the bootloader at `0x0`, partition table at `0x8000`, and application at
`0x10000`. Do not erase the chip or write the merged image from `0x0` in that
case: its padding can reset data partitions. The new partition table must remain
compatible with the offsets above.

Use the verified merged image only for blank-device provisioning or an
intentional complete refresh. See [firmware layout](development/engineering/firmware-layout.md)
for the repository-wide flashing policy.
