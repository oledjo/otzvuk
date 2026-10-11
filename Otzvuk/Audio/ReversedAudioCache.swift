import Foundation

/// Готовит и кеширует развёрнутые копии записей. Оригиналы не изменяются.
actor ReversedAudioCache {
    private var inFlight: [String: Task<Void, Error>] = [:]

    /// Гарантирует, что `destination` — актуальная развёрнутая копия `source`.
    /// Параллельные запросы на один файл объединяются.
    func ensureReversed(source: URL, destination: URL) async throws {
        if Self.isFresh(destination: destination, source: source) { return }

        let key = destination.path
        if let running = inFlight[key] {
            try await running.value
            return
        }
        let task = Task.detached(priority: .utility) {
            try AudioReverser.reverse(source: source, destination: destination)
            // Запись могли удалить, пока шла обработка: не оставляем лишнюю копию.
            if !FileManager.default.fileExists(atPath: source.path) {
                try? FileManager.default.removeItem(at: destination)
                throw CancellationError()
            }
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        try await task.value
    }

    /// Останавливает обработку (если идёт) и удаляет копию.
    func discard(destination: URL) {
        inFlight[destination.path]?.cancel()
        try? FileManager.default.removeItem(at: destination)
    }

    private static func isFresh(destination: URL, source: URL) -> Bool {
        let fm = FileManager.default
        guard let dst = try? fm.attributesOfItem(atPath: destination.path),
              let src = try? fm.attributesOfItem(atPath: source.path),
              let dstSize = dst[.size] as? Int, dstSize > 0,
              let dstDate = dst[.modificationDate] as? Date,
              let srcDate = src[.modificationDate] as? Date else { return false }
        return dstDate >= srcDate
    }
}
