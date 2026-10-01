import AVFoundation
import Foundation
import RemoteKit
import Speech

/// 有界的实机诊断：从同一 CoreAudio 输入录制，不执行任何遥控器映射或文字输入。
enum MicrophoneCheck {
    static func transcribe(_ url: URL) async -> Int32 {
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh-CN")) else { return 1 }
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
        let status = await AssetInventory.status(forModules: [transcriber])
        guard status == .installed else { print("TRANSCRIPTION_MODEL=\(status)"); return 2 }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let results = Task {
            var final = "", partial = ""
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                if result.isFinal { final += text; partial = "" } else { partial = text }
            }
            return final + partial
        }
        do {
            let file = try AVAudioFile(forReading: url)
            _ = try await analyzer.analyzeSequence(from: file)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let text = try await results.value
            print("TRANSCRIPTION_RESULT=\(text)")
            return text.isEmpty ? 3 : 0
        } catch {
            results.cancel()
            await analyzer.cancelAndFinishNow()
            print("TRANSCRIPTION_ERROR=\(error.localizedDescription)")
            return 4
        }
    }

    static func run(seconds: Int, output: URL) async -> Int32 {
        guard AudioInputDevices.deviceID(uid: AudioInputDevices.remoteMicrophoneUID) != nil else {
            print("CHECK_ERROR=遥控器音频输入未安装"); return 1
        }
        var permitted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if !permitted { permitted = await AVCaptureDevice.requestAccess(for: .audio) }
        guard permitted else { print("CHECK_ERROR=麦克风权限未允许"); return 2 }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let stats = Samples()
        do {
            try AudioInputDevices.useAsDefault(uid: AudioInputDevices.remoteMicrophoneUID)
            try input.auAudioUnit.setDeviceID(AudioInputDevices.deviceID(uid: AudioInputDevices.remoteMicrophoneUID)!)
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate == 48000, format.channelCount == 1 else {
                print("CHECK_ERROR=输入格式异常"); return 3
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: makeTap(stats))
            engine.prepare()
            try engine.start()
            print("CHECK_READY=\(seconds)秒；按住 Siri 说话约8秒，再松开等待")
            fflush(stdout)
            for second in 1...seconds {
                try await Task.sleep(for: .seconds(1))
                let current = stats.interval()
                print(String(format: "CHECK_LEVEL t=%d samples=%d rms=%.6f peak=%.6f", second, current.count, current.rms, current.peak))
                fflush(stdout)
            }
            input.removeTap(onBus: 0)
            engine.stop()
            let samples = stats.all()
            let file = try AVAudioFile(forWriting: output, settings: format.settings)
            if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
               let channel = buffer.floatChannelData?[0] {
                buffer.frameLength = AVAudioFrameCount(samples.count)
                samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
                try file.write(from: buffer)
            }
            let nonSilent = samples.filter { abs($0) > 0.001 }.count
            print("CHECK_RESULT samples=\(samples.count) nonSilent=\(nonSilent) path=\(output.path)")
            return nonSilent > 4800 ? 0 : 4
        } catch {
            engine.stop()
            print("CHECK_ERROR=\(error.localizedDescription)")
            return 5
        }
    }

    private nonisolated static func makeTap(_ stats: Samples) -> AVAudioNodeTapBlock {
        { buffer, _ in stats.append(buffer) }
    }

    private nonisolated final class Samples: @unchecked Sendable {
        private let lock = NSLock()
        private var samples: [Float] = []
        private var offset = 0
        func append(_ buffer: AVAudioPCMBuffer) {
            guard let channel = buffer.floatChannelData?[0] else { return }
            lock.lock(); defer { lock.unlock() }
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }
        func all() -> [Float] {
            lock.lock(); defer { lock.unlock() }; return samples
        }
        func interval() -> (count: Int, rms: Double, peak: Float) {
            lock.lock(); defer { lock.unlock() }
            let values = samples[offset...]
            offset = samples.count
            let rms = sqrt(values.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, values.count)))
            return (values.count, rms, values.map { abs($0) }.max() ?? 0)
        }
    }
}
