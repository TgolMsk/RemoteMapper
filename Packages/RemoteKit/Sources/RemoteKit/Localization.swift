import Foundation
import Observation
import Synchronization

/// 界面语言独立于语音识别语言和映射配置，切换语言不会改写用户数据。
nonisolated public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case portuguese = "pt-BR"
    case italian = "it"
    case russian = "ru"
    case arabic = "ar"

    public var id: String { rawValue }

    /// 语言名称始终以其本国语言显示，避免切换后找不到原来的语言。
    public var displayName: String {
        switch self {
        case .system: L10n.text("跟随系统")
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .french: "Français"
        case .german: "Deutsch"
        case .spanish: "Español"
        case .portuguese: "Português (Brasil)"
        case .italian: "Italiano"
        case .russian: "Русский"
        case .arabic: "العربية"
        }
    }

    public var isRightToLeft: Bool { self == .arabic }

    /// 按系统语言优先级匹配地区变体；没有支持的语言时回退到英语。
    public static func resolve(preferredLanguages: [String]) -> AppLanguage {
        for identifier in preferredLanguages {
            let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            let parts = normalized.split(separator: "-").map(String.init)
            guard let base = parts.first else { continue }
            if base == "zh" {
                if parts.contains("hant") || (!parts.contains("hans") && parts.contains(where: { ["tw", "hk", "mo"].contains($0) })) {
                    return .traditionalChinese
                }
                return .simplifiedChinese
            }
            if base == "pt" { return .portuguese }
            if let language = allCases.first(where: { $0 != .system && $0.rawValue.lowercased() == base }) {
                return language
            }
        }
        return .english
    }
}

@Observable
nonisolated public final class LanguageSettings: @unchecked Sendable {
    public static let preferenceKey = "RemoteMapper.interfaceLanguage"
    public static let shared: LanguageSettings = {
        let arguments = ProcessInfo.processInfo.arguments
        let override: AppLanguage?
        if let index = arguments.firstIndex(of: "--language"), arguments.indices.contains(index + 1) {
            override = AppLanguage(rawValue: arguments[index + 1])
        } else {
            override = nil
        }
        return LanguageSettings(sessionOverride: override)
    }()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sessionOverride: AppLanguage?

    @ObservationIgnored private let selection: Mutex<AppLanguage>

    public var selectedLanguage: AppLanguage {
        get {
            access(keyPath: \.selectedLanguage)
            return selection.withLock { $0 }
        }
        set {
            withMutation(keyPath: \.selectedLanguage) {
                selection.withLock {
                    $0 = newValue
                    defaults.set(newValue.rawValue, forKey: Self.preferenceKey)
                }
            }
        }
    }

    public init(defaults: UserDefaults = .standard, sessionOverride: AppLanguage? = nil) {
        self.defaults = defaults
        self.sessionOverride = sessionOverride
        selection = Mutex(AppLanguage(rawValue: defaults.string(forKey: Self.preferenceKey) ?? "system") ?? .system)
    }

    public var resolvedLanguage: AppLanguage {
        let selection = sessionOverride ?? selectedLanguage
        return selection == .system ? AppLanguage.resolve(preferredLanguages: Locale.preferredLanguages) : selection
    }
}

nonisolated public enum L10n {
    private static let bundles: [AppLanguage: Bundle] = Dictionary(uniqueKeysWithValues:
        AppLanguage.allCases.filter { $0 != .system }.compactMap { language in
            guard let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { return nil }
            return (language, bundle)
        })
    public static var language: AppLanguage { LanguageSettings.shared.resolvedLanguage }
    public static var locale: Locale { Locale(identifier: language.rawValue) }

    public static func text(_ key: String) -> String { text(key, language: language) }

    public static func text(_ key: String, language: AppLanguage) -> String {
        let resolved = language == .system ? AppLanguage.resolve(preferredLanguages: Locale.preferredLanguages) : language
        if let translated = translation(key, language: resolved) { return translated }
        // 简体中文以原始文案为回退；其它语言缺译时优先显示英语。
        if resolved == .simplifiedChinese { return key }
        return translation(key, language: .english) ?? key
    }

    static func translation(_ key: String, language: AppLanguage) -> String? {
        let missing = "__RemoteMapper_missing_localization__"
        let translated = bundle(for: language)?.localizedString(forKey: key, value: missing, table: "Localizable")
        if let translated, translated != missing { return translated }
        return nil
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    private static func bundle(for language: AppLanguage) -> Bundle? {
        bundles[language]
    }
}
