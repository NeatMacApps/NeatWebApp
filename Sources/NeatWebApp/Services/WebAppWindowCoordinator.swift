import AppKit

@MainActor
final class WebAppWindowCoordinator {
    private let preferencesStore: WebAppPreferencesStore
    private let onActiveSessionChange: (BrowserSession?) -> Void
    private var windowControllers: [String: WebAppWindowController] = [:]

    init(
        preferencesStore: WebAppPreferencesStore,
        onActiveSessionChange: @escaping (BrowserSession?) -> Void
    ) {
        self.preferencesStore = preferencesStore
        self.onActiveSessionChange = onActiveSessionChange
    }

    func open(_ definition: WebAppDefinition) {
        if let existingWindowController = windowControllers[definition.id] {
            existingWindowController.showAndFocus()
            return
        }

        let windowController = WebAppWindowController(
            definition: definition,
            preferencesStore: preferencesStore,
            onFocusChange: onActiveSessionChange
        )

        windowControllers[definition.id] = windowController
        windowController.showAndFocus()
    }
}
