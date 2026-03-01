import Foundation

struct FormattingSteps {
    static func applyDictionary(_ text: String, entries: [DictionaryEntry]) -> String {
        var output = text
        let ordered = entries.filter(\.enabled).sorted { lhs, rhs in
            let lhsLen = lhs.input.count
            let rhsLen = rhs.input.count
            return lhsLen > rhsLen
        }

        for entry in ordered where !entry.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let outputValue = transformedValue(for: entry) else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: entry.input)
            let pattern = "\\\\b(?:" + escaped + ")\\\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(location: 0, length: (output as NSString).length)
            output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: outputValue)
        }
        return output
    }

    static func applySnippets(
        _ text: String,
        snippets: [SnippetEntry],
        globalRequireExactMatch: Bool
    ) -> String {
        var output = text
        let ordered = snippets.filter(\.enabled).sorted { lhs, rhs in
            lhs.trigger.count > rhs.trigger.count
        }

        for snippet in ordered where !snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if globalRequireExactMatch || snippet.requireExactMatch {
                if trimForMatch(output).caseInsensitiveCompare(snippet.trigger) == .orderedSame {
                    output = snippet.content
                }
                continue
            }

            let escaped = NSRegularExpression.escapedPattern(for: snippet.trigger)
            guard let regex = try? NSRegularExpression(pattern: "\\\\b(" + escaped + ")\\\\b", options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(location: 0, length: (output as NSString).length)
            output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: snippet.content)
        }

        return output
    }

    static func trimForMatch(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func transformedValue(for entry: DictionaryEntry) -> String? {
        switch entry.kind {
        case .term:
            return nil
        case .replacement:
            return entry.output?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : (entry.output ?? entry.input)
        case .expansion:
            return entry.output?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : (entry.output ?? entry.input)
        }
    }

    static func normalizeFillers(_ text: String) -> String {
        var output = text
        output = output.replacingOccurrences(of: #"(?i)\b(um+|uh+|erm|like)\b"#, with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizeVoiceCommands(_ text: String) -> String {
        var output = " " + text.lowercased() + " "
        let replacements: [(String, String)] = [
            (" new paragraph ", "\n\n"),
            (" new line ", "\n"),
            (" new sentence ", ". "),
            (" period ", ". "),
            (" comma ", ", "),
            (" question mark ", "? "),
            (" exclamation point ", "! "),
            (" exclamation mark ", "! "),
            (" colon ", ": "),
            (" semicolon ", "; "),
            (" dash ", " - ")
        ]
        for (from, to) in replacements {
            output = output.replacingOccurrences(of: from, with: to)
        }
        output = output.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return output
            .replacingOccurrences(of: #"\s+([,.!?:;])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func applyCaps(_ text: String, mode: CapsMode) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        switch mode {
        case .lowercase:
            return trimmed.lowercased()
        case .sentenceCase:
            var mutable = trimmed
            let first = mutable.prefix(1).uppercased()
            mutable.replaceSubrange(mutable.startIndex...mutable.startIndex, with: first)
            return mutable
        }
    }

    static func applyPunctuation(_ text: String, mode: PunctuationMode) -> String {
        guard !text.isEmpty else { return "" }
        var output = text
        switch mode {
        case .normal:
            output = output.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
            if let last = output.last, ".!?;:".contains(last) {
                return output
            }
            return output + "."
        case .light:
            output = output.replacingOccurrences(of: #"[\s\n]+"#, with: " ", options: .regularExpression)
            output = output.replacingOccurrences(of: "  ", with: " ")
            if let last = output.last, ".!?;:".contains(last) {
                return output
            }
            return output + "."
        }
    }

    static func applyExclamations(_ text: String, mode: ExclamationMode) -> String {
        switch mode {
        case .normal:
            return text
        case .more:
            if text.hasSuffix("!") {
                return text
            }
            if text.hasSuffix("?") {
                return String(text.dropLast()) + "!"
            }
            return text + "!"
        case .none:
            return text.replacingOccurrences(of: "!", with: "")
        }
    }
}
