import AVFoundation
import Accelerate

enum AudioReverserError: LocalizedError {
    case emptyFile
    case shortRead

    var errorDescription: String? {
        switch self {
        case .emptyFile: return "Запись пуста."
        case .shortRead: return "Не удалось прочитать запись целиком."
        }
    }
}

/// Разворачивает аудио во времени: сэмплы идут от конца к началу.
/// Частота дискретизации и число каналов сохраняются, поэтому скорость и высота голоса не меняются.
/// Файл читается и пишется кусками с конца к началу — память не зависит от длины записи.
enum AudioReverser {
    static let chunkFrames: AVAudioFrameCount = 65_536

    /// Блокирующая операция: вызывать вне главного потока. Поддерживает отмену через `Task`.
    static func reverse(source: URL, destination: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let total = input.length
        guard total > 0 else { throw AudioReverserError.emptyFile }

        let fm = FileManager.default
        let temp = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp.caf")
        defer { try? fm.removeItem(at: temp) }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let output = try AVAudioFile(forWriting: temp, settings: settings,
                                         commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
                throw AudioReverserError.shortRead
            }

            var position = total
            while position > 0 {
                try Task.checkCancellation()
                let count = AVAudioFrameCount(min(Int64(chunkFrames), position))
                position -= Int64(count)
                input.framePosition = position
                buffer.frameLength = 0
                try input.read(into: buffer, frameCount: count)
                guard buffer.frameLength == count, let channels = buffer.floatChannelData else {
                    throw AudioReverserError.shortRead
                }
                for channel in 0..<Int(format.channelCount) {
                    vDSP_vrvrs(channels[channel], 1, vDSP_Length(count))
                }
                try output.write(from: buffer)
            }
        }

        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: temp, to: destination)
    }

    static func duration(of url: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
