import AppKit
import SwiftUI

@MainActor
final class WebAppWindowController: NSWindowController, NSWindowDelegate {
    enum WindowMetrics {
        static let defaultContentSize = NSSize(width: 460, height: 900)
        static let minimumContentSize = NSSize(width: 390, height: 640)
    }

    let session: BrowserSession
    private let onFocusChange: (BrowserSession?) -> Void
    private let preferredGeometry: ScreenNotchGeometry?

    init(
        definition: WebAppDefinition,
        preferencesStore: WebAppPreferencesStore,
        preferredGeometry: ScreenNotchGeometry?,
        onFocusChange: @escaping (BrowserSession?) -> Void
    ) {
        let preference = preferencesStore.load(for: definition.id)
        self.session = BrowserSession(
            definition: definition,
            preference: preference,
            preferencesStore: preferencesStore
        )
        self.onFocusChange = onFocusChange
        self.preferredGeometry = preferredGeometry

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: WindowMetrics.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        configureWindow(window, definition: definition, isPinned: preference.isPinned)
        applyInitialFrame(using: preference, to: window, preferredGeometry: preferredGeometry)
        wireSession(to: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAndFocus(preferredGeometry: ScreenNotchGeometry? = nil) {
        ensureWindowFrameIsVisible(preferredGeometry: preferredGeometry ?? self.preferredGeometry)
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
        guard let window else {
            return
        }

        session.persistWindowFrame(window.frame, on: window.screen)
    }

    private func applyInitialFrame(
        using preference: StoredWebAppPreference,
        to window: NSWindow,
        preferredGeometry: ScreenNotchGeometry?
    ) {
        let defaultFrameSize = window.frame.size
        let minimumFrameSize = window.frameRect(forContentRect: CGRect(origin: .zero, size: WindowMetrics.minimumContentSize)).size
        let availableScreens = NSScreen.screens.map(WebAppWindowPlacementScreen.init(screen:))
        let fallbackDisplayID = NSScreen.main?.displayID

        let frame = WebAppWindowPlacementResolver.resolveFrame(
            preference: preference,
            preferredGeometry: preferredGeometry,
            availableScreens: availableScreens,
            fallbackDisplayID: fallbackDisplayID,
            defaultFrameSize: defaultFrameSize,
            minimumFrameSize: minimumFrameSize
        )

        window.setFrame(frame, display: false)
    }

    private func ensureWindowFrameIsVisible(preferredGeometry: ScreenNotchGeometry?) {
        guard let window else {
            return
        }

        let availableScreens = NSScreen.screens.map(WebAppWindowPlacementScreen.init(screen:))
        guard !WebAppWindowPlacementResolver.isFrameVisible(window.frame, across: availableScreens) else {
            return
        }

        let transientPreference = StoredWebAppPreference(
            pageZoom: session.pageZoom,
            isPinned: session.isPinned,
            windowFrame: window.frame,
            windowPlacement: StoredWindowPlacement(frame: window.frame, display: nil)
        )
        let minimumFrameSize = window.frameRect(forContentRect: CGRect(origin: .zero, size: WindowMetrics.minimumContentSize)).size
        let fallbackDisplayID = NSScreen.main?.displayID
        let nextFrame = WebAppWindowPlacementResolver.resolveFrame(
            preference: transientPreference,
            preferredGeometry: preferredGeometry ?? self.preferredGeometry,
            availableScreens: availableScreens,
            fallbackDisplayID: fallbackDisplayID,
            defaultFrameSize: window.frame.size,
            minimumFrameSize: minimumFrameSize
        )

        window.setFrame(nextFrame, display: false)
    }
}

struct WebAppWindowPlacementScreen: Equatable, Sendable {
    let displayID: UInt32?
    let localizedName: String
    let frame: CGRect
    let visibleFrame: CGRect
    let notchGeometry: ScreenNotchGeometry?

    init(
        displayID: UInt32?,
        localizedName: String,
        frame: CGRect,
        visibleFrame: CGRect,
        notchGeometry: ScreenNotchGeometry?
    ) {
        self.displayID = displayID
        self.localizedName = localizedName
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.notchGeometry = notchGeometry
    }

    init(screen: NSScreen) {
        self.init(
            displayID: screen.displayID,
            localizedName: screen.localizedName,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            notchGeometry: ScreenNotchGeometry(screen: screen)
        )
    }
}

enum WebAppWindowPlacementResolver {
    private static let notchSpacing: CGFloat = 80
    private static let fallbackTopMargin: CGFloat = 84

    static func resolveFrame(
        preference: StoredWebAppPreference,
        preferredGeometry: ScreenNotchGeometry?,
        availableScreens: [WebAppWindowPlacementScreen],
        fallbackDisplayID: UInt32?,
        defaultFrameSize: CGSize,
        minimumFrameSize: CGSize
    ) -> CGRect {
        let preferredScreen = resolvePreferredScreen(
            preferredGeometry: preferredGeometry,
            availableScreens: availableScreens,
            fallbackDisplayID: fallbackDisplayID
        )
        let preferredNotch = resolvePreferredNotch(
            preferredGeometry: preferredGeometry,
            preferredScreen: preferredScreen
        )

        if let storedPlacement = preference.resolvedWindowPlacement,
           let matchedScreen = resolveStoredScreen(for: storedPlacement, availableScreens: availableScreens) {
            let size = clampedSize(
                storedPlacement.frame.size,
                within: matchedScreen.visibleFrame.size,
                minimumFrameSize: minimumFrameSize
            )
            let frame = CGRect(origin: storedPlacement.frame.origin, size: size)
            return clamp(frame, into: matchedScreen.visibleFrame)
        }

        let fallbackScreen = preferredScreen ?? availableScreens.first
        let requestedSize = preference.resolvedWindowPlacement?.frame.size ?? defaultFrameSize
        let placementBounds = fallbackPlacementBounds(
            preferredNotch: preferredNotch ?? fallbackScreen?.notchGeometry,
            visibleFrame: fallbackScreen?.visibleFrame
        )
        let size = clampedSize(
            requestedSize,
            within: placementBounds?.size ?? fallbackScreen?.visibleFrame.size ?? defaultFrameSize,
            minimumFrameSize: minimumFrameSize
        )

        guard let fallbackScreen else {
            return CGRect(origin: .zero, size: size)
        }

        return fallbackFrame(
            size: size,
            preferredNotch: preferredNotch ?? fallbackScreen.notchGeometry,
            visibleFrame: fallbackScreen.visibleFrame,
            placementBounds: placementBounds ?? fallbackScreen.visibleFrame
        )
    }

    static func isFrameVisible(_ frame: CGRect, across screens: [WebAppWindowPlacementScreen]) -> Bool {
        screens.contains { $0.visibleFrame.contains(frame) }
    }

    private static func resolveStoredScreen(
        for placement: StoredWindowPlacement,
        availableScreens: [WebAppWindowPlacementScreen]
    ) -> WebAppWindowPlacementScreen? {
        guard let storedDisplay = placement.display else {
            return nil
        }

        return availableScreens.first(where: { screen in
            if let storedDisplayID = storedDisplay.displayID,
               let screenDisplayID = screen.displayID,
               storedDisplayID == screenDisplayID {
                return true
            }

            return storedDisplay.localizedName == screen.localizedName &&
            storedDisplay.frame.size == screen.frame.size
        })
    }

    private static func resolvePreferredScreen(
        preferredGeometry: ScreenNotchGeometry?,
        availableScreens: [WebAppWindowPlacementScreen],
        fallbackDisplayID: UInt32?
    ) -> WebAppWindowPlacementScreen? {
        if let preferredGeometry,
           let screen = availableScreens.first(where: { $0.frame == preferredGeometry.screenFrame }) {
            return screen
        }

        if let fallbackDisplayID,
           let screen = availableScreens.first(where: { $0.displayID == fallbackDisplayID }) {
            return screen
        }

        return availableScreens.first(where: { $0.notchGeometry != nil }) ?? availableScreens.first
    }

    private static func resolvePreferredNotch(
        preferredGeometry: ScreenNotchGeometry?,
        preferredScreen: WebAppWindowPlacementScreen?
    ) -> ScreenNotchGeometry? {
        if let preferredGeometry {
            return preferredGeometry
        }

        return preferredScreen?.notchGeometry
    }

    private static func clampedSize(
        _ size: CGSize,
        within availableSize: CGSize,
        minimumFrameSize: CGSize
    ) -> CGSize {
        CGSize(
            width: min(availableSize.width, max(minimumFrameSize.width, size.width)),
            height: min(availableSize.height, max(minimumFrameSize.height, size.height))
        )
    }

    private static func fallbackFrame(
        size: CGSize,
        preferredNotch: ScreenNotchGeometry?,
        visibleFrame: CGRect,
        placementBounds: CGRect
    ) -> CGRect {
        let origin: CGPoint

        if let preferredNotch {
            origin = CGPoint(
                x: preferredNotch.notchRect.midX - (size.width / 2),
                y: placementBounds.maxY - size.height
            )
        } else {
            origin = CGPoint(
                x: visibleFrame.midX - (size.width / 2),
                y: visibleFrame.maxY - size.height - fallbackTopMargin
            )
        }

        return clamp(CGRect(origin: origin, size: size), into: placementBounds)
    }

    private static func fallbackPlacementBounds(
        preferredNotch: ScreenNotchGeometry?,
        visibleFrame: CGRect?
    ) -> CGRect? {
        guard let visibleFrame else {
            return nil
        }

        guard let preferredNotch else {
            return visibleFrame
        }

        let maxY = max(visibleFrame.minY, preferredNotch.notchRect.minY - notchSpacing)
        return CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: maxY - visibleFrame.minY
        )
    }

    private static func clamp(_ frame: CGRect, into visibleFrame: CGRect) -> CGRect {
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let maxX = visibleFrame.maxX - width
        let maxY = visibleFrame.maxY - height

        return CGRect(
            x: min(max(frame.minX, visibleFrame.minX), maxX),
            y: min(max(frame.minY, visibleFrame.minY), maxY),
            width: width,
            height: height
        )
    }
}

private extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
