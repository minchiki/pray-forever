import Foundation

enum Prayer: String, CaseIterable, Codable, Identifiable {
    case fajr, dhuhr, asr, maghrib, isha

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .fajr: return String(localized: "prayer.fajr")
        case .dhuhr: return String(localized: "prayer.dhuhr")
        case .asr: return String(localized: "prayer.asr")
        case .maghrib: return String(localized: "prayer.maghrib")
        case .isha: return String(localized: "prayer.isha")
        }
    }
}

/// Одно конкретное срабатывание: намаз в конкретный день.
struct AlarmInstance: Identifiable, Equatable, Codable {
    /// Например "2026-10-16-dhuhr" или "test-1760600000".
    let id: String
    let prayer: Prayer
    let prayerTime: Date
    let alarmTime: Date
    let alarmEnabled: Bool

    var isTest: Bool { id.hasPrefix("test-") }

    static func makeID(prayer: Prayer, day: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d-%@", c.year ?? 0, c.month ?? 0, c.day ?? 0, prayer.rawValue)
    }

    static func test(now: Date = Date()) -> AlarmInstance {
        AlarmInstance(
            id: "test-\(Int(now.timeIntervalSince1970))",
            prayer: .dhuhr,
            prayerTime: now,
            alarmTime: now,
            alarmEnabled: true
        )
    }
}
