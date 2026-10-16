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
    /// Проверка «не уснул», ожидающая нажатия.
    @Published private(set) var wakeCheck: AlarmInstance?
    @Published private(set) var instances: [AlarmInstance] = []
    @Published var locationError: String?

    private var ticker: Timer?
    private var lastRefresh: Date = .distantPast

    init(store: SettingsStore? = nil) {
        self.store = store ?? SettingsStore()
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
        instances.first { $0.prayerTime > now && !$0.isWakeCheck }
    }

    func refresh(now: Date = Date()) {
        lastRefresh = now
        let settings = store.settings
        let dismissed = Set(store.dismissedIDs().keys)
        let checks = AlarmPolicy.liveWakeChecks(store.wakeChecks, dismissed: dismissed, now: now)
        store.wakeChecks = checks
        instances = (calculator.instances(from: now, days: Self.planningDays, settings: settings,
                                          lookBack: AlarmPlanner.maxRingDuration) + checks)
            .sorted { $0.prayerTime < $1.prayerTime }
        let pause = settings.activePause(now: now)
        let active = currentDue(now: now, dismissed: dismissed)
        // На паузе планируем только то, что после её окончания — будильники вернутся сами.
        let schedulable = pause.map { end in
            calculator.instances(from: end, days: Self.planningDays, settings: settings).filter { $0.prayerTime >= end }
        } ?? instances
        let plan = AlarmPlanner().plan(instances: schedulable, active: active, dismissed: dismissed,
                                       notifyAtPrayerTime: settings.notifyAtPrayerTime, now: now)
        let upcomingAlarms = schedulable.filter { $0.alarmEnabled && $0.alarmTime > now && !dismissed.contains($0.id) }

        Task {
            await notifications.apply(plan, settings: settings)
            if let pause { await notifications.schedulePauseEnded(at: pause) }
            #if canImport(AlarmKit)
            if #available(iOS 26.0, *) {
                await SystemAlarmBridge.shared.sync(upcoming: upcomingAlarms, sound: settings.sound)
            }
            #endif
        }
        updateKeepAlive(hasUpcoming: pause == nil && !upcomingAlarms.isEmpty)
        tick(now: now)
    }

    private func currentDue(now: Date, dismissed: Set<String>) -> AlarmInstance? {
        if store.settings.activePause(now: now) != nil { return nil }
        if let ringing = store.ringingInstance, !dismissed.contains(ringing.id),
           now < ringing.alarmTime.addingTimeInterval(AlarmPlanner.maxRingDuration) {
            return ringing
        }
        return AlarmPlanner.dueInstance(in: instances, dismissed: dismissed, now: now)
    }

    private func tick(now: Date = Date()) {
        let dismissed = Set(store.dismissedIDs().keys)
        updateWakeCheck(now: now, dismissed: dismissed)
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
        audio.startRinging(sound: store.settings.sound)
        if isNew {
            let settings = store.settings
            let plan = AlarmPlanner().plan(instances: instances, active: instance,
                                           dismissed: Set(store.dismissedIDs().keys),
                                           notifyAtPrayerTime: settings.notifyAtPrayerTime, now: Date())
            Task { await notifications.apply(plan, settings: settings) }
        }
    }

    // MARK: - Проверка «не уснул»

    private func updateWakeCheck(now: Date, dismissed: Set<String>) {
        let pending = activeAlarm == nil
            ? AlarmPolicy.pendingWakeCheck(in: store.wakeChecks, dismissed: dismissed, now: now)
            : nil
        guard pending?.id != wakeCheck?.id else { return }
        wakeCheck = pending
        if pending != nil { audio.preview(sound: store.settings.sound) }
    }

    /// Пользователь подтвердил, что не спит.
    func confirmAwake() {
        guard let check = wakeCheck else { return }
        store.markDismissed(check.id)
        wakeCheck = nil
        Task { await notifications.clearAlarm(instanceID: check.id) }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            SystemAlarmBridge.shared.clear(instanceID: check.id)
        }
        #endif
        refresh()
    }

    // MARK: - Защита от обхода

    /// Ослабить будильник (выключить, сдвинуть) сейчас можно только через испытание.
    var changesLocked: Bool {
        AlarmPolicy.changesLocked(instances: instances, dismissed: Set(store.dismissedIDs().keys),
                                  isRinging: activeAlarm != nil, now: Date())
    }

    var emergencyRemaining: Int {
        AlarmPolicy.emergencyRemaining(uses: store.emergencyUses, now: Date())
    }

    var nextEmergencyDate: Date? {
        AlarmPolicy.nextEmergencyDate(uses: store.emergencyUses, now: Date())
    }

    // MARK: - Пауза

    var pausedUntil: Date? { store.settings.activePause() }

    /// Вызывается только после успешного прохождения испытания.
    func pause(for duration: TimeInterval) {
        guard activeAlarm == nil else { return }
        store.update { $0.pausedUntil = Date().addingTimeInterval(duration) }
    }

    func resume() {
        store.update { $0.pausedUntil = nil }
    }

    func startTestAlarm() {
        ring(AlarmInstance.test())
    }

    /// Задание выполнено (фото распознано).
    func completeTask() {
        guard let active = activeAlarm else { return }
        if store.settings.wakeCheck, let check = AlarmPolicy.wakeCheck(after: active, completedAt: Date()) {
            store.wakeChecks = store.wakeChecks + [check]
        }
        finish(active, markDismissed: true)
    }

    /// Аварийное отключение.
    func emergencyStop() {
        guard let active = activeAlarm else { return }
        if !active.isTest {
            guard emergencyRemaining > 0 else { return }
            store.emergencyUses = AlarmPolicy.recentEmergencyUses(store.emergencyUses, now: Date()) + [Date()]
        }
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
        audio.preview(sound: store.settings.sound)
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
