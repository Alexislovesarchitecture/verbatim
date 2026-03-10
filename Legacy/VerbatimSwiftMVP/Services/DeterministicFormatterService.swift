import Foundation

final class DeterministicFormatterService: DeterministicFormatterServiceProtocol {
    private let fillerPatterns: [String] = [
        #"\bum+\b"#,
        #"\buh+\b"#,
        #"\byou know\b"#,
    ]

    func format(text: String, settings: LogicSettings, glossary: [GlossaryEntry]) -> DeterministicResult {
        var working = normalizeWhitespace(text)
        var removedFillers: [String] = []

        if settings.removeFillerWords {
            for pattern in fillerPatterns {
                let matches = regexMatches(pattern: pattern, in: working, options: [.caseInsensitive])
                removedFillers.append(contentsOf: matches)
                working = regexReplace(pattern: pattern, in: working, with: "", options: [.caseInsensitive])
            }

            working = regexReplace(pattern: #"\s+,"#, in: working, with: ",")
            working = regexReplace(pattern: #",\s*,"#, in: working, with: ",")
            working = regexReplace(pattern: #"\s{2,}"#, in: working, with: " ")
            working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let relevantGlossary = relevantGlossaryEntries(from: glossary, for: working)
        for entry in relevantGlossary {
            let escaped = NSRegularExpression.escapedPattern(for: entry.from)
            let pattern = "\\b\(escaped)\\b"
            working = regexReplace(pattern: pattern, in: working, with: entry.to, options: [.caseInsensitive])
        }

        let prePunctuation = working
        working = applyPunctuationAndCapitalization(working)

        return DeterministicResult(
            text: working,
            punctuationAdjusted: prePunctuation != working,
            removedFillers: removedFillers,
            appliedGlossary: relevantGlossary
        )
    }

    private func normalizeWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func relevantGlossaryEntries(from glossary: [GlossaryEntry], for text: String) -> [GlossaryEntry] {
        glossary.filter { entry in
            guard !entry.from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            let escaped = NSRegularExpression.escapedPattern(for: entry.from)
            let pattern = "\\b\(escaped)\\b"
            return regexHasMatch(pattern: pattern, in: text, options: [.caseInsensitive])
        }
    }

    private func applyPunctuationAndCapitalization(_ input: String) -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return value
        }

        if let firstLetterRange = value.rangeOfCharacter(from: .letters) {
            let firstCharacter = String(value[firstLetterRange]).uppercased()
            value.replaceSubrange(firstLetterRange, with: firstCharacter)
        }

        if let last = value.unicodeScalars.last,
           !CharacterSet(charactersIn: ".!?").contains(last) {
            value.append(".")
        }

        return value
    }

    private func regexReplace(
        pattern: String,
        in input: String,
        with replacement: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return input
        }
        let range = NSRange(location: 0, length: (input as NSString).length)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: replacement)
    }

    private func regexMatches(
        pattern: String,
        in input: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let range = NSRange(location: 0, length: (input as NSString).length)
        return regex.matches(in: input, options: [], range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: input) else { return nil }
            return String(input[swiftRange])
        }
    }

    private func regexHasMatch(
        pattern: String,
        in input: String,
        options: NSRegularExpression.Options = []
    ) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return false
        }
        let range = NSRange(location: 0, length: (input as NSString).length)
        return regex.firstMatch(in: input, options: [], range: range) != nil
    }
}
