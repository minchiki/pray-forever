import Foundation

/// Общее хранилище приложения и виджета (App Group).
enum SharedStorage {
    static let appGroup = "group.com.prayforever.app"
    static let settingsKey = "sajda.settings.v1"

    /// Если App Group недоступна (например, при подписи без неё) — обычные UserDefaults приложения.
    static let defaults: UserDefaults = UserDefaults(suiteName: appGroup) ?? .standard

    static func loadSettings(from defaults: UserDefaults = defaults) -> AppSettings? {
        guard let data = defaults.data(forKey: settingsKey) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    /// Переносит данные из старого места хранения (версии до виджетов).
    static func migrateIfNeeded(keys: [String]) {
        guard defaults !== UserDefaults.standard else { return }
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = UserDefaults.standard.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }
}
