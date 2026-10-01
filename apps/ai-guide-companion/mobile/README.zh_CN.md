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

iOS 锁屏前需要先打开应用并连接 Passport。应用已启用 BLE Central 状态恢复，
并为每轮 Passport 语音提问申请有时限的后台任务，因此锁屏时可以继续中转，但
不能保证无限后台运行：处理过久仍可能被 iOS 挂起，网络或 VPN 中断会影响在线
请求；从多任务界面强制划掉应用后，需要重新打开并连接。

## 运行配置

打开“设置”并填写：

- 用于路线生成和 AI 问答的方舟模型 Endpoint ID 与方舟 API Key；
- 用于流式 ASR 和 SAIL/SAMI TTS 的 Speech AppKey、AK 与 SK。

申请入口：

- [火山方舟控制台](https://ark.bytedance.net)：开通对话模型、创建推理接入点并
  获取 `ep-...` Endpoint ID 与 API Key；
- [Speech/SAIL 应用管理](https://speech.bytedance.net/sail/cn/self/app)：
  创建或选择 CN 应用，申请流式大模型 ASR 与 SAIL/SAMI TTS 权限，并获取
  AppKey、AK、SK。

设置页按 **LLM API** 和 **语音 API** 分组展示。LLM 默认填充火山方舟 CN 的
完整 Chat Completions 地址，也可改为兼容接口的自定义地址；语音默认填充
Speech 流式 ASR WebSocket 地址与 SAIL/SAMI TTS HTTP 地址，也可以分别替换为
兼容的自定义 Endpoint。SAIL Token 地址会从 TTS Endpoint 的同级 `token` 路径
自动推导。

自定义 LLM 服务需兼容 OpenAI Chat Completions 请求与流式响应。所有凭据都应
向对应服务负责人申请，并确保应用、凭据和接口地区一致。密钥由
`flutter_secure_storage` 保存，非敏感偏好使用 shared preferences 保存。

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
