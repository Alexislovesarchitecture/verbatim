import Foundation

struct FormattingContext {
    let settings: AppSettings
    let styleCategory: AppStyleCategory
    let dictionaryEntries: [DictionaryEntry]
    let snippets: [SnippetEntry]
}

struct FormatterPipeline {
    func format(_ input: String, context: FormattingContext) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        if context.settings.useSnippetExpansion,
           let snippet = context.snippets.first(where: { $0.trigger.lowercased() == text.lowercased() }) {
            return applyTone(to: snippet.expansion, tone: context.settings.tone(for: context.styleCategory))
        }

        text = normalizeVoiceCommands(in: text)

        if context.settings.removeFillers {
            text = text.replacingOccurrences(of: #"(?i)\b(um+|uh+|er+|ah+)\b"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        }

        for entry in context.dictionaryEntries {
            guard let replacement = entry.replacement, !replacement.isEmpty else { continue }
            let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: entry.phrase) + #"\b"#
            text = text.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = applyTone(to: text, tone: context.settings.tone(for: context.styleCategory))
        return text
    }

    private func normalizeVoiceCommands(in input: String) -> String {
        var text = input

        let directReplacements: [(String, String)] = [
            (" new paragraph ", "\n\n"),
            (" new line ", "\n"),
            (" comma ", ", "),
            (" period ", ". "),
            (" full stop ", ". "),
            (" question mark ", "? "),
            (" exclamation point ", "! "),
            (" exclamation mark ", "! "),
            (" colon ", ": "),
            (" semicolon ", "; ")
        ]

        text = " \(text) "
        for (spoken, symbol) in directReplacements {
            text = text.replacingOccurrences(of: spoken, with: symbol, options: .caseInsensitive)
        }

        if let range = text.range(of: "scratch that", options: .caseInsensitive) {
            let after = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            text = String(after)
        }

        if let range = text.range(of: "actually", options: .caseInsensitive) {
            let after = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !after.isEmpty {
                text = after
            }
        }

        text = text.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyTone(to input: String, tone: StyleTone) -> String {
        switch tone {
        case .formal:
            return sentenceCase(input, endPunctuation: ".")
        case .casual:
            return sentenceCase(input, endPunctuation: "")
        case .veryCasual:
            return input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
        case .excited:
            let base = sentenceCase(input, endPunctuation: "!")
            return base.replacingOccurrences(of: ".", with: "!")
        }
    }

    private func sentenceCase(_ input: String, endPunctuation: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        let first = text.prefix(1).uppercased()
        text.replaceSubrange(text.startIndex...text.startIndex, with: first)
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)

        if !endPunctuation.isEmpty, !text.hasSuffix("."), !text.hasSuffix("?"), !text.hasSuffix("!"), !text.hasSuffix(":") {
            text += endPunctuation
        }
        return text
    }
}
