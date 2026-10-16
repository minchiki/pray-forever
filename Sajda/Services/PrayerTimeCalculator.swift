import Foundation
import Adhan

/// Расчёт времени намаза (библиотека Adhan) + ручные поправки пользователя.
struct PrayerTimeCalculator {
    /// Выше этой широты используется правило «седьмой части ночи» — иначе летом в России Иша/Фаджр не вычисляются.
    static let highLatitudeThreshold = 48.0

    var calendar: Calendar = .current

    func times(on day: Date, settings: AppSettings) -> [Prayer: Date]? {
        guard let location = settings.location else { return nil }
        let coordinates = Coordinates(latitude: location.latitude, longitude: location.longitude)
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let params = Self.parameters(for: settings, latitude: location.latitude)

        guard let pt = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: params) else {
            return nil
        }
        let raw: [Prayer: Date] = [
            .fajr: pt.fajr, .dhuhr: pt.dhuhr, .asr: pt.asr, .maghrib: pt.maghrib, .isha: pt.isha
        ]
        return raw.reduce(into: [:]) { result, item in
            result[item.key] = item.value.addingTimeInterval(TimeInterval(settings.offset(for: item.key) * 60))
        }
    }

    /// Все срабатывания начиная с `now` (включая ещё звонящее окно) на `days` дней вперёд.
    func instances(from now: Date, days: Int, settings: AppSettings, lookBack: TimeInterval = 0) -> [AlarmInstance] {
        let startOfToday = calendar.startOfDay(for: now)
        let delay = TimeInterval(settings.delayMinutes * 60)

        let all = (-1..<days).flatMap { offset -> [AlarmInstance] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  let times = times(on: day, settings: settings) else { return [] }
            return Prayer.allCases.compactMap { prayer in
                guard let time = times[prayer] else { return nil }
                return AlarmInstance(
                    id: AlarmInstance.makeID(prayer: prayer, day: day, calendar: calendar),
                    prayer: prayer,
                    prayerTime: time,
                    alarmTime: time.addingTimeInterval(delay),
                    alarmEnabled: settings.isAlarmEnabled(prayer)
                )
            }
        }
        let cutoff = now.addingTimeInterval(-lookBack)
        return all
            .filter { $0.alarmTime >= cutoff || $0.prayerTime >= cutoff }
            .sorted { $0.prayerTime < $1.prayerTime }
    }

    static func parameters(for settings: AppSettings, latitude: Double) -> CalculationParameters {
        var params: CalculationParameters
        switch settings.method {
        case .russia:
            // ДУМ РФ: Фаджр 16°, Иша 15°
            params = CalculationMethod.other.params
            params.fajrAngle = 16
            params.ishaAngle = 15
        case .muslimWorldLeague: params = CalculationMethod.muslimWorldLeague.params
        case .egyptian: params = CalculationMethod.egyptian.params
        case .karachi: params = CalculationMethod.karachi.params
        case .ummAlQura: params = CalculationMethod.ummAlQura.params
        case .dubai: params = CalculationMethod.dubai.params
        case .moonsightingCommittee: params = CalculationMethod.moonsightingCommittee.params
        case .northAmerica: params = CalculationMethod.northAmerica.params
        case .kuwait: params = CalculationMethod.kuwait.params
        case .qatar: params = CalculationMethod.qatar.params
        case .singapore: params = CalculationMethod.singapore.params
        case .turkey: params = CalculationMethod.turkey.params
        case .tehran: params = CalculationMethod.tehran.params
        }
        params.madhab = settings.madhab == .hanafi ? .hanafi : .shafi
        params.highLatitudeRule = abs(latitude) > highLatitudeThreshold
            ? HighLatitudeRule.seventhOfTheNight
            : HighLatitudeRule.middleOfTheNight
        return params
    }
}
