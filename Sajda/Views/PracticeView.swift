import SwiftUI

/// Тренировка: прочитать любую суру вслух и проверить распознавание, без будильника.
struct PracticeView: View {
    @EnvironmentObject private var coordinator: AlarmCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Surah?
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Surah.allCases) { surah in
                        Button { start(surah) } label: { SurahRow(surah: surah) }
                    }
                } footer: {
                    Text("practice.footer")
                }
            }
            .navigationTitle(Text("practice.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .fullScreenCover(item: $selected, onDismiss: coordinator.endPractice) { surah in
            RecitationView(surah: surah,
                           practice: PracticeActions(close: { selected = nil }, retry: { attempt += 1 }))
                .id(attempt)
                .environmentObject(coordinator)
        }
    }

    private func start(_ surah: Surah) {
        coordinator.beginPractice()
        attempt = 0
        selected = surah
    }
}

private struct SurahRow: View {
    let surah: Surah

    var body: some View {
        HStack(spacing: 14) {
            Text("\(surah.number)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(RecitationTheme.accent)
                .frame(width: 36, height: 36)
                .background(Circle().fill(RecitationTheme.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(surah.localizedName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(String(format: String(localized: "practice.ayat"), surah.ayat.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(surah.arabicName)
                .font(RecitationTheme.arabic(24))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
