import XCTest
@testable import Sajda

final class PrayerTimeTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return c
    }()

    private var kazan: AppSettings {
        AppSettings().with { $0.location = SavedLocation(latitude: 55.79, longitude: 49.12, name: "Kazan") }
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testFivePrayersInOrder() throws {
        let times = try XCTUnwrap(PrayerTimeCalculator(calendar: calendar).times(on: day(2026, 3, 15), settings: kazan))
        let ordered = Prayer.allCases.compactMap { times[$0] }

        XCTAssertEqual(ordered.count, 5)
        XCTAssertEqual(ordered, ordered.sorted())
    }

    func testSummerHighLatitudeStillProducesTimes() throws {
        let times = PrayerTimeCalculator(calendar: calendar).times(on: day(2026, 6, 21), settings: kazan)
        XCTAssertEqual(times?.count, 5)
    }

    func testManualOffsetIsApplied() throws {
        let calc = PrayerTimeCalculator(calendar: calendar)
        let base = try XCTUnwrap(calc.times(on: day(2026, 3, 15), settings: kazan))
        let shifted = try XCTUnwrap(calc.times(on: day(2026, 3, 15),
                                               settings: kazan.with { $0.offsetMinutes["asr"] = 7 }))

        XCTAssertEqual(shifted[.asr]!.timeIntervalSince(base[.asr]!), 7 * 60, accuracy: 0.001)
        XCTAssertEqual(shifted[.fajr], base[.fajr])
    }

    func testInstancesUseDelayAndAreSorted() {
        let settings = kazan.with { $0.delayMinutes = 9; $0.alarmEnabled["isha"] = false }
        let now = day(2026, 3, 15)

        let list = PrayerTimeCalculator(calendar: calendar).instances(from: now, days: 2, settings: settings)

        XCTAssertFalse(list.isEmpty)
        XCTAssertEqual(list.map(\.prayerTime), list.map(\.prayerTime).sorted())
        XCTAssertTrue(list.allSatisfy { abs($0.alarmTime.timeIntervalSince($0.prayerTime) - 9 * 60) < 0.001 })
        XCTAssertTrue(list.filter { $0.prayer == .isha }.allSatisfy { !$0.alarmEnabled })
    }

    func testNoLocationGivesNoTimes() {
        XCTAssertNil(PrayerTimeCalculator(calendar: calendar).times(on: Date(), settings: AppSettings()))
    }
}

final class AppSettingsTests: XCTestCase {
    func testDecodingOldDataFallsBackToDefaults() throws {
        let json = Data(#"{"delayMinutes": 12, "method": "unknownMethod"}"#.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.delayMinutes, 12)
        XCTAssertEqual(settings.method, AppSettings().method)
        XCTAssertTrue(settings.keepAlive)
        XCTAssertTrue(settings.isAlarmEnabled(.fajr))
    }

    func testRoundTrip() throws {
        let original = AppSettings().with {
            $0.task = .sink
            $0.sound = .siren
            $0.offsetMinutes["fajr"] = -3
        }
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testWithDoesNotMutateOriginal() {
        let original = AppSettings()
        let changed = original.with { $0.delayMinutes = 30 }
        XCTAssertEqual(original.delayMinutes, 5)
        XCTAssertEqual(changed.delayMinutes, 30)
    }

    func testInstanceIDFormat() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        XCTAssertEqual(AlarmInstance.makeID(prayer: .asr, day: date, calendar: cal), "2026-01-05-asr")
    }
}

@MainActor
final class CoordinateParsingTests: XCTestCase {
    func testParsesDotAndCommaDecimals() {
        let parsed = LocationPickerView.parseCoordinates("55,7961", " 49.1064 ")
        XCTAssertEqual(parsed?.0 ?? 0, 55.7961, accuracy: 0.00001)
        XCTAssertEqual(parsed?.1 ?? 0, 49.1064, accuracy: 0.00001)
    }

    func testRejectsOutOfRangeAndGarbage() {
        XCTAssertNil(LocationPickerView.parseCoordinates("91", "10"))
        XCTAssertNil(LocationPickerView.parseCoordinates("10", "-181"))
        XCTAssertNil(LocationPickerView.parseCoordinates("abc", "10"))
    }
}
