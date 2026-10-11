import Foundation

struct MusicTrack: Identifiable, Codable, Equatable, Hashable {
    /// У встроенных мелодий id вида "builtin.dawn", у импортированных — UUID.
    var id: String
    var title: String
    /// Имя ресурса в бандле (для встроенных).
    var bundledResource: String?
    /// Имя файла в хранилище приложения (для импортированных).
    var importedFileName: String?

    var isImported: Bool { importedFileName != nil }

    static let builtIn: [MusicTrack] = [
        MusicTrack(id: "builtin.dawn", title: "Рассвет", bundledResource: "dawn", importedFileName: nil),
        MusicTrack(id: "builtin.water", title: "Тихая вода", bundledResource: "water", importedFileName: nil),
        MusicTrack(id: "builtin.calm", title: "Глубокий покой", bundledResource: "calm", importedFileName: nil),
    ]
}
