import Foundation

/// Сопоставляет метки встроенного классификатора Vision с заданием (коврик / раковина).
struct LabelMatcher {
    struct Label: Equatable {
        let identifier: String
        let confidence: Double
    }

    enum Decision: Equatable {
        case match(TaskKind)
        case screenOrPrint
        case noMatch
    }

    static let strongThreshold = 0.30
    static let scoreThreshold = 0.50
    static let weakWeight = 0.5
    static let negativeThreshold = 0.35
    static let minConfidence = 0.05

    static let rugStrong: Set<String> = ["rug", "carpet", "carpeting", "mat", "doormat", "kilim", "tapestry", "prayer"]
    static let rugWeak: Set<String> = ["textile", "fabric", "cloth", "quilt", "blanket", "embroidery", "velvet",
                                       "wool", "upholstery", "pattern", "ornament", "paisley", "fringe", "lace"]
    static let sinkStrong: Set<String> = ["sink", "faucet", "washbasin", "basin", "tap", "lavatory", "bathroom",
                                          "washroom", "restroom", "bathtub", "shower"]
    static let sinkWeak: Set<String> = ["tile", "ceramic", "porcelain", "plumbing", "soap", "towel", "mirror",
                                        "water", "countertop", "kitchen", "toilet", "drain"]
    /// Снимок экрана, монитора или распечатки — не засчитываем.
    static let negative: Set<String> = ["screen", "monitor", "display", "television", "tv", "computer", "laptop",
                                        "screenshot", "cellphone", "smartphone", "tablet", "document", "poster"]

    func decide(labels: [Label], task: TaskKind) -> Decision {
        let relevant = labels.filter { $0.confidence >= Self.minConfidence }
        if relevant.contains(where: { $0.confidence >= Self.negativeThreshold && Self.matches($0.identifier, Self.negative) }) {
            return .screenOrPrint
        }
        let candidates: [TaskKind] = task == .any ? [.rug, .sink] : [task]
        let best = candidates
            .map { ($0, score(relevant, for: $0)) }
            .max { $0.1 < $1.1 }
        guard let best, best.1 >= Self.scoreThreshold || strongest(relevant, for: best.0) >= Self.strongThreshold else {
            return .noMatch
        }
        return .match(best.0)
    }

    func score(_ labels: [Label], for kind: TaskKind) -> Double {
        let (strong, weak) = Self.sets(for: kind)
        let strongMax = labels.filter { Self.matches($0.identifier, strong) }.map(\.confidence).max() ?? 0
        let weakSum = labels.filter { Self.matches($0.identifier, weak) }.map(\.confidence).reduce(0, +)
        return strongMax + min(weakSum, 1) * Self.weakWeight
    }

    private func strongest(_ labels: [Label], for kind: TaskKind) -> Double {
        let strong = Self.sets(for: kind).strong
        return labels.filter { Self.matches($0.identifier, strong) }.map(\.confidence).max() ?? 0
    }

    private static func sets(for kind: TaskKind) -> (strong: Set<String>, weak: Set<String>) {
        switch kind {
        case .rug: return (rugStrong, rugWeak)
        case .sink: return (sinkStrong, sinkWeak)
        case .any: return (rugStrong.union(sinkStrong), rugWeak.union(sinkWeak))
        }
    }

    /// Сравнение по целым словам идентификатора ("bathroom_faucet" → ["bathroom", "faucet"]).
    static func matches(_ identifier: String, _ keywords: Set<String>) -> Bool {
        let tokens = identifier.lowercased().split { !$0.isLetter }.map(String.init)
        return tokens.contains { keywords.contains($0) || keywords.contains(singular($0)) }
    }

    private static func singular(_ word: String) -> String {
        word.count > 3 && word.hasSuffix("s") ? String(word.dropLast()) : word
    }
}
