import Foundation

/// Нормализация арабского текста для сравнения распознанной речи с текстом суры.
enum ArabicText {
    /// Убирает огласовки и знаки чтения, приводит варианты алифа, та марбуту и алиф максуру к базовым буквам.
    static func normalize(_ word: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in word.unicodeScalars {
            switch scalar.value {
            case 0x0610...0x061A, 0x064B...0x065F, 0x0670, 0x06D6...0x06ED, 0x0640:
                continue
            case 0x0622, 0x0623, 0x0625, 0x0671:
                out.append("\u{0627}")
            case 0x0629:
                out.append("\u{0647}")
            case 0x0649, 0x0626:
                out.append("\u{064A}")
            case 0x0624:
                out.append("\u{0648}")
            default:
                if CharacterSet.letters.contains(scalar) { out.append(scalar) }
            }
        }
        return String(out)
    }

    /// Нормализованные слова фразы.
    static func words(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .map(normalize)
            .filter { !$0.isEmpty }
    }

    /// Нечёткое совпадение слов: распознавание часто ошибается на одну-две буквы.
    static func matches(_ heard: String, _ expected: String) -> Bool {
        if heard == expected { return true }
        let a = Array(heard.unicodeScalars)
        let b = Array(expected.unicodeScalars)
        let longest = max(a.count, b.count)
        let shortest = min(a.count, b.count)
        let allowed: Int
        switch longest {
        case ...3: allowed = shortest >= 3 ? 1 : 0
        case 4...5: allowed = 1
        default: allowed = 2
        }
        guard allowed > 0, longest - shortest <= allowed else { return false }
        return levenshtein(a, b) <= allowed
    }

    static func levenshtein(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Int {
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, y) in b.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
