# RemoteMapper

把 Apple TV 的 Siri Remote 变成 Mac 上的开发工具遥控器：按住 Siri 键对 Claude Code 说话、播放键切换权限模式、TV 键在 Claude / Codex / iTerm 之间切换……所有映射都可以在设置界面里改。

菜单栏常驻、不占程序坞；设置窗口里有一个实时响应的遥控器，按下实体遥控器上的键，界面上对应的键会亮起并被选中。

## 快速开始

```bash
make run        # 生成工程、编译并启动
make test       # 核心库单元测试
make snapshot   # 渲染所有界面截图到 build/snapshots
make install    # Release 版安装到 /Applications（开机自启需要从这里运行）
```

依赖：Xcode 27、macOS 26、[XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

首次运行需要在「系统设置 › 隐私与安全性 › 辅助功能」中授权 RemoteMapper，否则无法模拟按键。

## 功能

- **四种手势**：单击、双击、长按、按住（按下开始、松开结束，用于按住说话）
- **App 专属配置**：例如在 iTerm / 终端 中让 Siri 键变成 Claude Code 的按住说话，其它 App 中仍是全局设置
- **动作类型**：快捷键、按住按键（模拟自动重复）、输入文本、打开 App、打开链接、Shell 命令、AppleScript，以及面向 Claude Code / Claude 桌面版 / Codex 的预设
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

触控板（Digitizer）、运动传感器、麦克风都是 Apple 私有格式，尚未解析。
