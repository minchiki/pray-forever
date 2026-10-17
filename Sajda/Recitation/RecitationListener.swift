import AVFoundation
import Speech

/// Микрофон и распознавание чтения.
/// Основной способ — модель Tarteel на устройстве (`QuranTranscriber`), запасной — распознаватель Apple,
/// без распознавания — детектор голоса, без микрофона — ручной режим.
@MainActor
final class RecitationListener: ObservableObject {
    enum Mode: Equatable {
        case starting
        /// Слова сверяются с распознанной речью.
        case speech
        /// Распознавание недоступно — засчитывается звучание голоса.
        case voice
        /// Нет доступа к микрофону.
        case manual
    }

    @Published private(set) var mode: Mode = .starting
    /// Модель распознавания Корана загружается (в первый раз — до полуминуты).
    @Published private(set) var preparingModel = false
    /// Громкость для индикатора, 0...1.
    @Published private(set) var level: Double = 0
    @Published private(set) var voiceActive = false
    /// Что распознаватель услышал в текущей сессии (показывается на тренировке).
    @Published private(set) var transcript = ""
    /// Почему распознавание не работает.
    @Published private(set) var problem: String?

    /// Ожидаемые фразы (текст суры) — подсказка распознавателю Apple.
    var contextualStrings: [String] = []
    /// Уже прочитанный текст перед текущим отрезком — модель Tarteel точнее продолжает его.
    var promptContext: (() -> String)?
    var onTranscript: ((String) -> Void)?
    /// Началась новая сессия распознавания (текст начинается заново).
    var onNewSession: (() -> Void)?

    // Распознаватель Apple (запасной).
    private static let locale = Locale(identifier: "ar-SA")
    private static let maxFailuresBeforeFallback = 4
    /// Ошибки, которые означают «человек молчал» или «сессию отменили», а не поломку.
    private static let benignErrorCodes: Set<Int> = [203, 216, 301, 1110]
    private static let restartDelay: UInt64 = 300_000_000

    // Модель Tarteel: каждые 0.7 с распознаём весь текущий отрезок записи.
    private static let quranStepInterval: UInt64 = 700_000_000
    /// Новый отрезок: после паузы, если записано больше 8 с, и всегда после 24 с (модель видит максимум 30 с).
    private static let segmentPauseCut = 8.0
    private static let segmentMaxLength = 24.0
    private static let minNewAudio = QuranTranscriber.sampleRate / 4

    private let engine = AVAudioEngine()
    private let feed = SpeechFeed()
    private let collector = SampleCollector()
    private let recognizer = SFSpeechRecognizer(locale: RecitationListener.locale)
    private var task: SFSpeechRecognitionTask?
    private var quranLoop: Task<Void, Never>?
    private var detector = VoiceActivityDetector()
    private var isRunning = false
    private var tapInstalled = false
    private var everHeard = false
    private var failures = 0
    private var useOnDevice = false
    private var segmentHasVoice = false
    private var transcribedUpTo = 0
    private var configObserver: NSObjectProtocol?

    /// Запрашивает разрешения заранее, при настройке. Распознавание речи Apple нужно, только если нет модели Tarteel.
    static func requestPermissions() async -> (microphone: Bool, speech: Bool) {
        let microphone = await requestMicrophone()
        guard microphone else { return (false, false) }
        guard QuranTranscriber.modelURL == nil else { return (true, false) }
        return (true, await requestSpeech())
    }

    private static func requestMicrophone() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    private static func requestSpeech() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        let microphone = await Self.requestMicrophone()
        guard isRunning else { return }
        guard microphone, startEngine() else {
            mode = .manual
            return
        }
        observeConfigurationChanges()

        preparingModel = QuranTranscriber.modelURL != nil
        let quranReady = await QuranTranscriber.shared.prepare()
        preparingModel = false
        guard isRunning else { return }
        if quranReady {
            startQuranRecognition()
            return
        }

