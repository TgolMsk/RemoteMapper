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
                .environment(\.locale, L10n.locale)
                .environment(\.layoutDirection, L10n.language.isRightToLeft ? .rightToLeft : .leftToRight)
        } label: {
            Image(systemName: model.engine.device.isConnected ? "appletvremote.gen4.fill" : "appletvremote.gen4")
        }
        .menuBarExtraStyle(.window)

        Window("RemoteMapper", id: SettingsWindow.id) {
            SettingsView()
                .environment(model)
                .environment(\.locale, L10n.locale)
                .environment(\.layoutDirection, L10n.language.isRightToLeft ? .rightToLeft : .leftToRight)
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
        if let index = arguments.firstIndex(of: "--microphone-check"), arguments.indices.contains(index + 2) {
            let seconds = min(60, max(3, Int(arguments[index + 1]) ?? 20))
            let output = URL(fileURLWithPath: arguments[index + 2])
            Task { exit(await MicrophoneCheck.run(seconds: seconds, output: output)) }
        }
        if let index = arguments.firstIndex(of: "--transcription-check"), arguments.indices.contains(index + 1) {
            let input = URL(fileURLWithPath: arguments[index + 1])
            Task { exit(await MicrophoneCheck.transcribe(input)) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
