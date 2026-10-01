import AppKit
import RemoteKit
import SwiftUI

/// 以 `--snapshot <目录>` 启动时，把各界面渲染成 PNG 后退出，用于不依赖屏幕录制权限的视觉自检。
enum SnapshotRenderer {
    static func renderAll(to requested: URL) {
        // 沙盒版只能写入自己的容器，改写到容器内的临时目录，由调用方复制出来
        let directory = Edition.isAppStore ? FileManager.default.temporaryDirectory.appending(path: "snapshots") : requested
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { print("SNAPSHOT_DIR=\(directory.path)") }
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
            appModel.selectedProfileID = appModel.config.profiles.first { !$0.isGlobal }!.id
            appModel.selectedButton = .playPause
            render(SettingsView().environment(appModel), size: size, appearance: appearance,
                   to: directory.appending(path: "settings-appprofile-\(suffix).png"))

            let pressedModel = AppModel.preview(pressed: [.up, .tv])
            pressedModel.selectedButton = .up
            render(SettingsView().environment(pressedModel), size: size, appearance: appearance,
                   to: directory.appending(path: "settings-pressed-\(suffix).png"))

            if Edition.supportsTouch {
                let touchModel = AppModel.preview(pressed: [], touches: [TouchContact(id: 1, state: 4, x: 0.78, y: 0.66)])
                touchModel.mappingMode = .touch
                render(SettingsView().environment(touchModel), size: size, appearance: appearance,
                       to: directory.appending(path: "settings-touch-\(suffix).png"))
            }

            let editors: [(String, EditorTarget)] = [("preset", .button(.siri, .hold)), ("keystroke", .button(.playPause, .tap)),
                                                     ("scroll", .touch(.rotateClockwise))]
            for (name, target) in editors {
                let model = AppModel.preview()
                let terminal = model.config.profiles.first { !$0.isGlobal }!.id
                let profileID = name == "scroll" ? model.config.globalProfile.id : terminal
                if name == "scroll" { model.setAction(BoundAction(.scroll(.down, lines: 5)), for: target, in: profileID) }
                let context = EditorContext(profileID: profileID, target: target)
                render(ActionEditorSheet(context: context).environment(model), size: CGSize(width: 760, height: 600),
                       appearance: appearance, to: directory.appending(path: "editor-\(name)-\(suffix).png"))
            }

            render(MenuBarPanel().environment(AppModel.preview()).fixedSize()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 300, height: 230),
                   appearance: appearance, to: directory.appending(path: "menubar-\(suffix).png"))
        }
    }

    private static func render(_ view: some View, size: CGSize, appearance: NSAppearance.Name, to url: URL) {
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
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
