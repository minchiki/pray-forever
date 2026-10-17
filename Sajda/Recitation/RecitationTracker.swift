import Foundation

/// Чистая логика проверки чтения: какое слово суры сейчас ожидается и что уже прочитано.
struct RecitationTracker {
    struct Word: Equatable {
        let display: String
        let key: String
        let ayah: Int
    }

    enum WordState: Equatable { case read, skipped, current, upcoming }

    /// На сколько слов вперёд можно «перепрыгнуть», если распознавание пропустило слово.
    static let lookahead = 2
    /// Точное совпадение надёжнее, поэтому для него окно шире — распознавание иногда теряет несколько слов подряд.
    static let exactLookahead = 5
    /// Голос слышен, а слово всё не распознаётся — засчитываем его, чтобы не застрять.
    static let stuckVoiceLimit: TimeInterval = 6
    /// Без распознавания речи слово засчитывается за это время звучания голоса.
    static let pacedSecondsPerWord: TimeInterval = 0.6
    /// Тишина дольше этого — будильник звонит снова.
    static let silenceLimit: TimeInterval = 30
    static let silenceWarning: TimeInterval = 15

    let surah: Surah
    let words: [Word]
    let ayahRanges: [Range<Int>]
    /// Слова басмалы в аль-Фатихе: по ханафитскому мазхабу её читают про себя, поэтому её можно пропустить.
    private let optionalPrefix: Int

    private(set) var position = 0
    private(set) var skipped: Set<Int> = []
    private(set) var silentTime: TimeInterval = 0
    private var voiceTimeOnWord: TimeInterval = 0
    /// Распознавание выдаёт весь текст текущей сессии, поэтому сопоставляем его с позиции начала сессии.
    private var sessionStart = 0
    private var sessionOffset = 0
    private var lastHeardCount = 0

    init(surah: Surah) {
        self.surah = surah
        var words: [Word] = []
        var ranges: [Range<Int>] = []
        for (index, ayah) in surah.ayat.enumerated() {
            let start = words.count
            words += ayah.arabic.split(separator: " ").map {
                Word(display: String($0), key: ArabicText.normalize(String($0)), ayah: index)
            }
            ranges.append(start..<words.count)
        }
        self.words = words
        self.ayahRanges = ranges
        self.optionalPrefix = surah == .fatiha ? ranges.first?.count ?? 0 : 0
    }

    var isComplete: Bool { position >= words.count }
    var isSilentTooLong: Bool { silentTime >= Self.silenceLimit }
    var currentAyah: Int { isComplete ? ayahRanges.count - 1 : words[position].ayah }
    var progress: Double { words.isEmpty ? 1 : Double(position) / Double(words.count) }

    func state(of index: Int) -> WordState {
        if index == position { return .current }
        if index > position { return .upcoming }
        return skipped.contains(index) ? .skipped : .read
    }

    /// Новая сессия распознавания начинается с пустого текста.
    mutating func beginSession() {
        sessionStart = position
        sessionOffset = 0
        lastHeardCount = 0
    }

    /// Обрабатывает распознанный текст текущей сессии. Возвращает true, если чтение продвинулось.
    @discardableResult
    mutating func hear(_ transcript: String) -> Bool {
        let heard = ArabicText.words(transcript)
        lastHeardCount = heard.count
        var cursor = sessionStart
        var missed: [Int] = []
        for word in heard.dropFirst(sessionOffset) {
            guard cursor < words.count else { break }
            let base = cursor < optionalPrefix ? optionalPrefix : cursor
            let fuzzyLimit = min(words.count - 1, base + Self.lookahead)
            let exactLimit = min(words.count - 1, base + Self.exactLookahead)
            // Точное совпадение важнее нечёткого: «الحمد» не должно засчитаться как «الرحمن».
            guard let hit = (cursor...exactLimit).first(where: { words[$0].key == word })
                ?? (cursor...fuzzyLimit).first(where: { ArabicText.matches(word, words[$0].key) }) else { continue }
            missed += Array(cursor..<hit)
            cursor = hit + 1
        }
        guard cursor > position else { return false }
        skipped.formUnion(missed.filter { $0 >= position && $0 >= optionalPrefix })
        position = cursor
        voiceTimeOnWord = 0
        silentTime = 0
        return true
    }

    /// - Parameters:
    ///   - voiceActive: в микрофоне сейчас слышен голос.
    ///   - paced: распознавания нет — слова засчитываются по времени звучания голоса.
    mutating func tick(_ dt: TimeInterval, voiceActive: Bool, paced: Bool) {
        guard !isComplete else { return }
        silentTime = voiceActive ? 0 : silentTime + dt
        guard voiceActive else { return }
        voiceTimeOnWord += dt
        let limit = paced ? Self.pacedSecondsPerWord : Self.stuckVoiceLimit
        guard voiceTimeOnWord >= limit else { return }
        if !paced { skipped.insert(position) }
        position += 1
        voiceTimeOnWord = 0
        // Уже распознанный текст не должен повторно сопоставляться с новой позиции.
        sessionStart = position
        sessionOffset = lastHeardCount
    }
}

/// Определяет, звучит ли голос: уровень заметно выше фонового шума.
struct VoiceActivityDetector {
    static let margin: Float = 10
    static let minimumLevel: Float = -50
    /// Голос держится активным ещё немного после паузы между словами.
    static let hangover: TimeInterval = 0.4
    /// Скорость, с которой оценка фона догоняет текущий уровень (доля в секунду).
    static let floorRiseRate: Float = 0.05

    private(set) var noiseFloor: Float?
    private(set) var isActive = false
    private var sinceVoice: TimeInterval = .infinity

    mutating func process(levelDB: Float, duration: TimeInterval) -> Bool {
        let floor = noiseFloor ?? levelDB
        let newFloor = levelDB < floor ? levelDB : floor + (levelDB - floor) * min(1, Self.floorRiseRate * Float(duration))
        noiseFloor = newFloor
        if levelDB > max(newFloor + Self.margin, Self.minimumLevel) {
            sinceVoice = 0
        } else {
            sinceVoice += duration
        }
        isActive = sinceVoice <= Self.hangover
        return isActive
    }
}
