import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var coordinator: AlarmCoordinator
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var pendingChange: GuardedChange?

    var body: some View {
        NavigationStack {
            Form {
                timesSection
                alarmSection
                taskSection
                reliabilitySection
            }
            .navigationTitle(Text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .guardedChallenge($pendingChange)
    }

    /// Ослабление будильника за час до звонка — только через испытание.
    private func guarded(weakening: Bool, _ change: @escaping () -> Void) {
        coordinator.perform(weakening: weakening, pending: $pendingChange, change)
    }

    // MARK: - Время намаза

    private var timesSection: some View {
        Section {
            Picker("settings.method", selection: $store.settings.method) {
                ForEach(CalculationMethodOption.allCases) { Text($0.localizedName).tag($0) }
            }
            Picker("settings.madhab", selection: $store.settings.madhab) {
                ForEach(MadhabOption.allCases) { Text($0.localizedName).tag($0) }
            }
            NavigationLink {
                LocationPickerView()
                    .environmentObject(coordinator)
                    .environmentObject(store)
            } label: {
                HStack {
                    Text("settings.location")
                    Spacer()
                    Text(store.settings.location?.name ?? coordinatesText ?? String(localized: "settings.location.none"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            NavigationLink {
                OffsetsView().environmentObject(store)
            } label: {
                Text("settings.offsets")
            }
        } header: {
            Text("settings.section.times")
        }
    }

    private var coordinatesText: String? {
        guard let loc = store.settings.location else { return nil }
        return String(format: "%.3f, %.3f", loc.latitude, loc.longitude)
    }

    // MARK: - Будильник

    private var alarmSection: some View {
        Section {
            ForEach(Prayer.allCases) { prayer in
                Toggle(prayer.localizedName, isOn: alarmBinding(prayer))
            }
            Stepper(value: delayBinding, in: AppSettings.delayRange) {
                HStack {
                    Text("settings.delay")
                    Spacer()
                    Text(String(format: String(localized: "common.minutes"), store.settings.delayMinutes))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Picker("settings.sound", selection: $store.settings.sound) {
                ForEach(AlarmSound.allCases) { Text($0.localizedName).tag($0) }
            }
            Button("settings.sound.preview") { coordinator.previewSound() }
            Toggle("settings.notifyAtTime", isOn: $store.settings.notifyAtPrayerTime)
        } header: {
            Text("settings.section.alarm")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("settings.alarmLimit.footer")
                Text("settings.delay.footer")
            }
        }
    }

    private func alarmBinding(_ prayer: Prayer) -> Binding<Bool> {
        Binding(
            get: { store.settings.isAlarmEnabled(prayer) },
            set: { value in coordinator.setAlarm(prayer, enabled: value, pending: $pendingChange) }
        )
    }

    private var delayBinding: Binding<Int> {
        Binding(
            get: { store.settings.delayMinutes },
            set: { value in
                guarded(weakening: value > store.settings.delayMinutes) { store.update { $0.delayMinutes = value } }
            }
        )
    }

    private func protectedToggle(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { value in guarded(weakening: !value) { store.update { $0[keyPath: keyPath] = value } } }
        )
    }

    // MARK: - Задание

    private var taskSection: some View {
        Section {
            Picker("settings.task", selection: $store.settings.task) {
                ForEach(TaskKind.allCases) { Text($0.localizedName).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)
            NavigationLink {
                ReferencePhotosView()
            } label: {
                Text("settings.references")
            }
            Picker("settings.recitation", selection: recitationBinding) {
                ForEach(RecitationChoice.allCases) { Text($0.localizedName).tag($0) }
            }
        } header: {
            Text("settings.section.task")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("settings.task.footer")
                Text("settings.recitation.footer")
            }
        }
    }

    /// Отключить чтение суры — ослабление будильника.
    private var recitationBinding: Binding<RecitationChoice> {
        Binding(
            get: { store.settings.recitation },
            set: { value in
                let weakening = value == .off && store.settings.recitation != .off
                guarded(weakening: weakening) { store.update { $0.recitation = value } }
            }
        )
    }

    // MARK: - Надёжность

    private var reliabilitySection: some View {
        Section {
            Toggle("settings.keepAlive", isOn: protectedToggle(\.keepAlive))
            Toggle("settings.wakeCheck", isOn: protectedToggle(\.wakeCheck))
            NavigationLink {
                PauseView()
                    .environmentObject(coordinator)
                    .environmentObject(store)
            } label: {
                HStack {
                    Text("pause.title")
                    Spacer()
                    if store.settings.activePause() != nil {
                        Text("pause.on").foregroundStyle(.secondary)
                    }
                }
            }
            Button("settings.test") {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { coordinator.startTestAlarm() }
            }
            Button("settings.permissions") {
                Task { await coordinator.requestPermissions() }
            }
            Button("common.openSettings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        } header: {
            Text("settings.section.reliability")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("settings.keepAlive.footer")
                Text("settings.wakeCheck.footer")
                if coordinator.changesLocked {
                    Text("settings.locked.footer").foregroundStyle(.orange)
                }
            }
        }
    }
}

/// Ручная корректировка времени каждого намаза.
struct OffsetsView: View {
    @EnvironmentObject private var store: SettingsStore
    @ObservedObject private var coordinator = AlarmCoordinator.shared
    @State private var pendingChange: GuardedChange?

    var body: some View {
        Form {
            Section {
                ForEach(Prayer.allCases) { prayer in
                    Stepper(value: offsetBinding(prayer), in: AppSettings.offsetRange) {
                        HStack {
                            Text(prayer.localizedName)
                            Spacer()
                            Text(offsetText(store.settings.offset(for: prayer)))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            } footer: {
                Text("offsets.footer")
            }
            Section {
                Button("offsets.reset", role: .destructive) {
                    coordinator.perform(weakening: true, pending: $pendingChange) {
                        store.update { $0.offsetMinutes = [:] }
                    }
                }
            }
        }
        .navigationTitle(Text("settings.offsets"))
        .navigationBarTitleDisplayMode(.inline)
        .guardedChallenge($pendingChange)
    }

    private func offsetBinding(_ prayer: Prayer) -> Binding<Int> {
        Binding(
            get: { store.settings.offset(for: prayer) },
            set: { value in
                coordinator.perform(weakening: true, pending: $pendingChange) {
                    store.update { $0.offsetMinutes[prayer.rawValue] = value }
                }
            }
        )
    }

    private func offsetText(_ value: Int) -> String {
        value == 0 ? "0" : String(format: "%+d %@", value, String(localized: "common.min"))
    }
}
