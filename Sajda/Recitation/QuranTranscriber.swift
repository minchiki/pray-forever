import Foundation
import WhisperKit

/// Распознавание чтения Корана моделью Tarteel (Whisper base, дообучен на чтении Корана), полностью на устройстве.
/// Модель кладётся в приложение при сборке (см. .github/workflows/build.yml).
///
/// Модель, обученная только на Коране, на любую речь пытается ответить аятом. Поэтому каждое слово
/// проходит проверку уверенности: слова, в которых модель не уверена, отбрасываются.
actor QuranTranscriber {
    static let shared = QuranTranscriber()
    static let sampleRate = 16_000

    private static let modelFolderName = "QuranModel"
    /// Слово засчитывается, только если модель уверена в нём хотя бы на столько (средняя вероятность токенов).
    static let minWordProbability: Float = 0.5
    /// Отрезок целиком отбрасывается, если модель считает его тишиной или в среднем не уверена.
    static let maxNoSpeechProbability: Float = 0.5
    static let minAverageLogProb: Float = -0.8
    static let maxCompressionRatio: Float = 2.4

    private var whisper: WhisperKit?
    /// WhisperKit не Sendable, поэтому сам объект живёт только внутри актора, наружу — лишь результат загрузки.
    private var loading: Task<Bool, Never>?

    nonisolated static var modelURL: URL? {
        Bundle.main.url(forResource: modelFolderName, withExtension: nil)
    }

    /// Загружает модель. В первый раз iOS готовит её под устройство — это может занять до полуминуты.
    func prepare() async -> Bool {
        if whisper != nil { return true }
        if let loading { return await loading.value }
        guard let url = Self.modelURL else { return false }
        let task = Task { await self.load(from: url) }
        loading = task
        let loaded = await task.value
        loading = nil
        return loaded
    }

    private func load(from url: URL) async -> Bool {
        let config = WhisperKitConfig(modelFolder: url.path, verbose: false, logLevel: .error,
                                      prewarm: false, load: true, download: false)
        whisper = try? await WhisperKit(config)
        return whisper != nil
    }

    /// Уверенно распознанные слова отрезка записи (16 кГц, моно), через пробел.
    /// nil — модель не загружена или распознавание не удалось.
    func transcribe(_ samples: [Float]) async -> String? {
        guard let whisper, !samples.isEmpty else { return nil }
        // Без подсказки текстом суры: с ней модель просто «дописывает» суру, что бы ни звучало.
        let options = DecodingOptions(language: "ar", temperature: 0, temperatureFallbackCount: 0,
                                      usePrefillPrompt: true, skipSpecialTokens: true,
                                      withoutTimestamps: true, suppressBlank: true)
        guard let results = try? await whisper.transcribe(audioArray: samples, decodeOptions: options) else {
            return nil
        }
        let segments = results.flatMap(\.segments)
        guard let tokenizer = whisper.tokenizer else { return nil }
        return segments.flatMap { confidentWords(in: $0, tokenizer: tokenizer) }.joined(separator: " ")
    }

    private func confidentWords(in segment: TranscriptionSegment, tokenizer: WhisperTokenizer) -> [String] {
        guard segment.noSpeechProb <= Self.maxNoSpeechProbability,
              segment.avgLogprob >= Self.minAverageLogProb,
              segment.compressionRatio <= Self.maxCompressionRatio else { return [] }

        // Вероятность каждого текстового токена (массивы идут параллельно, как в SegmentSeeker WhisperKit).
        let special = tokenizer.specialTokens.specialTokenBegin
        var textTokens: [Int] = []
        var logProbs: [Float] = []
        for (index, token) in segment.tokens.enumerated() where token < special {
            guard index < segment.tokenLogProbs.count, let logProb = segment.tokenLogProbs[index][token] else {
                return []
            }
            textTokens.append(token)
            logProbs.append(logProb)
        }

        let split = tokenizer.splitToWordTokens(tokenIds: textTokens)
        var cursor = 0
        var words: [String] = []
        for (word, tokens) in zip(split.words, split.wordTokens) {
            let end = min(cursor + tokens.count, logProbs.count)
            guard end > cursor else { break }
            let meanLogProb = logProbs[cursor..<end].reduce(0, +) / Float(end - cursor)
            cursor = end
            if exp(meanLogProb) >= Self.minWordProbability {
                words.append(word.trimmingCharacters(in: .whitespaces))
            }
        }
        return words
    }

    /// Освобождает память (~150 МБ), когда чтение закончено.
    func unload() async {
        await whisper?.unloadModels()
        whisper = nil
    }
}
