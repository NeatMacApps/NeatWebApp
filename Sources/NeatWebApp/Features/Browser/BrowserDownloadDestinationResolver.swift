import Foundation

struct BrowserDownloadDestinationResolver {
    let downloadsDirectoryURL: URL
    private let fileManager: FileManager
    private var reservedURLs: Set<URL> = []

    init(
        downloadsDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.downloadsDirectoryURL = downloadsDirectoryURL
            ?? fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
    }

    mutating func reserveDestination(suggestedFilename: String) -> URL {
        let safeFilename = Self.sanitizedFilename(from: suggestedFilename)
        let destinationURL = uniqueDestinationURL(for: safeFilename)
        reservedURLs.insert(destinationURL)
        return destinationURL
    }

    mutating func releaseReservation(for destinationURL: URL) {
        reservedURLs.remove(destinationURL)
    }

    static func sanitizedFilename(from suggestedFilename: String) -> String {
        guard suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return "下载文件"
        }

        let lastPathComponent = URL(fileURLWithPath: suggestedFilename).lastPathComponent
        let invalidCharacters = CharacterSet(charactersIn: "/:\\\0")
        let sanitized = lastPathComponent
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-")))

        guard sanitized.isEmpty == false, sanitized != ".", sanitized != ".." else {
            return "下载文件"
        }

        return sanitized
    }

    private func uniqueDestinationURL(for filename: String) -> URL {
        let firstCandidate = downloadsDirectoryURL.appendingPathComponent(filename, isDirectory: false)
        if isAvailable(firstCandidate) {
            return firstCandidate
        }

        let filenameParts = splitFilename(filename)
        var suffix = 1

        while true {
            let candidateFilename: String
            if filenameParts.extensionName.isEmpty {
                candidateFilename = "\(filenameParts.baseName) (\(suffix))"
            } else {
                candidateFilename = "\(filenameParts.baseName) (\(suffix)).\(filenameParts.extensionName)"
            }

            let candidateURL = downloadsDirectoryURL.appendingPathComponent(candidateFilename, isDirectory: false)
            if isAvailable(candidateURL) {
                return candidateURL
            }

            suffix += 1
        }
    }

    private func isAvailable(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path) == false && reservedURLs.contains(url) == false
    }

    private func splitFilename(_ filename: String) -> (baseName: String, extensionName: String) {
        let nsFilename = filename as NSString
        let extensionName = nsFilename.pathExtension
        let baseName = extensionName.isEmpty ? filename : nsFilename.deletingPathExtension
        return (baseName.isEmpty ? "下载文件" : baseName, extensionName)
    }
}
