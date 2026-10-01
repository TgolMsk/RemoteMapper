# RemoteMapper

macOS 菜单栏 App，把 Siri Remote 的按键映射为开发工具（Claude Code、Claude 桌面版、Codex 等）的动作。

## 命令

- `make build` / `make run`：XcodeGen 生成工程后编译（`*.xcodeproj` 不入库，改 `project.yml`）
- `make test`：核心库测试（Swift Testing），改 `Packages/RemoteKit` 后必跑
- `make snapshot`：把所有界面（深色/浅色）渲染为 PNG 到 `build/snapshots`，改 UI 后用它做视觉自检，不需要屏幕录制权限

## 两个版本

- 官网版 `RemoteMapper`（com.ws.RemoteMapper）：Developer ID 签名 + 公证，`make dist` 发布，功能完整。
- App Store 版 `RemoteMapperLite`（com.ws.RemoteMapper.Lite）：沙盒，`make appstore` 发布。编译条件 `APP_STORE`，功能差异集中在 `App/Sources/Edition.swift`；不得链接 `RemoteKitTouch`（私有接口）与 `RemoteKitScripts`（外部命令）。
- 已验证（2026-09-30）：沙盒内读取遥控器按键、读取电量、在用户手动开启辅助功能后模拟按键均可用；沙盒拒绝打开 AppleMultitouchDevice，也无法弹出辅助功能授权框。

## 架构

- `Packages/RemoteKit`：与 UI 无关的核心。`RemoteDevice`（IOHIDManager 读报告 0xFB）→ `GestureEngine`（单击/双击/长按/按住）→ `RemoteEngine`（按前台 App 解析配置）→ `ActionRunner`（CGEvent、NSWorkspace、子进程）。`MediaKeyInterceptor` 用 CGEventTap 拦截被映射的媒体键。`TouchSurface`（dlsym 加载 MultitouchSupport，按偏移读 96 字节的 MTTouch）→ `TouchGestureRecognizer`（滑动 / 转动）→ `RemoteEngine`。`BatteryMonitor` 用 CoreBluetooth 共享系统已建立的 BLE 连接，读 Battery Level（0x2A19），按 HID 产品名匹配外设。`DotCall` 用辅助功能 API 操作 ChatGPT（com.openai.codex）里 dot 的通话按钮：先设 `AXManualAccessibility` 打开 Electron 的无障碍树，按标签（Start call / Hang up / 将麦克风静音）找按钮；这些按钮没有 AXPress，只能合成鼠标点击，点击前用 `AXUIElementCopyElementAtPosition` 确认最上层是 ChatGPT。dot 名字读自 `~/.codex/.codex-global-state.json`，App Store 版不支持。
- `App/Sources`：SwiftUI。`AppModel` 持有 `ConfigStore` 与 `RemoteEngine`；`AppModel.preview()` 提供截图用的假数据。
- 两个 target 都开启了默认 MainActor 隔离；IOKit / CGEventTap 的 C 回调写成 `nonisolated` 全局函数，指针以地址形式传入后 `MainActor.assumeIsolated`。

## 约定

- 代码注释、界面文案使用简体中文。
- 新的开发工具绑定优先加到 `Presets.swift`，默认映射在 `RemoteConfig.default`。
- 配置 JSON 需保持可手写：`Action` 用 `type` 区分，`KeyCombo` 编码为 `{"key": "tab", "modifiers": ["shift"]}`。
- 设计规范集中在 `App/Sources/Design/Theme.swift`；舞台区域始终是深色。

## 调试

- 运行日志：`/usr/bin/log show --last 5m --info --predicate 'subsystem == "com.ws.RemoteMapper"'`（zsh 里 `log` 是内置命令，必须写完整路径）。

## 待验证

- dot 通话：已在 ChatGPT 26.928 上实测呼叫、挂断、静音、跳转与焦点恢复（2026-09-30）；ChatGPT 若翻译「Start call / Hang up」或改版，先用 `make dotcall && build/dotcall dump` 核对标签，再同步更新 `DotCall` 与 `Tools/dotcall.swift`。

- 按键位序是从报告描述符推断的，需按实体遥控器核对（诊断页的按键位图）。
- 遥控器的音量/播放键在 macOS 上是否以 NX_SYSDEFINED 媒体键事件出现（决定拦截是否生效）。
- Siri 键在 macOS 上是否触发系统 Siri / 听写。
- 触控：MTTouch 字段偏移与 y 轴方向（假设 y 向上）需用实体遥控器核对（诊断页「触控面 › 当前触点」）。
