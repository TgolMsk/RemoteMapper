import AVFoundation
import CoreAudio
import Observation
import Speech
import os

/// 语音输入：采集所选 CoreAudio 输入（包括遥控器虚拟麦克风），在本机识别。
///
/// 一次会话：start() 开始录音并实时识别 → stop() 结束并返回最终文字。
/// 录音期间 transcript 会随识别进度更新，供浮窗实时显示。
@Observable
public final class VoiceDictation {
    public enum Phase: Equatable, Sendable {
        case idle
        case starting
        case listening
        case finishing
        case failed(String)
    }

    public enum ModelState: Equatable, Sendable {
        case unknown
        case unsupported
        case notInstalled
        case downloading(Double)
        case installed
    }

    public private(set) var phase: Phase = .idle
    /// 本次录音是否在松开遥控器按键时结束（按住、长按）；否则要再按一次（单击、双击）
    public var endsOnRelease = true
    /// 输入音量 0...1
    public private(set) var level: Float = 0
    /// 已确定的文字加上正在识别中的文字
    public private(set) var transcript = ""
    public private(set) var modelState: ModelState = .unknown {
        didSet {
            switch (modelState, oldValue) {
            case (.downloading, .downloading): break
            default: if modelState != oldValue { Self.log.info("语音模型：\(String(describing: self.modelState), privacy: .public)") }
            }
        }
    }

    @ObservationIgnored public var settings = VoiceSettings() {
        didSet { if settings.localeIdentifier != oldValue.localeIdentifier { Task { await refreshModelState() } } }
    }

    @ObservationIgnored private var session: Session?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var resetTask: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.ws.RemoteMapper", category: "voice")

    private final class Session {
        let analyzer: SpeechAnalyzer
        let continuation: AsyncStream<AnalyzerInput>.Continuation
        var capture: AudioCapture?
        var resultsTask: Task<Void, Never>?
        var finalized = ""
        var volatile = ""

        init(analyzer: SpeechAnalyzer, continuation: AsyncStream<AnalyzerInput>.Continuation) {
            self.analyzer = analyzer
            self.continuation = continuation
        }
    }

    public init() {}

    public var isActive: Bool {
        switch phase {
        case .starting, .listening, .finishing: true
        default: false
        }
    }

    /// 开始录音与识别（立即返回，准备过程在后台进行）
    public func start() {
        guard !isActive else { return }
        resetTask?.cancel()
        phase = .starting
        transcript = ""
        level = 0
        startTask = Task { await begin() }
    }

