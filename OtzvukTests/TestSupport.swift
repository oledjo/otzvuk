import AVFoundation
import XCTest
@testable import Otzvuk

enum TestSupport {
    static func tempStore() -> FileStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("otzvuk-tests-\(UUID().uuidString)")
        return FileStore(appSupport: root.appendingPathComponent("support"), caches: root.appendingPathComponent("caches"))
    }

    /// Пишет файл с сигналом, `generator(frame, channel)` возвращает значение сэмпла.
    @discardableResult
    static func writeAudio(to url: URL, frames: Int, channels: Int = 1, sampleRate: Double = 44_100,
                           aac: Bool = false, generator: (Int, Int) -> Float) throws -> URL {
        let settings: [String: Any]
        if aac {
            settings = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
                        AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: 128_000 * channels]
        } else {
            settings = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
                        AVNumberOfChannelsKey: channels, AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        }
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let chunk = 8_192
        var written = 0
        while written < frames {
            let n = min(chunk, frames - written)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
            buffer.frameLength = AVAudioFrameCount(n)
            for c in 0..<channels {
                let ptr = buffer.floatChannelData![c]
                for i in 0..<n { ptr[i] = generator(written + i, c) }
            }
            try file.write(from: buffer)
            written += n
        }
        return url
    }

    static func writeTone(to url: URL, seconds: Double, frequency: Double = 440) throws {
        let frames = Int(seconds * 44_100)
        try writeAudio(to: url, frames: frames) { i, _ in
            0.3 * Float(sin(2 * Double.pi * frequency * Double(i) / 44_100))
        }
    }

    /// Читает весь файл как массивы по каналам.
    static func readAll(_ url: URL) throws -> (sampleRate: Double, channels: [[Float]]) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let n = Int(buffer.frameLength)
        let channels = (0..<Int(format.channelCount)).map { c in
            Array(UnsafeBufferPointer(start: buffer.floatChannelData![c], count: n))
        }
        return (format.sampleRate, channels)
    }

    @MainActor
    static func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }
}
