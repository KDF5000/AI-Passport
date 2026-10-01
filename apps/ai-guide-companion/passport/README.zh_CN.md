<p align="right"><strong>简体中文</strong> · <a href="README.md">English</a></p>

# Passport Guide 固件

这是 AI 随行导游 MVP 的 FoloToy AI Passport 固件。它提供独立设计的语音对话
页面，不进入官方测试菜单，也不复用“微光日记”界面。Passport 只负责按键、
录音、BLE 传输、文字显示与语音播放；联网和 AI 请求由手机应用承担。

## 操作

- 手机连接前，屏幕显示 `Waiting for phone`。
- 手机连接且 BLE MTU 满足要求后，屏幕显示 `Ready`。
- 长按 OK 500 ms 开始录音，松开 OK 结束并发送。
- 手机返回回答后自动播放；播放期间按 OK 可停止。
- UP 和 DOWN 在此 MVP 中暂不分配功能。

音频为 16 kHz、16-bit、单声道，并以独立 IMA-ADPCM 块通过 BLE 传输。
协议详情见 [`../protocol/README.zh_CN.md`](../protocol/README.zh_CN.md)。

## 构建

```bash
source <path-to-esp-idf-v5.5.3>/export.sh
./tools/validate.sh
```

构建目标为 ESP32-C3、8 MB Flash、无 PSRAM。固件使用 NVS、PHY 和单 factory
应用分区，不包含照片或其他应用专用分区。
