import AVFoundation
import Speech

/// Микрофон и распознавание арабской речи. Без распознавания — только детектор голоса, без микрофона — ручной режим.
@MainActor
final class RecitationListener: ObservableObject {
    enum Mode: Equatable {
        case starting
        /// Слова сверяются с распознанной речью.
        case speech
        /// Распознавание арабского недоступно — засчитывается звучание голоса.
        case voice
        /// Нет доступа к микрофону.
        case manual
    }

    @Published private(set) var mode: Mode = .starting
    /// Громкость для индикатора, 0...1.
    @Published private(set) var level: Double = 0
    @Published private(set) var voiceActive = false

    var onTranscript: ((String) -> Void)?
    /// Началась новая сессия распознавания (текст начинается заново).
    var onNewSession: (() -> Void)?

    private static let locale = Locale(identifier: "ar-SA")
    private static let maxFailuresBeforeFallback = 3
    private static let restartDelay: UInt64 = 300_000_000

    private let engine = AVAudioEngine()
    private let feed = SpeechFeed()
    private let recognizer = SFSpeechRecognizer(locale: RecitationListener.locale)
    private var task: SFSpeechRecognitionTask?
    private var detector = VoiceActivityDetector()
    private var isRunning = false
    private var tapInstalled = false
    private var everHeard = false
    private var failures = 0
    private var configObserver: NSObjectProtocol?

    /// Запрашивает микрофон и распознавание речи (можно вызвать заранее, при настройке).
    static func requestPermissions() async -> (microphone: Bool, speech: Bool) {
        let microphone: Bool
        if #available(iOS 17.0, *) {
            microphone = await AVAudioApplication.requestRecordPermission()
        } else {
            microphone = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
            }
        }
        guard microphone else { return (false, false) }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        return (true, speech)
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        let permissions = await Self.requestPermissions()
        guard isRunning else { return }
        guard permissions.microphone, startEngine() else {
            mode = .manual
            return
        }
        observeConfigurationChanges()
        if permissions.speech, let recognizer, recognizer.isAvailable {
            mode = .speech
            startRecognition()
        } else {
            mode = .voice
        }
    }

    func stop() {
        isRunning = false
        task?.cancel()
        task = nil
        feed.request = nil
        if engine.isRunning { engine.stop() }
        removeTap()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        voiceActive = false
        level = 0
    }

    // MARK: - Микрофон

    private func startEngine() -> Bool {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        let tap = Self.makeTap(feed: feed) { [weak self] db, duration in
            Task { @MainActor in self?.handle(levelDB: db, duration: duration) }
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: tap)
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
            return true
        } catch {
            removeTap()
            return false
        }
    }

    private func removeTap() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    /// Смена маршрута (наушники, звонок) останавливает движок — перезапускаем.
    private func observeConfigurationChanges() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.removeTap()
                if !self.startEngine() { self.mode = .manual }
            }
        }
    }

    private func handle(levelDB: Float, duration: TimeInterval) {
        guard isRunning else { return }
        let active = detector.process(levelDB: levelDB, duration: duration)
        if active != voiceActive { voiceActive = active }
        let newLevel = Double(max(0, min(1, (levelDB + 60) / 50)))
        // Индикатору не нужна каждая порция звука — перерисовываем при заметном изменении.
        if abs(newLevel - level) > 0.03 { level = newLevel }
    }

    /// Блок вызывается на аудиопотоке, поэтому создаётся вне главного актора.
    nonisolated private static func makeTap(feed: SpeechFeed,
                                            onLevel: @escaping @Sendable (Float, TimeInterval) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            feed.append(buffer)
            onLevel(decibels(buffer), Double(buffer.frameLength) / buffer.format.sampleRate)
        }
    }

    nonisolated private static func decibels(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return -100 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += samples[i] * samples[i] }
        let rms = (sum / Float(count)).squareRoot()
        return rms > 0 ? max(-100, 20 * log10(rms)) : -100
    }

    // MARK: - Распознавание

    private func startRecognition() {
        guard isRunning, let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        feed.request = request
        onNewSession?()
        task = Self.recognize(with: recognizer, request: request) { [weak self] text, isFinal, failed in
            Task { @MainActor in
                self?.handleRecognition(text: text, isFinal: isFinal, failed: failed, request: request)
            }
        }
    }

    /// Ответы распознавания приходят на фоновой очереди.
    nonisolated private static func recognize(
        with recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onResult: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            onResult(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    private func handleRecognition(text: String?, isFinal: Bool, failed: Bool,
                                   request: SFSpeechAudioBufferRecognitionRequest) {
        // Ответы от старой, уже заменённой сессии игнорируем.
        guard isRunning, feed.request === request else { return }
        if let text, !text.isEmpty {
            everHeard = true
            failures = 0
            onTranscript?(text)
        }
        guard isFinal || failed else { return }
        task = nil
        if failed, !everHeard { failures += 1 }
        // Распознавание ни разу не сработало — переходим на детектор голоса.
        if failures >= Self.maxFailuresBeforeFallback {
            feed.request = nil
            mode = .voice
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.restartDelay)
            self.startRecognition()
        }
    }
}

/// Передаёт аудиобуферы из потока микрофона в текущий запрос распознавания.
private final class SpeechFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var current: SFSpeechAudioBufferRecognitionRequest?

    var request: SFSpeechAudioBufferRecognitionRequest? {
        get { lock.withLock { current } }
        set {
            let old = lock.withLock { () -> SFSpeechAudioBufferRecognitionRequest? in
                let old = current
                current = newValue
                return old
            }
            if old !== newValue { old?.endAudio() }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }
}
