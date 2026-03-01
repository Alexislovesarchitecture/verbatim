import Foundation

struct SmartFormatter {
    func format(
        rawText: String,
        dictionary: [DictionaryEntry],
        snippets: [SnippetEntry],
        style: StyleProfile?
    ) -> String {
        var output = rawText.trimmed()
        output = expandSnippetIfNeeded(output, snippets: snippets)
        output = applyCommandFormatting(output)
        output = applyDictionary(output, dictionary: dictionary)
        output = removeFillers(output, enabled: style?.fillerRemovalEnabled ?? true)
        output = normalizePunctuation(output, style: style)
        output = applySentenceCase(output, style: style)
        return output.collapsingWhitespace()
    }

    private func expandSnippetIfNeeded(_ text: String, snippets: [SnippetEntry]) -> String {
        if let match = snippets.first(where: { $0.trigger.lowercased() == text.lowercased() }) {
            return match.expansion
        }
        return text
    }

    private func applyDictionary(_ text: String, dictionary: [DictionaryEntry]) -> String {
        dictionary.reduce(text) { result, entry in
            let escaped = NSRegularExpression.escapedPattern(for: entry.source)
            let pattern = "\\b\(escaped)\\b"
            return result.replacingOccurrences(
                of: pattern,
                with: entry.replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
    }

    private func applyCommandFormatting(_ text: String) -> String {
        var output = text
        let replacements = [
            (#"\bnew paragraph\b"#, "\n\n"),
            (#"\bnew line\b"#, "\n"),
            (#"\bcomma\b"#, ","),
            (#"\bperiod\b"#, "."),
            (#"\bquestion mark\b"#, "?"),
            (#"\bexclamation point\b"#, "!"),
            (#"\bexclamation mark\b"#, "!"),
            (#"\bcolon\b"#, ":"),
            (#"\bsemicolon\b"#, ";")
        ]

        for (pattern, replacement) in replacements {
            output = output.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }

        output = applySimpleScratchThat(output)
        output = applySimpleActuallyCorrection(output)
        return output
    }

    private func applySimpleScratchThat(_ text: String) -> String {
        guard let range = text.range(of: #"\bscratch that\b"#, options: [.regularExpression, .caseInsensitive]) else {
            return text
        }
        let prefix = text[..<range.lowerBound]
        if let sentenceBoundary = prefix.lastIndex(where: { ".!?\n".contains($0) }) {
            return String(prefix[..<prefix.index(after: sentenceBoundary)])
        }
        return String(prefix)
    }

    private func applySimpleActuallyCorrection(_ text: String) -> String {
        let pattern = #"(\b\d+[a-zA-Z:]*\b)\s+actually\s+(\b\d+[a-zA-Z:]*\b)"#
        return text.replacingOccurrences(of: pattern, with: "$2", options: [.regularExpression, .caseInsensitive])
    }

    private func removeFillers(_ text: String, enabled: Bool) -> String {
        guard enabled else { return text }
        let fillers = #"\b(um|uh|erm|ah)\b"#
        return text.replacingOccurrences(of: fillers, with: "", options: [.regularExpression, .caseInsensitive])
    }

    private func normalizePunctuation(_ text: String, style: StyleProfile?) -> String {
        var output = text
        output = output.replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
        output = output.replacingOccurrences(of: #"([,.;:!?])(\S)"#, with: "$1 $2", options: .regularExpression)

        let punctuationLevel = style?.punctuationLevel ?? 1.0
        if punctuationLevel < 0.4 {
            output = output.replacingOccurrences(of: ".", with: "")
            output = output.replacingOccurrences(of: ",", with: "")
        } else if punctuationLevel < 0.8 {
            output = output.replacingOccurrences(of: #",(?=\S)"#, with: ", ", options: .regularExpression)
        }

        if let style, style.exclamationRate > 0, !output.hasSuffix("!") {
            output += String(repeating: "!", count: min(style.exclamationRate, 2))
        }

        return output
    }

    private func applySentenceCase(_ text: String, style: StyleProfile?) -> String {
        guard style?.sentenceCase ?? true else { return text.lowercased() }
        return text.sentenceCased()
    }
}
