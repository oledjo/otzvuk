import Foundation

struct SessionSettings: Codable, Equatable {
    /// Пауза между записями, секунды.
    var gapSeconds: Int = 5
    /// Таймер остановки, секунды. 0 — без ограничения.
    var timerSeconds: Int = 15 * 60
    /// nil — без музыки.
    var musicTrackID: String? = nil
    var voiceVolume: Double = 1.0
    var musicVolume: Double = 0.35
    /// Играть все записи задом наперёд (настройка всего плейлиста).
    var reversed: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SessionSettings()
        gapSeconds = try c.decodeIfPresent(Int.self, forKey: .gapSeconds) ?? d.gapSeconds
        timerSeconds = try c.decodeIfPresent(Int.self, forKey: .timerSeconds) ?? d.timerSeconds
        musicTrackID = try c.decodeIfPresent(String.self, forKey: .musicTrackID)
        voiceVolume = try c.decodeIfPresent(Double.self, forKey: .voiceVolume) ?? d.voiceVolume
        musicVolume = try c.decodeIfPresent(Double.self, forKey: .musicVolume) ?? d.musicVolume
        reversed = try c.decodeIfPresent(Bool.self, forKey: .reversed) ?? d.reversed
    }

    static let gapOptions = [0, 3, 5, 10]
    static let timerOptions = [5 * 60, 10 * 60, 15 * 60, 30 * 60, 0]
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var value: SessionSettings {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let key = "otzvuk.sessionSettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(SessionSettings.self, from: data) {
            value = decoded
        } else {
            value = SessionSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}
