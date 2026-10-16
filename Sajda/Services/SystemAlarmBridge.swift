import Foundation
import SwiftUI

#if canImport(AlarmKit)
import AlarmKit
import AppIntents

@available(iOS 26.0, *)
struct SajdaAlarmMetadata: AlarmMetadata {
    var instanceID: String
}

/// Системный будильник iOS 26 (AlarmKit): звонит в беззвучном режиме, при фокусе и выгруженном приложении.
@available(iOS 26.0, *)
@MainActor
final class SystemAlarmBridge {
    static let shared = SystemAlarmBridge()

    private static let mappingKey = "sajda.alarmkit.map.v1"
    private static let rearmDelay: TimeInterval = 15
    private static let maxScheduled = 10

    private let manager = AlarmManager.shared
    private let defaults = UserDefaults.standard
    private let tint = Color(red: 0.12, green: 0.40, blue: 0.29)

    var isAuthorized: Bool { manager.authorizationState == .authorized }

    func requestAuthorization() async -> Bool {
        if manager.authorizationState == .notDetermined {
            _ = try? await manager.requestAuthorization()
        }
        return isAuthorized
    }

    /// Пересобирает запланированные системные будильники. Звонящие сейчас не трогаем.
    func sync(upcoming: [AlarmInstance], sound: AlarmSound) async {
        guard isAuthorized else { return }
        var mapping = loadMapping()
        let existing = (try? manager.alarms) ?? []
        for alarm in existing where alarm.state == .scheduled {
            try? manager.cancel(id: alarm.id)
            mapping[alarm.id.uuidString] = nil
        }
        for instance in upcoming.prefix(Self.maxScheduled) where instance.alarmTime > Date() {
            if let id = await schedule(instance: instance, at: instance.alarmTime, sound: sound) {
                mapping[id.uuidString] = instance.id
            }
        }
        saveMapping(mapping)
    }

    /// Задание выполнено (или аварийное отключение) — гасим все системные будильники этого срабатывания.
    func clear(instanceID: String) {
        var mapping = loadMapping()
        for (uuid, mapped) in mapping where mapped == instanceID {
            if let id = UUID(uuidString: uuid) {
                try? manager.stop(id: id)
                try? manager.cancel(id: id)
            }
            mapping[uuid] = nil
        }
        saveMapping(mapping)
    }

    /// Пользователь нажал системную кнопку «Стоп», но задание не выполнено — перевзводим будильник.
    func rearmIfNeeded(instanceID: String, isDismissed: Bool, sound: AlarmSound) async {
        guard !isDismissed else { return }
        let instance = AlarmInstance(id: instanceID, prayer: Self.prayer(fromID: instanceID),
                                     prayerTime: Date(), alarmTime: Date(), alarmEnabled: true)
        if let id = await schedule(instance: instance, at: Date().addingTimeInterval(Self.rearmDelay), sound: sound) {
            var mapping = loadMapping()
            mapping[id.uuidString] = instanceID
            saveMapping(mapping)
        }
    }

    private func schedule(instance: AlarmInstance, at date: Date, sound: AlarmSound) async -> UUID? {
        let title = LocalizedStringResource(stringLiteral:
            String(format: String(localized: "notif.alarm.title"), instance.prayer.localizedName))
        let alert = AlarmPresentation.Alert(
            title: title,
            stopButton: AlarmButton(text: "alarmkit.stop", textColor: .white, systemImageName: "stop.fill"),
            secondaryButton: AlarmButton(text: "alarmkit.task", textColor: .white, systemImageName: "camera.fill"),
            secondaryButtonBehavior: .custom
        )
        let attributes = AlarmAttributes<SajdaAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: SajdaAlarmMetadata(instanceID: instance.id),
            tintColor: tint
        )
        let configuration = AlarmManager.AlarmConfiguration<SajdaAlarmMetadata>.alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: SystemAlarmStopIntent(instanceID: instance.id),
            secondaryIntent: OpenAlarmTaskIntent(instanceID: instance.id),
            sound: .named(sound.fileName)
        )
        let id = UUID()
        do {
            _ = try await manager.schedule(id: id, configuration: configuration)
            return id
        } catch {
            return nil
        }
    }

    private static func prayer(fromID id: String) -> Prayer {
        Prayer.allCases.first { id.hasSuffix($0.rawValue) } ?? .dhuhr
    }

    private func loadMapping() -> [String: String] {
        defaults.dictionary(forKey: Self.mappingKey) as? [String: String] ?? [:]
    }

    private func saveMapping(_ mapping: [String: String]) {
        defaults.set(mapping, forKey: Self.mappingKey)
    }
}

/// Системная кнопка «Стоп»: будильник не выключается, пока задание не выполнено.
@available(iOS 26.0, *)
struct SystemAlarmStopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "alarmkit.stop"
    static var isDiscoverable: Bool = false

    @Parameter(title: "ID")
    var instanceID: String

    init() { instanceID = "" }
    init(instanceID: String) { self.instanceID = instanceID }

    func perform() async throws -> some IntentResult {
        await AlarmCoordinator.handleSystemStop(instanceID: instanceID)
        return .result()
    }
}

/// Кнопка «Задание»: открывает приложение на экране с камерой.
@available(iOS 26.0, *)
struct OpenAlarmTaskIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "alarmkit.task"
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    @Parameter(title: "ID")
    var instanceID: String

    init() { instanceID = "" }
    init(instanceID: String) { self.instanceID = instanceID }

    func perform() async throws -> some IntentResult {
        await AlarmCoordinator.handleOpenTask(instanceID: instanceID)
        return .result()
    }
}
#endif
