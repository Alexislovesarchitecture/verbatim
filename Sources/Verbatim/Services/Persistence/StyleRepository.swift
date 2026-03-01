import Foundation
import SwiftData

@MainActor
final class SwiftDataStyleRepository: StyleRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func all() -> [StyleProfile] {
        let descriptor = FetchDescriptor<StyleProfile>()
        return (try? context.fetch(descriptor))?.sorted(by: { $0.category.rawValue < $1.category.rawValue }) ?? []
    }

    func profile(for category: StyleCategory) -> StyleProfile? {
        let descriptor = FetchDescriptor<StyleProfile>(predicate: #Predicate { $0.category == category && $0.enabled })
        return (try? context.fetch(descriptor))?.first
    }

    func upsert(_ profile: StyleProfile) {
        let existing = profile(for: profile.category)
        if let existing {
            existing.tone = profile.tone
            existing.capsMode = profile.capsMode
            existing.punctuationMode = profile.punctuationMode
            existing.exclamationMode = profile.exclamationMode
            existing.removeFillers = profile.removeFillers
            existing.interpretVoiceCommands = profile.interpretVoiceCommands
            existing.enabled = profile.enabled
        } else {
            context.insert(profile)
        }
        save()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            print("Failed to save style profile: \(error)")
        }
    }
}

extension SwiftDataStyleRepository {
    func ensureDefaults() {
        if all().isEmpty {
            StyleCategory.allCases.forEach {
                context.insert(StyleProfile(category: $0, tone: .casual))
            }
            save()
        }
    }
}
