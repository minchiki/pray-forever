import Foundation
import UIKit
import BackgroundTasks

/// Центральная логика будильника: расписание, звонок, выключение.
@MainActor
final class AlarmCoordinator: ObservableObject {
    static let shared = AlarmCoordinator()
    static let refreshTaskID = "com.prayforever.app.refresh"

    private static let planningDays = 3
    private static let refreshInterval: TimeInterval = 5 * 60

    let store: SettingsStore
    let location = LocationService()
    private let calculator = PrayerTimeCalculator()
    private let notifications = NotificationScheduler()
    private let audio = AlarmAudioEngine()

    /// Срабатывание, для которого показывается полноэкранное задание.
    @Published private(set) var activeAlarm: AlarmInstance?
    @Published private(set) var instances: [AlarmInstance] = []
    @Published var locationError: String?

    private var ticker: Timer?
    private var lastRefresh: Date = .distantPast

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
    }

    // MARK: - Жизненный цикл

    func start() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        refresh()
    }

    func appBecameActive() {
        refresh()
        if store.settings.location == nil, location.authorization != .denied {
            Task { await updateLocation() }
        }
    }

    func appWillTerminate() {
        if activeAlarm != nil {
            notifications.postImmediate(title: String(localized: "notice.killed.ringing.title"),
                                        body: String(localized: "notice.killed.ringing.body"),
                                        sound: store.settings.sound)
        } else if store.settings.keepAlive, nextAlarm != nil {
            notifications.postImmediate(title: String(localized: "notice.killed.title"),
                                        body: String(localized: "notice.killed.body"),
                                        sound: nil)
        }
    }

    func settingsChanged() {
        refresh()
    }

    // MARK: - Расписание

    var nextAlarm: AlarmInstance? {
        instances.first { $0.alarmEnabled && $0.alarmTime > Date() && !store.isDismissed($0.id) }
    }

    func todayTimes(now: Date = Date()) -> [Prayer: Date]? {
        calculator.times(on: now, settings: store.settings)
    }

    /// Ближайший намаз (время намаза ещё не наступило).
    func nextPrayer(now: Date = Date()) -> AlarmInstance? {
        instances.first { $0.prayerTime > now }
    }

    func refresh(now: Date = Date()) {
        lastRefresh = now
        let settings = store.settings
        instances = calculator.instances(from: now, days: Self.planningDays, settings: settings,
                                         lookBack: AlarmPlanner.maxRingDuration)
        let dismissed = Set(store.dismissedIDs().keys)
        let active = currentDue(now: now, dismissed: dismissed)
        let plan = AlarmPlanner().plan(instances: instances, active: active, dismissed: dismissed,
                                       notifyAtPrayerTime: settings.notifyAtPrayerTime, now: now)
        let upcomingAlarms = instances.filter { $0.alarmEnabled && $0.alarmTime > now && !dismissed.contains($0.id) }

        Task {
            await notifications.apply(plan, settings: settings)
            #if canImport(AlarmKit)
            if #available(iOS 26.0, *) {
                await SystemAlarmBridge.shared.sync(upcoming: upcomingAlarms, sound: settings.sound)
            }
            #endif
        }
        updateKeepAlive(hasUpcoming: !upcomingAlarms.isEmpty)
        tick(now: now)
    }

    private func currentDue(now: Date, dismissed: Set<String>) -> AlarmInstance? {
        if let ringing = store.ringingInstance, !dismissed.contains(ringing.id),
           now < ringing.alarmTime.addingTimeInterval(AlarmPlanner.maxRingDuration) {
            return ringing
        }
        return AlarmPlanner.dueInstance(in: instances, dismissed: dismissed, now: now)
    }

    private func tick(now: Date = Date()) {
        let dismissed = Set(store.dismissedIDs().keys)
        if let due = currentDue(now: now, dismissed: dismissed) {
            if activeAlarm?.id != due.id || audio.mode != .ringing {
                ring(due)
            }
        } else if let active = activeAlarm {
            // Время звонка истекло (час), никто не выключил — тихо завершаем.
            finish(active, markDismissed: !dismissed.contains(active.id))
        }
        if now.timeIntervalSince(lastRefresh) > Self.refreshInterval {
            refresh(now: now)
        }
    }

    private func updateKeepAlive(hasUpcoming: Bool) {
        guard audio.mode != .ringing else { return }
        if store.settings.keepAlive && hasUpcoming {
            audio.startKeepAlive()
        } else {
            audio.stopKeepAlive()
        }
    }

    // MARK: - Звонок

    private func ring(_ instance: AlarmInstance) {
        let isNew = activeAlarm?.id != instance.id
        activeAlarm = instance
        store.ringingInstance = instance
        audio.startRinging(sound: store.settings.sound, volume: store.settings.volume)
        if isNew {
            let settings = store.settings
            let plan = AlarmPlanner().plan(instances: instances, active: instance,
                                           dismissed: Set(store.dismissedIDs().keys),
                                           notifyAtPrayerTime: settings.notifyAtPrayerTime, now: Date())
            Task { await notifications.apply(plan, settings: settings) }
        }
    }

    func startTestAlarm() {
        ring(AlarmInstance.test())
    }

    /// Задание выполнено (фото распознано).
    func completeTask() {
        guard let active = activeAlarm else { return }
        finish(active, markDismissed: true)
    }

    /// Аварийное отключение.
    func emergencyStop() {
        guard let active = activeAlarm else { return }
        finish(active, markDismissed: true)
    }

    private func finish(_ instance: AlarmInstance, markDismissed: Bool) {
        if markDismissed { store.markDismissed(instance.id) }
        store.ringingInstance = nil
        activeAlarm = nil
        audio.stopRinging(keepAlive: false)
        UIApplication.shared.applicationIconBadgeNumber = 0
        Task { await notifications.clearAlarm(instanceID: instance.id) }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            SystemAlarmBridge.shared.clear(instanceID: instance.id)
        }
        #endif
        refresh()
    }

    func previewSound() {
        audio.preview(sound: store.settings.sound, volume: store.settings.volume)
    }

    // MARK: - Разрешения и геолокация

    func requestPermissions() async {
        _ = await notifications.requestAuthorization()
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            _ = await SystemAlarmBridge.shared.requestAuthorization()
        }
        #endif
        refresh()
    }

    func updateLocation() async {
        do {
            let loc = try await location.currentLocation()
            locationError = nil
            store.update { $0.location = loc }
            refresh()
        } catch LocationService.Failure.denied {
            locationError = String(localized: "location.error.denied")
        } catch {
            locationError = String(localized: "location.error.generic")
        }
    }

    // MARK: - Фоновое обновление

    static func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            Task { @MainActor in
                AlarmCoordinator.shared.refresh()
                scheduleBackgroundRefresh()
                // Даём уведомлениям время записаться.
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                task.setTaskCompleted(success: true)
            }
        }
    }

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Системный будильник (AlarmKit)

    static func handleSystemStop(instanceID: String) async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let coordinator = AlarmCoordinator.shared
            await SystemAlarmBridge.shared.rearmIfNeeded(instanceID: instanceID,
                                                         isDismissed: coordinator.store.isDismissed(instanceID),
                                                         sound: coordinator.store.settings.sound)
        }
        #endif
    }

    static func handleOpenTask(instanceID: String) async {
        let coordinator = AlarmCoordinator.shared
        guard !coordinator.store.isDismissed(instanceID) else { return }
        await handleSystemStop(instanceID: instanceID)
        coordinator.start()
        coordinator.refresh()
    }
}
