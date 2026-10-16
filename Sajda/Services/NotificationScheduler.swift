import Foundation
import UserNotifications

/// Обёртка над UNUserNotificationCenter: цепочка повторяющихся уведомлений-будильников.
final class NotificationScheduler {
    static let alarmCategory = "SAJDA_ALARM"
    static let instanceKey = "instanceID"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async -> Bool {
        // .criticalAlert игнорируется системой без entitlement от Apple — запрос безопасен.
        let options: UNAuthorizationOptions = [.alert, .sound, .badge, .criticalAlert]
        let granted = (try? await center.requestAuthorization(options: options)) ?? false
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.alarmCategory, actions: [], intentIdentifiers: [],
                                   options: [.customDismissAction])
        ])
        return granted
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    private func criticalAlertsEnabled() async -> Bool {
        await center.notificationSettings().criticalAlertSetting == .enabled
    }

    /// Полностью пересобирает наши ожидающие уведомления по плану.
    func apply(_ plan: [AlarmPlanner.Planned], settings: AppSettings) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(AlarmPlanner.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let critical = await criticalAlertsEnabled()
        for item in plan {
            let content = makeContent(for: item, settings: settings, critical: critical)
            let interval = max(1, item.fireDate.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
        }
    }

    /// Убирает и ожидающие, и уже показанные уведомления будильника для срабатывания.
    func clearAlarm(instanceID: String) async {
        let prefix = AlarmPlanner.chainPrefix(for: instanceID)
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(prefix) }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }

    /// Мгновенное уведомление (например, если приложение выгрузили во время будильника).
    func postImmediate(title: String, body: String, sound: AlarmSound?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound.map { UNNotificationSound(named: UNNotificationSoundName($0.fileName)) } ?? .default
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: "\(AlarmPlanner.idPrefix)notice.\(UUID().uuidString)",
                                            content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        center.add(request)
    }

    private func makeContent(for item: AlarmPlanner.Planned, settings: AppSettings, critical: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let name = item.instance.prayer.localizedName
        content.userInfo = [Self.instanceKey: item.instance.id]
        content.threadIdentifier = item.instance.id

        switch item.kind {
        case .prayerTime:
            content.title = name
            content.body = item.instance.alarmEnabled
                ? String(format: String(localized: "notif.prayer.body.alarm"), settings.delayMinutes)
                : String(localized: "notif.prayer.body")
            content.sound = .default
            content.interruptionLevel = .timeSensitive
        case .alarm:
            content.title = String(format: String(localized: "notif.alarm.title"), name)
            content.body = String(localized: "notif.alarm.body")
            content.categoryIdentifier = Self.alarmCategory
            let soundName = UNNotificationSoundName(settings.sound.fileName)
            if critical {
                content.sound = .criticalSoundNamed(soundName, withAudioVolume: Float(settings.volume))
                content.interruptionLevel = .critical
            } else {
                content.sound = UNNotificationSound(named: soundName)
                content.interruptionLevel = .timeSensitive
            }
        }
        return content
    }
}
