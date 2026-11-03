import XCTest
@testable import Sajda

final class AlarmPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func instance(_ id: String, minutesFromNow: Double, delay: Double = 5, enabled: Bool = true) -> AlarmInstance {
        let time = now.addingTimeInterval(minutesFromNow * 60)
        return AlarmInstance(id: id, prayer: .dhuhr, prayerTime: time,
                             alarmTime: time.addingTimeInterval(delay * 60), alarmEnabled: enabled)
    }

    func testPlanRespectsNotificationBudget() {
        let instances = (0..<20).map { instance("i\($0)", minutesFromNow: Double(60 + $0 * 180)) }

        let plan = AlarmPlanner().plan(instances: instances, active: nil, dismissed: [], notifyAtPrayerTime: true, now: now)

        XCTAssertLessThanOrEqual(plan.count, AlarmPlanner.notificationBudget)
        XCTAssertEqual(Set(plan.map(\.identifier)).count, plan.count, "identifiers must be unique")
    }

    func testChainStartsAtAlarmTimeWithFixedInterval() {
        let item = instance("a", minutesFromNow: 10)

        let plan = AlarmPlanner().plan(instances: [item], active: nil, dismissed: [], notifyAtPrayerTime: true, now: now)
        let alarms = plan.filter { $0.kind == .alarm }

        XCTAssertEqual(plan.first { $0.kind == .prayerTime }?.fireDate, item.prayerTime)
        XCTAssertEqual(alarms.count, AlarmPlanner.chainLength)
        XCTAssertEqual(alarms.first?.fireDate, item.alarmTime)
        XCTAssertEqual(alarms[1].fireDate.timeIntervalSince(alarms[0].fireDate), AlarmPlanner.chainInterval, accuracy: 0.001)
    }

    func testDismissedAndDisabledInstancesGetNoAlarmChain() {
        let dismissed = instance("d", minutesFromNow: 10)
        let disabled = instance("x", minutesFromNow: 200, enabled: false)

        let plan = AlarmPlanner().plan(instances: [dismissed, disabled], active: nil, dismissed: ["d"],
                                       notifyAtPrayerTime: true, now: now)

        XCTAssertTrue(plan.allSatisfy { $0.kind == .prayerTime })
        XCTAssertEqual(plan.count, 2)
    }

    func testNoPrayerTimeNotificationWhenDisabled() {
        let plan = AlarmPlanner().plan(instances: [instance("a", minutesFromNow: 10)], active: nil, dismissed: [],
                                       notifyAtPrayerTime: false, now: now)

        XCTAssertFalse(plan.contains { $0.kind == .prayerTime })
    }

    func testActiveAlarmChainIsScheduledFirst() {
        let active = instance("active", minutesFromNow: -6)
        let later = instance("later", minutesFromNow: 120)

        let plan = AlarmPlanner().plan(instances: [active, later], active: active, dismissed: [],
                                       notifyAtPrayerTime: true, now: now)

        XCTAssertEqual(plan.first?.instance.id, "active")
        XCTAssertGreaterThan(plan.first!.fireDate, now)
        XCTAssertEqual(plan.filter { $0.instance.id == "active" }.count, AlarmPlanner.activeChainLength)
    }

    func testChainDoesNotExceedMaxRingDuration() {
        let old = instance("old", minutesFromNow: -64)

        let chain = AlarmPlanner.chain(for: old, from: now, count: 20)

        XCTAssertTrue(chain.allSatisfy { $0.fireDate <= old.alarmTime.addingTimeInterval(AlarmPlanner.maxRingDuration) })
        XCTAssertLessThan(chain.count, 20)
    }

    func testDueInstanceWithinRingWindow() {
        let ringing = instance("r", minutesFromNow: -10)
        let future = instance("f", minutesFromNow: 30)
        let expired = instance("e", minutesFromNow: -200)

        XCTAssertEqual(AlarmPlanner.dueInstance(in: [expired, ringing, future], dismissed: [], now: now)?.id, "r")
        XCTAssertNil(AlarmPlanner.dueInstance(in: [ringing], dismissed: ["r"], now: now))
        XCTAssertNil(AlarmPlanner.dueInstance(in: [future, expired], dismissed: [], now: now))
    }
}
