import AppKit

/// Each assigned helper owns one native Dock/switcher tile; standby helpers never install one.
@MainActor
final class RuntimeDockIdentity {
    private let faviconStore: WebAppFaviconStore
    private let setIcon: (NSImage) -> Void
    private let promoteApplication: () -> Bool
    private var faviconObserver: NSObjectProtocol?

    init(
        faviconStore: WebAppFaviconStore = WebAppFaviconStore(),
        setIcon: @escaping (NSImage) -> Void = { NSApplication.shared.applicationIconImage = $0 },
        promoteApplication: @escaping () -> Bool = { NSApplication.shared.setActivationPolicy(.regular) }
    ) {
        self.faviconStore = faviconStore
        self.setIcon = setIcon
        self.promoteApplication = promoteApplication
    }

    func update(for definition: WebAppDefinition) {
        stop()
        applyIcon(for: definition)
        faviconObserver = faviconStore.observeChanges(for: definition.id) { [weak self] in
            self?.applyIcon(for: definition)
        }
        // Set the website image before promotion so a cached site never flashes the host icon.
        if !promoteApplication() {
            NSLog("Unable to expose the web app in the system Dock and application switcher.")
        }
    }

    func stop() {
        if let faviconObserver {
            faviconStore.removeObserver(faviconObserver)
            self.faviconObserver = nil
        }
    }

    private func applyIcon(for definition: WebAppDefinition) {
        let source = faviconStore.loadDockSource(for: definition.id)
            ?? NSImage(systemSymbolName: "globe", accessibilityDescription: definition.name)
        // Missing or offline icons use the same rounded tile, never NeatWebApp's branding.
        if let source, let image = WebAppIconNormalizer.normalizedDockIcon(from: source) {
            setIcon(image)
        }
    }
}
