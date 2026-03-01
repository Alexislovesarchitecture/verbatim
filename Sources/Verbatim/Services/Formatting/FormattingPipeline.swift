import Foundation

protocol FormattingPipelineProtocol {
    func apply(
        rawText: String,
        styleProfile: StyleProfile,
        dictionaryEntries: [DictionaryEntry],
        snippetEntries: [SnippetEntry],
        applyDictionaryReplacements: Bool,
        applySnippets: Bool,
        snippetGlobalExactMatch: Bool,
        removeFillers: Bool,
        interpretVoiceCommands: Bool
    ) -> String
}

struct FormattingPipeline: FormattingPipelineProtocol {
    func apply(
        rawText: String,
        styleProfile: StyleProfile,
        dictionaryEntries: [DictionaryEntry],
        snippetEntries: [SnippetEntry],
        applyDictionaryReplacements: Bool,
        applySnippets: Bool,
        snippetGlobalExactMatch: Bool,
        removeFillers: Bool,
        interpretVoiceCommands: Bool
    ) -> String {
        var current = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return "" }

        if applyDictionaryReplacements {
            current = FormattingSteps.applyDictionary(current, entries: dictionaryEntries)
        }

        if applySnippets {
            current = FormattingSteps.applySnippets(current, snippets: snippetEntries, globalRequireExactMatch: snippetGlobalExactMatch)
        }

        if interpretVoiceCommands {
            current = FormattingSteps.normalizeVoiceCommands(current)
        }

        if removeFillers {
            current = FormattingSteps.normalizeFillers(current)
        }

        current = FormattingSteps.applyCaps(current, mode: styleProfile.capsMode)
        current = FormattingSteps.applyPunctuation(current, mode: styleProfile.punctuationMode)
        current = FormattingSteps.applyExclamations(current, mode: styleProfile.exclamationMode)

        return current
    }
}
