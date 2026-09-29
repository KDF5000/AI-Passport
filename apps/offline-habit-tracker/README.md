<p align="right">
  <a href="README.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Offline Habit Tracker

An offline habit-check-in application for the FoloToy AI Passport. It replaces
the official hardware-test menu with a dedicated 240 × 320 interface featuring
a GitHub-style daily contribution heatmap, persistent check-ins, phone-based
photo management, and an automatic photo screensaver.

This is an independently maintained derivative application, not an official
FoloToy firmware release.

## Upstream

This application was developed from the official
[`FoloToy/ai-passport`](https://github.com/FoloToy/ai-passport) repository:

- Upstream baseline commit:
  [`0b9e4c81ee4421c0bac39ca3561d65a8285acd4a`](https://github.com/FoloToy/ai-passport/commit/0b9e4c81ee4421c0bac39ca3561d65a8285acd4a)
- Target: ESP32-C3, 8 MB Flash, no PSRAM
- Framework: ESP-IDF 5.5.3
- Reused foundation: board support package, hardware definitions, build
  configuration, validation tooling, and project documentation
- Application-specific work: redesigned habit UI, check-in model and storage,
  photo partition and redundant metadata, local Wi-Fi upload/delete portal,
  screensaver behavior, and related tests

The upstream MIT license is retained in [`LICENSE`](LICENSE). See the upstream
repository for the original project, hardware documentation, and later
upstream changes.

## Features

- GitHub-style 13-week heatmap organized by day.
- Three-button navigation and offline date setup.
- Power-loss-safe check-ins stored in NVS.
- Automatic photo screensaver after three seconds of inactivity.
- Temporary local Wi-Fi portal for uploading and deleting phone photos.
- Up to 13 center-cropped 240 × 320 RGB565 photos in a dedicated Flash
  partition.
- No cloud service, mobile app, Web Bluetooth, or internet connection required.

The upload hotspot is named `FoloHabit-XXXX`, uses the password `12345678`,
and is enabled only while the photo-management screen is open.

## Controls

| Screen | UP | DOWN | OK |
| --- | --- | --- | --- |
| Heatmap | Previous day | Next day | Toggle selected day |
| Heatmap, hold | Open photo upload | Previous 13 weeks | Set offline date |
| Date setup | Increase field | Decrease field | Next field; save on day |
| Photo upload | Hold to stop hotspot and return | No action | No action |
| Photo screensaver | Any button wakes the heatmap without applying its normal action | | |

For phone upload/delete instructions, persistence details, and the exact Flash
layout, read the [application guide](docs/habit-tracker.md).

## Project layout

```text
components/bsp/  Board drivers and reusable hardware APIs
main/            Habit application, UI, persistence, and photo portal
tests/           Host-side state, format, BSP, and tooling tests
docs/            Application, hardware, and development documentation
tools/           Repository checks and firmware validation/package scripts
```

The baseline demo sources remain as reference files, but `main/CMakeLists.txt`
builds the dedicated habit application rather than the original test menu.

## Build and validate

Activate ESP-IDF 5.5.3, then run the complete gate from this directory:

```bash
source <path-to-esp-idf-v5.5.3>/export.sh
./tools/validate.sh
```

Useful narrower checks:

```bash
./tools/validate.sh --static
./tools/validate.sh --firmware
```

Successful firmware validation produces:

- `build/FoloToy-AI-Passport-full.bin`
- A matching debug bundle under `build/firmware/<full-image-sha256>/`

Use the merged image only for a blank device or an intentional full refresh.
To preserve existing check-ins and photos during development, use the segmented
flash procedure described in the [application guide](docs/habit-tracker.md#persistent-layout-and-flashing).

## Development

Read [`AGENTS.md`](AGENTS.md) and
[`docs/hardware-design/AI_HARDWARE_DEVELOPMENT_GUIDE.md`](docs/hardware-design/AI_HARDWARE_DEVELOPMENT_GUIDE.md)
before changing firmware. Application state and UI belong in `main/`; reusable
board logic belongs in `components/bsp/`.
