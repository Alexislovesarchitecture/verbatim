import Foundation

@MainActor
protocol ModelCatalogServiceProtocol {
    func fetchRemoteModelIDs(apiKey: String?) async throws -> Set<String>
}

enum OpenAIModelCatalogError: LocalizedError {
    case missingApiKey
    case invalidResponse
    case requestFailed(Error)
    case noCompatibleModelsFound

    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Set an OpenAI API key to load remote models."
        case .invalidResponse:
            return "Model catalog returned an invalid response."
        case .requestFailed(let error):
            return "Could not load remote models: \(error.localizedDescription)"
        case .noCompatibleModelsFound:
            return "No compatible OpenAI models were returned for the selected role/mode."
        }
    }
}

private struct OpenAIModelListResponse: Decodable {
    let data: [OpenAIModelDescriptor]
}

    private struct OpenAIModelDescriptor: Decodable {
        let id: String
        let owned_by: String?
    }

@MainActor
final class OpenAIModelCatalogService: ModelCatalogServiceProtocol {
    private let endpoint = URL(string: "https://api.openai.com/v1/models")!
    private let session: URLSession
    private var cachedModels: Set<String>?

    init(session: URLSession = .shared) {
        self.session = session
    }

    var cachedOrFallbackModelIDs: Set<String> {
        cachedModels ?? Set(
            ModelRegistry.entries(for: .transcription, mode: .remote, includeAdvanced: true).map(\.id)
                + ModelRegistry.entries(for: .logic, mode: .remote, includeAdvanced: true).map(\.id)
        )
    }

    func fetchRemoteModelIDs(apiKey: String?) async throws -> Set<String> {
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            throw OpenAIModelCatalogError.missingApiKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 45
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenAIModelCatalogError.requestFailed(error)
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OpenAIModelCatalogError.invalidResponse
        }

        guard let decoded = try? JSONDecoder().decode(OpenAIModelListResponse.self, from: data) else {
            throw OpenAIModelCatalogError.invalidResponse
        }

        let availableSet = Set(decoded.data.compactMap(\.id))

        let registryIDs = Set(ModelRegistry.entries(for: .transcription, mode: .remote, includeAdvanced: true).map(\.id))
            .union(Set(ModelRegistry.entries(for: .logic, mode: .remote, includeAdvanced: true).map(\.id)))
        let filtered = availableSet.intersection(registryIDs)
            .sorted()

        guard !filtered.isEmpty else {
            throw OpenAIModelCatalogError.noCompatibleModelsFound
        }

        cachedModels = Set(filtered)
        return cachedModels ?? Set(filtered)
    }

    func isModelAvailableFromCache(_ modelID: String) -> Bool {
        cachedModels?.contains(modelID) == true
    }

    func isModelAvailable(_ modelID: String, apiKey: String?) async -> Bool {
        guard let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return false
        }

        do {
            let available = try await fetchRemoteModelIDs(apiKey: key)
            return available.contains(modelID)
        } catch {
            return cachedModels?.contains(modelID) == true
        }
    }

    private func priority(for id: String) -> Int {
        switch id {
        case "gpt-4o-mini-transcribe":
            return 0
        case "gpt-4o-transcribe":
            return 1
        default:
            return 2
        }
    }

    private func sortRemoteModels(lhs: String, rhs: String) -> Bool {
        let leftPriority = priority(for: lhs)
        let rightPriority = priority(for: rhs)
        if leftPriority != rightPriority {
            return leftPriority < rightPriority
        }
        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }

    func orderedModelIDs(_ modelIDs: Set<String>) -> [String] {
        modelIDs.sorted { sortRemoteModels(lhs: $0, rhs: $1) }
    }

    func hasCachedModelSupport(_ modelID: String) -> Bool {
        isModelAvailableFromCache(modelID)
    }
}
