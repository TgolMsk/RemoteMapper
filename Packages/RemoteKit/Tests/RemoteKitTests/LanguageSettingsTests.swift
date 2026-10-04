import Foundation
import Observation
import Testing
@testable import RemoteKit

@Suite("Interface language")
struct LanguageSettingsTests {
    @Test func resolvesRegionalPreferencesInPriorityOrder() {
        #expect(AppLanguage.resolve(preferredLanguages: ["en-GB", "ja"]) == .english)
        #expect(AppLanguage.resolve(preferredLanguages: ["nl-NL", "fr-CA"]) == .french)
        #expect(AppLanguage.resolve(preferredLanguages: ["pt-PT"]) == .portuguese)
        #expect(AppLanguage.resolve(preferredLanguages: ["zh-TW"]) == .traditionalChinese)
        #expect(AppLanguage.resolve(preferredLanguages: ["zh-HK"]) == .traditionalChinese)
        #expect(AppLanguage.resolve(preferredLanguages: ["zh_Hans_TW"]) == .simplifiedChinese)
        #expect(AppLanguage.resolve(preferredLanguages: ["zh-Hant-CN"]) == .traditionalChinese)
        #expect(AppLanguage.resolve(preferredLanguages: ["ar-SA"]) == .arabic)
        #expect(AppLanguage.resolve(preferredLanguages: ["nl", "sv"]) == .english)
        #expect(AppLanguage.resolve(preferredLanguages: []) == .english)
    }

    @Test func persistsSelectionWithoutChangingSystemLanguages() throws {
        let suiteName = "RemoteMapper.LanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["zh-CN"], forKey: "AppleLanguages")
        let settings = LanguageSettings(defaults: defaults)
        #expect(settings.selectedLanguage == .system)
        settings.selectedLanguage = .german
        #expect(settings.resolvedLanguage == .german)
        #expect(LanguageSettings(defaults: defaults).selectedLanguage == .german)
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["zh-CN"])
        settings.selectedLanguage = .system
        #expect(LanguageSettings(defaults: defaults).selectedLanguage == .system)
        defaults.set("unknown-language", forKey: LanguageSettings.preferenceKey)
        #expect(LanguageSettings(defaults: defaults).selectedLanguage == .system)
    }

    @Test func snapshotOverrideDoesNotPersist() throws {
        let suiteName = "RemoteMapper.LanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(AppLanguage.japanese.rawValue, forKey: LanguageSettings.preferenceKey)
        let settings = LanguageSettings(defaults: defaults, sessionOverride: .arabic)
        #expect(settings.resolvedLanguage == .arabic)
        #expect(LanguageSettings(defaults: defaults).selectedLanguage == .japanese)
    }

    @Test func concurrentSelectionsKeepSavedPreferenceConsistent() throws {
        let suiteName = "RemoteMapper.LanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = LanguageSettings(defaults: defaults)
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            settings.selectedLanguage = index.isMultiple(of: 2) ? .french : .japanese
        }
        #expect(defaults.string(forKey: LanguageSettings.preferenceKey) == settings.selectedLanguage.rawValue)
    }

    @Test func resourcesLoadAcrossAllSupportedLanguages() {
        for language in AppLanguage.allCases where language != .system {
            #expect(L10n.translation("启用映射", language: language) != nil)
            let value = L10n.text("启用映射", language: language)
            #expect(!value.isEmpty)
            if language != .simplifiedChinese { #expect(value != "启用映射") }
        }
        #expect(L10n.text("启用映射", language: .english) == "Enable mappings")
        #expect(L10n.text("启用映射", language: .traditionalChinese) == "啟用映射")
        // 同字文案也是有效翻译，不能误判为缺失而回退英语。
        #expect(L10n.text("音量 +", language: .traditionalChinese) == "音量 +")
        #expect(L10n.text("unregistered.localization.key", language: .german) == "unregistered.localization.key")
        #expect(AppLanguage.arabic.isRightToLeft)
        #expect(!AppLanguage.english.isRightToLeft)
    }

    @Test func switchingIsObservable() throws {
        let suiteName = "RemoteMapper.LanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = LanguageSettings(defaults: defaults)
        nonisolated(unsafe) var changed = false
        withObservationTracking {
            _ = settings.selectedLanguage
        } onChange: {
            changed = true
        }
        settings.selectedLanguage = .spanish
        #expect(changed)
    }
}
