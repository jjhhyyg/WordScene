import Foundation
import Security

protocol CredentialStoring: Sendable {
    func save(_ value: String, account: String) throws
    func read(account: String) throws -> String?
    func delete(account: String) throws
}

struct KeychainCredentialStore: CredentialStoring {
    let service: String
    let accessGroup: String?

    init(
        service: String = "com.erikssonhou.leximemory.deepseek",
        accessGroup: String? = KeychainAccessGroupResolver.sharedAccessGroup
    ) {
        self.service = service
        self.accessGroup = accessGroup
    }

    func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account, accessGroup: accessGroup)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainCredentialError.unhandledStatus(status)
        }
    }

    func read(account: String) throws -> String? {
        if let value = try read(account: account, accessGroup: accessGroup) {
            return value
        }

        guard accessGroup != nil,
              let legacyValue = try read(account: account, accessGroup: nil) else {
            return nil
        }

        try save(legacyValue, account: account)
        return legacyValue
    }

    func delete(account: String) throws {
        try delete(account: account, accessGroup: accessGroup)

        if accessGroup != nil {
            try delete(account: account, accessGroup: nil)
        }
    }

    private func read(account: String, accessGroup: String?) throws -> String? {
        var query = baseQuery(account: account, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainCredentialError.unhandledStatus(status)
        }

        guard let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private func delete(account: String, accessGroup: String?) throws {
        let status = SecItemDelete(baseQuery(account: account, accessGroup: accessGroup) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialError.unhandledStatus(status)
        }
    }

    private func baseQuery(account: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }
}

private enum KeychainAccessGroupResolver {
    #if os(iOS)
    static let sharedAccessGroup: String? = "JU68L3U235.com.erikssonhou.leximemory"
    #else
    static let sharedAccessGroup: String? = nil
    #endif
}

enum KeychainCredentialError: Error, Equatable {
    case unhandledStatus(OSStatus)
}
