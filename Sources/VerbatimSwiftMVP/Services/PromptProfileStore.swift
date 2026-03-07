import Foundation

actor PromptProfileStore {
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var loadedProfiles: [PromptProfile] = []

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func profiles() -> [PromptProfile] {
        if loadedProfiles.isEmpty {
            loadedProfiles = loadMergedProfiles()
        }
        return loadedProfiles
    }

    func profile(id: String) -> PromptProfile? {
        profiles().first { $0.id == id }
    }

    func setProfileEnabled(id: String, enabled: Bool) {
        if loadedProfiles.isEmpty {
            loadedProfiles = loadMergedProfiles()
        }

        guard let index = loadedProfiles.firstIndex(where: { $0.id == id }) else {
            return
        }

        loadedProfiles[index].enabled = enabled
        persistOverrides(loadedProfiles)
    }

    func replaceProfiles(_ profiles: [PromptProfile]) {
        loadedProfiles = profiles
        persistOverrides(profiles)
    }

    private func loadMergedProfiles() -> [PromptProfile] {
        let bundled = loadBundledProfiles()
        guard !bundled.isEmpty else { return [] }

        guard let overrides = loadOverrides(), !overrides.isEmpty else {
            return bundled.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        var mergedByID = Dictionary(uniqueKeysWithValues: bundled.map { ($0.id, $0) })
        for override in overrides {
            mergedByID[override.id] = override
        }

        return mergedByID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func loadBundledProfiles() -> [PromptProfile] {
        guard let url = Bundle.module.url(forResource: "PromptProfiles", withExtension: "json") else {
            return []
        }

        guard let data = try? Data(contentsOf: url) else {
            return []
        }

        return (try? decoder.decode([PromptProfile].self, from: data)) ?? []
    }

    private func loadOverrides() -> [PromptProfile]? {
        let url = overridesURL
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? decoder.decode([PromptProfile].self, from: data)
    }

    private func persistOverrides(_ profiles: [PromptProfile]) {
        let url = overridesURL
        ensureDirectoryExists(at: url.deletingLastPathComponent())

        guard let data = try? encoder.encode(profiles) else {
            return
        }

        try? data.write(to: url, options: .atomic)
    }

    private var overridesURL: URL {
        appSupportDirectory.appendingPathComponent("PromptProfiles.json")
    }

    private var appSupportDirectory: URL {
        if let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return root.appendingPathComponent("VerbatimSwiftMVP", isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("VerbatimSwiftMVP", isDirectory: true)
    }

    private func ensureDirectoryExists(at url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
