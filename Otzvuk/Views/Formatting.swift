import Foundation

enum Format {
    /// 83 -> «1:23»
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func gap(_ seconds: Int) -> String {
        seconds == 0 ? "Без пауз" : "Пауза \(seconds) с"
    }

    static func gapOption(_ seconds: Int) -> String {
        seconds == 0 ? "Нет" : "\(seconds) с"
    }

    static func timer(_ seconds: Int) -> String {
        seconds == 0 ? "Без таймера" : "\(seconds / 60) мин"
    }

    static func timerOption(_ seconds: Int) -> String {
        seconds == 0 ? "Без ограничения" : "\(seconds / 60) мин"
    }

    /// Русское склонение: 1 запись, 2 записи, 5 записей.
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod100 = n % 100, mod10 = n % 10
        if mod100 >= 11 && mod100 <= 14 { return many }
        switch mod10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }
}
