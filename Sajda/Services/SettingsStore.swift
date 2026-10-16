import Foundation
import Combine
import WidgetKit

/// Хранит настройки и служебное состояние будильника в UserDefaults.
@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let settings = SharedStorage.settingsKey
        static let dismissed = "sajda.dismissed.v1"
        static let ringing = "sajda.ringing.v1"
        static let onboarded = "sajda.onboarded.v1"
        static let wakeChecks = "sajda.wakechecks.v1"
        static let emergencyUses = "sajda.emergency.v1"
    }

    private static let dismissedRetention: TimeInterval = 3 * 24 * 3600

    private let defaults: UserDefaults

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            save(settings, key: Key.settings)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @Published var hasOnboarded: Bool {
        didSet { defaults.set(hasOnboarded, forKey: Key.onboarded) }
    }

    init(defaults: UserDefaults? = nil) {
        if defaults == nil {
            SharedStorage.migrateIfNeeded(keys: [Key.settings, Key.dismissed, Key.ringing, Key.onboarded,
                                                 Key.wakeChecks, Key.emergencyUses])
        }
        let defaults = defaults ?? SharedStorage.defaults
        self.defaults = defaults
        self.settings = Self.load(AppSettings.self, key: Key.settings, from: defaults) ?? AppSettings()
        self.hasOnboarded = defaults.bool(forKey: Key.onboarded)
    }

    func update(_ change: (inout AppSettings) -> Void) {
        settings = settings.with(change)
    }

    // MARK: - Отключённые (выполненные задания) срабатывания

    func dismissedIDs() -> [String: Date] {
        Self.load([String: Date].self, key: Key.dismissed, from: defaults) ?? [:]
    }

    func isDismissed(_ id: String) -> Bool { dismissedIDs()[id] != nil }

    func markDismissed(_ id: String, now: Date = Date()) {
        let pruned = dismissedIDs().filter { now.timeIntervalSince($0.value) < Self.dismissedRetention }
        save(pruned.merging([id: now]) { _, new in new }, key: Key.dismissed)
    }

    // MARK: - Текущее звонящее срабатывание (переживает перезапуск приложения)

    var ringingInstance: AlarmInstance? {
        get { Self.load(AlarmInstance.self, key: Key.ringing, from: defaults) }
        set {
            if let newValue { save(newValue, key: Key.ringing) } else { defaults.removeObject(forKey: Key.ringing) }
        }
    }

    // MARK: - Проверки «не уснул»

    var wakeChecks: [AlarmInstance] {
        get { Self.load([AlarmInstance].self, key: Key.wakeChecks, from: defaults) ?? [] }
        set { save(newValue, key: Key.wakeChecks) }
    }

    // MARK: - Аварийные отключения

    var emergencyUses: [Date] {
        get { Self.load([Date].self, key: Key.emergencyUses, from: defaults) ?? [] }
        set { save(newValue, key: Key.emergencyUses) }
    }

    // MARK: - Helpers

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
