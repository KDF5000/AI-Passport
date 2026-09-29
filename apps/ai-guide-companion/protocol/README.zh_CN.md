<p align="right"><strong>简体中文</strong> · <a href="README.md">English</a></p>

# 随行导游 BLE 协议 v1

Passport 提供一组兼容 Nordic UART 布局的 GATT 服务：

- 服务：`6e400001-b5a3-f393-e0a9-e50e24dcca9e`
- 手机写入 RX：`6e400002-b5a3-f393-e0a9-e50e24dcca9e`
- Passport 通知 TX：`6e400003-b5a3-f393-e0a9-e50e24dcca9e`

每个包首字节是类型；跨包文字均为 UTF-8。

| 类型 | 方向 | 载荷 |
| ---: | --- | --- |
| `0x01` | Passport → 手机 | 开始录音：小端 `uint16` 采样率 |
| `0x02` | Passport → 手机 | IMA-ADPCM 音频块 |
| `0x03` | Passport → 手机 | 录音结束 |
| `0x10` | 手机 → Passport | 识别出的提问文字分片 |
| `0x11` | 手机 → Passport | 回答文字分片 |
| `0x12` | 手机 → Passport | 开始播放：小端 `uint16` 采样率 |
| `0x13` | 手机 → Passport | IMA-ADPCM 音频块 |
| `0x14` | 手机 → Passport | 回答与播放结束 |
| `0x7f` | 双向 | UTF-8 错误信息 |

每个 ADPCM 块都可独立解码：四字节头依次是小端有符号 PCM 预测值、
步长索引和保留字节，之后每字节承载两个 4 bit 采样。独立块可把丢包影响限制
在单个分片内。

MVP 一次只处理一轮半双工对话，不包含路线、定位、账号或模型凭据。
