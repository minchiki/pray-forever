import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        AlarmCoordinator.registerBackgroundRefresh()
        Task { @MainActor in AlarmCoordinator.shared.start() }
        return true
    }

    /// Приложение выгружают из переключателя — предупреждаем, что будильник продолжит звонить уведомлениями.
    func applicationWillTerminate(_ application: UIApplication) {
        // UIApplicationDelegate изолирован на MainActor.
        AlarmCoordinator.shared.appWillTerminate()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let isAlarm = notification.request.content.categoryIdentifier == NotificationScheduler.alarmCategory
        Task { @MainActor in
            let coordinator = AlarmCoordinator.shared
            coordinator.refresh()
            // Когда приложение открыто, будильник уже звучит на экране задания — баннер не нужен.
            completionHandler(isAlarm ? [] : [.banner, .sound, .list])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            AlarmCoordinator.shared.refresh()
            completionHandler()
        }
    }
}
