import AppKit

/// Each assigned helper owns one native Dock/switcher tile; standby helpers never install one.
@MainActor
final class RuntimeDockIdentity {
    private let faviconStore: WebAppFaviconStore
    private let setIcon: (NSImage) -> Void
    private let promoteApplication: () -> Bool
    private let demoteApplication: () -> Bool
    private var faviconObserver: NSObjectProtocol?

    init(
        faviconStore: WebAppFaviconStore = WebAppFaviconStore(),
        setIcon: @escaping (NSImage) -> Void = { NSApplication.shared.applicationIconImage = $0 },
        promoteApplication: @escaping () -> Bool = { NSApplication.shared.setActivationPolicy(.regular) },
        demoteApplication: @escaping () -> Bool = { NSApplication.shared.setActivationPolicy(.accessory) }
    ) {
        self.faviconStore = faviconStore
        self.setIcon = setIcon
        self.promoteApplication = promoteApplication
        self.demoteApplication = demoteApplication
    }

    func update(for definition: WebAppDefinition) {
        applyVisibility(true, for: definition)
    }

    func applyVisibility(_ visibleInSystemDock: Bool, for definition: WebAppDefinition) {
        stop()
        guard visibleInSystemDock else {
            if !demoteApplication() {
                NSLog("Unable to hide the web app from the system Dock and application switcher.")
            }
            return
        }

        // Promotion recreates the native tile and discards an image set while still accessory.
        if !promoteApplication() {
            NSLog("Unable to expose the web app in the system Dock and application switcher.")
        }
        applyIcon(for: definition)
        faviconObserver = faviconStore.observeChanges(for: definition.id) { [weak self] in
            self?.applyIcon(for: definition)
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
