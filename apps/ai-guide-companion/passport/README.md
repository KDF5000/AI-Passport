<p align="right"><a href="README.zh_CN.md">简体中文</a> · <strong>English</strong></p>

# Passport Guide firmware

This is the FoloToy AI Passport firmware for the AI Guide Companion MVP. It
uses a purpose-built voice conversation screen and never enters the official
test menu or reuses the Glow Diary interface. Passport handles buttons,
recording, BLE transport, text display, and audio playback; the phone owns the
network and AI requests.

## Controls

- Before the phone connects, the screen shows `Waiting for phone`.
- Once connected with a sufficient BLE MTU, it shows `Ready`.
- Hold OK for 500 ms to record, then release OK to send.
- The returned answer plays automatically; press OK during playback to stop.
- UP and DOWN are intentionally unused in this MVP.

Audio is 16 kHz, 16-bit mono and travels over BLE as independent IMA-ADPCM
blocks. See [`../protocol/README.md`](../protocol/README.md) for the packet
contract.

## Build

```bash
source <path-to-esp-idf-v5.5.3>/export.sh
./tools/validate.sh
```

The target is ESP32-C3 with 8 MB flash and no PSRAM. The firmware uses NVS,
PHY, and one factory application partition; it has no photo or other
application-specific data partition.
