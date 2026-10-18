import Foundation

/// Список «хочу записать»: тексты из библиотеки, ожидающие записи.
@MainActor
final class Wishlist: ObservableObject {
    @Published private(set) var items: [WishItem] = []

    private let file: URL

    init(store: FileStore) {
        file = store.wishlistFile
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([WishItem].self, from: data) {
            items = decoded
        }
    }

    func contains(sourceID: Int) -> Bool { items.contains { $0.sourceID == sourceID } }

    /// Добавляет текст, если его ещё нет в списке; повторное нажатие убирает.
    func toggle(_ text: TextItem) {
        if let existing = items.first(where: { $0.sourceID == text.id }) {
            remove(id: existing.id)
        } else {
            items.append(WishItem(id: UUID(), text: text.text, sourceID: text.id))
            save()
        }
    }

    /// Добавляет все тексты, которых ещё нет в списке (порядок сохраняется).
    func addAll(_ texts: [TextItem]) {
        let new = texts.filter { !contains(sourceID: $0.id) }
        guard !new.isEmpty else { return }
        items += new.map { WishItem(id: UUID(), text: $0.text, sourceID: $0.id) }
        save()
    }

    /// Убирает из списка все переданные тексты.
    func removeAll(_ texts: [TextItem]) {
        let ids = Set(texts.map(\.id))
        items.removeAll { $0.sourceID.map(ids.contains) ?? false }
        save()
    }

    /// Следующий текст для записи после `id`; если `id` последний — первый из оставшихся; если других нет — nil.
    func next(after id: UUID) -> WishItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return items.first }
        let following = items.suffix(from: index + 1).first
        return following ?? items.first { $0.id != id }
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    private func save() {
        do {
            try JSONEncoder().encode(items).write(to: file, options: .atomic)
        } catch {
            NSLog("Otzvuk: не удалось сохранить список «хочу записать»: \(error)")
        }
    }
}
