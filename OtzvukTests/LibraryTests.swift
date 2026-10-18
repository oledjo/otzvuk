import XCTest
@testable import Otzvuk

@MainActor
final class LibraryTests: XCTestCase {
    private func addItem(_ library: Library, title: String, seconds: Double = 0.5) throws -> Affirmation {
        let id = UUID()
        let name = "\(id.uuidString).m4a"
        try TestSupport.writeTone(to: library.store.recordingURL(name), seconds: seconds)
        return library.add(id: id, title: title, fileName: name, duration: seconds)
    }

    func testRecordingsSurviveRelaunch() throws {
        let store = TestSupport.tempStore()
        let first = Library(store: store)
        let item = try addItem(first, title: "Я спокоен")

        let second = Library(store: store) // «перезапуск»
        XCTAssertEqual(second.affirmations.count, 1)
        XCTAssertEqual(second.affirmations[0].title, "Я спокоен")
        XCTAssertTrue(second.affirmations[0].isSelected)
    }

    func testRenameTrimsAndRejectsEmpty() throws {
        let library = Library(store: TestSupport.tempStore())
        let item = try addItem(library, title: "Старое")
        library.rename(id: item.id, to: "  Новое  ")
        XCTAssertEqual(library.affirmation(id: item.id)?.title, "Новое")
        library.rename(id: item.id, to: "   ")
        XCTAssertEqual(library.affirmation(id: item.id)?.title, "Новое")
    }

    func testDeleteRemovesOriginalAndReversedCopy() async throws {
        let library = Library(store: TestSupport.tempStore())
        let item = try addItem(library, title: "A")
        let reversed = library.store.reversedURL(item.reversedFileName)
        try await ReversedAudioCache().ensureReversed(source: library.store.recordingURL(item.fileName), destination: reversed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reversed.path))

        library.delete(id: item.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.store.recordingURL(item.fileName).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: reversed.path))
        XCTAssertTrue(Library(store: library.store).affirmations.isEmpty)
    }

    func testOrphanFilesAreRemovedOnCleanup() throws {
        let library = Library(store: TestSupport.tempStore())
        let kept = try addItem(library, title: "Keep")
        let strayRecording = library.store.recordingURL("stray.m4a")
        let strayReversed = library.store.reversedURL("stray.caf")
        try Data([1]).write(to: strayRecording)
        try Data([1]).write(to: strayReversed)
        library.cleanOrphans(keepingMusic: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: strayRecording.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: strayReversed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.store.recordingURL(kept.fileName).path))
    }

    func testMissingFileIsDroppedOnLoad() throws {
        let store = TestSupport.tempStore()
        let library = Library(store: store)
        let item = try addItem(library, title: "Lost")
        try FileManager.default.removeItem(at: store.recordingURL(item.fileName))
        XCTAssertTrue(Library(store: store).affirmations.isEmpty)
    }
}
