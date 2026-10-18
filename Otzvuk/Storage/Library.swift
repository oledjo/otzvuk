import Foundation

/// Библиотека аффирмаций: список в памяти + JSON на диске.
@MainActor
final class Library: ObservableObject {
    @Published private(set) var affirmations: [Affirmation] = []

    let store: FileStore

    init(store: FileStore) {
        self.store = store
        load()
    }

    var selected: [Affirmation] { affirmations.filter(\.isSelected) }

    func affirmation(id: UUID) -> Affirmation? { affirmations.first { $0.id == id } }

    /// Следующее название по умолчанию: «Аффирмация N».
    func nextDefaultTitle() -> String { "Аффирмация \(affirmations.count + 1)" }

    @discardableResult
    func add(id: UUID, title: String, fileName: String, duration: TimeInterval) -> Affirmation {
        let item = Affirmation(
            id: id,
            title: Self.clean(title, fallback: nextDefaultTitle()),
            fileName: fileName,
            duration: duration,
            createdAt: Date(),
            isSelected: true
        )
        affirmations.append(item)
        save()
        return item
    }

    func rename(id: UUID, to title: String) {
        update(id) { $0.title = Self.clean(title, fallback: $0.title) }
    }

    func setSelected(_ on: Bool, id: UUID) { update(id) { $0.isSelected = on } }

    func toggleSelected(id: UUID) { update(id) { $0.isSelected.toggle() } }

    /// Удаляет запись вместе с оригиналом и обработанной копией.
    func delete(id: UUID) {
        guard let item = affirmation(id: id) else { return }
        affirmations.removeAll { $0.id == id }
        save()
        let fm = FileManager.default
        try? fm.removeItem(at: store.recordingURL(item.fileName))
        try? fm.removeItem(at: store.reversedURL(item.reversedFileName))
    }

    /// Файлы без записи в библиотеке (хвосты прерванной записи или обработки) удаляются.
    func cleanOrphans(keepingMusic: Set<String>) {
        store.removeOrphans(
            recordings: Set(affirmations.map(\.fileName)),
            music: keepingMusic,
            reversed: Set(affirmations.map(\.reversedFileName))
        )
    }

    // MARK: - Private

    private func update(_ id: UUID, _ change: (inout Affirmation) -> Void) {
        guard let index = affirmations.firstIndex(where: { $0.id == id }) else { return }
        change(&affirmations[index])
        save()
    }

    private static func clean(_ title: String, fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(80))
    }

    private func load() {
        guard let data = try? Data(contentsOf: store.libraryFile),
              let items = try? JSONDecoder().decode([Affirmation].self, from: data) else { return }
        // Записи, чьи файлы пропали, не показываем — иначе очередь сломается.
        affirmations = items.filter { FileManager.default.fileExists(atPath: store.recordingURL($0.fileName).path) }
        if affirmations.count != items.count { save() }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(affirmations)
            try data.write(to: store.libraryFile, options: .atomic)
        } catch {
            NSLog("Otzvuk: не удалось сохранить библиотеку: \(error)")
        }
    }
}
