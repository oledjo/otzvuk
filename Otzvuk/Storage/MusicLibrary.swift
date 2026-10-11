import AVFoundation
import Foundation

enum MusicImportError: LocalizedError {
    case unsupported(String)
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let name): return "Файл «\(name)» не удалось открыть: формат не поддерживается."
        case .copyFailed(let name): return "Не удалось скопировать «\(name)»."
        }
    }
}

/// Встроенные и импортированные мелодии.
@MainActor
final class MusicLibrary: ObservableObject {
    @Published private(set) var imported: [MusicTrack] = []

    let store: FileStore
    private let bundle: Bundle

    init(store: FileStore, bundle: Bundle = .main) {
        self.store = store
        self.bundle = bundle
        load()
    }

    var allTracks: [MusicTrack] { MusicTrack.builtIn + imported }

    func track(id: String?) -> MusicTrack? {
        guard let id else { return nil }
        return allTracks.first { $0.id == id }
    }

    /// Адрес файла мелодии, если он существует.
    func url(for id: String?) -> URL? {
        guard let track = track(id: id) else { return nil }
        let url: URL?
        if let resource = track.bundledResource {
            url = bundle.url(forResource: resource, withExtension: "m4a")
        } else if let name = track.importedFileName {
            url = store.musicURL(name)
        } else {
            url = nil
        }
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    var importedFileNames: Set<String> { Set(imported.compactMap(\.importedFileName)) }

    /// Копирует файл из «Файлов» в хранилище приложения и проверяет, что он воспроизводится.
    func importFile(from source: URL) async throws -> MusicTrack {
        let store = self.store
        let displayName = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension.isEmpty ? "audio" : source.pathExtension.lowercased()
        let id = UUID()
        let fileName = "\(id.uuidString).\(ext)"
        let destination = store.musicURL(fileName)

        try await Task.detached(priority: .userInitiated) {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            do {
                try FileManager.default.copyItem(at: source, to: destination)
            } catch {
                throw MusicImportError.copyFailed(displayName)
            }
            do {
                let player = try AVAudioPlayer(contentsOf: destination)
                guard player.duration > 0.5 else { throw MusicImportError.unsupported(displayName) }
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw MusicImportError.unsupported(displayName)
            }
        }.value

        let track = MusicTrack(id: id.uuidString, title: displayName, bundledResource: nil, importedFileName: fileName)
        imported.append(track)
        save()
        return track
    }

    func delete(id: String) {
        guard let track = imported.first(where: { $0.id == id }) else { return }
        imported.removeAll { $0.id == id }
        save()
        if let name = track.importedFileName {
            try? FileManager.default.removeItem(at: store.musicURL(name))
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: store.musicFile),
              let items = try? JSONDecoder().decode([MusicTrack].self, from: data) else { return }
        imported = items.filter {
            guard let name = $0.importedFileName else { return false }
            return FileManager.default.fileExists(atPath: store.musicURL(name).path)
        }
    }

    private func save() {
        do {
            try JSONEncoder().encode(imported).write(to: store.musicFile, options: .atomic)
        } catch {
            NSLog("Otzvuk: не удалось сохранить список мелодий: \(error)")
        }
    }
}
