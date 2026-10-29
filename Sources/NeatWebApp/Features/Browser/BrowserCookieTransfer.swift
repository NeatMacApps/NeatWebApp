import Foundation
import Security
import WebKit

@MainActor
enum BrowserCookieTransfer {
    private nonisolated static let service = "com.geraltgraham.NeatWebApp.bookmark-cookie-handoff"

    /// Stage credentials in Keychain, never in distributed notifications or catalog preferences.
    static func stage(from source: WKWebsiteDataStore, for appID: String) async throws {
        let cookies = await source.httpCookieStore.allCookies()
        let properties = cookies.map { cookie in
            (cookie.properties ?? [:]).reduce(into: [String: Any]()) { result, entry in
                result[entry.key.rawValue] = (entry.value as? URL)?.absoluteString ?? entry.value
            }
        }
        let data = try PropertyListSerialization.data(fromPropertyList: properties, format: .binary, options: 0)
        try await Task.detached {
            try stageData(data, for: appID)
        }.value
    }

    /// Run in the destination runtime, before its first webpage request.
    @discardableResult
    static func restore(to destination: WKWebsiteDataStore, for appID: String) async throws -> Bool {
        guard let data = try await Task.detached(operation: {
            try loadData(for: appID)
        }).value else { return false }
        guard let rows = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]] else {
            throw TransferError.invalidSnapshot
        }
        let cookies = try rows.map { properties in
            let typed = Dictionary(uniqueKeysWithValues: properties.map { (HTTPCookiePropertyKey($0.key), $0.value) })
            guard let cookie = HTTPCookie(properties: typed) else { throw TransferError.invalidSnapshot }
            return cookie
        }
        try await install(cookies, into: destination)
        try await discard(for: appID)
        return true
    }

    static func discard(for appID: String) async throws {
        try await Task.detached {
            let status = SecItemDelete(query(appID: appID) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw TransferError.keychain(status) }
        }.value
    }

    private nonisolated static func stageData(_ data: Data, for appID: String) throws {
        var item = query(appID: appID)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw TransferError.keychain(status) }
    }

    private nonisolated static func loadData(for appID: String) throws -> Data? {
        var search = query(appID: appID)
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw TransferError.keychain(status) }
        guard let data = result as? Data else { throw TransferError.invalidSnapshot }
        return data
    }

    private nonisolated static func query(appID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: appID
        ]
    }

    private static func install(_ cookies: [HTTPCookie], into destination: WKWebsiteDataStore) async throws {
        let snapshot = cookies.filter { $0.expiresDate.map { $0 > Date() } ?? true }
        for cookie in snapshot {
            await destination.httpCookieStore.setCookie(cookie)
        }
        let copied = await destination.httpCookieStore.allCookies()
        guard snapshot.allSatisfy({ original in
            copied.contains {
                $0.name == original.name && $0.domain == original.domain
                    && $0.path == original.path && $0.value == original.value
                    && $0.isSecure == original.isSecure && $0.isHTTPOnly == original.isHTTPOnly
                    && $0.isSessionOnly == original.isSessionOnly
                    && $0.expiresDate == original.expiresDate
            }
        }) else {
            throw TransferError.incomplete
        }
    }

    enum TransferError: Error {
        case keychain(OSStatus)
        case invalidSnapshot
        case incomplete
    }
}
