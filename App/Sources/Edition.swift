import Foundation
import RemoteKit
#if !APP_STORE
import RemoteKitScripts
import RemoteKitTouch
#endif

/// 发行版本：官网版（Developer ID 签名 + 公证）功能完整；
/// App Store 版运行在沙盒中，去掉私有接口（触控面）与执行外部命令（Shell、AppleScript）的功能。
enum Edition {
    #if APP_STORE
    static let isAppStore = true
    #else
    static let isAppStore = false
    #endif

    static let name = isAppStore ? "RemoteMapper Lite" : "RemoteMapper"

    /// 触控手势依赖私有框架 MultitouchSupport
    static let supportsTouch = !isAppStore
    /// Shell 命令与 AppleScript 在沙盒中无法正常工作，也不符合审核要求；
    /// dot 通话要读取 ~/.codex 并用辅助功能操作 ChatGPT 的界面，沙盒内同样不可行；
    /// 按住滚动与切换触控鼠标依赖触控面
    static let unsupportedActions: Set<Action.Kind> = isAppStore
        ? [.shell, .appleScript, .dotCall, .pointerScroll, .toggleTouchMode] : []

    static var scriptExecutor: ((Action) async -> String?)? {
        #if APP_STORE
        nil
        #else
        ScriptExecutor.run
        #endif
    }

    static func makeTouchSource() -> (any TouchSource)? {
        #if APP_STORE
        nil
        #else
        TouchSurface()
        #endif
    }

    /// 仅用于界面预览与截图
    static func makePreviewTouchSource(contacts: [TouchContact]) -> (any TouchSource)? {
        #if APP_STORE
        nil
        #else
        let surface = TouchSurface()
        surface.simulate(contacts: contacts)
        return surface
        #endif
    }
}
