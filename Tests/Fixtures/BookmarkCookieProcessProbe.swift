import AppKit
import Foundation
import WebKit

/// Standalone regression fixture: compile with BrowserCookieTransfer.swift and sign once.
/// Every process uses the same executable identity; no cookie values leave Keychain/WebKit.
@main
struct BookmarkCookieProcessProbe {
    enum Failure: Error { case invalidArguments, cookieMismatch, childFailed }

    @MainActor
    static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let arguments = CommandLine.arguments
        if arguments.count == 2, arguments[1] == "cleanup" {
            let cleanupContext = WKWebsiteDataStore.nonPersistent()
            _ = cleanupContext
            let identifiers: [UUID] = await withCheckedContinuation { continuation in
                WKWebsiteDataStore.fetchAllDataStoreIdentifiers { continuation.resume(returning: $0) }
            }
            for identifier in identifiers { try await WKWebsiteDataStore.remove(forIdentifier: identifier) }
            print("PASS: removed retained fixture stores")
            return
        }
        if arguments.count == 1 {
            let destinationID = UUID()
            let sourceID = UUID()
            let status = try await runChild(["stage", destinationID.uuidString, sourceID.uuidString])
            guard status == 0 else { throw Failure.childFailed }
            // Initialize WebKit in this coordinator before using its static cleanup API.
            let cleanupContext = WKWebsiteDataStore.nonPersistent()
            _ = cleanupContext
            try await WKWebsiteDataStore.remove(forIdentifier: sourceID)
            try await WKWebsiteDataStore.remove(forIdentifier: destinationID)
            print("PASS: separate-process cookie import, isolation, consumption and fixture cleanup")
            return
        }
        guard arguments.count >= 3, let destinationID = UUID(uuidString: arguments[2]) else {
            throw Failure.invalidArguments
        }
        if arguments[1] == "verify" {
            let destination = WKWebsiteDataStore(forIdentifier: destinationID)
            let imported = try await BrowserCookieTransfer.restore(to: destination, for: destinationID.uuidString)
            let cookies = await destination.httpCookieStore.allCookies()
            guard imported, cookies.count == 2,
                  cookies.contains(where: { $0.name == "persistent" && $0.isHTTPOnly && $0.isSecure }),
                  cookies.contains(where: { $0.name == "session" && $0.isSessionOnly }) else {
                throw Failure.cookieMismatch
            }
            let replayed = try await BrowserCookieTransfer.restore(to: destination, for: destinationID.uuidString)
            guard !replayed, let cookie = cookies.first else { throw Failure.cookieMismatch }
            await destination.httpCookieStore.deleteCookie(cookie)
            print("PASS: destination read persistent + session cookies; one-time handoff consumed")
            return
        }
        guard arguments[1] == "stage", arguments.count == 4,
              let sourceID = UUID(uuidString: arguments[3]) else { throw Failure.invalidArguments }
        let source = WKWebsiteDataStore(forIdentifier: sourceID)
        for persistent in [true, false] {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: persistent ? "persistent" : "session", .value: "fixture-only",
                .domain: "example.com", .path: "/", .secure: "TRUE", HTTPCookiePropertyKey("HttpOnly"): "TRUE"
            ]
            if persistent { properties[.expires] = Date(timeIntervalSince1970: 2_000_000_000) }
            guard let cookie = HTTPCookie(properties: properties) else { throw Failure.cookieMismatch }
            await source.httpCookieStore.setCookie(cookie)
        }
        try await BrowserCookieTransfer.stage(from: source, for: destinationID.uuidString)
        let status = try await runChild(["verify", destinationID.uuidString])
        guard status == 0 else { throw Failure.childFailed }
        let unchanged = await source.httpCookieStore.allCookies()
        guard unchanged.count == 2 else { throw Failure.cookieMismatch }
    }

    @MainActor
    private static func runChild(_ arguments: [String]) async throws -> Int32 {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = arguments
        try child.run()
        while child.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        return child.terminationStatus
    }
}
