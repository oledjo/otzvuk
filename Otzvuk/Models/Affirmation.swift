import Foundation

/// Запись аффирмации. Хранит только имя файла: путь к контейнеру приложения может меняться.
struct Affirmation: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var fileName: String
    var duration: TimeInterval
    var createdAt: Date
    var playsReversed: Bool = false
    var isSelected: Bool = false

    /// Имя файла обработанной копии (кеш обратного воспроизведения).
    var reversedFileName: String { "\(id.uuidString).caf" }
}
