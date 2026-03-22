import AppKit

@MainActor
final class NotchDebugOverlayController {
    private var panelsByScreenID: [String: NotchDebugPanel] = [:]

    func update(with geometries: [ScreenNotchGeometry], isVisible: Bool) {
        guard isVisible else {
            hideAll()
            return
        }

        let activeScreenIDs = Set(geometries.map(\.id))

        for geometry in geometries {
            let panel = panelsByScreenID[geometry.id] ?? makePanel(for: geometry)
            panel.geometry = geometry
            panel.setFrame(geometry.screenFrame.integral, display: true)
            panel.orderFrontRegardless()
            panelsByScreenID[geometry.id] = panel
        }

        let staleScreenIDs = Set(panelsByScreenID.keys).subtracting(activeScreenIDs)
        for screenID in staleScreenIDs {
            panelsByScreenID[screenID]?.orderOut(nil)
            panelsByScreenID[screenID] = nil
        }
    }

    func hideAll() {
        for panel in panelsByScreenID.values {
            panel.orderOut(nil)
        }
        panelsByScreenID.removeAll()
    }

    private func makePanel(for geometry: ScreenNotchGeometry) -> NotchDebugPanel {
        let panel = NotchDebugPanel(
            contentRect: geometry.screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.geometry = geometry
        return panel
    }
}

@MainActor
private final class NotchDebugPanel: NSPanel {
    private let overlayView = NotchDebugOverlayView()

    var geometry: ScreenNotchGeometry = .placeholder {
        didSet {
            overlayView.geometry = geometry
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        contentView = overlayView
    }
}

private final class NotchDebugOverlayView: NSView {
    var geometry: ScreenNotchGeometry = .placeholder {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        context.clear(bounds)

        draw(rect: localRect(for: geometry.activationRect), fillColor: NSColor.systemBlue.withAlphaComponent(0.16), strokeColor: NSColor.systemBlue)
        draw(rect: localRect(for: geometry.notchRect), fillColor: NSColor.systemRed.withAlphaComponent(0.28), strokeColor: NSColor.systemRed)
        drawLabel(in: localRect(for: geometry.notchRect), title: "Notch \(geometry.notchRect.debugSummary)")
        drawLabel(in: localRect(for: geometry.activationRect), title: "Activation \(geometry.activationRect.debugSummary)", offsetY: -22)
    }

    private func localRect(for rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - geometry.screenFrame.minX,
            y: rect.minY - geometry.screenFrame.minY,
            width: rect.width,
            height: rect.height
        )
    }

    private func draw(rect: CGRect, fillColor: NSColor, strokeColor: NSColor) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        fillColor.setFill()
        path.fill()

        strokeColor.setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    private func drawLabel(in rect: CGRect, title: String, offsetY: CGFloat = 10) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let label = NSAttributedString(string: title, attributes: attributes)
        let labelSize = label.size()
        let paddedRect = CGRect(
            x: max(rect.minX, 16),
            y: min(rect.maxY + offsetY, bounds.maxY - labelSize.height - 12),
            width: labelSize.width + 18,
            height: labelSize.height + 10
        )

        let backgroundPath = NSBezierPath(roundedRect: paddedRect, xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.78).setFill()
        backgroundPath.fill()

        label.draw(at: CGPoint(x: paddedRect.minX + 9, y: paddedRect.minY + 5))
    }
}

private extension CGRect {
    var debugSummary: String {
        "[x:\(Int(origin.x)) y:\(Int(origin.y)) w:\(Int(width)) h:\(Int(height))]"
    }
}

private extension ScreenNotchGeometry {
    static var placeholder: ScreenNotchGeometry {
        ScreenNotchGeometry(
            screenFrame: .zero,
            visibleFrame: .zero,
            safeAreaInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: .zero,
            auxiliaryTopRightArea: .zero,
            localizedName: "Placeholder"
        )
    }
}
