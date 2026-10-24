import AppKit

/// Opens the single management window (the SwiftUI `Settings` scene) from AppKit code that
/// runs outside the scene graph, such as the notch launcher panel.
///
/// Scene actions (`openSettings`, `openWindow`) only resolve inside a SwiftUI view that
/// belongs to a scene, and the launcher hosts its own `NSHostingView` in a status-bar panel.
/// On macOS 14+ the legacy `showSettingsWindow:` responder action no longer opens the
/// window either. The public path that works before the window exists is the Settings item
/// SwiftUI installs in the app menu — the same item ⌘, performs.
@MainActor
enum ManagementWindowPresenter {
    private static let settingsWindowAutosaveName = "com_apple_SwiftUI_Settings_window"

    static func present() {
        if let window = settingsWindow() {
            activate(window)
            return
        }

        if performSettingsMenuCommand() {
            focusSettingsWindowAfterPresentation()
        }
    }

    /// Shown by the Settings scene and the scene's autosave name; no other window uses it.
    private static func settingsWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window.identifier?.rawValue == settingsWindowAutosaveName
                || window.frameAutosaveName == settingsWindowAutosaveName
        }
    }

    private static func activate(_ window: NSWindow) {
        // A panel click does not make the app active, so the window would open behind
        // whatever the user is working in. Keep the established activation call used by
        // the rest of the app; plain `activate()` is not enough from a status-bar panel.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// SwiftUI realises the window asynchronously, and activating before it exists is
    /// dropped by the system. Poll for a short while and then bring the app forward.
    private static func focusSettingsWindowAfterPresentation() {
        Task { @MainActor in
            for _ in 0..<12 {
                if let window = settingsWindow() {
                    activate(window)
                    return
                }

                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    @discardableResult
    private static func performSettingsMenuCommand() -> Bool {
        guard let mainMenu = NSApp.mainMenu else {
            return false
        }

        let appMenu = mainMenu.items.first?.submenu
        let menus = ([appMenu].compactMap { $0 }) + mainMenu.items.dropFirst().compactMap(\.submenu)
        for menu in menus {
            guard let item = menu.items.first(where: {
                $0.keyEquivalent == "," && $0.keyEquivalentModifierMask.contains(.command)
            }) else {
                continue
            }

            if let action = item.action, NSApp.sendAction(action, to: item.target, from: item) {
                return true
            }

            return postSettingsShortcut()
        }

        return postSettingsShortcut()
    }

    /// Fallback for a Settings item that SwiftUI drives through a private handler instead of
    /// a selector: send the app its own ⌘, command. The menu consumes it before any window.
    private static func postSettingsShortcut() -> Bool {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: ",",
            charactersIgnoringModifiers: ",",
            isARepeat: false,
            keyCode: 43
        ) else {
            return false
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.postEvent(event, atStart: false)
        return true
    }
}
