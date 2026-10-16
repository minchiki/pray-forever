import XCTest
@testable import Sajda

final class AlarmPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func instance(_ id: String, alarmInMinutes: Double, enabled: Bool = true) -> AlarmInstance {
        let alarm = now.addingTimeInterval(alarmInMinutes * 60)
        return AlarmInstance(id: id, prayer: .asr, prayerTime: alarm.addingTimeInterval(-300),
                             alarmTime: alarm, alarmEnabled: enabled)
    }

    func testWakeCheckIsScheduledFiveMinutesLaterWithOneMinuteWindow() throws {
        let check = try XCTUnwrap(AlarmPolicy.wakeCheck(after: instance("2026-10-16-asr", alarmInMinutes: 0),
                                                        completedAt: now))

        XCTAssertTrue(check.isWakeCheck)
        XCTAssertEqual(check.prayerTime.timeIntervalSince(now), AlarmPolicy.wakeCheckDelay, accuracy: 0.001)
        XCTAssertEqual(check.alarmTime.timeIntervalSince(check.prayerTime), AlarmPolicy.wakeCheckWindow, accuracy: 0.001)
        XCTAssertTrue(check.alarmEnabled)
    }

    func testNoWakeCheckAfterWakeCheck() throws {
        let check = try XCTUnwrap(AlarmPolicy.wakeCheck(after: instance("a", alarmInMinutes: 0), completedAt: now))
        XCTAssertNil(AlarmPolicy.wakeCheck(after: check, completedAt: now))
    }

    func testPendingWakeCheckOnlyInsideWindow() throws {
        let check = try XCTUnwrap(AlarmPolicy.wakeCheck(after: instance("a", alarmInMinutes: 0), completedAt: now))
        let inside = check.prayerTime.addingTimeInterval(10)

        XCTAssertNil(AlarmPolicy.pendingWakeCheck(in: [check], dismissed: [], now: now))
        XCTAssertEqual(AlarmPolicy.pendingWakeCheck(in: [check], dismissed: [], now: inside)?.id, check.id)
        XCTAssertNil(AlarmPolicy.pendingWakeCheck(in: [check], dismissed: [check.id], now: inside))
        XCTAssertNil(AlarmPolicy.pendingWakeCheck(in: [check], dismissed: [], now: check.alarmTime))
    }

    func testMissedWakeCheckBecomesDueAlarm() throws {
        let check = try XCTUnwrap(AlarmPolicy.wakeCheck(after: instance("a", alarmInMinutes: 0), completedAt: now))
        let afterDeadline = check.alarmTime.addingTimeInterval(1)

        XCTAssertEqual(AlarmPlanner.dueInstance(in: [check], dismissed: [], now: afterDeadline)?.id, check.id)
    }

    func testWakeCheckNotificationIsSentEvenWhenPrayerNotificationsAreOff() throws {
        let check = try XCTUnwrap(AlarmPolicy.wakeCheck(after: instance("a", alarmInMinutes: 0), completedAt: now))

        let plan = AlarmPlanner().plan(instances: [check], active: nil, dismissed: [],
                                       notifyAtPrayerTime: false, now: now)

        XCTAssertTrue(plan.contains { $0.kind == .prayerTime })
        XCTAssertTrue(plan.contains { $0.kind == .alarm })
    }

    func testEmergencyLimitIsTwoPerWeek() {
        let day: TimeInterval = 24 * 3600
        let uses = [now.addingTimeInterval(-2 * day), now.addingTimeInterval(-1 * day)]

        XCTAssertEqual(AlarmPolicy.emergencyRemaining(uses: [], now: now), 2)
        XCTAssertEqual(AlarmPolicy.emergencyRemaining(uses: uses, now: now), 0)
        XCTAssertEqual(AlarmPolicy.nextEmergencyDate(uses: uses, now: now), uses[0].addingTimeInterval(7 * day))
        XCTAssertEqual(AlarmPolicy.emergencyRemaining(uses: uses, now: now.addingTimeInterval(5.5 * day)), 1)
    }

    func testChangesLockedWithinHourBeforeAlarm() {
        XCTAssertTrue(AlarmPolicy.changesLocked(instances: [instance("a", alarmInMinutes: 30)],
                                                dismissed: [], isRinging: false, now: now))
        XCTAssertFalse(AlarmPolicy.changesLocked(instances: [instance("a", alarmInMinutes: 90)],
                                                 dismissed: [], isRinging: false, now: now))
        XCTAssertFalse(AlarmPolicy.changesLocked(instances: [instance("a", alarmInMinutes: 30, enabled: false)],
                                                 dismissed: [], isRinging: false, now: now))
        XCTAssertFalse(AlarmPolicy.changesLocked(instances: [instance("a", alarmInMinutes: 30)],
                                                 dismissed: ["a"], isRinging: false, now: now))
        XCTAssertTrue(AlarmPolicy.changesLocked(instances: [], dismissed: [], isRinging: true, now: now))
    }
}
