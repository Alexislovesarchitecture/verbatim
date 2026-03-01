import Foundation

final class DataStore {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let stateURL: URL

    init(filename: String = "verbatim-state.json") {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = baseURL.appendingPathComponent("Verbatim", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
        stateURL = folder.appendingPathComponent(filename)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> PersistedState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? decoder.decode(PersistedState.self, from: data) else {
            return .sample
        }
        return state
    }

    func save(_ state: PersistedState) {
        do {
            let data = try encoder.encode(state)
            try data.write(to: stateURL, options: [.atomic])
        } catch {
            print("Failed to save state: \(error)")
        }
    }
}
