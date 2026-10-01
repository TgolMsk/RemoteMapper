import AppKit
import RemoteKit
import SwiftUI

@main
struct RemoteMapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .environment(model)
        } label: {
            Image(systemName: model.engine.device.isConnected ? "appletvremote.gen4.fill" : "appletvremote.gen4")
        }
        .menuBarExtraStyle(.window)

        Window(Edition.name, id: SettingsWindow.id) {
            SettingsView()
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: SettingsWindow.size.width, height: SettingsWindow.size.height)
        .defaultLaunchBehavior(.presented)
    }
}

enum SettingsWindow {
    static let id = "settings"
    static let size = CGSize(width: 1120, height: 740)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) {
            SnapshotRenderer.renderAll(to: URL(fileURLWithPath: arguments[index + 1]))
            exit(0)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
