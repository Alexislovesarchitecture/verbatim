import Foundation
import SwiftData

@MainActor
final class SwiftDataSettingsRepository: SettingsRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func settings() -> AppSettings {
        if let existing = (try? context.fetch(FetchDescriptor<AppSettings>()))?.first {
            return existing
        }

        let settings = AppSettings()
        context.insert(LocalBehaviorSettings())
        context.insert(settings)
        save()
        return settings
    }

    func behaviorSettings() -> LocalBehaviorSettings {
        if let existing = (try? context.fetch(FetchDescriptor<LocalBehaviorSettings>()))?.first {
            return existing
        }

        let behavior = LocalBehaviorSettings()
        context.insert(behavior)
        save()
        return behavior
    }

    func save(settings: AppSettings) {
        save()
    }

    func save(behavior: LocalBehaviorSettings) {
        save()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            print("Failed to save settings: \(error)")
        }
    }
}
