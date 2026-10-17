import Foundation

/// Связывает микрофон с проверкой чтения и сообщает, чем всё закончилось.
@MainActor
final class RecitationSession: ObservableObject {
    enum Outcome { case completed, silent }

    @Published private(set) var tracker: RecitationTracker
    let listener = RecitationListener()
    var onFinish: ((Outcome) -> Void)?

    private static let tickInterval: TimeInterval = 0.1
    private var timer: Timer?
    private var lastTick = Date()
    private var finished = false
    private let failsOnSilence: Bool

    init(surah: Surah, failsOnSilence: Bool = true) {
        tracker = RecitationTracker(surah: surah)
        self.failsOnSilence = failsOnSilence
    }

    func start() {
        guard timer == nil, !finished else { return }
        listener.contextualStrings = tracker.surah.ayat.map { ArabicText.words($0.arabic).joined(separator: " ") }
        listener.onNewSession = { [weak self] in self?.tracker.beginSession() }
        listener.onTranscript = { [weak self] text in
            guard let self, self.tracker.hear(text) else { return }
            self.checkFinished()
        }
        Task { await listener.start() }
        lastTick = Date()
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        listener.stop()
    }

    /// Секунды до повторного звонка, если человек замолчал (nil — предупреждать рано).
    var silenceCountdown: Int? {
        guard failsOnSilence, tracker.silentTime >= RecitationTracker.silenceWarning else { return nil }
        return max(0, Int((RecitationTracker.silenceLimit - tracker.silentTime).rounded(.up)))
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        switch listener.mode {
        case .starting:
            return
        case .manual:
            tracker.tick(dt, voiceActive: true, paced: true)
        case .voice:
            tracker.tick(dt, voiceActive: listener.voiceActive, paced: true)
        case .speech:
            tracker.tick(dt, voiceActive: listener.voiceActive, paced: false)
        }
        checkFinished()
    }

    private func checkFinished() {
        guard !finished else { return }
        let outcome: Outcome
        if tracker.isComplete {
            outcome = .completed
        } else if failsOnSilence, tracker.isSilentTooLong {
            outcome = .silent
        } else {
            return
        }
        finished = true
        stop()
        onFinish?(outcome)
    }
}
