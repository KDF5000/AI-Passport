<p align="right">
  <strong>简体中文</strong> · <a href="README.md">English</a>
</p>

# 离线习惯打卡

这是一个面向 FoloToy AI Passport 的离线习惯打卡应用。它不再使用官方硬件
测试菜单，而是提供专门设计的 240 × 320 界面，包括 GitHub 风格的每日热力图、
掉电保存打卡、手机照片管理和自动照片屏保。

本项目是独立维护的衍生应用，并非 FoloToy 官方发布的固件。

## 上游来源

本应用基于 FoloToy 官方
[`FoloToy/ai-passport`](https://github.com/FoloToy/ai-passport) 仓库开发：

- 上游基线提交：
  [`0b9e4c81ee4421c0bac39ca3561d65a8285acd4a`](https://github.com/FoloToy/ai-passport/commit/0b9e4c81ee4421c0bac39ca3561d65a8285acd4a)
- 目标硬件：ESP32-C3、8 MB Flash、无 PSRAM
- 开发框架：ESP-IDF 5.5.3
- 复用基础：板级支持包、硬件定义、构建配置、验证工具和项目文档
- 本应用新增：重新设计的打卡 UI、打卡模型与存储、照片分区和双副本元数据、
  本地 Wi-Fi 上传/删除页面、屏保逻辑及相关测试

上游 MIT 许可证保留在 [`LICENSE`](LICENSE) 中。原始项目、硬件资料及后续
上游更新请以官方仓库为准。

## 功能

- 按天展示 GitHub 风格的 13 周热力图。
- 使用三个实体按键导航和设置离线日期。
- 打卡记录通过 NVS 掉电保存。
- 无操作三秒后自动进入照片屏保。
- 通过临时本地 Wi-Fi 页面从手机上传和删除照片。
- 专用 Flash 分区最多保存 13 张居中裁剪的 240 × 320 RGB565 照片。
- 无需云服务、手机 App、Web Bluetooth 或互联网连接。

上传热点名称为 `FoloHabit-XXXX`，密码为 `12345678`，并且仅在照片管理
页面打开时启用。

## 按键操作

| 页面 | UP | DOWN | OK |
| --- | --- | --- | --- |
| 热力图 | 前一天 | 后一天 | 切换选中日期的打卡状态 |
| 热力图，长按 | 打开照片上传 | 前 13 周 | 设置离线日期 |
| 日期设置 | 增加当前字段 | 减少当前字段 | 下一字段；在日期字段保存 |
| 照片上传 | 长按停止热点并返回 | 无操作 | 无操作 |
| 照片屏保 | 任意按键唤醒热力图，但不执行该键原本的操作 | | |

手机上传/删除步骤、持久化说明和准确的 Flash 布局见
[应用指南](docs/habit-tracker.zh_CN.md)。

## 工程结构

```text
components/bsp/  板级驱动和可复用硬件 API
main/            打卡应用、UI、持久化和照片管理页面
tests/           状态、格式、BSP 和工具的主机测试
docs/            应用、硬件和开发文档
tools/           仓库检查及固件验证/打包脚本
```

官方基线 demo 源码仍作为参考文件保留，但 `main/CMakeLists.txt` 构建的是
独立打卡应用，不会进入原有测试菜单。

## 构建与验证

激活 ESP-IDF 5.5.3，然后在当前目录运行完整门禁：

```bash
source <path-to-esp-idf-v5.5.3>/export.sh
./tools/validate.sh
```

也可以按需运行：

```bash
./tools/validate.sh --static
./tools/validate.sh --firmware
```

固件验证成功后会生成：

- `build/FoloToy-AI-Passport-full.bin`
- `build/firmware/<完整镜像SHA256>/` 下与固件匹配的调试包

合并镜像只用于空白设备初始化或有意完整刷新。开发过程中若要保留现有打卡
和照片，请使用[应用指南](docs/habit-tracker.zh_CN.md#持久化布局与烧录)中的
分段烧录方法。

## 开发约束

修改固件前请阅读 [`AGENTS.md`](AGENTS.md) 和
[`docs/hardware-design/AI_HARDWARE_DEVELOPMENT_GUIDE.md`](docs/hardware-design/AI_HARDWARE_DEVELOPMENT_GUIDE.md)。
应用状态和 UI 放在 `main/`，可复用板级逻辑放在 `components/bsp/`。
