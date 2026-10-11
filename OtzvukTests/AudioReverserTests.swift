import AVFoundation
import XCTest
@testable import Otzvuk

final class AudioReverserTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("rev-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testReversesSamplesInTimeAndKeepsFormat() throws {
        // 150 003 кадра: несколько кусков и неполный последний.
        let frames = 150_003
        let src = dir.appendingPathComponent("ramp.caf")
        try TestSupport.writeAudio(to: src, frames: frames) { i, _ in Float(i) / Float(frames) * 0.9 }
        let dst = dir.appendingPathComponent("out.caf")
        try AudioReverser.reverse(source: src, destination: dst)

        let original = try TestSupport.readAll(src)
        let reversed = try TestSupport.readAll(dst)
        XCTAssertEqual(reversed.sampleRate, original.sampleRate)
        XCTAssertEqual(reversed.channels[0].count, frames)
        for i in stride(from: 0, to: frames, by: 997) {
            XCTAssertEqual(reversed.channels[0][i], original.channels[0][frames - 1 - i], accuracy: 1e-4, "кадр \(i)")
        }
        XCTAssertEqual(reversed.channels[0][0], original.channels[0][frames - 1], accuracy: 1e-4)
        XCTAssertEqual(reversed.channels[0][frames - 1], original.channels[0][0], accuracy: 1e-4)
    }

    func testStereoChannelsStayIndependent() throws {
        let frames = 70_000
        let src = dir.appendingPathComponent("st.caf")
        try TestSupport.writeAudio(to: src, frames: frames, channels: 2) { i, c in
            c == 0 ? Float(i) / Float(frames) * 0.8 : -Float(i) / Float(frames) * 0.8
        }
        let dst = dir.appendingPathComponent("st-out.caf")
        try AudioReverser.reverse(source: src, destination: dst)
        let o = try TestSupport.readAll(src), r = try TestSupport.readAll(dst)
        XCTAssertEqual(r.channels.count, 2)
        for c in 0..<2 {
            for i in stride(from: 0, to: frames, by: 811) {
                XCTAssertEqual(r.channels[c][i], o.channels[c][frames - 1 - i], accuracy: 1e-4)
            }
        }
    }

    /// Рабочий формат записей — AAC (m4a): проверяем точность перемотки с конца.
    func testReversesCompressedM4A() throws {
        let frames = 200_000
        let src = dir.appendingPathComponent("voice.m4a")
        try TestSupport.writeAudio(to: src, frames: frames, aac: true) { i, _ in
            0.4 * Float(sin(2 * Double.pi * 300 * Double(i) / 44_100)) * Float(0.3 + 0.7 * Double(i) / Double(frames))
        }
        let dst = dir.appendingPathComponent("voice-rev.caf")
        try AudioReverser.reverse(source: src, destination: dst)

        let o = try TestSupport.readAll(src), r = try TestSupport.readAll(dst)
        XCTAssertEqual(r.channels[0].count, o.channels[0].count)
        let n = o.channels[0].count
        var maxError: Float = 0
        for i in 0..<n { maxError = max(maxError, abs(r.channels[0][i] - o.channels[0][n - 1 - i])) }
        XCTAssertLessThan(maxError, 0.01, "максимальное расхождение после разворота AAC")
    }

    func testOriginalFileIsNotModified() throws {
        let src = dir.appendingPathComponent("orig.m4a")
        try TestSupport.writeTone(to: src, seconds: 1)
        let before = try Data(contentsOf: src)
        try AudioReverser.reverse(source: src, destination: dir.appendingPathComponent("o.caf"))
        XCTAssertEqual(try Data(contentsOf: src), before)
    }

    func testLeavesNoTemporaryFiles() throws {
        let src = dir.appendingPathComponent("a.caf")
        try TestSupport.writeTone(to: src, seconds: 0.5)
        try AudioReverser.reverse(source: src, destination: dir.appendingPathComponent("b.caf"))
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(names.contains { $0.contains("tmp") }, "\(names)")
    }

    func testBrokenFileThrows() throws {
        let src = dir.appendingPathComponent("broken.m4a")
        try Data("not audio".utf8).write(to: src)
        let dst = dir.appendingPathComponent("x.caf")
        XCTAssertThrowsError(try AudioReverser.reverse(source: src, destination: dst))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst.path))
    }

    func testCacheReusesFreshCopyAndDiscards() async throws {
        let src = dir.appendingPathComponent("c.caf"), dst = dir.appendingPathComponent("c-rev.caf")
        try TestSupport.writeTone(to: src, seconds: 0.5)
        let cache = ReversedAudioCache()
        try await cache.ensureReversed(source: src, destination: dst)
        let first = try FileManager.default.attributesOfItem(atPath: dst.path)[.modificationDate] as! Date
        try await cache.ensureReversed(source: src, destination: dst)
        let second = try FileManager.default.attributesOfItem(atPath: dst.path)[.modificationDate] as! Date
        XCTAssertEqual(first, second, "свежая копия не должна пересоздаваться")
        await cache.discard(destination: dst)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst.path))
    }
}
