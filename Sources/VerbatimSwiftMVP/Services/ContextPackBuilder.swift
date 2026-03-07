import Foundation

final class ContextPackBuilder {
    func build(
        activeContext: ActiveAppContext,
        logicSettings: LogicSettings,
        refineSettings: RefineSettings,
        deterministicText: String
    ) -> ContextPack {
        let relevantGlossary = relevantGlossaryEntries(from: refineSettings.glossary, text: deterministicText)
        let sessionMemory = Array(
            refineSettings.sessionMemory
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(3)
        )

        return ContextPack(
            activeAppName: activeContext.appName,
            bundleID: activeContext.bundleID,
            styleCategory: activeContext.styleCategory,
            windowTitle: activeContext.windowTitle,
            focusedElementRole: activeContext.focusedElementRole,
            punctuationMode: logicSettings.outputFormat == .paragraph ? "sentence" : "auto",
            fillerRemovalEnabled: logicSettings.removeFillerWords,
            autoDetectLists: logicSettings.autoDetectLists,
            outputFormat: logicSettings.outputFormat,
            selfCorrectionMode: logicSettings.selfCorrectionMode,
            flagLowConfidenceWords: logicSettings.flagLowConfidenceWords,
            reasoningEffort: logicSettings.reasoningEffort,
            glossary: relevantGlossary,
            sessionMemory: sessionMemory
        )
    }

    private func relevantGlossaryEntries(from glossary: [GlossaryEntry], text: String) -> [GlossaryEntry] {
        glossary.filter { entry in
            guard !entry.from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            let escaped = NSRegularExpression.escapedPattern(for: entry.from)
            let pattern = "\\b\(escaped)\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(location: 0, length: (text as NSString).length)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
    }
}
