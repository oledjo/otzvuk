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
        let item = library.add(id: take.id, title: title, fileName: take.fileName, duration: take.duration)
        if let wish { wishlist.remove(id: wish.id) }
        if settings.value.reversed { prepareReversed([item]) }
    }

    // MARK: - Библиотека

    func delete(_ item: Affirmation) {
        session.remove(id: item.id)
        library.delete(id: item.id)
        preparing.remove(item.id)
        let destination = store.reversedURL(item.reversedFileName)
        Task { await cache.discard(destination: destination) }
    }

    /// Включает или выключает обратное воспроизведение для всего плейлиста.
    /// При включении заранее готовит развёрнутые копии выбранных записей.
    func setReversedForAll(_ on: Bool) {
        settings.value.reversed = on
        if on { prepareReversed(library.selected) }
    }

    /// Готовит развёрнутые копии заранее, чтобы включение режима не задерживало воспроизведение.
    private func prepareReversed(_ items: [Affirmation]) {
        let pending = items.filter { !preparing.contains($0.id) }
        guard !pending.isEmpty else { return }
        pending.forEach { preparing.insert($0.id) }
        let store = self.store, cache = self.cache
        Task {
            var failed = 0
            for item in pending {
                do {
                    try await cache.ensureReversed(source: store.recordingURL(item.fileName),
                                                   destination: store.reversedURL(item.reversedFileName))
                } catch is CancellationError {
                } catch {
                    failed += 1
                }
                preparing.remove(item.id)
            }
            if failed > 0 {
                alertMessage = "Не удалось подготовить обратную версию для записей: \(failed). Исходные записи не изменены."
            }
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
