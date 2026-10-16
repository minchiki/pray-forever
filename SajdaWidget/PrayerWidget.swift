import SwiftUI
import WidgetKit

// MARK: - Данные

struct PrayerEntry: TimelineEntry {
    struct Item: Equatable {
        let prayer: Prayer
        let time: Date
    }

    enum State {
        case ready(today: [Item], next: Item)
        case paused(until: Date, next: Item?)
        case noLocation
    }

    let date: Date
    let state: State

    static let placeholder: PrayerEntry = {
        let now = Date()
        let today = Prayer.allCases.enumerated().map { index, prayer in
            Item(prayer: prayer, time: now.addingTimeInterval(Double(index) * 3 * 3600 + 1800))
        }
        return PrayerEntry(date: now, state: .ready(today: today, next: today[0]))
    }()
}

struct PrayerProvider: TimelineProvider {
    /// Сколько часов вперёд строить расписание виджета.
    private static let horizonHours: Double = 24

    func placeholder(in context: Context) -> PrayerEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entries(from: Date()).first ?? .placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
        let now = Date()
        let list = entries(from: now)
        let refresh = list.last.map { $0.date.addingTimeInterval(60) } ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: list, policy: .after(refresh)))
    }

    /// Запись на «сейчас» и на каждый момент наступления намаза — так «следующий» переключается вовремя.
    private func entries(from now: Date) -> [PrayerEntry] {
        guard let settings = SharedStorage.loadSettings(), settings.location != nil else {
            return [PrayerEntry(date: now, state: .noLocation)]
        }
        let calculator = PrayerTimeCalculator()
        let all = calculator.instances(from: now, days: 3, settings: settings)
            .map { PrayerEntry.Item(prayer: $0.prayer, time: $0.prayerTime) }
        let horizon = now.addingTimeInterval(Self.horizonHours * 3600)
        let switchPoints = [now] + all.map(\.time).filter { $0 > now && $0 <= horizon }

        return switchPoints.map { moment in
            let next = all.first { $0.time > moment }
            if let pause = settings.activePause(now: moment) {
                return PrayerEntry(date: moment, state: .paused(until: pause, next: next))
            }
            guard let next else { return PrayerEntry(date: moment, state: .noLocation) }
            let today = calculator.times(on: moment, settings: settings).map { times in
                Prayer.allCases.compactMap { p in times[p].map { PrayerEntry.Item(prayer: p, time: $0) } }
            } ?? []
            return PrayerEntry(date: moment, state: .ready(today: today, next: next))
        }
    }
}

// MARK: - Оформление

enum WidgetStyle {
    static let accent = Color(red: 0.11, green: 0.39, blue: 0.28)
    static let accentDark = Color(red: 0.37, green: 0.75, blue: 0.57)
}

extension View {
    /// Фон виджета: на iOS 17+ через containerBackground, на iOS 16 — обычный фон.
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) { Color(.systemBackground) }
        } else {
            padding().background(Color(.systemBackground))
        }
    }
}

private struct AccentText: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.foregroundStyle(scheme == .dark ? WidgetStyle.accentDark : WidgetStyle.accent)
    }
}

private extension View {
    func accentText() -> some View { modifier(AccentText()) }
}

// MARK: - Виды

struct PrayerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PrayerEntry

    var body: some View {
        switch family {
        case .systemMedium: MediumView(entry: entry)
        case .accessoryInline: InlineView(entry: entry)
        case .accessoryCircular: CircularView(entry: entry)
        case .accessoryRectangular: RectangularView(entry: entry)
        default: SmallView(entry: entry)
        }
    }
}

private struct SmallView: View {
    let entry: PrayerEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch entry.state {
            case .ready(_, let next):
                Text("home.next").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(next.prayer.localizedName).font(.title3.weight(.semibold))
                Text(next.time, style: .time)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .accentText()
                Text(next.time, style: .relative)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            case .paused(let until, _):
                PausedContent(until: until)
            case .noLocation:
                NoLocationContent()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetBackground()
    }
}

private struct MediumView: View {
    let entry: PrayerEntry

    var body: some View {
        Group {
            switch entry.state {
            case .ready(let today, let next):
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("home.next").font(.caption).foregroundStyle(.secondary)
                        Text(next.prayer.localizedName).font(.headline)
                        Text(next.time, style: .time)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .accentText()
                        Text(next.time, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 3) {
                        ForEach(today, id: \.prayer) { item in
                            let isNext = item == next
                            HStack {
                                Text(item.prayer.localizedName)
                                Spacer(minLength: 8)
                                Text(item.time, style: .time).monospacedDigit()
                            }
                            .font(.subheadline.weight(isNext ? .bold : .regular))
                            .modifier(ConditionalAccent(active: isNext))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            case .paused(let until, _):
                VStack(alignment: .leading) { PausedContent(until: until) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .noLocation:
                VStack(alignment: .leading) { NoLocationContent() }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .widgetBackground()
    }
}

private struct ConditionalAccent: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active { content.accentText() } else { content }
    }
}

private struct InlineView: View {
    let entry: PrayerEntry
    var body: some View {
        switch entry.state {
        case .ready(_, let next):
            Text("\(next.prayer.localizedName) \(next.time, style: .time)")
        case .paused:
            Text("pause.active")
        case .noLocation:
            Text("widget.noLocation.short")
        }
    }
}

private struct CircularView: View {
    let entry: PrayerEntry
    var body: some View {
        ZStack {
            AccessoryBackground()
            switch entry.state {
            case .ready(_, let next):
                VStack(spacing: 0) {
                    Text(next.prayer.localizedName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(next.time, style: .time)
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                }
                .padding(4)
            case .paused:
                Image(systemName: "pause.fill")
            case .noLocation:
                Image(systemName: "location.slash")
            }
        }
        .widgetBackground()
    }
}

private struct RectangularView: View {
    let entry: PrayerEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            switch entry.state {
            case .ready(_, let next):
                Text(next.prayer.localizedName).font(.headline).widgetAccentable()
                Text(next.time, style: .time).font(.body.weight(.semibold)).monospacedDigit()
                Text(next.time, style: .relative).font(.caption).lineLimit(1)
            case .paused(let until, _):
                Label("pause.active", systemImage: "pause.fill").font(.headline)
                Text(until, style: .time).font(.caption)
            case .noLocation:
                Text("widget.noLocation.short").font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetBackground()
    }
}

private struct AccessoryBackground: View {
    var body: some View {
        if #available(iOS 16.0, *) {
            AccessoryWidgetBackground()
        }
    }
}

private struct PausedContent: View {
    let until: Date
    var body: some View {
        Image(systemName: "pause.circle.fill").font(.title2).accentText()
        Spacer(minLength: 0)
        Text("pause.active").font(.headline)
        Text(String(format: NSLocalizedString("pause.until", comment: ""),
                    until.formatted(date: .abbreviated, time: .shortened)))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct NoLocationContent: View {
    var body: some View {
        Image(systemName: "location.slash").font(.title2).foregroundStyle(.secondary)
        Spacer(minLength: 0)
        Text("widget.noLocation").font(.subheadline).foregroundStyle(.secondary)
    }
}

// MARK: - Виджет

struct PrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PrayerWidget", provider: PrayerProvider()) { entry in
            PrayerWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("widget.name"))
        .description(Text("widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct PrayerWidgetBundle: WidgetBundle {
    var body: some Widget {
        PrayerWidget()
    }
}
