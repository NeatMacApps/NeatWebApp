import Foundation
import AppKit

@MainActor
final class WebAppFaviconStore {
    private let fileManager: FileManager
    private let directoryURL: URL

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "NeatWebApp"
    ) {
        self.fileManager = fileManager

        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)
            self.directoryURL = applicationSupportURL
                .appending(path: bundleIdentifier, directoryHint: .isDirectory)
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

    func save(_ image: NSImage, for appID: String) {
        guard let data = image.pngRepresentation else {
            return
        }

        do {
            try createDirectoryIfNeeded()
            try data.write(to: fileURL(for: appID), options: .atomic)
        } catch {
            return
        }
    }

    func delete(for appID: String) {
        let url = fileURL(for: appID)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            return
        }
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
