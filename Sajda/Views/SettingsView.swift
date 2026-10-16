import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var coordinator: AlarmCoordinator
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.dismiss) private var dismiss

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
            Stepper(value: $store.settings.delayMinutes, in: AppSettings.delayRange) {
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
            Text("settings.delay.footer")
        }
    }

    private func alarmBinding(_ prayer: Prayer) -> Binding<Bool> {
        Binding(
            get: { store.settings.isAlarmEnabled(prayer) },
            set: { value in store.update { $0.alarmEnabled[prayer.rawValue] = value } }
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
        } header: {
            Text("settings.section.task")
        } footer: {
            Text("settings.task.footer")
        }
    }

    // MARK: - Надёжность

    private var reliabilitySection: some View {
        Section {
            Toggle("settings.keepAlive", isOn: $store.settings.keepAlive)
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
            Text("settings.keepAlive.footer")
        }
    }
}

/// Ручная корректировка времени каждого намаза.
struct OffsetsView: View {
    @EnvironmentObject private var store: SettingsStore

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
                    store.update { $0.offsetMinutes = [:] }
                }
            }
        }
        .navigationTitle(Text("settings.offsets"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func offsetBinding(_ prayer: Prayer) -> Binding<Int> {
        Binding(
            get: { store.settings.offset(for: prayer) },
            set: { value in store.update { $0.offsetMinutes[prayer.rawValue] = value } }
        )
    }

    private func offsetText(_ value: Int) -> String {
        value == 0 ? "0" : String(format: "%+d %@", value, String(localized: "common.min"))
    }
}
