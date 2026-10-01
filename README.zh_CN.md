<p align="right">
  <strong>简体中文</strong> · <a href="README.md">English</a>
</p>

# AI Passport 应用集合

本仓库用于存放可独立构建的 FoloToy AI Passport 应用。每个应用位于 `apps/`
下，并拥有独立的源码、配置、文档、测试和构建说明。

## 应用

| 应用 | 说明 |
| --- | --- |
| [`offline-habit-tracker`](apps/offline-habit-tracker/README.zh_CN.md) | 离线每日习惯热力图，支持掉电保存打卡、本地 Wi-Fi 照片管理和照片屏保 |
| [`ai-guide-companion`](apps/ai-guide-companion/README.zh_CN.md) | 手机中转、AI Passport 作为语音终端的 BLE 对话 MVP |

请进入应用自己的目录执行构建和测试。例如：

```bash
cd apps/offline-habit-tracker
source <path-to-esp-idf-v5.5.3>/export.sh
./tools/validate.sh
```

应用目标硬件为配备 8 MB Flash、无 PSRAM 的 ESP32-C3 FoloToy AI Passport。
修改前请遵守所选应用目录内的 `AGENTS.md` 和硬件文档。
