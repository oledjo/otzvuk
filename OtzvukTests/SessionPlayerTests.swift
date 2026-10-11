import AVFoundation
import XCTest
@testable import Otzvuk

@MainActor
final class SessionPlayerTests: XCTestCase {
    private var store: FileStore!
    private var library: Library!
    private var music: MusicLibrary!
    private var settings: SettingsStore!
    private var session: SessionPlayer!
    private var cache: ReversedAudioCache!
    private var errors: [String] = []

    override func setUp() async throws {
        store = TestSupport.tempStore()
        library = Library(store: store)
        music = MusicLibrary(store: store)
        let defaults = UserDefaults(suiteName: "otzvuk-tests-\(UUID().uuidString)")!
        settings = SettingsStore(defaults: defaults)
        settings.value.gapSeconds = 0
        settings.value.timerSeconds = 0
        settings.value.musicTrackID = nil
        cache = ReversedAudioCache()
        session = SessionPlayer(library: library, music: music, settings: settings, cache: cache)
        errors = []
        session.reportError = { [unowned self] in self.errors.append($0) }
    }

    override func tearDown() async throws { session.stop() }

    private func addItem(_ title: String, seconds: Double = 0.6, reversed: Bool = false) throws -> Affirmation {
        let id = UUID()
        let name = "\(id.uuidString).m4a"
        try TestSupport.writeTone(to: store.recordingURL(name), seconds: seconds, frequency: 300 + Double(library.affirmations.count) * 100)
        let item = library.add(id: id, title: title, fileName: name, duration: seconds)
        if reversed { library.setReversed(true, id: id) }
        return item
    }

    func testVoiceAndMusicPlayTogetherAndMusicContinuesInGaps() async throws {
        _ = try addItem("A", seconds: 0.6)
        settings.value.musicTrackID = "builtin.dawn"
        settings.value.gapSeconds = 3
        session.start()
        let playing = await TestSupport.waitUntil { self.session.isVoicePlaying }
        XCTAssertTrue(playing, "голос должен играть")
        XCTAssertTrue(session.isMusicPlaying, "музыка должна играть одновременно с голосом")

        let gap = await TestSupport.waitUntil { self.session.isInGap }
        XCTAssertTrue(gap, "после записи должна начаться пауза")
        XCTAssertFalse(session.isVoicePlaying)
        XCTAssertTrue(session.isMusicPlaying, "музыка не должна прерываться в паузе")
    }

    func testQueueLoopsInOrderAndRepeats() async throws {
        let a = try addItem("A", seconds: 0.4), b = try addItem("B", seconds: 0.4)
        session.start()
        var seen: [UUID] = []
        _ = await TestSupport.waitUntil(6) {
            if let id = self.session.currentID, seen.last != id { seen.append(id) }
            return seen.count >= 5
        }
        XCTAssertEqual(Array(seen.prefix(5)), [a.id, b.id, a.id, b.id, a.id])
    }

    func testGapIsHonoured() async throws {
        _ = try addItem("A", seconds: 0.4)
        settings.value.gapSeconds = 3
        session.start()
        _ = await TestSupport.waitUntil { self.session.isInGap }
        let started = Date()
        _ = await TestSupport.waitUntil(5) { self.session.isVoicePlaying && !self.session.isInGap }
        let gap = Date().timeIntervalSince(started)
        XCTAssertGreaterThan(gap, 2.7)
        XCTAssertLessThan(gap, 3.6)
    }

    func testPauseAndResumeControlBothPlayers() async throws {
        _ = try addItem("A", seconds: 3)
        settings.value.musicTrackID = "builtin.calm"
        session.start()
        _ = await TestSupport.waitUntil { self.session.isVoicePlaying }
        session.pause()
        XCTAssertEqual(session.state, .paused)
        XCTAssertFalse(session.isVoicePlaying)
        XCTAssertFalse(session.isMusicPlaying)
        session.resume()
        XCTAssertEqual(session.state, .playing)
        XCTAssertTrue(session.isVoicePlaying)
        XCTAssertTrue(session.isMusicPlaying)
    }

