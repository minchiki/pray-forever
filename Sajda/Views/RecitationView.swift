import SwiftUI
import UIKit

/// Кнопки экрана в режиме тренировки (без будильника).
struct PracticeActions {
    let close: () -> Void
    let retry: () -> Void
}

/// Чтение суры вслух. Арабский текст с подсветкой слов и транскрипция под ним.
/// Без `practice` — второй шаг задания будильника, с `practice` — тренировка.
struct RecitationView: View {
    let surah: Surah
    let practice: PracticeActions?

    @EnvironmentObject private var coordinator: AlarmCoordinator
    @StateObject private var session: RecitationSession
    @State private var completed = false

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
            RecitationTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ayatList
                RecitationStatusPanel(listener: session.listener,
                                      countdown: session.silenceCountdown,
                                      ayahText: ayahProgressText,
                                      showsDiagnostics: practice != nil)
            }
            if let practice {
                closeButton(practice.close)
            }
            if completed {
                if let practice { practiceResult(practice) } else { successOverlay }
            }
        }
        .statusBarHidden()
        .onAppear {
            session.onFinish = handle
            session.start()
        }
        .onDisappear { session.stop() }
    }

    // MARK: - Шапка

    private var header: some View {
        VStack(spacing: 6) {
            Text(String(format: String(localized: "recitation.subtitle"), surah.number, surah.ayat.count))
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(RecitationTheme.gold)
            Text(surah.arabicName)
                .font(RecitationTheme.arabic(40))
                .foregroundStyle(.white)
            Text(surah.localizedName)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
            progressBar
                .padding(.top, 10)
            legend
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(RecitationTheme.gold)
                    .frame(width: proxy.size.width * tracker.progress)
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.25), value: tracker.progress)
        .accessibilityElement()
        .accessibilityLabel(Text(ayahProgressText))
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: RecitationTheme.read, text: "recitation.legend.read")
            legendItem(color: RecitationTheme.skipped, text: "recitation.legend.skipped")
            legendItem(color: .white.opacity(0.42), text: "recitation.legend.next")
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.6))
    }

    private func legendItem(color: Color, text: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }

    private var ayahProgressText: String {
        String(format: String(localized: "recitation.ayah"), tracker.currentAyah + 1, surah.ayat.count)
    }

    // MARK: - Аяты

    private var ayatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    if surah.showsBasmala { basmala }
                    ForEach(Array(surah.ayat.enumerated()), id: \.offset) { index, ayah in
                        AyahCard(ayah: ayah,
                                 states: tracker.ayahRanges[index].map(tracker.state(of:)),
                                 isCurrent: index == tracker.currentAyah && !tracker.isComplete,
                                 isDone: index < tracker.currentAyah || tracker.isComplete)
                            .id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: tracker.currentAyah) { ayah in
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(ayah, anchor: .center) }
            }
        }
    }

    /// Басмала перед сурой: не проверяется, поэтому без подсветки.
    private var basmala: some View {
        RightToLeftFlow(spacing: 6, lineSpacing: 6) {
            ForEach(Array(zip(Surah.basmala.arabicWords, Surah.basmala.transliterationWords).enumerated()),
                    id: \.offset) { _, pair in
                WordCell(arabic: pair.0, transliteration: pair.1, state: nil, arabicSize: 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func closeButton(_ action: @escaping () -> Void) -> some View {
        VStack {
            HStack {
                Button(action: action) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("practice.close"))
                Spacer()
            }
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Итог

    private func practiceResult(_ practice: PracticeActions) -> some View {
        let total = tracker.words.count
        let recognized = total - tracker.skipped.count
        return VStack(spacing: 16) {
            Image(systemName: recognized == total ? "checkmark.seal.fill" : "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(RecitationTheme.read)
            Text("بَارَكَ اللَّهُ فِيكَ")
                .font(RecitationTheme.arabic(30))
                .foregroundStyle(RecitationTheme.gold)
            Text(String(format: String(localized: "practice.result"), recognized, total))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            if recognized < total {
                Text("practice.result.hint")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.65))
            }
            VStack(spacing: 10) {
                Button(action: practice.retry) {
                    Label("practice.again", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                .tint(RecitationTheme.gold)
                .foregroundStyle(.black)
                Button("common.done", action: practice.close)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.8).ignoresSafeArea())
        .transition(.opacity)
    }

    private var successOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(RecitationTheme.read)
            Text("بَارَكَ اللَّهُ فِيكَ")
                .font(RecitationTheme.arabic(30))
                .foregroundStyle(RecitationTheme.gold)
            Text("verify.success")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.75).ignoresSafeArea())
        .transition(.opacity)
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
    static let gold = Color(red: 0.84, green: 0.72, blue: 0.42)
    static let read = Color(red: 0.55, green: 0.86, blue: 0.66)
    static let skipped = Color(red: 0.96, green: 0.68, blue: 0.33)
    static let background = LinearGradient(
        colors: [Color(red: 0.05, green: 0.21, blue: 0.16), Color(red: 0.02, green: 0.07, blue: 0.06)],
        startPoint: .top, endPoint: .bottom
    )

    static func arabic(_ size: CGFloat) -> Font {
        .custom(arabicFontName, size: size, relativeTo: .title)
    }

    /// Восточно-арабские цифры для номеров аятов.
    static func arabicDigits(_ number: Int) -> String {
        let digits = Array("٠١٢٣٤٥٦٧٨٩")
        return String(String(number).compactMap { $0.wholeNumberValue.map { digits[$0] } })
    }
}

/// Карточка аята: номер в восьмиконечной звезде и слова справа налево, под каждым — его транскрипция.
private struct AyahCard: View {
    let ayah: Ayah
    let states: [RecitationTracker.WordState]
    let isCurrent: Bool
    let isDone: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AyahNumberBadge(number: ayah.number, highlighted: isCurrent || isDone)
            RightToLeftFlow(spacing: 6, lineSpacing: 10) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    WordCell(arabic: cell.arabic, transliteration: cell.transliteration,
                             state: cell.state, arabicSize: 28)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(isCurrent ? 0.09 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(RecitationTheme.gold.opacity(isCurrent ? 0.55 : 0), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.25), value: isCurrent)
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
    let arabicSize: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            Text(arabic)
                .font(RecitationTheme.arabic(arabicSize))
                .foregroundStyle(arabicColor)
            Text(transliteration)
                .font(.system(size: 12, weight: state == .current ? .semibold : .regular))
                .foregroundStyle(transliterationColor)
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(state == .current ? 0.14 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(RecitationTheme.gold.opacity(state == .current ? 0.6 : 0), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.2), value: state)
    }

    private var arabicColor: Color {
        switch state {
        case nil: return RecitationTheme.gold
        case .read: return RecitationTheme.read
        case .skipped: return RecitationTheme.skipped
        case .current: return .white
        case .upcoming: return .white.opacity(0.42)
        }
    }

    private var transliterationColor: Color {
        switch state {
        case nil: return .white.opacity(0.5)
        case .read: return RecitationTheme.read.opacity(0.8)
        case .skipped: return RecitationTheme.skipped.opacity(0.8)
        case .current: return .white.opacity(0.95)
        case .upcoming: return .white.opacity(0.35)
        }
    }
}

/// Переносит элементы по строкам справа налево, как арабский текст.
private struct RightToLeftFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, maxWidth: bounds.width) {
            var x = bounds.maxX
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
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty, needed > maxWidth {
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

private struct AyahNumberBadge: View {
    let number: Int
    let highlighted: Bool

    var body: some View {
        ZStack {
            ForEach([0.0, 45.0], id: \.self) { angle in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(RecitationTheme.gold.opacity(highlighted ? 1 : 0.45), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(angle))
            }
            Text(RecitationTheme.arabicDigits(number))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(highlighted ? 1 : 0.6))
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}

/// Нижняя панель: индикатор микрофона, подсказка и предупреждение о тишине.
private struct RecitationStatusPanel: View {
    @ObservedObject var listener: RecitationListener
    let countdown: Int?
    let ayahText: String
    /// На тренировке видно, что именно слышит распознаватель и почему он не работает.
    let showsDiagnostics: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                LevelBars(level: listener.level, active: listener.voiceActive && listener.mode != .manual)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.footnote).opacity(0.7)
                }
                Spacer(minLength: 0)
                Text(ayahText)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(RecitationTheme.gold)
            }
            if showsDiagnostics { diagnostics }
            if let countdown {
                Label(String(format: String(localized: "recitation.silence"), countdown),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(RecitationTheme.skipped)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
            if listener.mode == .manual {
                Button("common.openSettings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.footnote.weight(.semibold))
                .frame(minHeight: 44)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .animation(.easeInOut(duration: 0.2), value: countdown != nil)
    }

    @ViewBuilder
    private var diagnostics: some View {
        if listener.mode == .speech {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("recitation.heard")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text(listener.transcript.isEmpty ? "—" : String(listener.transcript.suffix(80)))
                    .font(RecitationTheme.arabic(18))
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        if let problem = listener.problem {
            Text(problem)
                .font(.caption)
                .foregroundStyle(RecitationTheme.skipped)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var title: String {
        switch listener.mode {
        case .starting: return String(localized: "recitation.status.starting")
        case .speech where listener.voiceActive: return String(localized: "recitation.status.listening")
        case .speech: return String(localized: "recitation.status.read")
        case .voice: return String(localized: "recitation.status.read")
        case .manual: return String(localized: "recitation.status.noMic")
        }
    }

    private var subtitle: String {
        switch listener.mode {
        case .starting: return String(localized: "recitation.hint.starting")
        case .speech: return String(localized: "recitation.hint.speech")
        case .voice: return String(localized: "recitation.hint.voice")
        case .manual: return String(localized: "recitation.hint.manual")
        }
    }
}

private struct LevelBars: View {
    let level: Double
    let active: Bool

    private static let weights: [Double] = [0.5, 0.8, 1.0, 0.75, 0.45]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Self.weights.indices, id: \.self) { index in
                Capsule()
                    .fill(active ? RecitationTheme.read : Color.white.opacity(0.35))
                    .frame(width: 4, height: 6 + 22 * level * Self.weights[index])
            }
        }
        .frame(width: 32, height: 30)
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }
}
