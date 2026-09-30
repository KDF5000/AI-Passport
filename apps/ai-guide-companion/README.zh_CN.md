<p align="right"><strong>简体中文</strong> · <a href="README.md">English</a></p>

# AI 随行导游

AI 随行导游是一套离线优先的旅行助手，由 iOS/Android 手机应用与 FoloToy
AI Passport 固件组成。手机负责规划并保存行程、在用户明确操作时调用 AI
以及访问网络；Passport 作为低打扰的路线显示、麦克风和扬声器终端。

当前实现支持：

- 根据目的地、日期、游玩时段、节奏和同行情况生成 AI 行程；
- 将用户已确认的演出和预约作为不可修改的时间硬约束；
- AI 草案必须经过用户审核后才能保存；
- 为每站生成小屏摘要、完整口语讲解、现场提示、规划假设和出发前待核对事项；
- 在手机本地持久保存路线与完成进度；
- 按需提前生成并缓存语音，之后可离线播放；
- 从手机或 Passport 主动发起结合当前路线的 AI 问答；
- 通过 BLE 向 Passport 同步路线、上传录音并流式传回回答文字和语音。

本应用不是实时地图或票务服务。AI 生成的时间安排属于规划建议；开放时间、入场
规则、演出场次和临时通知仍需以场馆官方信息为准。

## 目录结构

- `mobile/`：Flutter 手机应用，当前以 iPhone 开发和真机验收，同时保留
  Android 目标。
- `passport/`：FoloToy AI Passport 的 ESP-IDF 固件。
- `protocol/`：手机与 Passport 共用的版本化 BLE 数据包协议。

## 行程生成闭环

1. 输入目的地、日期、到达/离开时间、游玩节奏和同行需求。
2. 只添加用户已经确认的演出、门票或预约，它们的名称和时间会成为硬约束。
3. 手机发起一次结构化 AI 请求，同时生成候选站点、按时间排序的路线、小屏摘要、
   完整讲解稿和待核对事项。
4. 审核草案。可调整或删除非固定站点，AI 不得悄悄修改已确认场次。
5. 保存到手机，按需准备离线语音，再连接并同步到 Passport。

路线生成一次返回所有站点的完整讲解，通常比普通对话耗时更长。生成页会显示已经
等待的时间，并允许取消；取消不会清空创建表单。

## 接口申请与权限准备

本应用使用两组相互独立的服务。凭据必须和实际调用的接口属于同一环境和地区。

### 1. 火山方舟：生成路线与 AI 问答

需要申请或准备：

1. 已开通火山方舟的账号，使用 **CN 生产区**。
2. 创建一个支持 Chat Completions、JSON 对象输出和流式输出的对话模型推理
   Endpoint。
3. 创建有权调用该 Endpoint 的方舟 API Key。
4. 确认输出 Token 和请求时长配额充足；一次完整行程可能返回数千 Token。

在手机应用的“设置”中填写：

- **方舟模型 / Endpoint**：方舟控制台显示的推理接入点 ID，通常以 `ep-` 开头；
- **方舟 API Key**：有权调用该 Endpoint 的 API Key。

应用默认调用 CN 方舟地址
`https://ark.cn-beijing.volces.com/api/v3` 和 `/chat/completions`。如果改用
内网代理，必须先保证手机自身可访问，例如已经开启可用的 VPN；不要把代理凭据
写入仓库。

### 2. 字节 Speech/SAIL：语音识别与语音合成

向 Speech/SAIL 服务负责人申请在 **CN 生产环境**创建或授权一个应用，并同时
获得：

- 应用级 **AppKey**；
- 与该应用绑定的 **Access Key（AK）** 和 **Secret Key（SK）**；
- 流式大模型 ASR 权限，资源为 `asr.streaming.model.big`，或已授权的
  two-pass 版本；
- 所选中文音色对应的 SAIL/SAMI TTS 权限；
- 满足对话式语音合成的请求频率配额。应用会串行发送 TTS，并在遇到一次限流时
  重试，但无法绕过服务端配额。

申请完成后，在手机设置中填写 **Speech AppKey**、**Speech AK** 和
**Speech SK**。CN 接口地址、资源 ID 和默认音色已经内置，无需普通用户填写。

如果返回 `UserNotFound` / `40200141`，通常是 AppKey 或 AK/SK 属于另一个
环境或地区，例如把 BOE 凭据用于 CN 生产接口。应核对申请地区和应用绑定关系，
不要盲目更换密钥。

方舟 API Key 与 Speech AK/SK 是两套不同凭据，不能混用。两者均禁止提交到
仓库；手机通过系统安全存储保存密钥，且不会把密钥发送给 Passport。

## 构建与运行

### 手机端

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter run -d <device-id> --profile
```

iPhone 如果需要以后从主屏幕独立启动，请安装 Profile 或 Release 版本。
iOS Debug 包只能在连接 Flutter 工具或 Xcode 时启动。

### Passport

使用 ESP-IDF 5.5.3：

```bash
cd passport
source <path-to-esp-idf-v5.5.3>/export.sh
./tools/validate.sh
idf.py -p <serial-port> flash monitor
```

刷写属于硬件写入操作，执行前需要确认目标串口和固件镜像。

## 使用方法

1. 在手机设置中配置上述两组服务。
2. 创建、审核并保存行程。路线与进度会立即保存在本地，讲解语音不会自动生成。
3. 在“离线包”中主动缓存尚未准备的讲解，建议在网络稳定时完成。站点文字和
   音色不变时会复用缓存。
4. 启动 Passport，连接 `Passport Guide` 并同步路线。
5. Passport 上使用 UP / DOWN 切换站点；短按 OK 播放缓存讲解；双击 OK
   切换完成状态；长按 OK 录制问题。播放时 UP / DOWN 调音量，OK 停止。

Passport 未连接时，缓存讲解仍可直接从手机播放。当前 BLE 中转要求手机应用保持
前台运行。

## 联网与调用成本边界

浏览已保存路线、切换站点、记录完成进度、重复播放缓存语音和重新打开应用都不会
请求网络。只有以下用户主动操作会联网：

- 生成新行程；
- 主动询问 AI；
- 主动准备缺失的离线讲解语音。

这一边界可以减少接口调用，并在旅途中网络较弱时保留核心体验。

## 验证

手机端检查：

```bash
cd mobile
flutter analyze
flutter test
```

固件检查：

```bash
cd passport
source <path-to-esp-idf-v5.5.3>/export.sh
./tools/validate.sh
```

Speech 在线集成测试默认不执行，只从环境变量读取测试凭据：

```bash
RUN_SAIL_LIVE=1 \
SAIL_APP=<appkey> \
SAIL_AK=<access-key> \
SAIL_SK=<secret-key> \
flutter test test/sail_live_integration_test.dart
```

禁止提交 API Key、AK/SK、个人代理地址、设备密钥或未脱敏日志。
