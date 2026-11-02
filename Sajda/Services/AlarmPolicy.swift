import Foundation

/// Правила, которые не дают просто так обойти будильник.
enum AlarmPolicy {
    /// Через сколько после выполненного задания приходит проверка «не уснул».
    static let wakeCheckDelay: TimeInterval = 5 * 60
    /// Сколько есть времени, чтобы подтвердить, что не спишь.
    static let wakeCheckWindow: TimeInterval = 60
    static let wakeCheckSuffix = ".check"

    static let emergencyHoldSeconds: Double = 30
    static let emergencyLimit = 2
    static let emergencyPeriod: TimeInterval = 7 * 24 * 3600

    /// За сколько до будильника ослабить настройки можно только через испытание.
    static let lockLeadTime: TimeInterval = 60 * 60

    // MARK: - Проверка «не уснул»

    /// Проверка после выполненного задания. Для самой проверки повторная не создаётся — без бесконечного цикла.
    static func wakeCheck(after instance: AlarmInstance, completedAt: Date) -> AlarmInstance? {
        guard !instance.isWakeCheck else { return nil }
        let checkAt = completedAt.addingTimeInterval(wakeCheckDelay)
        return AlarmInstance(id: instance.id + wakeCheckSuffix,
                             prayer: instance.prayer,
                             prayerTime: checkAt,
                             alarmTime: checkAt.addingTimeInterval(wakeCheckWindow),
                             alarmEnabled: true)
    }

    /// Проверка, которая ждёт ответа прямо сейчас.
    static func pendingWakeCheck(in checks: [AlarmInstance], dismissed: Set<String>, now: Date) -> AlarmInstance? {
        checks.first { $0.prayerTime <= now && now < $0.alarmTime && !dismissed.contains($0.id) }
    }

    /// Проверки, которые ещё могут сработать (не подтверждены и не истекли).
    static func liveWakeChecks(_ checks: [AlarmInstance], dismissed: Set<String>, now: Date) -> [AlarmInstance] {
        checks.filter {
            !dismissed.contains($0.id) && now < $0.alarmTime.addingTimeInterval(AlarmPlanner.maxRingDuration)
        }
    }

    // MARK: - Аварийное отключение

    static func recentEmergencyUses(_ uses: [Date], now: Date) -> [Date] {
        uses.filter { now.timeIntervalSince($0) < emergencyPeriod }
    }

    static func emergencyRemaining(uses: [Date], now: Date) -> Int {
        max(0, emergencyLimit - recentEmergencyUses(uses, now: now).count)
    }

    /// Когда снова станет доступно аварийное отключение (если лимит исчерпан).
    static func nextEmergencyDate(uses: [Date], now: Date) -> Date? {
        guard emergencyRemaining(uses: uses, now: now) == 0 else { return nil }
        return recentEmergencyUses(uses, now: now).min()?.addingTimeInterval(emergencyPeriod)
    }

    // MARK: - Выключение будильника отдельных намазов

    /// Сколько намазов можно выключить тумблером без испытания.
    static let freeDisabledPrayersLimit = 1

    /// true, если выключение будильника этого намаза превысит лимит и требует испытания.
    static func disablingNeedsChallenge(_ prayer: Prayer, settings: AppSettings) -> Bool {
        let othersOff = Prayer.allCases.filter { $0 != prayer && !settings.isAlarmEnabled($0) }.count
        return othersOff >= freeDisabledPrayersLimit
    }

    // MARK: - Блокировка ослабления настроек

    /// true, если новые настройки позволяют будильнику зазвонить позже или выключиться проще.
    /// Метод расчёта, мазхаб, место и поправки сдвигают время намаза — их смена всегда считается ослаблением.
    static func weakens(_ new: AppSettings, comparedTo old: AppSettings) -> Bool {
        if new.method != old.method || new.madhab != old.madhab || new.offsetMinutes != old.offsetMinutes {
            return true
        }
        if old.location != nil, new.location != old.location { return true }
        if new.delayMinutes > old.delayMinutes { return true }
        if Prayer.allCases.contains(where: { old.isAlarmEnabled($0) && !new.isAlarmEnabled($0) }) { return true }
        if new.recitation == .off, old.recitation != .off { return true }
        if old.keepAlive && !new.keepAlive { return true }
        if old.wakeCheck && !new.wakeCheck { return true }
        return false
    }

    /// true, если звонит будильник или до ближайшего меньше часа.
    static func changesLocked(instances: [AlarmInstance], dismissed: Set<String>,
                              isRinging: Bool, now: Date) -> Bool {
        if isRinging { return true }
        return instances.contains {
            $0.alarmEnabled && !dismissed.contains($0.id)
                && $0.alarmTime > now && $0.alarmTime.timeIntervalSince(now) <= lockLeadTime
        }
    }
}

extension AlarmInstance {
    var isWakeCheck: Bool { id.hasSuffix(AlarmPolicy.wakeCheckSuffix) }
}
