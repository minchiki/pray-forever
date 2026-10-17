import SwiftUI
import UIKit

/// Кнопки экрана в режиме тренировки (без будильника).
struct PracticeActions {
    let close: () -> Void
    let retry: () -> Void
}

/// Чтение суры вслух: каждое арабское слово с транскрипцией под ним, слова отмечаются по мере чтения.
/// Без `practice` — второй шаг задания будильника, с `practice` — тренировка.
struct RecitationView: View {
    let surah: Surah
    let practice: PracticeActions?

    @EnvironmentObject private var coordinator: AlarmCoordinator
    @StateObject private var session: RecitationSession
    @State private var completed = false
    /// Тренировка наизусть: непрочитанные слова скрыты.
    @State private var hideText = false

    private static let successDelay: UInt64 = 1_400_000_000

    init(surah: Surah, practice: PracticeActions? = nil) {
        self.surah = surah
        self.practice = practice
        // На тренировке тишина не наказывается.
        _session = StateObject(wrappedValue: RecitationSession(surah: surah, failsOnSilence: practice == nil))
    }

    private var tracker: RecitationTracker { session.tracker }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                // Панель закреплена снизу на своей подложке, а список прокручивается над ней и не залезает под неё.
                ayatList
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        RecitationStatusPanel(listener: session.listener,
                                              notice: session.notice,
                                              countdown: session.silenceCountdown,
                                              ayahText: ayahProgressText,
                                              showsDiagnostics: practice != nil)
                            .padding(.top, 8)
                            .background(Theme.background.ignoresSafeArea(edges: .bottom))
                            .overlay(alignment: .top) { Divider() }
                    }
            }
            if completed {
                resultScreen.transition(.opacity)
            }
        }
        .onAppear {
            session.onFinish = handle
            session.start()
        }
        .onDisappear { session.stop() }
    }

    // MARK: - Шапка

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                VStack(spacing: 2) {
                    Text(surah.localizedName)
                        .font(.headline)
                    Text(String(format: String(localized: "recitation.subtitle"), surah.number, surah.ayat.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let practice {
                    HStack {
                        Button(action: practice.close) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(Text("practice.close"))
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { hideText.toggle() }
                        } label: {
                            Label("practice.hide", systemImage: hideText ? "eye.slash" : "eye")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 10)
                                .frame(minHeight: 32)
                                .background(Capsule().fill(hideText ? RecitationTheme.accent.opacity(0.15)
                                                                    : Color(.tertiarySystemFill)))
                                .foregroundStyle(hideText ? RecitationTheme.accent : Color.primary)
                        }
                        .frame(minHeight: 44)
                        .accessibilityAddTraits(hideText ? .isSelected : [])
                    }
                }
            }
            ProgressView(value: tracker.progress)
                .tint(RecitationTheme.accent)
                .animation(.easeOut(duration: 0.25), value: tracker.progress)
                .accessibilityLabel(Text(ayahProgressText))
            if practice != nil {
                Text(LocalizedStringKey(hideText ? "practice.hide.on" : "practice.tapAyah"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var ayahProgressText: String {
        String(format: String(localized: "recitation.ayah"), tracker.currentAyah + 1, surah.ayat.count)
    }

    // MARK: - Аяты

    private var ayatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    if surah.showsBasmala { basmala }
                    ForEach(Array(surah.ayat.enumerated()), id: \.offset) { index, ayah in
                        AyahCard(ayah: ayah,
                                 states: tracker.ayahRanges[index].map(tracker.state(of:)),
                                 isCurrent: index == tracker.currentAyah && !tracker.isComplete,
                                 hidesUnread: hideText)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // На тренировке можно начать с любого аята.
                                guard practice != nil else { return }
                                UISelectionFeedbackGenerator().selectionChanged()
                                session.restart(fromAyah: index)
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: tracker.currentAyah) { ayah in
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(ayah, anchor: .center) }
            }
        }
    }

    /// Басмала перед сурой не проверяется.
    private var basmala: some View {
        RightToLeftFlow(spacing: 4, lineSpacing: 6, alignment: .center) {
            ForEach(Array(zip(Surah.basmala.arabicWords, Surah.basmala.transliterationWords).enumerated()),
                    id: \.offset) { _, pair in
                WordCell(arabic: pair.0, transliteration: pair.1, state: nil)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - Итог

    private var resultScreen: some View {
        let total = tracker.words.count
        let recognized = total - tracker.skipped.count
        return VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(RecitationTheme.accent)
            Text("verify.success")
                .font(.title2.weight(.semibold))
            Text(String(format: String(localized: "practice.result"), recognized, total))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if practice != nil, recognized < total {
                Text("practice.result.hint")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let practice {
                VStack(spacing: 8) {
                    Button(action: practice.retry) {
                        Text("practice.again")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .tint(RecitationTheme.accent)
                    Button("common.done", action: practice.close)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }

    private func handle(_ outcome: RecitationSession.Outcome) {
        switch outcome {
        case .completed:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { completed = true }
            guard practice == nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: Self.successDelay)
                coordinator.recitationCompleted()
            }
        case .silent:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            coordinator.recitationFailed()
        }
    }
}

// MARK: - Компоненты

enum RecitationTheme {
    static let arabicFontName = "AmiriQuran-Regular"
    static let accent = Color.blue
    static let skipped = Color.orange

    static func arabic(_ size: CGFloat) -> Font {
        .custom(arabicFontName, size: size, relativeTo: .title)
    }
}

/// Карточка аята: номер и слова справа налево, под каждым — его транскрипция.
private struct AyahCard: View {
    let ayah: Ayah
    let states: [RecitationTracker.WordState]
    let isCurrent: Bool
    let hidesUnread: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(ayah.number)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? RecitationTheme.accent : .secondary)
            RightToLeftFlow(spacing: 4, lineSpacing: 8, alignment: .trailing) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    WordCell(arabic: cell.arabic, transliteration: cell.transliteration, state: cell.state,
                             hidden: hidesUnread && (cell.state == .upcoming || cell.state == .current))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(RecitationTheme.accent, lineWidth: isCurrent ? 1.5 : 0)
        )
        .animation(.easeInOut(duration: 0.2), value: isCurrent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(ayah.transliteration))
    }

    private var cells: [(arabic: String, transliteration: String, state: RecitationTracker.WordState)] {
        let arabic = ayah.arabicWords
        let latin = ayah.transliterationWords
        return arabic.indices.map { i in
            (arabic[i], i < latin.count ? latin[i] : "", i < states.count ? states[i] : .upcoming)
        }
    }
}

/// Одно слово: арабский сверху, транскрипция под ним. `state == nil` — слово не проверяется (басмала).
private struct WordCell: View {
    let arabic: String
    let transliteration: String
    let state: RecitationTracker.WordState?
    var hidden = false

    var body: some View {
        VStack(spacing: 1) {
            Text(arabic)
                .font(RecitationTheme.arabic(26))
                .foregroundStyle(arabicColor)
            Text(transliteration)
                .font(.system(size: 11, weight: state == .current ? .semibold : .regular))
                .foregroundStyle(transliterationColor)
                .lineLimit(1)
        }
        .fixedSize()
        // Наизусть: слово скрыто серой плашкой того же размера, пока его не прочитают.
        .redacted(reason: hidden ? .placeholder : [])
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(RecitationTheme.accent.opacity(state == .current ? 0.12 : 0))
        )
        .animation(.easeOut(duration: 0.15), value: state)
    }

    private var arabicColor: Color {
        switch state {
        case nil, .current: return .primary
        case .read: return RecitationTheme.accent
        case .skipped: return RecitationTheme.skipped
        case .upcoming: return .secondary
        }
    }

    private var transliterationColor: Color {
        switch state {
        case .read: return RecitationTheme.accent.opacity(0.8)
        case .skipped: return RecitationTheme.skipped.opacity(0.8)
        case .current: return .primary
        case nil, .upcoming: return .secondary
        }
    }
}