    /// 结束录音，等待识别完成并返回文字；没有识别出内容或出错时返回 nil
    public func stop() async -> String? {
        // 准备期间松开即取消，权限或模型准备结束后不能再偷偷开始录音。
        if phase == .starting { cancel(); return nil }
        await startTask?.value
        startTask = nil
        guard let session, phase == .listening else { return nil }
        phase = .finishing
        session.capture?.stop()
        session.continuation.finish()
        // 超时主动结束分析器与结果任务；不能用不可取消的 Task.value 阻塞任务组。
        let deadline = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await session.analyzer.cancelAndFinishNow()
            session.resultsTask?.cancel()
        }
        defer { deadline.cancel() }
        do {
            try await session.analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            Self.log.error("结束识别失败：\(error.localizedDescription, privacy: .public)")
        }
        await session.resultsTask?.value
        session.resultsTask?.cancel()
        guard self.session === session else { return nil }
        let text = (session.finalized + session.volatile).trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = nil
        level = 0
        phase = .idle
        Self.log.info("识别完成，\(text.count) 个字符")
        return text.isEmpty ? nil : text
    }

    /// 放弃当前会话，不输出文字
    public func cancel() {
        startTask?.cancel()
        startTask = nil
        if let session {
            session.capture?.stop()
            session.continuation.finish()
            session.resultsTask?.cancel()
            Task { await session.analyzer.cancelAndFinishNow() }
        }
        session = nil
        level = 0
        if isActive { phase = .idle }
    }

    // MARK: 模型

    public func refreshModelState() async {
        guard let locale = await resolvedLocale() else {
            modelState = .unsupported
            return
        }
        if await Self.isInstalled(locale) {
            modelState = .installed
            return
        }
        switch await AssetInventory.status(forModules: [Self.makeTranscriber(locale)]) {
        case .installed: modelState = .installed
        case .downloading: if case .downloading = modelState {} else { modelState = .downloading(0) }
        case .supported: modelState = .notInstalled
        case .unsupported: modelState = .unsupported
        @unknown default: modelState = .unknown
        }
    }

    /// 下载并安装当前语言的识别模型
    public func installModel() async {
        if case .downloading = modelState { return }
        guard let locale = await resolvedLocale() else {
            modelState = .unsupported
            return
        }
        if await Self.isInstalled(locale) {
            modelState = .installed
            return
        }
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [Self.makeTranscriber(locale)]) {
                modelState = .downloading(0)
                let progress = request.progress
                let monitor = Task { [weak self] in
                    while !Task.isCancelled {
                        self?.modelState = .downloading(progress.fractionCompleted)
                        try? await Task.sleep(for: .milliseconds(300))
                    }
                }
                defer { monitor.cancel() }
                try await request.downloadAndInstall()
            }
            modelState = .installed
        } catch {
            Self.log.error("下载语音模型失败：\(error.localizedDescription, privacy: .public)")
            modelState = .notInstalled
        }
    }

    /// 仅用于界面预览与截图
    public func simulate(phase: Phase, transcript: String = "", level: Float = 0, model: ModelState = .installed) {
        self.phase = phase
        self.transcript = transcript
        self.level = level
        modelState = model
    }

    // MARK: 会话

    private func begin() async {
        let access = await ensureMicrophoneAccess()
        guard !Task.isCancelled else { return }
        guard access else {
            return fail(L10n.text("没有麦克风权限：请在「系统设置 › 隐私与安全性 › 麦克风」中允许"))
        }
        let locale = await resolvedLocale()
        guard !Task.isCancelled else { return }
        guard let locale else {
            return fail(L10n.text("不支持当前识别语言"))
        }
        let transcriber = Self.makeTranscriber(locale)
        if await !Self.isInstalled(locale) {
            let status = await AssetInventory.status(forModules: [transcriber])
            guard !Task.isCancelled else { return }
            if status == .unsupported { return fail(L10n.text("此 Mac 不支持该语言的语音识别")) }
            if status != .installed {
                Task { await installModel() }
                return fail(L10n.text("正在下载语音识别模型，下载完成后即可使用"))
            }
        }
        guard !Task.isCancelled else { return }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            ?? AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        guard !Task.isCancelled else { return }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let session = Session(analyzer: analyzer, continuation: continuation)
        self.session = session

        session.resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    self?.apply(String(result.text.characters), isFinal: result.isFinal, to: session)
                }
            } catch {
                Self.log.error("识别出错：\(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            try await analyzer.start(inputSequence: stream)
            guard !Task.isCancelled, self.session === session else {
                continuation.finish()
                await analyzer.cancelAndFinishNow()
                return
            }
            let capture = AudioCapture()
            try capture.start(deviceUID: settings.captureDeviceUID, targetFormat: format,
                              onBuffer: { continuation.yield(AnalyzerInput(buffer: $0)) },
                              onLevel: { [weak self] value in
                                  Task { @MainActor in
                                      guard self?.session === session, self?.phase == .listening else { return }
                                      self?.level = value
                                  }
                              })
            session.capture = capture
            phase = .listening
            Self.log.info("开始录音，语言 \(locale.identifier, privacy: .public)")
        } catch {
            guard self.session === session else { return }
            fail((error as? DictationError)?.message ?? L10n.format("无法开始录音：%@", error.localizedDescription))
        }
    }

    private func apply(_ text: String, isFinal: Bool, to session: Session) {
        guard self.session === session else { return }
        if isFinal {
            session.finalized += text
            session.volatile = ""
        } else {
            session.volatile = text
        }
        transcript = session.finalized + session.volatile
    }

    private func fail(_ message: String) {
        Self.log.error("语音输入失败：\(message, privacy: .public)")
        if let session {
            session.capture?.stop()
            session.continuation.finish()
            session.resultsTask?.cancel()
            Task { await session.analyzer.cancelAndFinishNow() }
        }
        session = nil
        level = 0
        phase = .failed(message)
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, case .failed = self.phase else { return }
            self.phase = .idle
        }
    }

    private func ensureMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    private func resolvedLocale() async -> Locale? {
        let requested = settings.localeIdentifier.map(Locale.init(identifier:)) ?? Locale.current
        return await DictationTranscriber.supportedLocale(equivalentTo: requested)
    }

    /// 模型是否已安装。不能只看 AssetInventory.status：系统语音服务（localspeechrecognition）空闲退出后，
    /// 进程内缓存的连接失效（XPC 4099），status 会一直返回 .supported 直到 App 重启，而识别与 installedLocales 都不受影响。
    private static func isInstalled(_ locale: Locale) async -> Bool {
        let identifier = locale.identifier(.bcp47)
        return await DictationTranscriber.installedLocales.contains { $0.identifier(.bcp47) == identifier }
    }

    private static func makeTranscriber(_ locale: Locale) -> DictationTranscriber {
        DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
    }
}

