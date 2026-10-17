import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var coordinator: AlarmCoordinator
    @EnvironmentObject private var store: SettingsStore
    @State private var showSettings = false
    @State private var showPractice = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let until = store.settings.activePause() {
                        PauseBanner(until: until) { coordinator.resume() }
                            .padding(.top, 8)
                    }
                    if store.settings.location == nil {
                        LocationPromptCard()
                    } else {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            NextPrayerCard(now: context.date)
                        }
                        TodayList()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Text(store.settings.location?.name ?? String(localized: "app.name")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showPractice = true } label: {
                        Image(systemName: "book")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("practice.title"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("settings.title"))
                }
            }
            .onChange(of: coordinator.activeAlarm) { if $0 != nil { showSettings = false; showPractice = false } }
            .onChange(of: coordinator.wakeCheck) { if $0 != nil { showSettings = false; showPractice = false } }
            .sheet(isPresented: $showPractice) {
                PracticeView()
                    .environmentObject(coordinator)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(coordinator)
                    .environmentObject(store)
            }
        }
    }
}

private struct NextPrayerCard: View {
    @EnvironmentObject private var coordinator: AlarmCoordinator
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let next = coordinator.nextPrayer(now: now) {
                Text("home.next")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(next.prayer.localizedName)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text(next.prayerTime.shortTime)
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(Countdown.string(from: now, to: next.prayerTime))
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
                Divider().padding(.vertical, 8)
                alarmLine(for: next)
            } else {
                Text("home.noData")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .padding(.top, 8)
    }

    @ViewBuilder
    private func alarmLine(for next: AlarmInstance) -> some View {
        if next.alarmEnabled {
            Label {
                Text(String(format: String(localized: "home.alarmAt"), next.alarmTime.shortTime))
            } icon: {
                Image(systemName: "alarm.fill")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        } else {
            Label("home.alarmOff", systemImage: "alarm")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct TodayList: View {
    @EnvironmentObject private var coordinator: AlarmCoordinator
    @EnvironmentObject private var store: SettingsStore
    @State private var pendingChange: GuardedChange?

    var body: some View {
        let times = coordinator.todayTimes() ?? [:]
        let nextID = coordinator.nextPrayer()?.prayer
        VStack(spacing: 0) {
            ForEach(Array(Prayer.allCases.enumerated()), id: \.element) { index, prayer in
                if index > 0 { Divider().padding(.leading, 20) }
                PrayerRow(prayer: prayer,
                          time: times[prayer],
                          isNext: prayer == nextID && times[prayer].map { $0 > Date() } == true,
                          alarmOn: store.settings.isAlarmEnabled(prayer)) {
                    let turningOff = store.settings.isAlarmEnabled(prayer)
                    coordinator.perform(weakening: turningOff, pending: $pendingChange) {
                        store.update { $0.alarmEnabled[prayer.rawValue] = !turningOff }
                    }
                }
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

private struct PrayerRow: View {
    let prayer: Prayer
    let time: Date?
    let isNext: Bool
    let alarmOn: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(prayer.localizedName)
                .font(.title3.weight(isNext ? .semibold : .regular))
                .foregroundStyle(isNext ? Color.accentColor : .primary)
            Spacer()
            Text(time?.shortTime ?? "—")
                .font(.title3.weight(isNext ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isNext ? Color.accentColor : .primary)
            Button(action: toggle) {
                Image(systemName: alarmOn ? "alarm.fill" : "alarm")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(alarmOn ? Color.accentColor : Color.secondary.opacity(0.5))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(alarmOn ? LocalizedStringKey("home.alarmOn.a11y")
                                             : LocalizedStringKey("home.alarmOff.a11y")))
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .frame(minHeight: 60)
    }
}

private struct LocationPromptCard: View {
    @EnvironmentObject private var coordinator: AlarmCoordinator
    @ObservedObject private var location = AlarmCoordinator.shared.location

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "location.circle")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text("location.prompt.title")
                .font(.title2.weight(.semibold))
            Text("location.prompt.body")
                .foregroundStyle(.secondary)
            if let error = coordinator.locationError {
                Text(error).font(.footnote).foregroundStyle(.red)
                if location.authorization == .denied {
                    Button("common.openSettings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            Button {
                Task { await coordinator.updateLocation() }
            } label: {
                HStack {
                    if location.isLocating { ProgressView().tint(.white) }
                    Text("location.prompt.button")
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .disabled(location.isLocating)
            NavigationLink {
                LocationPickerView()
            } label: {
                Text("location.prompt.manual")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .padding(.top, 8)
    }
}
