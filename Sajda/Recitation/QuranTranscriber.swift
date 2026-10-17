import Foundation
import WhisperKit

/// Распознавание чтения Корана моделью Tarteel (Whisper base, дообучен на чтении Корана), полностью на устройстве.
/// Модель кладётся в приложение при сборке (см. .github/workflows/build.yml).
actor QuranTranscriber {
    static let shared = QuranTranscriber()
    static let sampleRate = 16_000

    private static let modelFolderName = "QuranModel"

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

    /// Текст отрезка записи (16 кГц, моно). nil — модель не загружена или распознавание не удалось.
    /// - Parameter context: уже прочитанный текст перед отрезком, как «предыдущая речь» для Whisper.
    func transcribe(_ samples: [Float], context: String = "") async -> String? {
        guard let whisper, !samples.isEmpty else { return nil }
        var options = DecodingOptions(language: "ar", temperature: 0, temperatureFallbackCount: 0,
                                      usePrefillPrompt: true, skipSpecialTokens: true,
                                      withoutTimestamps: true, suppressBlank: true)
        if !context.isEmpty, let tokens = whisper.tokenizer?.encode(text: " " + context), !tokens.isEmpty {
            options.promptTokens = tokens
        }
        guard let results = try? await whisper.transcribe(audioArray: samples, decodeOptions: options) else {
            return nil
        }
        return results.map(\.text).joined(separator: " ")
    }

    /// Освобождает память (~150 МБ), когда чтение закончено.
    func unload() async {
        await whisper?.unloadModels()
        whisper = nil
    }
}
