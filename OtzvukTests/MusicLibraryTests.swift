import XCTest
@testable import Otzvuk

@MainActor
final class MusicLibraryTests: XCTestCase {
    private func sourceDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("music-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testImportCopiesFileIntoAppStorageAndSurvivesRelaunch() async throws {
        let store = TestSupport.tempStore()
        let source = try sourceDir().appendingPathComponent("Моя мелодия.m4a")
        try TestSupport.writeTone(to: source, seconds: 2)

        let library = MusicLibrary(store: store)
        let track = try await library.importFile(from: source)
        XCTAssertEqual(track.title, "Моя мелодия")
        XCTAssertTrue(track.isImported)

        // Оригинал можно удалить: приложение хранит свою копию.
        try FileManager.default.removeItem(at: source)
        XCTAssertNotNil(library.url(for: track.id))

        let relaunched = MusicLibrary(store: store)
        XCTAssertEqual(relaunched.imported.map(\.id), [track.id])
        XCTAssertNotNil(relaunched.url(for: track.id))
    }

    func testUnsupportedFileIsRejectedAndLeavesNothingBehind() async throws {
        let store = TestSupport.tempStore()
        let source = try sourceDir().appendingPathComponent("notes.mp3")
        try Data("это не аудио".utf8).write(to: source)

        let library = MusicLibrary(store: store)
        do {
            _ = try await library.importFile(from: source)
            XCTFail("Должна быть ошибка")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("notes"))
        }
        XCTAssertTrue(library.imported.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.music.path), [])
    }

    func testDeleteRemovesFileAndBuiltInsAreResolvable() async throws {
        let store = TestSupport.tempStore()
        let source = try sourceDir().appendingPathComponent("a.m4a")
        try TestSupport.writeTone(to: source, seconds: 2)
        let library = MusicLibrary(store: store)
        let track = try await library.importFile(from: source)
        library.delete(id: track.id)
        XCTAssertNil(library.url(for: track.id))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.music.path), [])

        for builtIn in MusicTrack.builtIn {
            XCTAssertNotNil(library.url(for: builtIn.id), "встроенная мелодия \(builtIn.id) не найдена в бандле")
        }
    }
}
