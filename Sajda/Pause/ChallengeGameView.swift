import SwiftUI

/// Испытание из 10 раундов. Ошибка откатывает прогресс на 2 раунда.
struct ChallengeGameView: View {
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var challenge = PauseChallenge()
    @State private var rng = SystemRandomNumberGenerator()
    @State private var kinds: [ChallengeTask.Kind] = []
    @State private var task: ChallengeTask?
    @State private var roundID = UUID()
    @State private var showWrong = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                progressHeader
                if let task {
                    ChallengeRoundView(task: task, onResult: handle)
                        .id(roundID)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .background(Theme.background.ignoresSafeArea())
            .overlay(alignment: .bottom) { if showWrong { wrongBanner } }
            .navigationTitle(Text("pause.challenge.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel", action: onCancel)
                }
            }
        }
        .onAppear(perform: start)
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(format: String(localized: "pause.challenge.round"),
                            min(challenge.completed + 1, PauseChallenge.rounds), PauseChallenge.rounds))
                    .font(.headline)
                    .monospacedDigit()
                Spacer()
                if challenge.mistakes > 0 {
                    Text(String(format: String(localized: "pause.challenge.mistakes"), challenge.mistakes))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(challenge.completed), total: Double(PauseChallenge.rounds))
                .tint(Color.accentColor)
        }
    }

    private var wrongBanner: some View {
        Text(String(format: String(localized: "pause.challenge.wrong"), PauseChallenge.penalty))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.red.opacity(0.9), in: Capsule())
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func start() {
        guard kinds.isEmpty else { return }
        kinds = ChallengeGenerator.plan(rounds: PauseChallenge.rounds, using: &rng)
        nextTask()
    }

    private func nextTask() {
        let index = min(challenge.completed, kinds.count - 1)
        task = ChallengeGenerator.make(kinds[index], using: &rng)
        roundID = UUID()
    }

    private func handle(_ success: Bool) {
        if success {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            challenge.registerSuccess()
            if challenge.isFinished {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onComplete()
                return
            }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            challenge.registerFailure()
            withAnimation { showWrong = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { showWrong = false } }
        }
        nextTask()
    }
}

/// Отрисовка одного задания.
private struct ChallengeRoundView: View {
    let task: ChallengeTask
    let onResult: (Bool) -> Void

    var body: some View {
        switch task {
        case .math(let question, _):
            TextAnswerRound(prompt: "pause.task.math", display: question, keyboard: .numberPad,
                            task: task, onResult: onResult)
        case .memory(let digits):
            MemoryRound(digits: digits, task: task, onResult: onResult)
        case .order(let numbers):
            OrderRound(numbers: numbers, onResult: onResult)
        case .oddOneOut(let symbols, _):
            OddOneOutRound(symbols: symbols, task: task, onResult: onResult)
        case .stroop(let word, let ink, let options):
            StroopRound(word: word, ink: ink, options: options, task: task, onResult: onResult)
        case .code(let code):
            TextAnswerRound(prompt: "pause.task.code", display: code, keyboard: .asciiCapable,
                            task: task, onResult: onResult)
        }
    }
}

private struct RoundPrompt: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

private struct TextAnswerRound: View {
    let prompt: LocalizedStringKey
    let display: String
    let keyboard: UIKeyboardType
    let task: ChallengeTask
    let onResult: (Bool) -> Void

    @State private var answer = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 24) {
            RoundPrompt(text: prompt)
            Text(display)
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            AnswerField(text: $answer, keyboard: keyboard, focused: $focused, submit: submit)
        }
        .onAppear { focused = true }
    }

    private func submit() {
        guard !answer.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onResult(task.accepts(answer))
    }
}

private struct AnswerField: View {
    @Binding var text: String
    let keyboard: UIKeyboardType
    var focused: FocusState<Bool>.Binding
    let submit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            TextField("pause.answer", text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .focused(focused)
                .submitLabel(.done)
                .onSubmit(submit)
            Button(action: submit) {
                Text("pause.check").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
        }
    }
}

private struct MemoryRound: View {
    static let showSeconds = 3

    let digits: String
    let task: ChallengeTask
    let onResult: (Bool) -> Void

    @State private var remaining = MemoryRound.showSeconds
    @State private var answer = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 24) {
            if remaining > 0 {
                RoundPrompt(text: "pause.task.memory.show")
                Text(digits)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .kerning(6)
                Text("\(remaining)")
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                RoundPrompt(text: "pause.task.memory.enter")
                AnswerField(text: $answer, keyboard: .numberPad, focused: $focused) {
                    guard !answer.isEmpty else { return }
                    onResult(task.accepts(answer))
                }
            }
        }
        .task {
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                remaining -= 1
            }
            focused = true
        }
    }
}

private struct OrderRound: View {
    let numbers: [Int]
    let onResult: (Bool) -> Void

    @State private var next = 1
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(spacing: 20) {
            RoundPrompt(text: "pause.task.order")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(numbers, id: \.self) { number in
                    let done = number < next
                    Button {
                        tap(number)
                    } label: {
                        Text("\(number)")
                            .font(.title.weight(.semibold).monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(done ? Color.accentColor.opacity(0.18) : Theme.card,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(done ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(done)
                }
            }
        }
    }

    private func tap(_ number: Int) {
        guard number == next else { return onResult(false) }
        next += 1
        if next > numbers.count { onResult(true) }
    }
}

private struct OddOneOutRound: View {
    let symbols: [String]
    let task: ChallengeTask
    let onResult: (Bool) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(spacing: 20) {
            RoundPrompt(text: "pause.task.odd")
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(symbols.indices, id: \.self) { index in
                    Button { onResult(task.accepts(index: index)) } label: {
                        Text(symbols[index])
                            .font(.system(size: 30, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct StroopRound: View {
    let word: StroopColor
    let ink: StroopColor
    let options: [StroopColor]
    let task: ChallengeTask
    let onResult: (Bool) -> Void

    var body: some View {
        VStack(spacing: 28) {
            RoundPrompt(text: "pause.task.stroop")
            Text(word.localizedName.uppercased())
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .foregroundStyle(Self.color(ink))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.vertical, 12)
            VStack(spacing: 10) {
                ForEach(options, id: \.self) { option in
                    Button { onResult(task.accepts(color: option)) } label: {
                        Text(option.localizedName)
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    static func color(_ color: StroopColor) -> Color {
        switch color {
        case .red: return Color(red: 0.85, green: 0.16, blue: 0.16)
        case .green: return Color(red: 0.13, green: 0.6, blue: 0.27)
        case .blue: return Color(red: 0.15, green: 0.38, blue: 0.9)
        case .yellow: return Color(red: 0.93, green: 0.73, blue: 0.0)
        case .purple: return Color(red: 0.55, green: 0.25, blue: 0.8)
        case .orange: return Color(red: 0.95, green: 0.5, blue: 0.1)
        }
    }
}
