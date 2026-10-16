import Foundation

/// Чистая логика: какие локальные уведомления запланировать с учётом лимита iOS (64 штуки).
struct AlarmPlanner {
    enum Kind: Equatable { case prayerTime, alarm }

    struct Planned: Equatable {
        let identifier: String
        let fireDate: Date
        let kind: Kind
        let instance: AlarmInstance
    }

    static let idPrefix = "sajda."
    /// iOS хранит не более 64 ожидающих уведомлений; оставляем запас.
    static let notificationBudget = 60
    /// Звук уведомления ≤ 30 с, поэтому повтор каждые 30 с даёт непрерывный сигнал.
    static let chainInterval: TimeInterval = 30
    static let chainLength = 10
    static let activeChainLength = 20
    /// Сколько максимум звонит будильник, если приложение никто не открыл.
    static let maxRingDuration: TimeInterval = 60 * 60

    static func chainPrefix(for instanceID: String) -> String { "\(idPrefix)alarm.\(instanceID)." }

    /// - Parameters:
    ///   - instances: срабатывания, отсортированные по времени.
    ///   - active: звонящее прямо сейчас срабатывание (если есть).
    func plan(instances: [AlarmInstance],
              active: AlarmInstance?,
              dismissed: Set<String>,
              notifyAtPrayerTime: Bool,
              now: Date) -> [Planned] {
        var result: [Planned] = []
        var budget = Self.notificationBudget

        if let active, !dismissed.contains(active.id) {
            let chain = Self.chain(for: active, from: now.addingTimeInterval(Self.chainInterval), count: Self.activeChainLength)
            result += chain.prefix(budget)
            budget -= min(budget, chain.count)
        }

        for instance in instances where instance.id != active?.id {
            guard budget > 0 else { break }
            let wantsAlarm = instance.alarmEnabled && !dismissed.contains(instance.id) && instance.alarmTime > now

            if notifyAtPrayerTime || instance.isWakeCheck, instance.prayerTime > now {
                result.append(Planned(identifier: "\(Self.idPrefix)prayer.\(instance.id)",
                                      fireDate: instance.prayerTime, kind: .prayerTime, instance: instance))
                budget -= 1
            }
            if wantsAlarm, budget > 0 {
                let chain = Self.chain(for: instance, from: instance.alarmTime, count: Self.chainLength)
                result += chain.prefix(budget)
                budget -= min(budget, chain.count)
            }
        }
        return result
    }

    static func chain(for instance: AlarmInstance, from start: Date, count: Int) -> [Planned] {
        let end = instance.alarmTime.addingTimeInterval(maxRingDuration)
        return (0..<count).compactMap { index in
            let date = start.addingTimeInterval(Double(index) * chainInterval)
            guard date <= end else { return nil }
            return Planned(identifier: "\(chainPrefix(for: instance.id))\(Int(date.timeIntervalSince1970))",
                           fireDate: date, kind: .alarm, instance: instance)
        }
    }

    /// Срабатывание, которое должно звонить прямо сейчас.
    static func dueInstance(in instances: [AlarmInstance], dismissed: Set<String>, now: Date) -> AlarmInstance? {
        instances
            .filter { $0.alarmEnabled && !dismissed.contains($0.id) }
            .filter { $0.alarmTime <= now && now < $0.alarmTime.addingTimeInterval(maxRingDuration) }
            .max { $0.alarmTime < $1.alarmTime }
    }
}