enum DictationError: Error {
    case noInputDevice
    case unsupportedFormat
    case inputDeviceUnavailable
    case remoteMicrophoneUnavailable

    var message: String {
        switch self {
        case .noInputDevice: L10n.text("没有可用的麦克风：请连接 AirPods、耳机或 USB 麦克风")
        case .unsupportedFormat: L10n.text("麦克风的音频格式无法转换")
        case .inputDeviceUnavailable: L10n.text("所选麦克风已断开，请在通用设置中重新选择")
        case .remoteMicrophoneUnavailable: L10n.text("遥控器麦克风尚未安装：请在「通用 › 语音输入」中安装音频组件")
        }
    }
}

// MARK: - 录音

/// 用 AVAudioEngine 采集麦克风，转换为识别器需要的格式。音频回调在实时线程上执行。
nonisolated final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var hasTap = false

    func start(deviceUID: String?, targetFormat: AVAudioFormat,
               onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
               onLevel: @escaping @Sendable (Float) -> Void) throws {
        // 在创建 inputNode 前确认输入，避免无麦克风的 Mac 抛出音频引擎异常。
        let selected = try AudioInputDevices.resolve(uid: deviceUID)
        let input = engine.inputNode
        if let deviceID = selected?.id {
            try input.auAudioUnit.setDeviceID(deviceID)
        }
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw DictationError.noInputDevice }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else { throw DictationError.unsupportedFormat }
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat,
                         block: Self.makeTap(converter: converter, target: targetFormat, onBuffer: onBuffer, onLevel: onLevel))
        hasTap = true
        engine.prepare()
        do { try engine.start() }
        catch { stop(); throw error }
    }

    func stop() {
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        engine.stop()
    }

    private final class Flag: @unchecked Sendable { var consumed = false }

    private static func makeTap(converter: AVAudioConverter, target: AVAudioFormat,
                                onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
                                onLevel: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        let converter = converter
        return { buffer, _ in
            onLevel(Self.level(of: buffer))
            let ratio = target.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            let flag = Flag()
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if flag.consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                flag.consumed = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil, output.frameLength > 0 { onBuffer(output) }
        }
    }

    /// 均方根音量映射到 0...1（-50 dB 以下视为静音）
    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        let rms = sqrt(sum / Float(buffer.frameLength))
        let decibels = 20 * log10(max(rms, 1e-6))
        return max(0, min(1, (decibels + 50) / 50))
    }
}

// MARK: - 麦克风设备

public struct AudioInputDevice: Identifiable, Hashable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
}

/// 通过 CoreAudio 枚举带输入通道的音频设备
public nonisolated enum AudioInputDevices {
    public static let remoteMicrophoneUID = "RemoteMapperMic_UID"

    static func resolve(uid: String?, devices: [AudioInputDevice]? = nil, defaultInput: AudioInputDevice? = nil) throws -> AudioInputDevice? {
        if let uid {
            guard let selected = (devices ?? all()).first(where: { $0.uid == uid }) else {
                throw uid == remoteMicrophoneUID ? DictationError.remoteMicrophoneUnavailable : DictationError.inputDeviceUnavailable
            }
            return selected
        }
        guard let selected = defaultInput ?? defaultDevice else { throw DictationError.noInputDevice }
        return selected
    }
    public static func all() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasInput(id), let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }
    }

    public static func deviceID(uid: String) -> AudioDeviceID? {
        all().first { $0.uid == uid }?.id
    }

    /// 用户明确选择后切换系统默认输入，不改变输出设备。
    public static func useAsDefault(uid: String) throws {
        guard let selected = try resolve(uid: uid) else { throw DictationError.noInputDevice }
        var id = selected.id
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let result = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                                UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        guard result == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
    }

    /// 当前系统默认输入设备
    public static var defaultDevice: AudioInputDevice? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return all().first { $0.id == id }
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
