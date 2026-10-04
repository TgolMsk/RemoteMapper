import Foundation
import Testing
@testable import RemoteKit

@Suite(.serialized)
struct LocalizationModelTests {
    private func withLanguage(_ language: AppLanguage, _ body: () throws -> Void) rethrows {
        let original = LanguageSettings.shared.selectedLanguage
        let savedPreference = UserDefaults.standard.object(forKey: LanguageSettings.preferenceKey)
        LanguageSettings.shared.selectedLanguage = language
        defer {
            LanguageSettings.shared.selectedLanguage = original
            if let savedPreference { UserDefaults.standard.set(savedPreference, forKey: LanguageSettings.preferenceKey) }
            else { UserDefaults.standard.removeObject(forKey: LanguageSettings.preferenceKey) }
        }
        try body()
    }

    @Test func modelLabelsUseSelectedLanguage() {
        withLanguage(.english) {
            #expect(Action.Kind.keystroke.displayName == L10n.text("快捷键", language: .english))
            #expect(Action.Kind.keystroke.displayName != "快捷键")
            #expect(RemoteButton.back.displayName == L10n.text("返回", language: .english))
            #expect(RemoteGesture.hold.detail == L10n.text("按下开始、松开结束，适合按住说话", language: .english))
            #expect(TouchGesture.swipeUp.detail == L10n.text("在触控板上快速上滑后抬起", language: .english))
            #expect(SystemCommand.lockScreen.displayName == L10n.text("锁屏", language: .english))
            #expect(DictationError.remoteMicrophoneUnavailable.message != "遥控器麦克风尚未安装：请在「通用 › 语音输入」中安装音频组件")
            #expect(Action.scroll(.down, lines: 7).summary.contains("7"))
            #expect(Action.scroll(.down, lines: 7).summary != "向下 7 行")
        }
        withLanguage(.simplifiedChinese) {
            #expect(Action.Kind.keystroke.displayName == "快捷键")
            #expect(TouchGesture.swipeUp.detail == "在触控板上快速上滑后抬起")
            #expect(Action.scroll(.down, lines: 7).summary == "向下 7 行")
        }
    }

    @Test func presetTranslationPreservesRawAndCustomTitles() throws {
        let preset = try #require(Preset.find("voice.dictation"))
        withLanguage(.english) {
            #expect(preset.title == "语音输入")
            #expect(preset.bound.title == "语音输入")
            #expect(preset.displayTitle != preset.title)
            #expect(preset.bound.displayTitle == preset.displayTitle)
            #expect(preset.displayDetail != preset.detail)
            var renamed = preset.bound
            renamed.title = "给团队留言"
            #expect(renamed.displayTitle == "给团队留言")
            renamed.title = "确定"
            #expect(renamed.displayTitle == "确定")
            #expect(BoundAction(.shell("printf ok"), title: preset.title).displayTitle == preset.title)
            #expect(BoundAction(.dictation(submit: false), title: preset.title, presetID: "custom.voice").displayTitle == preset.title)
        }
    }

    @Test func legacyNavigationTitlesTranslateOnlyMatchingActions() {
        withLanguage(.english) {
            #expect(BoundAction(.keystroke(.upArrow), title: "方向键").displayTitle == L10n.text("方向键", language: .english))
            #expect(BoundAction(.keystroke(.returnKey), title: "确认").displayTitle == L10n.text("确认", language: .english))
            #expect(BoundAction(.keystroke(.escape), title: "返回").displayTitle == L10n.text("返回", language: .english))
            #expect(RemoteConfig.defaultPointerProfile.mapping(for: .siri)?.tap?.displayTitle == L10n.text("确定", language: .english))
            #expect(BoundAction(.keystroke(.space), title: "方向键").displayTitle == "方向键")
            #expect(BoundAction(.mouseButton(.right), title: "确定").displayTitle == "确定")
            #expect(BoundAction(.text("payload", submit: false), title: "返回").displayTitle == "返回")
        }
    }

    @Test func builtInProfileNamesTranslateWithoutRenamingCustomProfiles() {
        withLanguage(.english) {
            let config = RemoteConfig.default
            #expect(config.globalProfile.name == "全局")
            #expect(config.globalProfile.displayName == L10n.text("全局", language: .english))
            #expect(config.profiles.first(where: { $0.name == "终端" })?.displayName == L10n.text("终端", language: .english))
            #expect(config.pointerProfile?.displayName == L10n.text("鼠标模式", language: .english))
            #expect(RemoteConfig.defaultPresentationProfile.displayName == L10n.text("演示", language: .english))
            #expect(Profile(name: "终端", bundleIDs: ["com.example.editor"]).displayName == "终端")
            #expect(Profile(name: "演示", bundleIDs: ["com.example.slides"]).displayName == "演示")
            #expect(Profile(name: "我的全局映射").displayName == "我的全局映射")
            var renamed = config.globalProfile
            renamed.name = "Living room"
            #expect(renamed.displayName == "Living room")
        }
    }

    @Test func languageChangeDoesNotRewriteConfigurationOrUserPayload() throws {
        var config = RemoteConfig.default
        let custom = BoundAction(.text("保留中文 text payload", submit: true), title: "我的动作", presetID: "voice.dictation")
        config.profiles.append(Profile(name: "我的编辑器", bundleIDs: ["com.example.editor"], mappings: [.siri: ButtonMapping(tap: custom)]))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let original = try encoder.encode(config)
        try withLanguage(.english) {
            _ = config.profiles.map(\.displayName)
            _ = config.globalProfile.mappings.values.compactMap { $0.hold?.displayTitle }
            #expect(try encoder.encode(config) == original)
            let decoded = try JSONDecoder().decode(RemoteConfig.self, from: original)
            #expect(decoded == config)
            #expect(decoded.profiles.last?.name == "我的编辑器")
            #expect(decoded.profiles.last?.mapping(for: .siri)?.tap == custom)
            #expect(decoded.profiles.last?.mapping(for: .siri)?.tap?.displayTitle == "我的动作")
        }
        try withLanguage(.traditionalChinese) {
            let encoded = try encoder.encode(config)
            #expect(encoded == original)
            #expect(config.profiles.last?.mapping(for: .siri)?.tap?.action == .text("保留中文 text payload", submit: true))
        }
    }
}
