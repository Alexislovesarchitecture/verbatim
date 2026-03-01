import Foundation

@MainActor
final class StyleViewModel: ObservableObject {
    @Published var selectedCategory: StyleCategory = .personal
    @Published private(set) var profiles: [StyleCategory: StyleProfile] = [:]

    private let styleRepository: StyleRepository
    private let sampleText = "hey can we move this call to tomorrow at ten"

    init(styleRepository: StyleRepository) {
        self.styleRepository = styleRepository
        load()
    }

    func load() {
        let all = styleRepository.all()
        profiles = Dictionary(uniqueKeysWithValues: all.map { ($0.category, $0) })
        if profiles[selectedCategory] == nil {
            let fallback = StyleProfile(category: selectedCategory)
            styleRepository.upsert(fallback)
            profiles[selectedCategory] = fallback
        }
    }

    var activeProfile: StyleProfile {
        profiles[selectedCategory] ?? StyleProfile(category: selectedCategory)
    }

    func profile(for category: StyleCategory) -> StyleProfile {
        profiles[category] ?? StyleProfile(category: category)
    }

    func toneCards() -> [StyleTone] {
        StyleTone.allCases
    }

    func selectTone(_ tone: StyleTone, for category: StyleCategory) {
        var profile = profile(for: category)
        profile.tone = tone
        profile.capsMode = tone == .veryCasual || tone == .excitedOptional ? .lowercase : .sentenceCase
        profile.punctuationMode = tone == .casual ? .light : .normal
        profile.exclamationMode = tone == .excitedOptional ? .more : (tone == .formal ? .normal : .none)
        profile.interpretVoiceCommands = profile.interpretVoiceCommands
        profile.removeFillers = profile.removeFillers
        styleRepository.upsert(profile)
        load()
    }

    func updateProfile(_ profile: StyleProfile, caps: CapsMode, punctuation: PunctuationMode, exclamations: ExclamationMode, removeFillers: Bool, interpretVoiceCommands: Bool) {
        profile.capsMode = caps
        profile.punctuationMode = punctuation
        profile.exclamationMode = exclamations
        profile.removeFillers = removeFillers
        profile.interpretVoiceCommands = interpretVoiceCommands
        styleRepository.upsert(profile)
        load()
    }

    func previewText(for category: StyleCategory) -> String {
        let profile = profile(for: category)
        let pipeline = FormattingPipeline()
        return pipeline.apply(
            rawText: sampleText,
            styleProfile: profile,
            dictionaryEntries: [],
            snippetEntries: [],
            applyDictionaryReplacements: false,
            applySnippets: false,
            snippetGlobalExactMatch: false,
            removeFillers: profile.removeFillers,
            interpretVoiceCommands: profile.interpretVoiceCommands
        )
    }
}
