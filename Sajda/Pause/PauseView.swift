import SwiftUI

/// Временное отключение всей системы. Включается только после испытания, снимается сразу.
struct PauseView: View {
    enum Duration: Int, CaseIterable, Identifiable {
        case hour1 = 1, hours3 = 3, hours12 = 12, day1 = 24, days3 = 72, days7 = 168

        var id: Int { rawValue }
        var interval: TimeInterval { TimeInterval(rawValue) * 3600 }
        var localizedName: String { NSLocalizedString("pause.duration.\(rawValue)", comment: "") }
    }

    @EnvironmentObject private var coordinator: AlarmCoordinator
    @EnvironmentObject private var store: SettingsStore
    @State private var duration: Duration = .hours3
    @State private var showGame = false

    var body: some View {
        Form {
            if let until = store.settings.activePause() {
                activeSection(until: until)
            } else {
                setupSection
            }
        }
        .navigationTitle(Text("pause.title"))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showGame) {
            ChallengeGameView(
                onComplete: {
                    coordinator.pause(for: duration.interval)
                    showGame = false
                },
                onCancel: { showGame = false }
            )
        }
    }

    private func activeSection(until: Date) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("pause.active", systemImage: "pause.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                Text(String(format: String(localized: "pause.until"),
                            until.formatted(date: .abbreviated, time: .shortened)))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            Button("pause.resume") { coordinator.resume() }
                .font(.headline)
        } footer: {
            Text("pause.active.footer")
        }
    }

    private var setupSection: some View {
        Section {
            Picker("pause.duration", selection: $duration) {
                ForEach(Duration.allCases) { Text($0.localizedName).tag($0) }
            }
            Button("pause.start") { showGame = true }
                .font(.headline)
        } footer: {
            Text(String(format: String(localized: "pause.footer"), PauseChallenge.rounds, PauseChallenge.penalty))
        }
    }
}

/// Плашка на главном экране, пока система на паузе.
struct PauseBanner: View {
    let until: Date
    let resume: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pause.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("pause.active").font(.headline)
                Text(String(format: String(localized: "pause.until"),
                            until.formatted(date: .abbreviated, time: .shortened)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("pause.resume.short", action: resume)
                .buttonStyle(.bordered)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}
