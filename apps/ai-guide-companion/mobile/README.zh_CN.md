<p align="right">
  <strong>简体中文</strong> · <a href="README.md">English</a>
</p>

# AI 导游手机伴侣应用

这个 Flutter 应用是 Passport AI 导游 MVP 的网络与 AI 中转端。它通过
低功耗蓝牙接收 Passport 的语音，使用手机的网络调用兼容 OpenAI 接口的
语音识别、对话和语音合成服务，再把回答文字与音频传回 Passport。

## 运行

1. 安装 Flutter，并准备一台可调试的 iPhone 或 Android 手机。
2. 在本目录运行 `flutter pub get`。
3. 运行 `flutter run` 启动应用。
4. 填写服务商的 Base URL、各接口路径、模型名、音色和 API Key。API Key
   会保存到系统安全存储中。
5. 启动已刷入配套固件的 Passport，点击“连接”，选择
   `Passport Guide`。

本 MVP 使用期间需保持手机应用在前台。手机可以使用移动网络、Wi-Fi 或
VPN 路由；API Key 不会发送到 Passport。

## 检查

```bash
flutter analyze
flutter test
```

当前 MVP 要求语音合成接口返回 16 kHz、16 位、单声道 PCM WAV。完整限制
和消息格式请参阅上层应用 README 与协议文档。
