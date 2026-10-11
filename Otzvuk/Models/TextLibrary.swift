import Foundation

/// Встроенная библиотека текстов аффирмаций (только текст, без аудио).
struct TextItem: Identifiable, Hashable {
    let id: Int
    let text: String
}

struct TextCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let items: [TextItem]
}

enum TextLibrary {
    static func item(id: Int) -> TextItem? {
        categories.lazy.flatMap(\.items).first { $0.id == id }
    }
}
