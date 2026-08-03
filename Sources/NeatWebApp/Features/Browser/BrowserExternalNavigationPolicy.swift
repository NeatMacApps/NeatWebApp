import Foundation

enum BrowserExternalNavigationDecision: Equatable {
    case allowInWebView
    case openExternally
    case confirmBeforeOpening
    case reject
}

struct BrowserExternalNavigationPolicy {
    static func decision(for url: URL?, isUserInitiated: Bool) -> BrowserExternalNavigationDecision {
        guard let scheme = url?.scheme?.lowercased() else {
            return .allowInWebView
        }

        switch scheme {
        case "http", "https", "about", "data", "blob", "file":
            return .allowInWebView
        case "javascript", "applescript", "x-apple.systempreferences":
            return .reject
        default:
            return isUserInitiated ? .openExternally : .confirmBeforeOpening
        }
    }
}
