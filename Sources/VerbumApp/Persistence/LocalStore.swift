import Foundation

struct LocalStore {
    private let rootURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(appFolderName: String = "Verbum") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.rootURL = base.appendingPathComponent(appFolderName, isDirectory: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func loadOrSeed<T: Codable>(_ type: T.Type, filename: String, seed: T) -> T {
        do {
            try prepare()
            let url = rootURL.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                return try decoder.decode(T.self, from: data)
            }
            try save(seed, filename: filename)
            return seed
        } catch {
            return seed
        }
    }

    func save<T: Codable>(_ value: T, filename: String) throws {
        try prepare()
        let url = rootURL.appendingPathComponent(filename)
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    func fileURL(_ filename: String) -> URL {
        rootURL.appendingPathComponent(filename)
    }
}
