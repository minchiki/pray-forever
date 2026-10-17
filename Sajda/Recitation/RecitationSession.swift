import Foundation
import UIKit

/// Связывает микрофон с проверкой чтения и сообщает, чем всё закончилось.
@MainActor
final class RecitationSession: ObservableObject {
    enum Outcome { case completed, silent }

    @Published private(set) var tracker: RecitationTracker
    /// Короткое сообщение над панелью (например, «прочитайте ещё раз»).
    @Published private(set) var notice: String?
    let listener = RecitationListener()
    var onFinish: ((Outcome) -> Void)?

    /// В будильнике суру нужно действительно прочитать: если распознано меньше — читать заново.
    static let minRecognizedRatio = 0.7
    /// Больше стольких повторов не требуем — вдруг микрофон или распознавание плохо слышат именно этого человека.
    static let maxStrictRetries = 2
    private static let tickInterval: TimeInterval = 0.1
    private static let noticeDuration: UInt64 = 5_000_000_000
    private var timer: Timer?
    private var lastTick = Date()
    private var finished = false
    private var strictRetries = 0
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

    /// Начать с выбранного аята (на тренировке — нажатием на аят).
    func restart(fromAyah ayah: Int) {
        guard !finished else { return }
        tracker.restart(fromAyah: ayah)
    }

    private func show(notice text: String) {
        notice = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.noticeDuration)
            if self?.notice == text { self?.notice = nil }
        }
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
            // Слова засчитаны по времени, а не распознаны — похоже, суру не читали. В будильнике — заново.
            if failsOnSilence, listener.mode == .speech, strictRetries < Self.maxStrictRetries,
               tracker.recognizedRatio < Self.minRecognizedRatio {
                strictRetries += 1
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                tracker.restart(fromAyah: 0)
                show(notice: String(localized: "recitation.retry"))
                return
            }
            outcome = .completed
        } else if failsOnSilence, tracker.isSilentTooLong || (listener.mode == .speech && tracker.isStalled) {
            outcome = .silent
        } else {
            return
        }
        finished = true
        stop()
        onFinish?(outcome)
    }
}
