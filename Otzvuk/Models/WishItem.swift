import Foundation

/// Текст из библиотеки, который пользователь хочет записать.
struct WishItem: Identifiable, Codable, Equatable {
    var id: UUID
    var text: String
    /// Номер текста в библиотеке (нужен, чтобы не добавлять один и тот же дважды).
    var sourceID: Int?

    /// Название записи по умолчанию: начало текста.
    var suggestedTitle: String {
        text.count <= 60 ? text : String(text.prefix(60)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Запрос на открытие окна записи (с текстом-подсказкой или без).
struct RecorderRequest: Identifiable {
    let id = UUID()
    let wish: WishItem?
}
