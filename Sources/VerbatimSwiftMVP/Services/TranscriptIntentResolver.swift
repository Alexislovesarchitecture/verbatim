import Foundation

protocol TranscriptIntentResolverProtocol {
    func resolve(
        transcript: Transcript,
        selfCorrectionMode: SelfCorrectionMode,
        glossary: [GlossaryEntry],
        activeContext: ActiveAppContext
    ) -> ResolvedTranscript
}

final class TranscriptIntentResolver: TranscriptIntentResolverProtocol {
    private enum ClauseSeparator {
        case pause
        case sentence

        var rendered: String {
            switch self {
            case .pause:
                return ", "
            case .sentence:
                return ". "
            }
        }
    }

    private struct Clause {
        var text: String
        var separatorAfter: ClauseSeparator?
    }

    private struct SpelledSequence {
        let original: String
        let collapsed: String
    }

    private struct CueParse {
        let kind: ResolvedCorrectionKind
        let cue: String
        let remainder: String
    }

    private struct ReplacementCandidate {
        let text: String
        let consumedClauses: Int
    }

    private let literalCues = [
        "type",
        "write out",
        "all caps",
        "dash",
        "hyphen",
        "the letters",
        "email",
        "url",
        "acronym",
        "initials",
        "exactly",
    ]

    private let spellingCues = [
        "that's",
        "that is",
        "spelled",
        "as in",
        "write",
        "with two",
    ]

    private let restartCues = [
        "let's start over",
        "let me start over",
        "let me start again",
        "ignore the last part",
        "let me rephrase that",
        "new message",
        "start over",
        "start again",
        "begin again",
        "clear all",
        "delete all",
        "erase all",
        "never mind",
        "cancel that",
        "scratch that",
    ]

    private let overwriteCues = [
        "replace that with",
        "replace this with",
        "change that with",
        "change that to",
        "change this to",
        "use this instead",
        "use that instead",
        "say that instead",
        "say this instead",
        "make that",
        "make this",
        "rewrite that",
        "rewrite this",
        "rephrase that",
        "rephrase this",
        "reword that",
        "reword this",
        "revise that",
        "revise this",
        "edit that",
        "edit this",
        "replace that",
        "replace this",
        "change that",
        "change this",
        "correct that",
        "correct this",
        "fix that",
        "fix this",
        "update that",
        "update this",
        "actually",
        "i mean",
        "instead",
        "rather",
        "say",
    ]

    private let deleteCues = [
        "delete that",
        "delete this",
        "delete the last part",
        "remove that",
        "remove this",
        "drop that",
        "drop this",
        "erase that",
        "erase this",
        "strike that",
        "strike this",
        "cut that",
        "undo that",
    ]

    private let formattingInstructionCues = [
        "all caps that",
        "no caps that",
        "capitalize that",
        "lowercase that",
        "uppercase that",
        "bold that",
        "italicize that",
        "italic that",
        "underline that",
        "strikethrough that",
        "clear formatting",
        "clear all formatting",
        "make that a list",
        "make this a list",
        "make that bullets",
        "make this bullets",
        "bullet that",
        "bullet this",
        "start list",
        "start numbered list",
        "exit list",
        "new line",
        "next line",
        "new paragraph",
        "paragraph break",
        "line break",
    ]

    private let preambleCues = [
        "no",
        "wait",
        "sorry",
    ]

    private let replacementAnchors = [
        "change to",
        "meet",
        "send",
        "write",
        "call",
        "email",
        "text",
        "do",
        "for",
        "to",
        "is",
        "are",
        "was",
        "were",
        "be",
        "with",
        "about",
        "on",
        "at",
    ]

    func resolve(
        transcript: Transcript,
        selfCorrectionMode: SelfCorrectionMode,
        glossary: [GlossaryEntry],
        activeContext: ActiveAppContext
    ) -> ResolvedTranscript {
        var notes: [String] = []
        var corrections: [ResolvedSelfCorrection] = []
        var clauses = clauses(from: transcript)

        resolveSpelledWords(
            clauses: &clauses,
            corrections: &corrections,
            notes: &notes,
            glossary: glossary,
            activeContext: activeContext
        )

        if selfCorrectionMode != .keepAll {
            resolveCorrections(
                clauses: &clauses,
                corrections: &corrections,
                notes: &notes,
                selfCorrectionMode: selfCorrectionMode
            )
        }

        return ResolvedTranscript(
            text: flatten(clauses: clauses),
            corrections: corrections,
            notes: notes
        )
    }

