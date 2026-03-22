import AppKit
import SwiftUI

@MainActor
final class WebAppWindowController: NSWindowController, NSWindowDelegate {
    private enum WindowMetrics {
        static let defaultContentSize = NSSize(width: 460, height: 900)
        static let minimumContentSize = NSSize(width: 390, height: 640)
    }

    let session: BrowserSession
    private let onFocusChange: (BrowserSession?) -> Void

    init(
        definition: WebAppDefinition,
        preferencesStore: WebAppPreferencesStore,
        onFocusChange: @escaping (BrowserSession?) -> Void
    ) {
        let preference = preferencesStore.load(for: definition.id)
        self.session = BrowserSession(
            definition: definition,
            preference: preference,
            preferencesStore: preferencesStore
        )
        self.onFocusChange = onFocusChange

        let initialFrame = preference.windowFrame ?? CGRect(
            x: 240,
            y: 160,
            width: WindowMetrics.defaultContentSize.width,
            height: WindowMetrics.defaultContentSize.height
        )
        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        configureWindow(window, definition: definition, isPinned: preference.isPinned)
        wireSession(to: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAndFocus() {
        window?.deminiaturize(nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updatePinnedState(_ isPinned: Bool) {
        window?.level = isPinned ? .floating : .normal
    }

    func windowDidMove(_ notification: Notification) {
        persistWindowFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistWindowFrame()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onFocusChange(session)
    }

    func windowDidResignKey(_ notification: Notification) {
        onFocusChange(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideWindow()
        return false
    }

    func hideWindow() {
        persistWindowFrame()
        window?.orderOut(nil)
    }

    private func configureWindow(_ window: NSWindow, definition: WebAppDefinition, isPinned: Bool) {
        window.delegate = self
        window.title = definition.name
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.backgroundColor = .black
        window.level = isPinned ? .floating : .normal
        window.contentMinSize = WindowMetrics.minimumContentSize
        window.setFrameAutosaveName("WebApp-\(definition.id)")
        window.toolbar = nil

        for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(buttonType)?.isHidden = true
        }
    }

    private func wireSession(to window: NSWindow) {
        let rootView = BrowserContainerView(session: session)
        let hostingController = NSHostingController(rootView: rootView)
        window.contentViewController = hostingController

        session.onPinnedChange = { [weak self] isPinned in
            self?.updatePinnedState(isPinned)
        }
        session.onCloseRequest = { [weak self] in
            self?.hideWindow()
        }
    }

    private func persistWindowFrame() {
        guard let frame = window?.frame else {
            return
        }

        session.persistWindowFrame(frame)
    }
}
