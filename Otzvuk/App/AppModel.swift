import SwiftUI

/// Корневая модель: создаёт и связывает хранилище, библиотеку, рекордер и плеер.
@MainActor
final class AppModel: ObservableObject {
    let store: FileStore
    let library: Library
    let music: MusicLibrary
    let wishlist: Wishlist
    let settings: SettingsStore
    let recorder: VoiceRecorder
    let session: SessionPlayer
    let cache = ReversedAudioCache()

    /// Записи, для которых сейчас готовится развёрнутая копия.
    @Published private(set) var preparing: Set<UUID> = []
    @Published var alertMessage: String?

    init(store: FileStore = .standard(), defaults: UserDefaults = .standard) {
        self.store = store
        library = Library(store: store)
        music = MusicLibrary(store: store)
        wishlist = Wishlist(store: store)
        settings = SettingsStore(defaults: defaults)
        recorder = VoiceRecorder(store: store)
        session = SessionPlayer(library: library, music: music, settings: settings, cache: cache)
        session.reportError = { [weak self] in self?.alertMessage = $0 }

        library.cleanOrphans(keepingMusic: music.importedFileNames)
        // Выбранной мелодии могло уже не быть (файл удалён) — сбрасываем на «без музыки».
        if let id = settings.value.musicTrackID, music.track(id: id) == nil {
            settings.value.musicTrackID = nil
        }
    }

    // MARK: - Сессия

    func startSession() {
        session.start()
    }

    // MARK: - Запись

    /// Перед записью останавливаем прослушивание: иначе голос и музыка попадут в микрофон.
    func prepareForRecording() {
        session.stop()
    }

    /// Сохраняет запись; если она сделана по тексту из «хочу записать», убирает его из списка.
    func saveRecording(title: String, wish: WishItem? = nil) {
        guard let take = recorder.commit() else { return }
        library.add(id: take.id, title: title, fileName: take.fileName, duration: take.duration)
        if let wish { wishlist.remove(id: wish.id) }
    }

    // MARK: - Библиотека

    func delete(_ item: Affirmation) {
        session.remove(id: item.id)
        library.delete(id: item.id)
        preparing.remove(item.id)
        let destination = store.reversedURL(item.reversedFileName)
        Task { await cache.discard(destination: destination) }
    }

    func setReversed(_ on: Bool, for item: Affirmation) {
        library.setReversed(on, id: item.id)
        if on { prepareReversed(item) }
    }

    /// Готовит развёрнутую копию заранее, чтобы включение режима не задерживало воспроизведение.
    private func prepareReversed(_ item: Affirmation) {
        guard !preparing.contains(item.id) else { return }
        preparing.insert(item.id)
        let source = store.recordingURL(item.fileName)
        let destination = store.reversedURL(item.reversedFileName)
        Task {
            do {
                try await cache.ensureReversed(source: source, destination: destination)
            } catch is CancellationError {
            } catch {
                if library.affirmation(id: item.id) != nil {
                    alertMessage = "Не удалось подготовить обратную версию «\(item.title)». Исходная запись не изменена."
                    library.setReversed(false, id: item.id)
                }
            }
            preparing.remove(item.id)
        }
    }

    // MARK: - Музыка

    func importMusic(from urls: [URL]) async -> [String] {
        var errors: [String] = []
        for url in urls {
            do {
                let track = try await music.importFile(from: url)
                if settings.value.musicTrackID == nil { settings.value.musicTrackID = track.id }
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        return errors
    }

    func deleteMusic(_ track: MusicTrack) {
        if settings.value.musicTrackID == track.id { settings.value.musicTrackID = nil }
        music.delete(id: track.id)
    }
}
