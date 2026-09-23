import Foundation
import WebKit

@MainActor
final class BrowserDownloadManager: NSObject, WKDownloadDelegate {
    private let session: BrowserSession
    private var destinationResolver = BrowserDownloadDestinationResolver()
    private var activeDownloads: [ObjectIdentifier: ActiveDownload] = [:]

    init(session: BrowserSession) {
        self.session = session
    }

    func track(_ download: WKDownload, suggestedFilename: String? = nil) {
        let identifier = ObjectIdentifier(download)
        guard activeDownloads[identifier] == nil else {
            return
        }

        let filename = BrowserDownloadDestinationResolver.sanitizedFilename(from: suggestedFilename ?? String(localized: "browser.download.unnamed_file"))
        let itemID = session.startDownload(filename: filename)
        let observation = download.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            Task { @MainActor in
                self?.session.updateDownload(id: itemID, fractionCompleted: progress.fractionCompleted)
            }
        }

        activeDownloads[identifier] = ActiveDownload(itemID: itemID, progressObservation: observation)
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor (URL?) -> Void
    ) {
        let destinationURL = destinationResolver.reserveDestination(suggestedFilename: suggestedFilename)
        let identifier = ObjectIdentifier(download)

        if let activeDownload = activeDownloads[identifier] {
            activeDownloads[identifier] = activeDownload.withDestinationURL(destinationURL)
            session.updateDownload(id: activeDownload.itemID, filename: destinationURL.lastPathComponent)
        } else {
            let itemID = session.startDownload(filename: destinationURL.lastPathComponent)
            activeDownloads[identifier] = ActiveDownload(itemID: itemID, destinationURL: destinationURL)
        }

        completionHandler(destinationURL)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let identifier = ObjectIdentifier(download)
        guard let activeDownload = activeDownloads.removeValue(forKey: identifier) else {
            return
        }

        if let destinationURL = activeDownload.destinationURL {
            destinationResolver.releaseReservation(for: destinationURL)
            session.finishDownload(id: activeDownload.itemID, destinationURL: destinationURL)
        } else {
            session.failDownload(id: activeDownload.itemID, message: String(localized: "browser.download.failed_missing_file"))
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let identifier = ObjectIdentifier(download)
        guard let activeDownload = activeDownloads.removeValue(forKey: identifier) else {
            return
        }

        if let destinationURL = activeDownload.destinationURL {
            destinationResolver.releaseReservation(for: destinationURL)
        }

        session.failDownload(id: activeDownload.itemID, message: String(format: String(localized: "browser.download.failed_format"), error.localizedDescription))
    }
}

private struct ActiveDownload {
    let itemID: UUID
    var destinationURL: URL?
    var progressObservation: NSKeyValueObservation?

    func withDestinationURL(_ url: URL) -> ActiveDownload {
        ActiveDownload(itemID: itemID, destinationURL: url, progressObservation: progressObservation)
    }
}
