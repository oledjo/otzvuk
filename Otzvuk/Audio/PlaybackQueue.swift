import Foundation

/// Циклическая очередь идентификаторов записей.
struct PlaybackQueue: Equatable {
    private(set) var ids: [UUID]
    private(set) var index: Int = 0

    enum Removal: Equatable {
        case notFound
        case other
        /// Удалена текущая запись; `current` теперь указывает на следующую (или nil, если очередь пуста).
        case current
    }

    init(ids: [UUID]) { self.ids = ids }

    var current: UUID? { ids.indices.contains(index) ? ids[index] : nil }
    var isEmpty: Bool { ids.isEmpty }
    var count: Int { ids.count }

    /// Переходит к следующей записи; после последней возвращается к первой.
    @discardableResult
    mutating func advance() -> UUID? {
        guard !ids.isEmpty else { return nil }
        index = (index + 1) % ids.count
        return current
    }

    @discardableResult
    mutating func remove(_ id: UUID) -> Removal {
        guard let removed = ids.firstIndex(of: id) else { return .notFound }
        ids.remove(at: removed)
        if removed < index {
            index -= 1
            return .other
        }
        if removed == index {
            if index >= ids.count { index = 0 }
            return .current
        }
        return .other
    }
}