/// Переносит элементы по строкам справа налево, как арабский текст.
private struct RightToLeftFlow: Layout {
    enum RowAlignment { case trailing, center }

    var spacing: CGFloat
    var lineSpacing: CGFloat
    var alignment: RowAlignment

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, maxWidth: bounds.width) {
            var x = alignment == .center ? bounds.midX + row.width / 2 : bounds.maxX
            for item in row.items {
                x -= item.size.width
                subviews[item.index].place(at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                                           proposal: ProposedViewSize(item.size))
                x -= spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.items.isEmpty, row.width + spacing + size.width > maxWidth {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

/// Нижняя панель: микрофон, подсказка, предупреждение о тишине, на тренировке — что услышано.
private struct RecitationStatusPanel: View {
    @ObservedObject var listener: RecitationListener
    let notice: String?
    let countdown: Int?
    let ayahText: String
    let showsDiagnostics: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                micIcon
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(ayahText)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let notice {
                Label(notice, systemImage: "arrow.counterclockwise")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(RecitationTheme.accent)
                    .transition(.opacity)
            }
            if showsDiagnostics { diagnostics }
            if let countdown {
                Label(String(format: String(localized: "recitation.silence"), countdown),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(RecitationTheme.skipped)
            }
            if listener.mode == .manual {
                Button("common.openSettings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.footnote.weight(.semibold))
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.2), value: countdown != nil)
        .animation(.easeInOut(duration: 0.2), value: notice)
    }

    @ViewBuilder
    private var micIcon: some View {
        if listener.mode == .starting {
            ProgressView().frame(width: 28, height: 28)
        } else {
            Image(systemName: listener.mode == .manual ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(listener.voiceActive ? Color.white : Color.secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(listener.voiceActive ? RecitationTheme.accent : Color(.tertiarySystemFill)))
                .scaleEffect(listener.voiceActive ? 1 + listener.level * 0.15 : 1)
                .animation(.easeOut(duration: 0.12), value: listener.level)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var diagnostics: some View {
        if listener.mode == .speech {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("recitation.heard")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                // Системный шрифт и одна строка: панель не меняет высоту, видны последние услышанные слова.
                Text(listener.transcript.isEmpty ? "—" : listener.transcript)
                    .font(.system(size: 15))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        if let problem = listener.problem {
            Text(problem)
                .font(.caption)
                .foregroundStyle(RecitationTheme.skipped)
        }
    }

    private var title: String {
        switch listener.mode {
        case .starting where listener.preparingModel: return String(localized: "recitation.status.preparing")
        case .starting: return String(localized: "recitation.status.starting")
        case .speech where listener.voiceActive: return String(localized: "recitation.status.listening")
        case .speech, .voice: return String(localized: "recitation.status.read")
        case .manual: return String(localized: "recitation.status.noMic")
        }
    }

    private var subtitle: String {
        switch listener.mode {
        case .starting where listener.preparingModel: return String(localized: "recitation.hint.preparing")
        case .starting: return String(localized: "recitation.hint.starting")
        case .speech: return String(localized: "recitation.hint.speech")
        case .voice: return String(localized: "recitation.hint.voice")
        case .manual: return String(localized: "recitation.hint.manual")
        }
    }
}
