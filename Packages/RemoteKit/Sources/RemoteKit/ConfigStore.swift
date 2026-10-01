import Foundation
import Observation

/// 负责配置的读写。界面的修改会延迟合并写盘；外部编辑配置文件后会自动重新载入。
@Observable
public final class ConfigStore {
    public var config: RemoteConfig {
        didSet {
            guard config != oldValue, !isApplyingExternalChange else { return }
            scheduleSave()
            onChange?(config)
        }
    }

    public private(set) var lastError: String?
    public let fileURL: URL

    @ObservationIgnored public var onChange: ((RemoteConfig) -> Void)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var watchTimer: Timer?
    @ObservationIgnored private var lastKnownModification: Date?
    @ObservationIgnored private var isApplyingExternalChange = false
    @ObservationIgnored private let persists: Bool

    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "RemoteMapper", directoryHint: .isDirectory)
            .appending(path: "config.json")
    }

    /// - Parameter persists: 为 false 时只在内存中工作（用于预览与截图）
    public init(fileURL: URL = ConfigStore.defaultFileURL, persists: Bool = true, initial: RemoteConfig? = nil) {
        self.fileURL = fileURL
        self.persists = persists
        if let initial {
            config = initial
        } else if persists, let loaded = try? Self.read(fileURL) {
            config = loaded
        } else {
            config = .default
        }
        if persists {
            if !FileManager.default.fileExists(atPath: fileURL.path) { saveNow() }
            lastKnownModification = modificationDate()
            startWatching()
        }
    }

    public func saveNow() {
        guard persists else { return }
        saveTask?.cancel()
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(config).write(to: fileURL, options: .atomic)
            lastKnownModification = modificationDate()
            lastError = nil
        } catch {
            lastError = "保存配置失败：\(error.localizedDescription)"
        }
    }

    public func reload() {
        do {
            let loaded = try Self.read(fileURL)
            lastKnownModification = modificationDate()
            lastError = nil
            guard loaded != config else { return }
            isApplyingExternalChange = true
            config = loaded
            isApplyingExternalChange = false
            onChange?(config)
        } catch {
            lastError = "配置文件无法解析：\(error.localizedDescription)"
        }
    }

    public func resetToDefault() {
        config = .default
        saveNow()
    }

    private static func read(_ url: URL) throws -> RemoteConfig {
        try JSONDecoder().decode(RemoteConfig.self, from: Data(contentsOf: url))
    }

    private func scheduleSave() {
        guard persists else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func modificationDate() -> Date? {
        try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
    }

    private func startWatching() {
        watchTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let date = self.modificationDate(), date != self.lastKnownModification else { return }
                self.reload()
            }
        }
    }
}
