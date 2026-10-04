import AppKit
import RemoteKit
import SwiftUI

/// 以 `--snapshot <目录>` 启动时，把各界面渲染成 PNG 后退出，用于不依赖屏幕录制权限的视觉自检。
enum SnapshotRenderer {
    static func renderAll(to directory: URL) {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let size = SettingsWindow.size

        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let suffix = appearance == .darkAqua ? "dark" : "light"
            for tab in SettingsTab.allCases {
                let model = AppModel.preview()
                model.tab = tab
                render(SettingsView().environment(model), size: size, appearance: appearance,
                       to: directory.appending(path: "settings-\(tab.rawValue)-\(suffix).png"))
            }

            let appModel = AppModel.preview(pressed: [])
            render(VoiceSettingsGroup().environment(appModel).padding(24)
                .background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 790, height: 640),
                   appearance: appearance, to: directory.appending(path: "voice-settings-\(suffix).png"))
            for saved in [false, true] {
                render(UnlockSettingsGroup().environment(AppModel.preview(pressed: [], unlockPassword: saved)).padding(24)
                    .background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 790, height: 150),
                       appearance: appearance, to: directory.appending(path: "unlock-\(saved ? "saved" : "empty")-\(suffix).png"))
            }
            appModel.selectedProfileID = appModel.config.profiles.first { !$0.isGlobal }!.id
            appModel.selectedButton = .playPause
            render(SettingsView().environment(appModel), size: size, appearance: appearance,
                   to: directory.appending(path: "settings-appprofile-\(suffix).png"))

            let pressedModel = AppModel.preview(pressed: [.up, .tv])
            pressedModel.selectedButton = .up
            render(SettingsView().environment(pressedModel), size: size, appearance: appearance,
                   to: directory.appending(path: "settings-pressed-\(suffix).png"))

            let touchModel = AppModel.preview(pressed: [], touches: [TouchContact(id: 1, state: 4, x: 0.78, y: 0.66)])
            touchModel.mappingMode = .touch
            render(SettingsView().environment(touchModel), size: size, appearance: appearance,
                   to: directory.appending(path: "settings-touch-\(suffix).png"))

            let editors: [(String, EditorTarget)] = [("preset", .button(.siri, .hold)), ("keystroke", .button(.playPause, .tap)),
                                                     ("scroll", .touch(.rotateClockwise)), ("slides", .button(.playPause, .longPress))]
            for (name, target) in editors {
                let model = AppModel.preview()
                let terminal = model.config.profiles.first { !$0.isGlobal }!.id
                let profileID = name == "scroll" ? model.config.globalProfile.id : terminal
                if name == "scroll" { model.setAction(BoundAction(.scroll(.down, lines: 5)), for: target, in: profileID) }
                if name == "slides" {
                    model.setAction(BoundAction(.playSlides(path: "~/Documents/产品发布会.pptx", unlock: true)), for: target, in: profileID)
                }
                let context = EditorContext(profileID: profileID, target: target)
                render(ActionEditorSheet(context: context).environment(model), size: CGSize(width: 760, height: 600),
                       appearance: appearance, to: directory.appending(path: "editor-\(name)-\(suffix).png"))
            }

            // 语音输入浮窗：识别中、出错两种状态
            for (name, phase, text, level) in [("listening", VoiceDictation.Phase.listening, "帮我把这个函数改成异步的，并补上单元测试", Float(0.7)),
                                               ("failed", .failed(L10n.text("没有可用的麦克风：请连接 AirPods、耳机或 USB 麦克风")), "", 0)] {
                let model = AppModel.preview()
                model.engine.dictation.simulate(phase: phase, transcript: text, level: level)
                // 让波形有历史数据可画
                for step in 0..<16 { model.engine.dictation.simulate(phase: phase, transcript: text, level: level * Float(0.3 + 0.7 * abs(sin(Double(step) * 0.9)))) }
                let hudSize = DictationHUDController.size
                render(DictationHUDView().environment(model).frame(width: hudSize.width, height: hudSize.height, alignment: .bottom)
                    .background(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.35)], startPoint: .top, endPoint: .bottom)),
                       size: hudSize, appearance: appearance,
                       to: directory.appending(path: "hud-\(name)-\(suffix).png"))
            }

            render(MenuBarPanel().environment(AppModel.preview()).fixedSize()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 340, height: 250),
                   appearance: appearance, to: directory.appending(path: "menubar-\(suffix).png"))
        }
    }

    private static func render(_ view: some View, size: CGSize, appearance: NSAppearance.Name, to url: URL) {
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .environment(\.locale, L10n.locale)
            .environment(\.layoutDirection, L10n.language.isRightToLeft ? .rightToLeft : .leftToRight))
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}
