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

    func testFirstPrayerCanBeDisabledWithoutChallenge() {
        XCTAssertFalse(AlarmPolicy.disablingNeedsChallenge(.isha, settings: AppSettings()))
    }

    func testSecondDisabledPrayerNeedsChallenge() {
        let settings = AppSettings().with { $0.alarmEnabled[Prayer.fajr.rawValue] = false }

        XCTAssertTrue(AlarmPolicy.disablingNeedsChallenge(.isha, settings: settings))
    }

    func testAlreadyDisabledPrayerDoesNotCountAgainstItself() {
        let settings = AppSettings().with { $0.alarmEnabled[Prayer.fajr.rawValue] = false }

        XCTAssertFalse(AlarmPolicy.disablingNeedsChallenge(.fajr, settings: settings))
    }

    func testShiftingPrayerTimesWeakensAlarm() {
        let base = AppSettings().with { $0.location = SavedLocation(latitude: 55.79, longitude: 49.11, name: "Kazan") }

        XCTAssertTrue(AlarmPolicy.weakens(base.with { $0.madhab = .shafi }, comparedTo: base))
        XCTAssertTrue(AlarmPolicy.weakens(base.with { $0.method = .turkey }, comparedTo: base))
        XCTAssertTrue(AlarmPolicy.weakens(base.with { $0.offsetMinutes[Prayer.fajr.rawValue] = -5 }, comparedTo: base))
        XCTAssertTrue(AlarmPolicy.weakens(base.with { $0.location = SavedLocation(latitude: 43.1, longitude: 131.9, name: nil) },
                                          comparedTo: base))
    }

    func testFirstLocationIsNotWeakening() {
        let located = AppSettings().with { $0.location = SavedLocation(latitude: 55.79, longitude: 49.11, name: nil) }

        XCTAssertFalse(AlarmPolicy.weakens(located, comparedTo: AppSettings()))
    }

    func testOnlyLooseningChangesWeakenAlarm() {
        let base = AppSettings()

        XCTAssertTrue(AlarmPolicy.weakens(base.with { $0.delayMinutes += 1 }, comparedTo: base))
        XCTAssertFalse(AlarmPolicy.weakens(base.with { $0.delayMinutes -= 1 }, comparedTo: base))
        XCTAssertTrue(AlarmPolicy.weakens(base.with { $0.alarmEnabled[Prayer.isha.rawValue] = false }, comparedTo: base))
        XCTAssertTrue(AlarmPolicy.weakens(base.with { $0.recitation = .off }, comparedTo: base))
        XCTAssertFalse(AlarmPolicy.weakens(base.with { $0.recitation = .random }, comparedTo: base))
        XCTAssertTrue(AlarmPolicy.weakens(base.with { $0.keepAlive = false }, comparedTo: base))
        XCTAssertTrue(AlarmPolicy.weakens(base.with { $0.wakeCheck = false }, comparedTo: base))
        XCTAssertFalse(AlarmPolicy.weakens(base.with { $0.sound = .siren }, comparedTo: base))
        XCTAssertFalse(AlarmPolicy.weakens(base.with { $0.task = .rug }, comparedTo: base))
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
