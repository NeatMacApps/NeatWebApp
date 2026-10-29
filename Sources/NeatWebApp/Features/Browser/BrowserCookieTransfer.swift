import Foundation
import WebKit

@MainActor
enum BrowserCookieTransfer {
    static func copy(from source: WKWebsiteDataStore, to destination: WKWebsiteDataStore) async throws {
        let snapshot = await source.httpCookieStore.allCookies().filter {
            $0.expiresDate.map { $0 > Date() } ?? true
        }
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
        case incomplete
    }
}