        let speech = await Self.requestSpeech()
        guard isRunning else { return }
        if speech, let recognizer, recognizer.isAvailable {
            mode = .speech
            startRecognition()
        } else {
            problem = speech
                ? String(localized: "recitation.problem.unavailable")
                : String(localized: "recitation.problem.denied")
            mode = .voice
        }
    }

    func stop() {
        isRunning = false
        quranLoop?.cancel()
        quranLoop = nil
        collector.isEnabled = false
        collector.reset()
        task?.cancel()
        task = nil
        feed.request = nil
        if engine.isRunning { engine.stop() }
        removeTap()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        voiceActive = false
        level = 0
        transcript = ""
    }

    // MARK: - Микрофон

    private func startEngine() -> Bool {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        let tap = Self.makeTap(feed: feed, collector: collector) { [weak self] db, duration in
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
        if active { segmentHasVoice = true }
        let newLevel = Double(max(0, min(1, (levelDB + 60) / 50)))
        // Индикатору не нужна каждая порция звука — перерисовываем при заметном изменении.
        if abs(newLevel - level) > 0.03 { level = newLevel }
    }

    /// Блок вызывается на аудиопотоке, поэтому создаётся вне главного актора.
    nonisolated private static func makeTap(feed: SpeechFeed, collector: SampleCollector,
                                            onLevel: @escaping @Sendable (Float, TimeInterval) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            feed.append(buffer)
            collector.append(buffer)
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

    // MARK: - Модель Tarteel

    private func startQuranRecognition() {
        mode = .speech
        problem = nil
        collector.reset()
        collector.isEnabled = true
        segmentHasVoice = false
        transcribedUpTo = 0
        onNewSession?()
        quranLoop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.quranStepInterval)
                guard let self, self.isRunning else { return }
                await self.quranStep()
            }
        }
    }

    private func quranStep() async {
        let end = collector.count
        guard segmentHasVoice, end - transcribedUpTo >= Self.minNewAudio else { return }
        let samples = collector.prefix(end)
        let text = await QuranTranscriber.shared.transcribe(samples, context: promptContext?() ?? "")
        guard isRunning else { return }
        transcribedUpTo = end
        if let text, !ArabicText.words(text).isEmpty {
            everHeard = true
            transcript = text
            onTranscript?(text)
        }
        let seconds = Double(end) / Double(QuranTranscriber.sampleRate)
        if seconds >= Self.segmentMaxLength || (seconds >= Self.segmentPauseCut && !voiceActive) {
            // Отрезок распознан целиком — дальше новый, с текущей позиции в суре.
            collector.discard(prefix: end)
            transcribedUpTo = 0
            segmentHasVoice = voiceActive
            onNewSession?()
        }
    }

    // MARK: - Распознаватель Apple (запасной)

    private func startRecognition() {
        guard isRunning, let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        request.taskHint = .dictation
        request.contextualStrings = contextualStrings
        request.requiresOnDeviceRecognition = useOnDevice && recognizer.supportsOnDeviceRecognition
        feed.request = request
        transcript = ""
        onNewSession?()
        task = Self.recognize(with: recognizer, request: request) { [weak self] text, isFinal, error in
            Task { @MainActor in
                self?.handleRecognition(text: text, isFinal: isFinal, error: error, request: request)
            }
        }
    }

    struct RecognitionError: Sendable {
        let code: Int
        let message: String
    }

    /// Ответы распознавания приходят на фоновой очереди.
    nonisolated private static func recognize(
        with recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onResult: @escaping @Sendable (String?, Bool, RecognitionError?) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let failure = error.map { RecognitionError(code: ($0 as NSError).code, message: $0.localizedDescription) }
            onResult(result?.bestTranscription.formattedString, result?.isFinal ?? false, failure)
        }
    }

    private func handleRecognition(text: String?, isFinal: Bool, error: RecognitionError?,
                                   request: SFSpeechAudioBufferRecognitionRequest) {
        // Ответы от старой, уже заменённой сессии игнорируем.
        guard isRunning, feed.request === request else { return }
        if let text, !text.isEmpty {
            everHeard = true
            failures = 0
            problem = nil
            transcript = text
            onTranscript?(text)
        }
        guard isFinal || error != nil else { return }
        task = nil
        if let error, !everHeard, !Self.benignErrorCodes.contains(error.code) {
            failures += 1
            problem = "\(error.message) (\(error.code))"
            // Сервер недоступен (нет интернета) — пробуем на устройстве, и наоборот.
            if recognizer?.supportsOnDeviceRecognition == true { useOnDevice.toggle() }
        }
        // Распознавание так и не заработало — переходим на детектор голоса.
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

/// Передаёт аудиобуферы из потока микрофона в текущий запрос распознавания Apple.
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

/// Копит звук с микрофона в формате модели Tarteel: 16 кГц, моно, Float.
private final class SampleCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var enabled = false
    /// Конвертер трогается только из аудиопотока.
    private var converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: Double(QuranTranscriber.sampleRate),
                                             channels: 1, interleaved: false)

    var isEnabled: Bool {
        get { lock.withLock { enabled } }
        set { lock.withLock { enabled = newValue } }
    }

    var count: Int { lock.withLock { samples.count } }

    func prefix(_ end: Int) -> [Float] {
        lock.withLock { Array(samples.prefix(end)) }
    }

    func discard(prefix end: Int) {
        lock.withLock { samples.removeFirst(min(end, samples.count)) }
    }

    func reset() {
        lock.withLock { samples.removeAll() }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard isEnabled, let outputFormat, buffer.frameLength > 0 else { return }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
        }
        guard let converter else { return }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = output.floatChannelData?[0], output.frameLength > 0 else { return }
        let chunk = Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
        lock.withLock { samples.append(contentsOf: chunk) }
    }
}
