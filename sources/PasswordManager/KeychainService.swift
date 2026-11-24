//
//  KeychainService.swift
//  iTerm2SharedARC
//

import Foundation
import Security

enum KeychainService {
    private static let errorDomain = "com.ecnelises.latterm.keychain"

    static func password(forService service: String,
                         account: String,
                         label: String? = nil) throws -> String {
        var query = baseQuery(forService: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw keychainError(for: status)
        }
        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw keychainError(for: errSecDecode)
        }
        return password
    }

    static func setPassword(_ password: String,
                            forService service: String,
                            account: String,
                            label: String? = nil) throws {
        guard let data = password.data(using: .utf8) else {
            throw keychainError(for: errSecParam)
        }

        let deleteQuery = baseQuery(forService: service, account: account)
        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            throw keychainError(for: deleteStatus)
        }

        var addQuery = baseQuery(forService: service, account: account)
        addQuery[kSecValueData as String] = data
        if let label {
            addQuery[kSecAttrLabel as String] = label
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw keychainError(for: addStatus)
        }
    }

    static func deletePassword(forService service: String,
                               account: String,
                               label: String? = nil) throws {
        let query = baseQuery(forService: service, account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else {
            throw keychainError(for: status)
        }
    }

    static func accounts(forService service: String) -> [NSDictionary] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [NSDictionary] else {
            return []
        }
        return items
    }

    private static func baseQuery(forService service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }

    private static func keychainError(for status: OSStatus) -> NSError {
        let message = (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
        return NSError(domain: errorDomain,
                       code: Int(status),
                       userInfo: [NSLocalizedDescriptionKey: message])
    }
}
