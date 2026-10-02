# RemoteMapper

macOS 菜单栏 App，把 Siri Remote 的按键映射为开发工具（Claude Code、Claude 桌面版、Codex 等）的动作。

## 命令

- `make build` / `make run`：XcodeGen 生成工程后编译（`*.xcodeproj` 不入库，改 `project.yml`）
- `make test`：核心库测试（Swift Testing），改 `Packages/RemoteKit` 后必跑
- `make snapshot`：把所有界面（深色/浅色）渲染为 PNG 到 `build/snapshots`，改 UI 后用它做视觉自检，不需要屏幕录制权限

## 发布

- 只做网页下载安装，不上架 App Store，不维护沙盒版本（触控面用私有框架，Shell / AppleScript / 电源控制也离不开非沙盒环境）。只有一个 target `RemoteMapper`（com.ws.RemoteMapper）。
- 正式版：`make dist`（`scripts/release-direct.sh`），Developer ID 签名 + 公证 + DMG。
- 云端自用构建：推送 `v版本号` 标签触发 `.github/workflows/release.yml`（`scripts/release-cloud.sh`），ad-hoc 签名、未公证。
- 版本号在 `project.yml` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`，标签须与 `MARKETING_VERSION` 一致。

## 架构

- `Packages/RemoteKit`：与 UI 无关的核心。`RemoteDevice`（IOHIDManager 读报告 0xFB）→ `GestureEngine`（单击/双击/长按/按住）→ `RemoteEngine`（按前台 App 解析配置）→ `ActionRunner`（CGEvent、NSWorkspace；Shell / AppleScript 经 `ScriptExecutor` 在子进程运行，锁屏 / 休眠 / 重启 / 关机经 `SystemControl`，两者在测试中可替换为记录器）。`MediaKeyInterceptor` 用 CGEventTap 拦截被映射的媒体键（独占按键接口时只作兜底）。`TouchSurface`（dlsym 加载 MultitouchSupport，按偏移读 96 字节的 MTTouch）→ 手势模式下 `TouchGestureRecognizer`（滑动 / 转动），鼠标模式下 `TouchPointer`（按起手位置分为移动光标、右侧滚动区、外圈转盘，滚动带触控板阶段与惯性，鼠标事件经 `PointerOutput` 输出，测试中替换为记录器）→ `RemoteEngine`。鼠标模式配置（`Profile.isPointerMode`）在触控板用作鼠标时优先于 App 专属配置。`BatteryMonitor` 用 CoreBluetooth 共享系统已建立的 BLE 连接，读 Battery Level（0x2A19），按 HID 产品名匹配外设。`DotCall` 用辅助功能 API 操作 ChatGPT（com.openai.codex）里 dot 的通话按钮：先设 `AXManualAccessibility` 打开 Electron 的无障碍树，按标签（Start call / Hang up / 将麦克风静音）找按钮；这些按钮没有 AXPress，只能合成鼠标点击，点击前用 `AXUIElementCopyElementAtPosition` 确认最上层是 ChatGPT。dot 名字读自 `~/.codex/.codex-global-state.json`。`LockScreen` 负责「解锁屏幕」：会话字典的 `CGSSessionScreenIsLocked` 判断锁屏（未锁屏时什么也不输入）；先 `IOPMAssertionDeclareUserActivity` 点亮屏幕，再用辅助功能等 loginwindow 的 `AXSecureTextField` 获得焦点（迟迟没有焦点就设焦点或点击它，找不到就按 Shift 唤出），然后按 ASCII 键盘布局的真实键位逐字输入 `UnlockPassword`（登录钥匙串里的通用密码）并回车。密码不进配置文件、界面与日志。`SlideShow` 负责「放映演示文稿」：（锁屏时先解锁或等待解锁）→ `NSWorkspace` 用默认 App 打开 → 等该 App 到前台且焦点窗口标题含文稿名（标题不含文件名时在前台 6 秒也算就绪）→ 发送「从头放映」预设的快捷键；日志分类 `slideshow`。
- `App/Sources`：SwiftUI。`AppModel` 持有 `ConfigStore` 与 `RemoteEngine`；`AppModel.preview()` 提供截图用的假数据。
- `AudioBridge`：遥控器麦克风的 CoreAudio 驱动与按需采集服务，独立于 App 构建（`make mic-build` 输出到 `build/Microphone`，作为资源打进 App，由 `MicrophoneBridge` 授权安装）。
- App 与 RemoteKit 都开启了默认 MainActor 隔离；IOKit / CGEventTap 的 C 回调写成 `nonisolated` 全局函数，指针以地址形式传入后 `MainActor.assumeIsolated`。

## 约定

- 代码注释、界面文案使用简体中文。
- 新的开发工具绑定优先加到 `Presets.swift`，默认映射在 `RemoteConfig.default`。给已有用户补默认配置要提升 `RemoteConfig.currentVersion` 并在 `migrate()` 里只填补空缺。
- 演示快捷键：PowerPoint、Keynote 以官方文档为准（链接在 `Presets.swift`）；WPS Mac 版没有文档，查 `/Applications/wpsoffice.app/Contents/Resources/office6/res/commands/wpp/**/*.kuip` 里的 `shortcutHint`，它基于 Qt，`Ctrl` 即 ⌘、`Meta` 即 ⌃、`Alt` 即 ⌥。WPS 的文字、表格、演示共用一个 Bundle ID，演示配置里不要放字母键这类会输入到文稿里的动作。
- 配置 JSON 需保持可手写：`Action` 用 `type` 区分，`KeyCombo` 编码为 `{"key": "tab", "modifiers": ["shift"]}`。
- 设计规范集中在 `App/Sources/Design/Theme.swift`；舞台区域始终是深色。

## 调试

- 运行日志：`/usr/bin/log show --last 5m --info --predicate 'subsystem == "com.ws.RemoteMapper"'`（zsh 里 `log` 是内置命令，必须写完整路径）。

## 已验证（2026-10-01，本机 PID 0x0315 遥控器）

- 遥控器没有运动数据：蓝牙抓包中挥动 15 秒无任何数据包；传感器用途的 HID 接口（20:42、20:E0）是不透明隧道，无系统服务使用。AirTag 也无法补充（Mac 无 UWB，NearbyInteraction 在 macOS 不可用）。
- 只有触控板有触控：轻触其它按键不产生数据；触控只支持单指，约 67 Hz，MTTouch 还带速度、毫米坐标、接触椭圆与疑似压力（偏移 92）。
- 触控 y 轴向上：鼠标模式下光标方向正确。
- 抓包：`sudo Tools/bt-capture.sh 输出文件 [motion|touch]`，`python3 Tools/bt-analyze.py 输出文件`；PacketLogger 的时间戳与系统时钟差一个时区偏移，分析脚本按整半小时自动对齐。

## 已验证（2026-10-02）

- 合成按键的修饰键会残留：只在按键事件上带 ⌘/⇧ 标志而不发送修饰键松开时，系统的 HID 修饰键状态会停在 ⌘，之后新建的鼠标、滚动事件都继承它（WPS 里触控板滚动变成缩放）。所以 `KeyboardSynth` 在组合键松开、逐字输入结束后都会补发一次 flagsChanged 松开；新增合成按键的代码也要这样做。

- 遥控器电源键的关机对话框挡不住事件流：电源键会产生 NX_POWER_KEY（= 6）事件，但即使拦截器把它全部丢弃，macOS 仍弹出「确定要现在将电脑关机吗？」——HID 驱动直接通知了电源管理。普通权限可以独占（seize）按键接口（usagePage 0x0C / usage 0x01），所以「启用映射 + 接管系统媒体键」时 `RemoteDevice.isExclusive` 独占该接口，系统收不到任何遥控器按键；未映射的音量、静音、播放键由 `KeyboardSynth.postMediaKey` 代发。触控面、麦克风是其它接口，不受影响。实测：独占后按键报告照常到达本 App，系统不再收到任何媒体键事件，电源键双击不再弹框。
- 媒体键拦截：遥控器的播放键会产生 NX_SYSDEFINED 媒体键事件，遥控器 HID 报告比它早约 3 ms 到达，拦截器据此丢弃（日志分类 `mediakey`）；音量键经用户实测符合需求。
- 锁屏解锁（亮屏锁屏）：锁屏时辅助功能能读到 loginwindow 已获得焦点的密码框（约 20 ms 就绪），按真实键位输入可进入密码框，锁屏时钥匙串可读；每一步记在日志分类 `lockscreen`。

## 待验证

- dot 通话：已在 ChatGPT 26.928 上实测呼叫、挂断、静音、跳转与焦点恢复（2026-09-30）；ChatGPT 若翻译「Start call / Hang up」或改版，先用 `make dotcall && build/dotcall dump` 核对标签，再同步更新 `DotCall` 与 `Tools/dotcall.swift`。

- 按键位序是从报告描述符推断的，需按实体遥控器核对（诊断页的按键位图）。
- 锁屏解锁在屏幕已熄灭时是否同样可靠（亮屏锁屏已验证）。
- 一键放映：⇧⌘↩ 在 WPS 里是否总能从头放映（WPS 打开文稿后焦点窗口标题含文件名已验证，约 1 秒即放映）。
- Siri 键在 macOS 上是否触发系统 Siri / 听写。
