<p align="right">
  <a href="README.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# AI Passport Applications

This repository contains independently buildable applications for the
FoloToy AI Passport. Each application lives under `apps/` with its own source,
configuration, documentation, tests, and build instructions.

## Applications

| Application | Description |
| --- | --- |
| [`offline-habit-tracker`](apps/offline-habit-tracker/docs/habit-tracker.md) | Offline daily habit heatmap with persistent check-ins, local Wi-Fi photo management, and a photo screensaver |

Build and test an application from its own directory. For example:

```bash
cd apps/offline-habit-tracker
source <path-to-esp-idf-v5.5.3>/export.sh
./tools/validate.sh
```

The application targets the ESP32-C3 FoloToy AI Passport with 8 MB Flash and
no PSRAM. Follow the `AGENTS.md` and hardware documentation inside the selected
application before making changes.