    private func clauses(from transcript: Transcript) -> [Clause] {
        let sourceText: String
        if !transcript.segments.isEmpty {
            sourceText = transcript.segments
                .map(\.text)
                .joined(separator: " ")
        } else {
            sourceText = transcript.rawText
        }

        let normalized = normalizeWhitespace(sourceText)
        guard !normalized.isEmpty else { return [] }

        var clauses: [Clause] = []
        var current = ""

        func appendCurrent(separator: ClauseSeparator?) {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                current = ""
                return
            }

            clauses.append(Clause(text: trimmed, separatorAfter: separator))
            current = ""
        }

        for character in normalized {
            switch character {
            case ",", ";", ":":
                appendCurrent(separator: .pause)
            case ".", "!", "?", "\n":
                appendCurrent(separator: .sentence)
            default:
                current.append(character)
            }
        }

        appendCurrent(separator: nil)
        if clauses.count > 1 {
            clauses[clauses.count - 1].separatorAfter = nil
        }
        return clauses
    }

    private func resolveSpelledWords(
        clauses: inout [Clause],
        corrections: inout [ResolvedSelfCorrection],
        notes: inout [String],
        glossary: [GlossaryEntry],
        activeContext: ActiveAppContext
    ) {
        var index = 0
        while index < clauses.count {
            let currentText = clauses[index].text

            if shouldPreserveLiteralSpelling(in: currentText, activeContext: activeContext) {
                if let sequence = spelledSequence(in: currentText) {
                    corrections.append(
                        ResolvedSelfCorrection(
                            kind: .literalSpellingPreserved,
                            cue: literalCue(in: currentText) ?? "literal",
                            originalText: sequence.original,
                            replacementText: sequence.original,
                            disposition: .preserved
                        )
                    )
                }
                index += 1
                continue
            }

            if let embeddedCue = embeddedSpellingCue(in: currentText),
               let sequence = spelledSequence(in: embeddedCue.remainder) {
                let preferred = preferredReplacementWord(
                    for: sequence.collapsed,
                    fallbackClause: embeddedCue.prefix,
                    glossary: glossary
                )
                let updated = replaceTrailingWord(in: embeddedCue.prefix, with: preferred)
                if updated != currentText {
                    clauses[index].text = updated
                    corrections.append(
                        ResolvedSelfCorrection(
                            kind: .spelledWordCollapse,
                            cue: embeddedCue.cue,
                            originalText: sequence.original,
                            replacementText: preferred,
                            disposition: .applied
                        )
                    )
                    index += 1
                    continue
                }
            }

            guard let sequence = spelledSequence(in: currentText) else {
                index += 1
                continue
            }

            guard let previousIndex = previousNonEmptyClauseIndex(before: index, clauses: clauses) else {
                notes.append("Preserved literal spelling for \"\(sequence.original)\" because intent was ambiguous.")
                index += 1
                continue
            }

            if shouldPreserveLiteralSpelling(in: clauses[previousIndex].text, activeContext: activeContext) {
                index += 1
                continue
            }

            let previousText = clauses[previousIndex].text
            let previousTail = trailingWord(in: previousText)
            let preferred = preferredReplacementWord(
                for: sequence.collapsed,
                fallbackClause: previousText,
                glossary: glossary
            )

            let hasCollapseCue = containsCue(currentText, cues: spellingCues)
            let matchesPreviousTail = normalizedWord(previousTail) == normalizedWord(preferred)

            guard hasCollapseCue || matchesPreviousTail else {
                notes.append("Preserved literal spelling for \"\(sequence.original)\" because intent was ambiguous.")
                index += 1
                continue
            }

            let updatedPrevious = replaceTrailingWord(in: previousText, with: preferred)
            clauses[previousIndex].text = updatedPrevious
            clauses[previousIndex].separatorAfter = clauses[index].separatorAfter
            clauses.remove(at: index)
            corrections.append(
                ResolvedSelfCorrection(
                    kind: .spelledWordCollapse,
                    cue: hasCollapseCue ? (matchingCue(in: currentText, cues: spellingCues) ?? "spelled") : "spelled",
                    originalText: sequence.original,
                    replacementText: preferred,
                    disposition: .applied
                )
            )
        }
    }

    private func resolveCorrections(
        clauses: inout [Clause],
        corrections: inout [ResolvedSelfCorrection],
        notes: inout [String],
        selfCorrectionMode: SelfCorrectionMode
    ) {
        guard !clauses.isEmpty else { return }

        var resolved: [Clause] = []
        var index = 0

        while index < clauses.count {
            let current = clauses[index]
            let strippedCurrent = stripLeadingPreambles(from: current.text)

            if strippedCurrent.isEmpty,
               let nextIndex = nextNonEmptyClauseIndex(after: index, clauses: clauses),
               leadingCue(in: clauses[nextIndex].text) != nil {
                index += 1
                continue
            }

            if let embedded = embeddedCue(in: current.text) {
                let updated = applyInlineCorrection(
                    baseText: embedded.prefix,
                    cue: embedded.parse,
                    separatorAfter: current.separatorAfter,
                    corrections: &corrections,
                    selfCorrectionMode: selfCorrectionMode
                )
                resolved.append(updated)
                index += 1
                continue
            }

            if let cue = leadingCue(in: current.text) {
                let replacementCandidate = replacementCandidate(
                    inlineRemainder: cue.remainder,
                    after: index,
                    clauses: clauses
                )
                let replacement = replacementCandidate?.text ?? ""

                if replacement.isEmpty {
                    if isFormattingCue(cue.cue) {
                        notes.append("Ignored formatting instruction \"\(cue.cue)\".")
                        index += 1
                        continue
                    }

                    if isDeleteCue(cue.cue), let last = resolved.indices.last {
                        let deleted = resolved.remove(at: last)
                        corrections.append(
                            ResolvedSelfCorrection(
                                kind: .restart,
                                cue: cue.cue,
                                originalText: deleted.text,
                                replacementText: "",
                                disposition: selfCorrectionMode == .annotate ? .annotated : .applied
                            )
                        )
                        index += 1
                        continue
                    }

                    if isInstructionOnlyClause(current.text) {
                        notes.append("Ignored edit instruction \"\(current.text.lowercased())\".")
                        index += 1
                        continue
                    }

                    resolved.append(current)
                    index += 1
                    continue
                }

                let consumedClauses = replacementCandidate?.consumedClauses ?? 0
                let replacementSeparator = consumedClauses > 0
                    ? clauses[index + consumedClauses].separatorAfter
                    : current.separatorAfter

                switch cue.kind {
                case .restart:
                    let useFullRestart = shouldTreatAsRestart(replacement)
                    if useFullRestart || resolved.isEmpty {
                        let replacedText = resolved.map(\.text).joined(separator: " ")
                        if !replacedText.isEmpty {
                            corrections.append(
                                ResolvedSelfCorrection(
                                    kind: .restart,
                                    cue: cue.cue,
                                    originalText: replacedText,
                                    replacementText: replacement,
                                    disposition: selfCorrectionMode == .annotate ? .annotated : .applied
                                )
                            )
                        }
                        resolved.removeAll()
                        resolved.append(Clause(text: replacement, separatorAfter: replacementSeparator))
                    } else if let last = resolved.indices.last {
                        let original = resolved[last].text
                        let updated = replaceTail(in: original, with: replacement)
                        resolved[last].text = updated
                        resolved[last].separatorAfter = replacementSeparator
                        corrections.append(
                            ResolvedSelfCorrection(
                                kind: .restart,
                                cue: cue.cue,
                                originalText: original,
                                replacementText: updated,
                                disposition: selfCorrectionMode == .annotate ? .annotated : .applied
                            )
                        )
                    }
                case .overwrite, .localReplacement:
                    if let last = resolved.indices.last {
                        let original = resolved[last].text
                        let updated = rewrittenText(from: original, replacement: replacement)
                        resolved[last].text = updated
                        resolved[last].separatorAfter = replacementSeparator
                        corrections.append(
                            ResolvedSelfCorrection(
                                kind: cue.kind,
                                cue: cue.cue,
                                originalText: original,
                                replacementText: updated,
                                disposition: selfCorrectionMode == .annotate ? .annotated : .applied
                            )
                        )
                    } else {
                        resolved.append(Clause(text: replacement, separatorAfter: replacementSeparator))
                    }
                case .spelledWordCollapse, .literalSpellingPreserved:
                    resolved.append(current)
                }

                index += 1 + consumedClauses
                continue
            }

            if isInstructionOnlyClause(current.text) {
                notes.append("Ignored edit instruction \"\(current.text.lowercased())\".")
                index += 1
                continue
            }

            resolved.append(current)
            index += 1
        }

        clauses = resolved
    }

    private func applyInlineCorrection(
        baseText: String,
        cue: CueParse,
        separatorAfter: ClauseSeparator?,
        corrections: inout [ResolvedSelfCorrection],
        selfCorrectionMode: SelfCorrectionMode
    ) -> Clause {
        let original = baseText.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated: String

        switch cue.kind {
        case .restart:
            updated = shouldTreatAsRestart(cue.remainder) ? cue.remainder : rewrittenText(from: original, replacement: cue.remainder)
        case .overwrite, .localReplacement:
            updated = rewrittenText(from: original, replacement: cue.remainder)
        case .spelledWordCollapse, .literalSpellingPreserved:
            updated = original
        }

        corrections.append(
            ResolvedSelfCorrection(
                kind: cue.kind,
                cue: cue.cue,
                originalText: original,
                replacementText: updated,
                disposition: selfCorrectionMode == .annotate ? .annotated : .applied
            )
        )

        return Clause(text: updated, separatorAfter: separatorAfter)
    }

    private func normalizeWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func flatten(clauses: [Clause]) -> String {
        guard let first = clauses.first else { return "" }

        var rendered = first.text
        for index in clauses.indices.dropFirst() {
            let separator = clauses[index - 1].separatorAfter?.rendered ?? " "
            rendered += separator + clauses[index].text
        }
        return normalizeWhitespace(rendered)
    }

    private func previousNonEmptyClauseIndex(before index: Int, clauses: [Clause]) -> Int? {
        guard index > 0 else { return nil }
        return clauses[..<index].indices.reversed().first { !clauses[$0].text.isEmpty }
    }

    private func nextNonEmptyClauseIndex(after index: Int, clauses: [Clause]) -> Int? {
        guard index + 1 < clauses.count else { return nil }
        return clauses[(index + 1)...].indices.first { !clauses[$0].text.isEmpty }
    }

    private func shouldPreserveLiteralSpelling(in text: String, activeContext: ActiveAppContext) -> Bool {
        if containsCue(text, cues: literalCues) {
            return true
        }

        let lowered = text.lowercased()
        if activeContext.styleCategory == .email,
           lowered.contains(" at "),
           lowered.contains(" dot ") {
            return true
        }

        return false
    }

    private func literalCue(in text: String) -> String? {
        matchingCue(in: text, cues: literalCues)
    }

    private func containsCue(_ text: String, cues: [String]) -> Bool {
        matchingCue(in: text, cues: cues) != nil
    }

    private func matchingCue(in text: String, cues: [String]) -> String? {
        let lowered = text.lowercased()
        return cues.first { lowered.contains($0) }
    }

    private func isDeleteCue(_ cue: String) -> Bool {
        deleteCues.contains(cue)
    }

    private func isFormattingCue(_ cue: String) -> Bool {
        formattingInstructionCues.contains(cue)
    }

    private func allInstructionCues() -> [String] {
        restartCues + overwriteCues + deleteCues + formattingInstructionCues
    }

    private func isInstructionOnlyClause(_ text: String) -> Bool {
        let trimmed = stripLeadingPreambles(from: text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lowered = trimmed.lowercased()
        return allInstructionCues().contains(where: { lowered == $0 })
    }

    private func embeddedSpellingCue(in text: String) -> (prefix: String, cue: String, remainder: String)? {
        for cue in spellingCues.sorted(by: { $0.count > $1.count }) {
            guard let range = range(of: cue, in: text) else { continue }
            let prefix = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let remainder = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prefix.isEmpty, !remainder.isEmpty else { continue }
            return (prefix, cue, remainder)
        }
        return nil
    }

    private func leadingCue(in text: String) -> CueParse? {
        parseCue(in: stripLeadingPreambles(from: text))
    }

    private func embeddedCue(in text: String) -> (prefix: String, parse: CueParse)? {
        let cues = allInstructionCues().sorted { $0.count > $1.count }

        for cue in cues {
            let token = " \(cue) "
            guard let range = range(of: token, in: text) else { continue }
            let prefix = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let remainder = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prefix.isEmpty, !remainder.isEmpty else { continue }

            let kind = correctionKind(for: cue)
            return (prefix, CueParse(kind: kind, cue: cue, remainder: normalizeReplacementRemainder(remainder)))
        }

        return nil
    }

    private func parseCue(in text: String) -> CueParse? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        let cues = allInstructionCues().sorted { $0.count > $1.count }

        for cue in cues {
            if lowered == cue {
                let kind = correctionKind(for: cue)
                return CueParse(kind: kind, cue: cue, remainder: "")
            }

            let candidate = cue + " "
            guard lowered.hasPrefix(candidate) else { continue }
            let offset = trimmed.index(trimmed.startIndex, offsetBy: candidate.count)
            let remainder = normalizeReplacementRemainder(String(trimmed[offset...]))
            let kind = correctionKind(for: cue)
            return CueParse(kind: kind, cue: cue, remainder: remainder)
        }

        return nil
    }

    private func stripLeadingPreambles(from text: String) -> String {
        var working = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var didStrip = true

        while didStrip {
            didStrip = false
            let lowered = working.lowercased()
            for cue in preambleCues {
                if lowered == cue {
                    working = ""
                    didStrip = true
                    break
                }

                if lowered.hasPrefix(cue + " ") {
                    working.removeFirst(cue.count + 1)
                    working = working.trimmingCharacters(in: .whitespacesAndNewlines)
                    didStrip = true
                    break
                }
            }
        }

        return working
    }

    private func normalizeReplacementRemainder(_ text: String) -> String {
        let trimmed = stripLeadingPreambles(from: text)
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("say ") {
            return String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func spelledSequence(in text: String) -> SpelledSequence? {
        let pattern = #"(?i)(?<![A-Za-z'’])[a-z](?:[-\s]+[a-z]){1,}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
              let range = Range(match.range, in: text) else {
            return nil
        }

        let original = String(text[range])
        let collapsed = original.unicodeScalars
            .filter { CharacterSet.letters.contains($0) }
            .map(String.init)
            .joined()

        guard collapsed.count >= 2 else { return nil }
        return SpelledSequence(original: original, collapsed: collapsed)
    }

    private func preferredReplacementWord(for collapsed: String, fallbackClause: String, glossary: [GlossaryEntry]) -> String {
        let normalizedCollapsed = normalizedWord(collapsed)

        if let glossaryMatch = glossary.first(where: { normalizedWord($0.to) == normalizedCollapsed }) {
            return glossaryMatch.to
        }

        if let glossaryMatch = glossary.first(where: { normalizedWord($0.from) == normalizedCollapsed }) {
            return glossaryMatch.to
        }

        let trailing = trailingWord(in: fallbackClause)
        if !trailing.isEmpty, trailing.first?.isUppercase == true {
            return collapsed.prefix(1).uppercased() + collapsed.dropFirst().lowercased()
        }

        return collapsed.lowercased()
    }

    private func trailingWord(in text: String) -> String {
        guard let match = text.range(of: #"[A-Za-z][A-Za-z'’\-]*$"#, options: .regularExpression) else {
            return ""
        }
        return String(text[match])
    }

    private func replaceTrailingWord(in text: String, with replacement: String) -> String {
        guard let match = text.range(of: #"[A-Za-z][A-Za-z'’\-]*$"#, options: .regularExpression) else {
            return text.isEmpty ? replacement : "\(text) \(replacement)"
        }

        var updated = text
        updated.replaceSubrange(match, with: replacement)
        return updated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedWord(_ value: String) -> String {
        value.unicodeScalars
            .filter { CharacterSet.letters.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
    }

    private func shouldTreatAsRestart(_ replacement: String) -> Bool {
        let trimmed = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        if wordCount >= 3 {
            return true
        }

        let lowered = trimmed.lowercased()
        return lowered.hasPrefix("hi ")
            || lowered.hasPrefix("hello ")
            || lowered.hasPrefix("can ")
            || lowered.hasPrefix("could ")
            || lowered.hasPrefix("please ")
    }

    private func replaceTail(in text: String, with replacement: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return cleanedReplacement }
        guard !cleanedReplacement.isEmpty else { return trimmed }

        let lowered = trimmed.lowercased()
        var bestRange: Range<String.Index>?
        var bestAnchor: String?

        for anchor in replacementAnchors {
            let escaped = NSRegularExpression.escapedPattern(for: anchor)
            let pattern = "(?i)\\b\(escaped)\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length))
            guard let match = matches.last,
                  let range = Range(match.range, in: trimmed) else {
                continue
            }

            if let existingRange = bestRange {
                if trimmed.distance(from: trimmed.startIndex, to: range.upperBound)
                    <= trimmed.distance(from: trimmed.startIndex, to: existingRange.upperBound) {
                    continue
                }
            }

            bestRange = range
            bestAnchor = anchor
        }

        if let bestRange, let bestAnchor, !lowered.hasSuffix(bestAnchor) {
            let anchorSuffix = String(trimmed[..<bestRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(anchorSuffix) \(cleanedReplacement)".trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard words.count > 1 else { return cleanedReplacement }
        let prefix = words.dropLast().joined(separator: " ")
        return "\(prefix) \(cleanedReplacement)"
    }

    private func rewrittenText(from original: String, replacement: String) -> String {
        if shouldReplaceEntireClause(original: original, replacement: replacement) {
            return replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return replaceTail(in: original, with: replacement)
    }

    private func shouldReplaceEntireClause(original: String, replacement: String) -> Bool {
        let originalWords = normalizedWords(in: original)
        let replacementWords = normalizedWords(in: replacement)
        guard !originalWords.isEmpty, !replacementWords.isEmpty else { return false }

        let suffixOverlap = commonSuffixCount(lhs: originalWords, rhs: replacementWords)
        let prefixOverlap = commonPrefixCount(lhs: originalWords, rhs: replacementWords)
        let minCount = min(originalWords.count, replacementWords.count)

        if originalWords.count == replacementWords.count, suffixOverlap >= max(2, minCount - 1) {
            return true
        }

        if prefixOverlap >= 2, replacementWords.count >= originalWords.count {
            return true
        }

        let shared = Set(originalWords).intersection(Set(replacementWords)).count
        return shared >= max(3, minCount - 1) && abs(originalWords.count - replacementWords.count) <= 1
    }

    private func normalizedWords(in text: String) -> [String] {
        text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { token in
                token.unicodeScalars
                    .filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
                    .map(String.init)
                    .joined()
                    .lowercased()
            }
            .filter { !$0.isEmpty }
    }

    private func commonSuffixCount(lhs: [String], rhs: [String]) -> Int {
        var count = 0
        var lhsIndex = lhs.count - 1
        var rhsIndex = rhs.count - 1

        while lhsIndex >= 0, rhsIndex >= 0, lhs[lhsIndex] == rhs[rhsIndex] {
            count += 1
            lhsIndex -= 1
            rhsIndex -= 1
        }

        return count
    }

    private func commonPrefixCount(lhs: [String], rhs: [String]) -> Int {
        var count = 0
        let limit = min(lhs.count, rhs.count)
        while count < limit, lhs[count] == rhs[count] {
            count += 1
        }
        return count
    }

    private func correctionKind(for cue: String) -> ResolvedCorrectionKind {
        if restartCues.contains(cue) {
            return .restart
        }

        if deleteCues.contains(cue) {
            return .restart
        }

        if formattingInstructionCues.contains(cue) {
            return .localReplacement
        }

        if cue == "i mean" || cue == "say" || cue == "change that to" || cue == "change this to" || cue.hasPrefix("rewrite") || cue.hasPrefix("rephrase") || cue.hasPrefix("reword") || cue.hasPrefix("replace") || cue.hasPrefix("change") || cue.hasPrefix("correct") || cue.hasPrefix("fix") || cue.hasPrefix("update") {
            return .localReplacement
        }

        return .overwrite
    }

    private func replacementCandidate(
        inlineRemainder: String,
        after index: Int,
        clauses: [Clause]
    ) -> ReplacementCandidate? {
        let trimmedRemainder = inlineRemainder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRemainder.isEmpty, !isInstructionOnlyClause(trimmedRemainder) {
            return ReplacementCandidate(text: trimmedRemainder, consumedClauses: 0)
        }

        var lookahead = index + 1
        while lookahead < clauses.count {
            let candidate = stripLeadingPreambles(from: clauses[lookahead].text).trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.isEmpty {
                lookahead += 1
                continue
            }
            if isInstructionOnlyClause(candidate) {
                lookahead += 1
                continue
            }
            return ReplacementCandidate(text: candidate, consumedClauses: lookahead - index)
        }

        return nil
    }

    private func range(of loweredNeedle: String, in original: String) -> Range<String.Index>? {
        let lowered = original.lowercased()
        guard let range = lowered.range(of: loweredNeedle.lowercased()) else { return nil }
        let lowerDistance = lowered.distance(from: lowered.startIndex, to: range.lowerBound)
        let upperDistance = lowered.distance(from: lowered.startIndex, to: range.upperBound)
        guard let lowerBound = original.index(original.startIndex, offsetBy: lowerDistance, limitedBy: original.endIndex),
              let upperBound = original.index(original.startIndex, offsetBy: upperDistance, limitedBy: original.endIndex) else {
            return nil
        }
        return lowerBound..<upperBound
    }
}
