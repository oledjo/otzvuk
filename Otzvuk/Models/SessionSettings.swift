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
