# RemoteMapper

把 Apple TV 的 Siri Remote 变成 Mac 上的开发工具遥控器：按住 Siri 键对 Claude Code 说话、播放键切换权限模式、TV 键在 Claude / Codex / iTerm 之间切换……所有映射都可以在设置界面里改。

菜单栏常驻、不占程序坞；设置窗口里有一个实时响应的遥控器，按下实体遥控器上的键，界面上对应的键会亮起并被选中。

## 两个版本

| | 官网版 RemoteMapper | App Store 版 RemoteMapper Lite |
|---|---|---|
| 发布方式 | Developer ID 签名 + 公证，`make dist` | 沙盒，`make appstore` |
| 触控手势、Shell、AppleScript | ✅ | — |
| 按键映射、电量、App 专属配置 | ✅ | ✅ |

## 快速开始

```bash
make run        # 生成工程、编译并启动
make test       # 核心库单元测试
make snapshot   # 渲染所有界面截图到 build/snapshots
make install    # Release 版安装到 /Applications（开机自启需要从这里运行）
```

依赖：Xcode 27、macOS 26、[XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

## 云端完整版下载

[GitHub Releases](https://github.com/TgolMsk/RemoteMapper/releases) 提供 Apple Silicon / macOS 26+
的完整版 DMG（私有仓库需登录有访问权限的 GitHub 帐户）。下载后将 App 拖入「应用程序」。
云端自用构建采用 ad-hoc 本地签名，未经 Apple 公证；首次打开如被拦截，在「系统设置 ›
隐私与安全性」中允许打开。Developer ID 签名和公证仍使用 `make dist` 的本机流程。

推送与 `MARKETING_VERSION` 一致的 `v版本号` 标签会触发 `Full macOS Release`，在 macOS 26 / Xcode 26.6
上运行核心测试、音频组件模拟验证并打包，只构建 `RemoteMapper` 完整版。
手动运行该工作流可下载 Actions 附件，不会创建 Release。附件包含音频组件对应源码、
Opus 源码、构建提交及 SHA-256 校验和。云端测试不替代实体遥控器的按键、录音与听写实测。

首次运行需要在「系统设置 › 隐私与安全性 › 辅助功能」中授权 RemoteMapper，否则无法模拟按键。

## 功能

- **四种手势**：单击、双击、长按、按住（按下开始、松开结束，用于按住说话）
- **触控手势**：在触控板上四向滑动、沿外圈顺/逆时针转动（每转过设定角度触发一次，适合滚动）
- **App 专属配置**：例如在 iTerm / 终端 中让 Siri 键变成 Claude Code 的按住说话，其它 App 中仍是全局设置
- **动作类型**：快捷键、按住按键（模拟自动重复）、输入文本、滚动、打开 App、打开链接、Shell 命令、AppleScript，以及面向 Claude Code / Claude 桌面版 / Codex 的预设
- **电量显示**：通过蓝牙标准电池服务（0x180F）读取遥控器电量，显示在设置窗口与菜单栏，低于 15% 变橙色（首次运行需允许蓝牙权限）
- **接管系统媒体键**：映射了音量、静音、播放键时，拦截它们原本的系统功能
- **配置即文件**：`~/Library/Application Support/RemoteMapper/config.json`，外部修改会自动载入

## 目录结构

```
App/                    SwiftUI 应用（菜单栏 + 设置窗口）
  Sources/Stage/        左侧遥控器主视觉、标注、实时事件
  Sources/Settings/     映射 / 通用 / 权限与诊断 三个页面
  Sources/Editor/       动作编辑器
Packages/RemoteKit/     核心库：HID 读取、手势识别、动作执行、配置
Tools/RemoteProbe.swift 原始 HID 探针
scripts/make-icon.swift 图标绘制脚本
project.yml             XcodeGen 工程描述
```

## 遥控器协议

Siri Remote（VID `0x004C` / PID `0x0315`）通过 BLE 连接，按键走 Consumer Control 接口的报告 `0xFB`：13 个 1 位字段，顺序为 TV、音量+、音量−、触控板按下、电源、Siri、返回、静音、播放/暂停、上、右、下、左。该顺序取自设备的报告描述符，可在「权限与诊断 › 按键位图」中实时核对。

触控面由系统注册为多点触控设备，通过私有框架 MultitouchSupport 读取触点（与 Mac 触控板同一套驱动），因此不能上架 App Store，系统大版本更新后可能需要适配。

## 遥控器麦克风接入 macOS

官网版「通用 › 语音输入」选择「遥控器麦克风」，点击「安装并设为系统输入」。安装需要
管理员授权，会短暂重启系统音频；安装后 macOS 和其他 App 的音频输入列表中出现
**Siri Remote Mic**。按住实体 Siri 键说话，松开后静音。应用内听写也使用同一输入，
不会在遥控器缺失时自动录制其他麦克风。

需 macOS 26、已配对的第三代 USB-C Siri Remote（PID `0x0315`），以及 Apple
[Additional Tools for Xcode](https://developer.apple.com/download/all/) 中的 PacketLogger，
安装到 `/Applications/PacketLogger.app`。本机开发还需 `brew install opus`。音频通过
PacketLogger 实时蓝牙记录 → ATT 分片重组 → Opus 解码 → 48 kHz 单声道共享缓冲 →
CoreAudio HAL 输入驱动传递；依赖未公开的蓝牙格式，系统或遥控器固件更新后需重新验证。
按需采集启动有延迟，首次使用等输入有反应后再开始说话。

只有输入设备正在使用时，独立服务才启用蓝牙实时记录；停止采集后删除临时文件，并
恢复 `HCITraces` 原值。临时蓝牙记录仅 root 可读，限制为 32 MiB。安装会观察 25 秒
`coreaudiod` 负载，异常则自动恢复旧组件。App Store 版不携带安装服务，能使用已安装
的标准 CoreAudio 输入。

```bash
make mic-build      # 解码、分片重组、驱动属性与实时缓冲模拟验证
make mic-install    # 单独安装音频组件（sudo）
make mic-uninstall  # 卸载并恢复蓝牙调试设置
```

独立音频组件源码与来源说明见 [AudioBridge/NOTICE.md](AudioBridge/NOTICE.md)，构建在
`build/Microphone`，测试记录在 `build/MicrophoneTests`。模拟测试不代表实体遥控器录音通过；
实机验证必须从 CoreAudio 输入录到非静音语音，并核对松键后静音和采集停止。
