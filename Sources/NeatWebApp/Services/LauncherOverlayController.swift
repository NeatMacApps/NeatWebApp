import AppKit
import SwiftUI

@MainActor
final class LauncherOverlayController {
    private var panel: LauncherPanel?

    var frame: CGRect? {
        guard let panel, panel.isVisible else {
            return nil
        }

        return panel.frame
    }

    func present(context: LauncherPresentationContext, appModel: AppModel) {
        let panel = panel ?? makePanel()
        let rootView = LauncherOverlayRootView(context: context) { app in
            appModel.openWebApp(app)
        }
        .environment(appModel)

        let hostingController = NSHostingController(rootView: AnyView(rootView))
        hostingController.view.frame = CGRect(origin: .zero, size: context.panelSize)
        hostingController.view.wantsLayer = true
        // The launcher panel relies on true transparency around the attached bar.
        // If this view ever gets an opaque background, it shows up as a stray gray block.
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        panel.contentViewController = hostingController
        panel.setFrame(context.panelFrame.integral, display: true)
        panel.orderFrontRegardless()

        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> LauncherPanel {
        let panel = LauncherPanel(
            contentRect: CGRect(x: 0, y: 0, width: 420, height: 82),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        return panel
    }
}

@MainActor
private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
