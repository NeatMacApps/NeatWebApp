import Foundation
import SwiftUI

struct BrowserDownloadControl: View {
    let session: BrowserSession
    let theme: BrowserChromeTheme

    @State private var isPresented = false

    var body: some View {
        if let item = session.downloadIndicatorItem {
            HStack(spacing: 0) {
                Button { isPresented.toggle() } label: {
                    Label(title(for: item), systemImage: item.statusSymbol)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: BrowserChromeMetrics.buttonSize)
                        .contentShape(Capsule())
                }
                .help(Text("browser.download.show"))
                .accessibilityLabel(String(format: downloadLocalized("browser.download.accessibility.label"), title(for: item)))

                if session.activeDownloadCount == 0 {
                    Button(action: session.clearFinishedDownloads) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: BrowserChromeMetrics.buttonSize, height: BrowserChromeMetrics.buttonSize)
                            .contentShape(Circle())
                    }
                    .help(Text("browser.download.clear_finished"))
                    .accessibilityLabel(downloadLocalized("browser.download.clear_finished"))
                }
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .foregroundStyle(theme.foregroundColor.color.opacity(0.88))
            .background(Capsule().fill(theme.highlightedFillColor.color))
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                BrowserDownloadPanel(session: session) { isPresented = false }
            }
        }
    }

    private func title(for item: BrowserDownloadItem) -> String {
        if session.activeDownloadCount > 1 {
            return String(format: downloadLocalized("browser.download.status.multiple"), session.activeDownloadCount)
        }
        if item.phase == .running, let fraction = item.fractionCompleted {
            return String(format: downloadLocalized("browser.download.status.progress"), Int(fraction * 100))
        }
        return item.statusTitle
    }
}

private struct BrowserDownloadPanel: View {
    let session: BrowserSession
    let dismiss: () -> Void

    private var items: [BrowserDownloadItem] {
        session.downloadItems.filter { $0.phase == .running }
            + session.downloadItems.filter { $0.phase != .running }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("browser.download.title")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Button("browser.download.clear") {
                    if session.activeDownloadCount == 0 { dismiss() }
                    session.clearFinishedDownloads()
                }
                .disabled(!session.hasFinishedDownloads)
                .help(Text("browser.download.clear_finished"))
                .accessibilityLabel(downloadLocalized("browser.download.clear_finished"))

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .help(Text("browser.download.close"))
                .accessibilityLabel(downloadLocalized("browser.download.close"))
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        BrowserDownloadRow(item: item, session: session)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        if item.id != items.last?.id {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(items.count) * 70, 280))
        }
        .buttonStyle(.borderless)
        .focusEffectDisabled()
        .font(.system(size: 11))
        .frame(width: 320)
    }
}

private struct BrowserDownloadRow: View {
    let item: BrowserDownloadItem
    let session: BrowserSession

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.phase == .failed || item.message != nil ? "exclamationmark.triangle" : "doc")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: item.filename)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.filename)

                if item.phase == .running {
                    ProgressView(value: item.fractionCompleted)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .accessibilityLabel(String(format: downloadLocalized("browser.download.help.running"), item.filename))
                }

                Text(verbatim: detail)
                    .font(.system(size: 10))
                    .foregroundStyle(item.message == nil ? Color.secondary : Color.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if item.phase == .completed {
                Button { session.revealDownload(id: item.id) } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 20, height: 24)
                        .contentShape(Rectangle())
                }
                .help(String(format: downloadLocalized("browser.download.help.reveal"), item.filename))
                .accessibilityLabel(String(format: downloadLocalized("browser.download.help.reveal"), item.filename))
            }

            if item.phase != .running {
                Button { session.clearDownload(id: item.id) } label: {
                    Image(systemName: "xmark")
                        .frame(width: 20, height: 24)
                        .contentShape(Rectangle())
                }
                .help(Text("browser.download.dismiss"))
                .accessibilityLabel(downloadLocalized("browser.download.dismiss"))
            }
        }
        .frame(minHeight: 46, alignment: .top)
    }

    private var detail: String {
        if let message = item.message { return message }
        guard item.phase == .running else { return item.statusTitle }
        let transferred = ByteCountFormatter.string(fromByteCount: item.completedBytes, countStyle: .file)
        guard let total = item.totalBytes, let fraction = item.fractionCompleted else {
            return item.completedBytes > 0 ? transferred : item.statusTitle
        }
        let size = String(format: downloadLocalized("browser.download.bytes"), transferred,
                          ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
        return "\(size) · \(fraction.formatted(.percent.precision(.fractionLength(0))))"
    }
}

private extension BrowserDownloadItem {
    var statusSymbol: String {
        switch phase {
        case .running: "arrow.down.circle"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    var statusTitle: String {
        switch phase {
        case .running: downloadLocalized("browser.download.status.running")
        case .completed: downloadLocalized("browser.download.status.completed")
        case .failed: downloadLocalized("browser.download.status.failed")
        }
    }
}

private func downloadLocalized(_ key: String) -> String {
    String(localized: LocalizedStringResource(stringLiteral: key))
}
