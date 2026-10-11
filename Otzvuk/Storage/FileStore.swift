import Foundation

/// Расположение файлов приложения.
/// - Recordings, Music, library.json — Application Support (сохраняются и попадают в резервную копию).
/// - Reversed — Caches: обработанные копии можно безопасно пересоздать.
struct FileStore {
    let recordings: URL
    let music: URL
    let reversed: URL
    let libraryFile: URL
    let musicFile: URL
    let wishlistFile: URL

    init(appSupport: URL, caches: URL) {
        let fm = FileManager.default
        let root = appSupport.appendingPathComponent("Otzvuk", isDirectory: true)
        recordings = root.appendingPathComponent("Recordings", isDirectory: true)
        music = root.appendingPathComponent("Music", isDirectory: true)
        reversed = caches.appendingPathComponent("Otzvuk/Reversed", isDirectory: true)
        libraryFile = root.appendingPathComponent("library.json")
        musicFile = root.appendingPathComponent("music.json")
        wishlistFile = root.appendingPathComponent("wishlist.json")
        for dir in [recordings, music, reversed] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func standard() -> FileStore {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let caches = (try? fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return FileStore(appSupport: support, caches: caches)
    }

    func recordingURL(_ fileName: String) -> URL { recordings.appendingPathComponent(fileName) }
    func musicURL(_ fileName: String) -> URL { music.appendingPathComponent(fileName) }
    func reversedURL(_ fileName: String) -> URL { reversed.appendingPathComponent(fileName) }

    /// Удаляет файлы, на которые никто не ссылается (например, после сбоя во время записи или удаления).
    func removeOrphans(recordings keepRecordings: Set<String>, music keepMusic: Set<String>, reversed keepReversed: Set<String>) {
        Self.prune(directory: recordings, keeping: keepRecordings)
        Self.prune(directory: music, keeping: keepMusic)
        Self.prune(directory: reversed, keeping: keepReversed)
    }

    private static func prune(directory: URL, keeping: Set<String>) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where !keeping.contains(name) {
            try? fm.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
