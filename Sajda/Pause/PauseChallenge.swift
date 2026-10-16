import Foundation

/// Цвета для раунда «Струп»: нужно выбрать цвет текста, а не прочитанное слово.
enum StroopColor: String, CaseIterable, Equatable {
    case red, green, blue, yellow, purple, orange

    var localizedName: String { NSLocalizedString("color.\(rawValue)", comment: "") }
}

/// Одно задание мини-игры.
enum ChallengeTask: Equatable {
    /// Пример вида «7 × 8 + 13».
    case math(question: String, answer: Int)
    /// Запомнить цифры, пока они видны, затем ввести.
    case memory(digits: String)
    /// Нажать числа по возрастанию.
    case order(numbers: [Int])
    /// Найти единственный отличающийся символ.
    case oddOneOut(symbols: [String], oddIndex: Int)
    /// Слово одного цвета написано другим цветом — выбрать цвет текста.
    case stroop(word: StroopColor, ink: StroopColor, options: [StroopColor])
    /// Перепечатать код.
    case code(String)

    enum Kind: CaseIterable { case math, memory, order, oddOneOut, stroop, code }

    /// Проверка текстового ответа (пример, память, код). Пробелы и регистр не важны.
    func accepts(_ text: String) -> Bool {
        let cleaned = text.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        switch self {
        case .math(_, let answer): return Int(cleaned) == answer
        case .memory(let digits): return cleaned == digits
        case .code(let code): return cleaned == code.filter { !$0.isWhitespace }
        default: return false
        }
    }

    func accepts(index: Int) -> Bool {
        if case .oddOneOut(_, let oddIndex) = self { return index == oddIndex }
        return false
    }

    func accepts(color: StroopColor) -> Bool {
        if case .stroop(_, let ink, _) = self { return color == ink }
        return false
    }
}

/// Генератор заданий. Принимает любой RandomNumberGenerator, чтобы в тестах был детерминизм.
struct ChallengeGenerator {
    static let codeAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let memoryLength = 6
    static let codeLength = 6
    static let orderCount = 12
    static let oddGridSize = 25
    static let oddPairs: [(String, String)] = [
        ("O", "Q"), ("E", "F"), ("b", "d"), ("p", "q"), ("M", "N"), ("C", "G"), ("6", "8"), ("V", "Y"), ("ш", "щ"), ("З", "Э")
    ]

    /// 10 раундов: каждый тип минимум один раз, остальные — случайные, порядок перемешан.
    static func plan<R: RandomNumberGenerator>(rounds: Int, using rng: inout R) -> [ChallengeTask.Kind] {
        let all = ChallengeTask.Kind.allCases
        let extra = (0..<max(0, rounds - all.count)).map { _ in all.randomElement(using: &rng)! }
        return Array((all + extra).shuffled(using: &rng).prefix(rounds))
    }

    static func make<R: RandomNumberGenerator>(_ kind: ChallengeTask.Kind, using rng: inout R) -> ChallengeTask {
        switch kind {
        case .math: return math(using: &rng)
        case .memory:
            let digits = (0..<memoryLength).map { _ in String(Int.random(in: 0...9, using: &rng)) }.joined()
            return .memory(digits: digits)
        case .order:
            return .order(numbers: Array(1...orderCount).shuffled(using: &rng))
        case .oddOneOut:
            let (base, odd) = oddPairs.randomElement(using: &rng)!
            let oddIndex = Int.random(in: 0..<oddGridSize, using: &rng)
            let symbols = (0..<oddGridSize).map { $0 == oddIndex ? odd : base }
            return .oddOneOut(symbols: symbols, oddIndex: oddIndex)
        case .stroop:
            let colors = StroopColor.allCases.shuffled(using: &rng)
            let word = colors[0]
            let ink = colors[1]
            let options = ([ink, word] + colors[2...].prefix(2)).shuffled(using: &rng)
            return .stroop(word: word, ink: ink, options: options)
        case .code:
            let raw = String((0..<codeLength).map { _ in codeAlphabet.randomElement(using: &rng)! })
            return .code("\(raw.prefix(3)) \(raw.suffix(3))")
        }
    }

    private static func math<R: RandomNumberGenerator>(using rng: inout R) -> ChallengeTask {
        let a = Int.random(in: 6...14, using: &rng)
        let b = Int.random(in: 3...9, using: &rng)
        let c = Int.random(in: 11...59, using: &rng)
        switch Int.random(in: 0..<3, using: &rng) {
        case 0: return .math(question: "\(a) × \(b) + \(c)", answer: a * b + c)
        case 1:
            // Ответ всегда положительный — на цифровой клавиатуре нет минуса.
            let minus = Int.random(in: 1...min(59, a * b - 1), using: &rng)
            return .math(question: "\(a) × \(b) − \(minus)", answer: a * b - minus)
        default: return .math(question: "(\(a) + \(c)) × \(b)", answer: (a + c) * b)
        }
    }
}

/// Прогресс испытания: 10 раундов, ошибка откатывает на 2 раунда назад.
struct PauseChallenge {
    static let rounds = 10
    static let penalty = 2

    private(set) var completed = 0
    private(set) var mistakes = 0

    var isFinished: Bool { completed >= Self.rounds }

    mutating func registerSuccess() {
        completed = min(Self.rounds, completed + 1)
    }

    mutating func registerFailure() {
        mistakes += 1
        completed = max(0, completed - Self.penalty)
    }
}

/// Детерминированный генератор для тестов.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
