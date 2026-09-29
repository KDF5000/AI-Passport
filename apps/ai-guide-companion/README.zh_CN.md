<p align="right"><strong>简体中文</strong> · <a href="README.md">English</a></p>

# AI 随行导游 MVP

本应用先验证 AI Passport 与手机之间的一轮完整语音对话：在 Passport 上长按
OK 录音，松开后通过 BLE 发送压缩语音；手机使用自己的网络或 VPN 调用可配置
的语音与大模型服务；最后由 Passport 显示并播放回答。

目录分为：

- `passport/`：ESP-IDF 固件与主机测试；
- `mobile/`：优先验收 iPhone、同时支持 Android 的 Flutter 应用；
- `protocol/`：有版本的 BLE 数据包约定。

路线规划、目的地资料、地图、定位和账号系统不属于本次 MVP。

## 快速体验

1. 构建并刷入 `passport/` 固件，在 iPhone 或 Android 手机运行 `mobile/`。
2. 手机设置页填写兼容 OpenAI 接口的 Base URL、STT/Chat/TTS 路径、模型和
   API Key；Key 只保存在系统安全存储中。
3. 点击“Scan and connect”，连接名为 `Passport Guide` 的设备。
4. Passport 显示 Ready 后长按 OK 说话，松开后等待；识别文字与回答会显示在
   两端，回答语音从 Passport 播放。播放期间短按 OK 可停止。

手机使用自身网络，因此可沿用 iPhone 上已经工作的 VPN。当前 TTS 服务必须返回
16 kHz、16-bit、单声道 PCM WAV。应用保持前台运行；不支持后台 BLE。

## 验证

```bash
cd mobile
flutter analyze
flutter test

cd ../passport
source <path-to-esp-idf-v5.5.3>/export.sh
./tools/validate.sh
```

禁止提交 API Key、个人代理地址或未脱敏日志。
