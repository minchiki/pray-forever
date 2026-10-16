import Foundation

enum CalculationMethodOption: String, CaseIterable, Codable, Identifiable {
    case russia, muslimWorldLeague, egyptian, karachi, ummAlQura, dubai,
         moonsightingCommittee, northAmerica, kuwait, qatar, singapore, turkey, tehran

    var id: String { rawValue }

    var localizedName: String { NSLocalizedString("method.\(rawValue)", comment: "") }
}

enum MadhabOption: String, CaseIterable, Codable, Identifiable {
    case shafi, hanafi
    var id: String { rawValue }
    var localizedName: String { NSLocalizedString("madhab.\(rawValue)", comment: "") }
}

enum TaskKind: String, CaseIterable, Codable, Identifiable {
    case rug, sink, any
    var id: String { rawValue }
    var localizedName: String { NSLocalizedString("task.\(rawValue)", comment: "") }
    var instruction: String { NSLocalizedString("task.\(rawValue).instruction", comment: "") }
}

enum AlarmSound: String, CaseIterable, Codable, Identifiable {
    case pulse, bell, siren
    var id: String { rawValue }
    var fileName: String { "alarm_\(rawValue).wav" }
    var localizedName: String { NSLocalizedString("sound.\(rawValue)", comment: "") }
}

struct SavedLocation: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var name: String?
}

struct AppSettings: Codable, Equatable {
    static let delayRange = 0...60
    static let offsetRange = -30...30

    var method: CalculationMethodOption = .russia
    var madhab: MadhabOption = .hanafi
    var alarmEnabled: [String: Bool] = Dictionary(uniqueKeysWithValues: Prayer.allCases.map { ($0.rawValue, true) })
    var offsetMinutes: [String: Int] = [:]
    var delayMinutes: Int = 5
    var sound: AlarmSound = .pulse
    var task: TaskKind = .any
    var notifyAtPrayerTime: Bool = true
    var keepAlive: Bool = true
    var location: SavedLocation?
    /// Вся система на паузе до этого момента (после прохождения испытания).
    var pausedUntil: Date?

    init() {}

    func isAlarmEnabled(_ prayer: Prayer) -> Bool { alarmEnabled[prayer.rawValue] ?? true }
    func offset(for prayer: Prayer) -> Int { offsetMinutes[prayer.rawValue] ?? 0 }

    /// Конец паузы, если она ещё действует.
    func activePause(now: Date = Date()) -> Date? {
        guard let pausedUntil, pausedUntil > now else { return nil }
        return pausedUntil
    }

    func with(_ change: (inout AppSettings) -> Void) -> AppSettings {
        var copy = self
        change(&copy)
        return copy
    }

    // Декодирование с дефолтами, чтобы новые поля не ломали старые сохранения.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        method = (try? c.decodeIfPresent(CalculationMethodOption.self, forKey: .method)) ?? d.method
        madhab = (try? c.decodeIfPresent(MadhabOption.self, forKey: .madhab)) ?? d.madhab
        alarmEnabled = (try? c.decodeIfPresent([String: Bool].self, forKey: .alarmEnabled)) ?? d.alarmEnabled
        offsetMinutes = (try? c.decodeIfPresent([String: Int].self, forKey: .offsetMinutes)) ?? d.offsetMinutes
        delayMinutes = (try? c.decodeIfPresent(Int.self, forKey: .delayMinutes)) ?? d.delayMinutes
        sound = (try? c.decodeIfPresent(AlarmSound.self, forKey: .sound)) ?? d.sound
        task = (try? c.decodeIfPresent(TaskKind.self, forKey: .task)) ?? d.task
        notifyAtPrayerTime = (try? c.decodeIfPresent(Bool.self, forKey: .notifyAtPrayerTime)) ?? d.notifyAtPrayerTime
        keepAlive = (try? c.decodeIfPresent(Bool.self, forKey: .keepAlive)) ?? d.keepAlive
        location = try? c.decodeIfPresent(SavedLocation.self, forKey: .location)
        pausedUntil = try? c.decodeIfPresent(Date.self, forKey: .pausedUntil)
    }
}
