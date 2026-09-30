<p align="right"><strong>简体中文</strong> · <a href="README.md">English</a></p>

# AI 随行导游手机应用

这个 Flutter 应用负责生成路线、保存旅行进度、缓存离线讲解、进行 AI 对话，
并维护与 FoloToy AI Passport 的 BLE 会话。网络由手机提供，API 凭据不会离开
手机。

完整产品流程、接口申请清单、配置字段、Passport 按键和离线策略请参阅
[应用说明](../README.zh_CN.md)。

## 开发

```bash
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run -d <device-id> --profile
```

当前已在 iPhone 上进行功能验收。Android 复用同一套 Flutter 代码，但仍需完成
对应平台的真机验收。

如果 iPhone 安装后需要从主屏幕独立启动，应使用 Profile 或 Release 模式。
iOS 14 及以上的 Debug 包必须保持 Flutter/Xcode 开发会话连接。

## 运行配置

打开“设置”并填写：

- 用于路线生成和 AI 问答的方舟模型 Endpoint ID 与方舟 API Key；
- 用于流式 ASR 和 SAIL/SAMI TTS 的 Speech AppKey、AK 与 SK。

CN 接口地址和默认 Speech 资源 ID 已内置。所有凭据都应向对应服务负责人申请，
并确保应用、凭据和接口地区一致。密钥由 `flutter_secure_storage` 保存，非敏感
偏好使用 shared preferences 保存。

语音合成结果必须能解析为 16 kHz、16 位、单声道 PCM/WAV，之后应用才会转换为
Passport 的流式播放格式。

## 可选 Speech 在线测试

普通测试不需要真实凭据。如需显式验证已经授权的 SAIL 应用：

```bash
RUN_SAIL_LIVE=1 \
SAIL_APP=<appkey> \
SAIL_AK=<access-key> \
SAIL_SK=<secret-key> \
flutter test test/sail_live_integration_test.dart
```

只通过本机环境变量传入凭据。禁止把它们写入 Dart 源码、测试数据、Shell 脚本、
Git 跟踪的 `.env` 文件、截图或问题日志。
