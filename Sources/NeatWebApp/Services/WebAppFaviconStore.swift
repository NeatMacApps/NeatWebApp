import Foundation
import AppKit

@MainActor
final class WebAppFaviconStore {
    private static let changedNotification = Notification.Name("com.geraltgraham.NeatWebApp.favicon.changed")
    private let fileManager: FileManager
    private let directoryURL: URL
    private let dockSourceDirectoryURL: URL

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        bundleIdentifier: String? = nil
    ) {
        self.fileManager = fileManager
        let supportBundleIdentifier = bundleIdentifier ?? Self.defaultSupportBundleIdentifier()
        if let directoryURL {
            self.directoryURL = directoryURL
            self.dockSourceDirectoryURL = directoryURL.appending(path: "DockSources", directoryHint: .isDirectory)
        } else {
            let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
                .flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) : nil }
                ?? fileManager.homeDirectoryForCurrentUser.appending(path: ".config", directoryHint: .isDirectory)
            self.dockSourceDirectoryURL = configHome
                .appending(path: supportBundleIdentifier, directoryHint: .isDirectory)
                .appending(path: "DockSources", directoryHint: .isDirectory)
            let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)
            self.directoryURL = applicationSupportURL
                .appending(path: supportBundleIdentifier, directoryHint: .isDirectory)
                .appending(path: "Favicons", directoryHint: .isDirectory)
        }
    }

    func load(for appID: String) -> NSImage? {
        let url = fileURL(for: appID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    func loadDockSource(for appID: String) -> NSImage? {
        let url = dockSourceDirectoryURL.appending(path: sanitizedFileName(for: appID))
        return NSImage(contentsOf: url) ?? load(for: appID)
    }

    func saveDockSource(_ image: NSImage, for appID: String) {
        guard let data = image.pngRepresentation else { return }
        do {
            try fileManager.createDirectory(at: dockSourceDirectoryURL, withIntermediateDirectories: true)
            try data.write(to: dockSourceDirectoryURL.appending(path: sanitizedFileName(for: appID)), options: .atomic)
            publishChange(for: appID)
        } catch {
            NSLog("Failed to cache the website Dock image: %@", error.localizedDescription)
        }
    }

    func contains(appID: String) -> Bool {
        fileManager.fileExists(atPath: fileURL(for: appID).path)
    }

    func save(_ image: NSImage, for appID: String) {
        guard let data = image.pngRepresentation else {
            return
        }

        do {
            try createDirectoryIfNeeded()
            try data.write(to: fileURL(for: appID), options: .atomic)
            publishChange(for: appID)
        } catch {
            return
        }
    }

    func delete(for appID: String) {
        let urls = [fileURL(for: appID), dockSourceDirectoryURL.appending(path: sanitizedFileName(for: appID))]
        do {
            for url in urls where fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            publishChange(for: appID)
        } catch {
            NSLog("Failed to remove the cached website icon: %@", error.localizedDescription)
        }
    }

    func observeChanges(for appID: String, using handler: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: Self.changedNotification, object: appID, queue: .main
        ) { _ in
            Task { @MainActor in handler() }
        }
    }

    func removeObserver(_ observer: NSObjectProtocol) {
        DistributedNotificationCenter.default().removeObserver(observer)
    }

    private func publishChange(for appID: String) {
        DistributedNotificationCenter.default().postNotificationName(
            Self.changedNotification, object: appID, userInfo: nil, deliverImmediately: true
        )
    }

    private func createDirectoryIfNeeded() throws {
        if fileManager.fileExists(atPath: directoryURL.path) {
            return
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func fileURL(for appID: String) -> URL {
        directoryURL.appending(path: sanitizedFileName(for: appID), directoryHint: .notDirectory)
    }

    private func sanitizedFileName(for appID: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitizedScalars = appID.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? String(scalar) : "_"
        }
        let baseName = sanitizedScalars.joined()
        return "\(baseName).png"
    }

    private static func defaultSupportBundleIdentifier() -> String {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty else {
            return "NeatWebApp"
        }

        if bundleIdentifier.hasSuffix("Runtime") {
            return String(bundleIdentifier.dropLast("Runtime".count))
        }

        return bundleIdentifier
    }
}

private extension NSImage {
    var pngRepresentation: Data? {
        guard let tiffRepresentation else {
            return nil
        }

        guard
            let bitmapRepresentation = NSBitmapImageRep(data: tiffRepresentation),
            let pngData = bitmapRepresentation.representation(using: .png, properties: [:])
        else {
            return nil
        }

        return pngData
    }
}
