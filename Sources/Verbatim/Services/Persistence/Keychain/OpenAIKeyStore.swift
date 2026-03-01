import Foundation
import Security

protocol OpenAIKeyStoring {
    func load() throws -> String?
    func save(_ key: String) throws
    func clear() throws
}

final class OpenAIKeyStore: OpenAIKeyStoring {
    private let service: String
    private let account: String

    init(service: String = "com.studiobluework.verbatim", account: String = "openai-api-key") {
        self.service = service
        self.account = account
    }

    func load() throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { return nil }
            throw KeyStoreError(status)
        }

        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ key: String) throws {
        let data = key.data(using: .utf8) ?? Data()
        do {
            _ = try? load()
            let update: [String: Any] = [kSecValueData as String: data]
            let status = SecItemUpdate(
                [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary,
                update as CFDictionary
            )

            if status != errSecSuccess {
                let add: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
                ]
                let addStatus = SecItemAdd(add as CFDictionary, nil)
                if addStatus != errSecSuccess {
                    throw KeyStoreError(addStatus)
                }
            }
        } catch {
            throw error
        }
    }

    func clear() throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeyStoreError(status)
        }
    }
}

struct KeyStoreError: LocalizedError {
    let code: OSStatus

    init(_ code: OSStatus) {
        self.code = code
    }

    var errorDescription: String? {
        String(describing: code)
    }
}