    func testPauseInsideGapKeepsRemainingTime() async throws {
        let a = try addItem("A", seconds: 0.3), b = try addItem("B", seconds: 3)
        settings.value.gapSeconds = 3
        session.start()
        _ = await TestSupport.waitUntil { self.session.isInGap }
        session.pause()
        try await Task.sleep(for: .seconds(1.5))
        XCTAssertEqual(session.currentID, a.id, "на паузе очередь не должна двигаться")
        session.resume()
        let moved = await TestSupport.waitUntil(5) { self.session.currentID == b.id && self.session.isVoicePlaying }
        XCTAssertTrue(moved)
    }

    func testNextSkipsToFollowingItem() async throws {
        let a = try addItem("A", seconds: 5), b = try addItem("B", seconds: 5)
        session.start()
        _ = await TestSupport.waitUntil { self.session.isVoicePlaying }
        XCTAssertEqual(session.currentID, a.id)
        session.next()
        let moved = await TestSupport.waitUntil { self.session.currentID == b.id && self.session.isVoicePlaying }
        XCTAssertTrue(moved)
    }

    func testReversedItemPlaysFromCachedCopyAndOriginalIsIntact() async throws {
        let item = try addItem("R", seconds: 2, reversed: true)
        let original = try Data(contentsOf: store.recordingURL(item.fileName))
        session.start()
        let playing = await TestSupport.waitUntil { self.session.isVoicePlaying }
        XCTAssertTrue(playing, "ошибки: \(errors)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.reversedURL(item.reversedFileName).path))
        XCTAssertEqual(try Data(contentsOf: store.recordingURL(item.fileName)), original)
    }

    func testTimerFadesOutAndStopsEverything() async throws {
        _ = try addItem("A", seconds: 8)
        settings.value.musicTrackID = "builtin.water"
        settings.value.timerSeconds = 2
        session.start()
        XCTAssertEqual(session.timerRemaining, 2)
        let fading = await TestSupport.waitUntil(4) { self.session.isFadingOut }
        XCTAssertTrue(fading)
        XCTAssertTrue(session.isMusicPlaying, "во время затухания музыка ещё звучит")
        let stopped = await TestSupport.waitUntil(8) { self.session.state == .idle }
        XCTAssertTrue(stopped)
        XCTAssertFalse(session.isMusicPlaying)
        XCTAssertFalse(session.isVoicePlaying)
    }

    func testDeletingCurrentItemKeepsSessionAlive() async throws {
        let a = try addItem("A", seconds: 5), b = try addItem("B", seconds: 5)
        session.start()
        _ = await TestSupport.waitUntil { self.session.isVoicePlaying }
        XCTAssertEqual(session.currentID, a.id)

        session.remove(id: a.id)
        library.delete(id: a.id)
        let moved = await TestSupport.waitUntil { self.session.currentID == b.id && self.session.isVoicePlaying }
        XCTAssertTrue(moved)
        XCTAssertEqual(session.queueIDs, [b.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.recordingURL(a.fileName).path))
    }

    func testDeletingLastItemStopsSession() async throws {
        let a = try addItem("A", seconds: 5)
        session.start()
        _ = await TestSupport.waitUntil { self.session.isVoicePlaying }
        session.remove(id: a.id)
        library.delete(id: a.id)
        XCTAssertEqual(session.state, .idle)
    }

    func testBrokenRecordingIsSkippedWithMessage() async throws {
        let bad = try addItem("Bad", seconds: 1)
        try Data("garbage".utf8).write(to: store.recordingURL(bad.fileName))
        let good = try addItem("Good", seconds: 3)
        session.start()
        let ok = await TestSupport.waitUntil { self.session.currentID == good.id && self.session.isVoicePlaying }
        XCTAssertTrue(ok)
        XCTAssertFalse(errors.isEmpty)
    }

    func testStartWithoutSelectionReportsError() async throws {
        let a = try addItem("A")
        library.setSelected(false, id: a.id)
        session.start()
        XCTAssertEqual(session.state, .idle)
        XCTAssertFalse(errors.isEmpty)
    }

    func testVolumeChangesApplyLive() async throws {
        _ = try addItem("A", seconds: 3)
        settings.value.musicTrackID = "builtin.dawn"
        session.start()
        _ = await TestSupport.waitUntil { self.session.isVoicePlaying }
        settings.value.musicVolume = 0.1
        settings.value.voiceVolume = 0.5
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(session.isMusicPlaying)
    }
}
