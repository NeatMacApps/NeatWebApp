import AppKit
import QuartzCore

enum FloatingIconSnapResolver {
    static func resolvePanelFrame(
        proposedFrame: CGRect,
        anchorPoint: CGPoint,
        availableScreens: [WebAppWindowPlacementScreen],
        fallbackScreen: WebAppWindowPlacementScreen?,
        shadowPadding: CGFloat
    ) -> CGRect {
        guard let screen = resolveScreen(
            for: anchorPoint,
            proposedFrame: proposedFrame,
            availableScreens: availableScreens,
            fallbackScreen: fallbackScreen
        ) else {
            return proposedFrame
        }

        let visualFrame = visualFrame(for: proposedFrame, shadowPadding: shadowPadding)
        guard screen.visibleFrame.width >= visualFrame.width,
              screen.visibleFrame.height >= visualFrame.height else {
            return proposedFrame
        }

        return panelFrame(
            for: topSnappedVisualFrame(
                from: clamp(visualFrame, into: screen.visibleFrame),
                within: screen.visibleFrame
            ),
            shadowPadding: shadowPadding
        )
    }

    static func clampPanelOrigin(
        _ origin: CGPoint,
        panelSize: CGSize,
        anchorPoint: CGPoint,
        availableScreens: [WebAppWindowPlacementScreen],
        fallbackScreen: WebAppWindowPlacementScreen?,
        shadowPadding: CGFloat
    ) -> CGPoint {
        let proposedFrame = CGRect(origin: origin, size: panelSize)
        guard let screen = resolveScreen(
            for: anchorPoint,
            proposedFrame: proposedFrame,
            availableScreens: availableScreens,
            fallbackScreen: fallbackScreen
        ) else {
            return origin
        }

        let visualFrame = visualFrame(for: proposedFrame, shadowPadding: shadowPadding)
        guard screen.visibleFrame.width >= visualFrame.width,
              screen.visibleFrame.height >= visualFrame.height else {
            return origin
        }

        let clampedVisualFrame = clamp(visualFrame, into: screen.visibleFrame)
        return panelFrame(for: clampedVisualFrame, shadowPadding: shadowPadding).origin
    }

    static func normalizeRestoredPanelFrame(
        _ restoredPanelFrame: CGRect,
        availableScreens: [WebAppWindowPlacementScreen],
        fallbackScreen: WebAppWindowPlacementScreen?,
        shadowPadding: CGFloat
    ) -> CGRect {
        guard let screen = resolveScreen(
            for: CGPoint(x: restoredPanelFrame.minX, y: restoredPanelFrame.maxY),
            proposedFrame: restoredPanelFrame,
            availableScreens: availableScreens,
            fallbackScreen: fallbackScreen
        ) else {
            return restoredPanelFrame
        }

        var normalizedFrame = restoredPanelFrame

        if abs(restoredPanelFrame.minX - screen.visibleFrame.minX) <= 1 {
            normalizedFrame.origin.x -= shadowPadding
        }

        if abs(restoredPanelFrame.maxX - screen.visibleFrame.maxX) <= 1 {
            normalizedFrame.origin.x += shadowPadding
        }

        if abs(restoredPanelFrame.minY - screen.visibleFrame.minY) <= 1 {
            normalizedFrame.origin.y -= shadowPadding
        }

        let normalizedVisualFrame = clamp(
            visualFrame(for: normalizedFrame, shadowPadding: shadowPadding),
            into: screen.visibleFrame
        )
        return panelFrame(for: normalizedVisualFrame, shadowPadding: shadowPadding)
    }

    private static func resolveScreen(
        for anchorPoint: CGPoint,
        proposedFrame: CGRect,
        availableScreens: [WebAppWindowPlacementScreen],
        fallbackScreen: WebAppWindowPlacementScreen?
    ) -> WebAppWindowPlacementScreen? {
        if let containingScreen = availableScreens.first(where: { $0.frame.contains(anchorPoint) || $0.visibleFrame.contains(anchorPoint) }) {
            return containingScreen
        }

        if let intersectingScreen = availableScreens.first(where: { $0.visibleFrame.intersects(proposedFrame) || $0.frame.intersects(proposedFrame) }) {
            return intersectingScreen
        }

        return availableScreens.min {
            squaredDistance(from: anchorPoint, to: $0.visibleFrame) < squaredDistance(from: anchorPoint, to: $1.visibleFrame)
        } ?? fallbackScreen
    }

    private static func clamp(_ frame: CGRect, into visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - frame.width),
            y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - frame.height),
            width: frame.width,
            height: frame.height
        )
    }

    private static func topSnappedVisualFrame(from frame: CGRect, within visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX,
            y: visibleFrame.maxY - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    private static func visualFrame(for panelFrame: CGRect, shadowPadding: CGFloat) -> CGRect {
        panelFrame.insetBy(dx: shadowPadding, dy: shadowPadding)
    }

    private static func panelFrame(for visualFrame: CGRect, shadowPadding: CGFloat) -> CGRect {
        visualFrame.insetBy(dx: -shadowPadding, dy: -shadowPadding)
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx: CGFloat
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }

        return (dx * dx) + (dy * dy)
    }
}

final class FloatingWebAppIconPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

final class WindowSnapshotTransitionPanel: NSPanel {
    private let snapshotView = NSImageView()

    var snapshotImage: NSImage? {
        get { snapshotView.image }
        set { snapshotView.image = newValue }
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing bufferingType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)

        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 14
        contentView.layer?.masksToBounds = true

        snapshotView.translatesAutoresizingMaskIntoConstraints = false
        snapshotView.imageScaling = .scaleAxesIndependently
        snapshotView.animates = false

        contentView.addSubview(snapshotView)
        NSLayoutConstraint.activate([
            snapshotView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            snapshotView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            snapshotView.topAnchor.constraint(equalTo: contentView.topAnchor),
            snapshotView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        self.contentView = contentView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class FloatingWebAppIconView: NSView {
    private enum AnimationMetrics {
        static let rippleDuration: CFTimeInterval = 1
        static let rippleStagger: CFTimeInterval = 0.22
        static let rippleExpansion: CGFloat = 18
        static let rippleLineWidth: CGFloat = 2
        static let rippleOpacity: Float = 0.34
    }

    private let onClick: () -> Void
    private var cursorTrackingArea: NSTrackingArea?
    private var mouseDownWindowOrigin: CGPoint = .zero
    private var mouseDownOffsetInWindow: CGPoint = .zero
    private var isDragging = false

    init(iconImage: NSImage?, appName: String, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        setupUI(iconImage: iconImage, appName: appName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        cursorTrackingArea = trackingArea
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownWindowOrigin = window?.frame.origin ?? .zero
        mouseDownOffsetInWindow = event.locationInWindow
        isDragging = false
        NSCursor.closedHand.set()
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else {
            return
        }

        isDragging = true

        let mouseLocation = NSEvent.mouseLocation
        let nextOrigin = CGPoint(
            x: mouseLocation.x - mouseDownOffsetInWindow.x,
            y: mouseLocation.y - mouseDownOffsetInWindow.y
        )
        let clampedOrigin = clampWindowOrigin(nextOrigin, for: window, around: mouseLocation)

        window.setFrameOrigin(clampedOrigin)
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isDragging else {
            return
        }

        NSCursor.openHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        guard !isDragging else {
            return
        }

        NSCursor.arrow.set()
    }

    override func mouseUp(with event: NSEvent) {
        let currentOrigin = window?.frame.origin ?? .zero
        let dragDistance = hypot(currentOrigin.x - mouseDownWindowOrigin.x, currentOrigin.y - mouseDownWindowOrigin.y)
        isDragging = false
        NSCursor.openHand.set()

        if dragDistance < 3 {
            onClick()
        }
    }

    private func clampWindowOrigin(_ origin: CGPoint, for window: NSWindow, around anchorPoint: CGPoint) -> CGPoint {
        FloatingIconSnapResolver.clampPanelOrigin(
            origin,
            panelSize: window.frame.size,
            anchorPoint: anchorPoint,
            availableScreens: NSScreen.screens.map(WebAppWindowPlacementScreen.init(screen:)),
            fallbackScreen: NSScreen.main.map(WebAppWindowPlacementScreen.init(screen:)),
            shadowPadding: WebAppWindowController.WindowMetrics.floatingIconShadowPadding
        )
    }

    func playCollapseRippleAnimation() {
        layoutSubtreeIfNeeded()

        guard let layer, !bounds.isEmpty else {
            return
        }

        layer.sublayers?
            .filter { $0.name == "collapseRippleLayer" }
            .forEach { $0.removeFromSuperlayer() }

        let startTime = CACurrentMediaTime()
        addRippleLayer(
            to: layer,
            delay: 0,
            duration: AnimationMetrics.rippleDuration - AnimationMetrics.rippleStagger,
            startTime: startTime
        )
        addRippleLayer(
            to: layer,
            delay: AnimationMetrics.rippleStagger,
            duration: AnimationMetrics.rippleDuration - AnimationMetrics.rippleStagger,
            startTime: startTime
        )
    }

    private func setupUI(iconImage: NSImage?, appName: String) {
        wantsLayer = true
        layer?.masksToBounds = false

        let shadowView = NSView()
        shadowView.translatesAutoresizingMaskIntoConstraints = false
        shadowView.wantsLayer = true
        shadowView.layer?.masksToBounds = false
        shadowView.layer?.backgroundColor = NSColor.clear.cgColor

        let shadowLayer = CAShapeLayer()
        shadowLayer.frame = CGRect(
            x: 0,
            y: 0,
            width: WebAppWindowController.WindowMetrics.floatingIconDiameter,
            height: WebAppWindowController.WindowMetrics.floatingIconDiameter
        )
        shadowLayer.path = CGPath(
            ellipseIn: shadowLayer.bounds,
            transform: nil
        )
        shadowLayer.fillColor = NSColor.white.withAlphaComponent(0.01).cgColor
        shadowLayer.shadowColor = NSColor.black.withAlphaComponent(0.24).cgColor
        shadowLayer.shadowOpacity = 1
        shadowLayer.shadowRadius = 5
        shadowLayer.shadowOffset = CGSize(width: 0, height: -1.5)
        shadowLayer.shadowPath = shadowLayer.path
        shadowView.layer?.addSublayer(shadowLayer)

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleAxesIndependently
        iconView.image = circularMaskedIcon(from: iconImage) ?? fallbackIconImage(for: appName)
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = WebAppWindowController.WindowMetrics.floatingIconDiameter / 2
        iconView.layer?.masksToBounds = true

        addSubview(shadowView)
        shadowView.addSubview(iconView)

        NSLayoutConstraint.activate([
            shadowView.widthAnchor.constraint(equalToConstant: WebAppWindowController.WindowMetrics.floatingIconDiameter),
            shadowView.heightAnchor.constraint(equalToConstant: WebAppWindowController.WindowMetrics.floatingIconDiameter),
            shadowView.centerXAnchor.constraint(equalTo: centerXAnchor),
            shadowView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.leadingAnchor.constraint(equalTo: shadowView.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: shadowView.trailingAnchor),
            iconView.topAnchor.constraint(equalTo: shadowView.topAnchor),
            iconView.bottomAnchor.constraint(equalTo: shadowView.bottomAnchor)
        ])
    }

    private func addRippleLayer(
        to containerLayer: CALayer,
        delay: CFTimeInterval,
        duration: CFTimeInterval,
        startTime: CFTimeInterval
    ) {
        let initialRect = CGRect(
            x: (bounds.width - WebAppWindowController.WindowMetrics.floatingIconDiameter) / 2,
            y: (bounds.height - WebAppWindowController.WindowMetrics.floatingIconDiameter) / 2,
            width: WebAppWindowController.WindowMetrics.floatingIconDiameter,
            height: WebAppWindowController.WindowMetrics.floatingIconDiameter
        )
        let expandedRect = initialRect.insetBy(
            dx: -AnimationMetrics.rippleExpansion,
            dy: -AnimationMetrics.rippleExpansion
        )
        let initialPath = CGPath(ellipseIn: initialRect, transform: nil)
        let finalPath = CGPath(ellipseIn: expandedRect, transform: nil)

        let rippleLayer = CAShapeLayer()
        rippleLayer.name = "collapseRippleLayer"
        rippleLayer.frame = bounds
        rippleLayer.path = finalPath
        rippleLayer.fillColor = NSColor.clear.cgColor
        rippleLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor
        rippleLayer.lineWidth = AnimationMetrics.rippleLineWidth
        rippleLayer.opacity = 0
        containerLayer.addSublayer(rippleLayer)

        let pathAnimation = CABasicAnimation(keyPath: "path")
        pathAnimation.fromValue = initialPath
        pathAnimation.toValue = finalPath

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = AnimationMetrics.rippleOpacity
        opacityAnimation.toValue = 0

        let lineWidthAnimation = CABasicAnimation(keyPath: "lineWidth")
        lineWidthAnimation.fromValue = AnimationMetrics.rippleLineWidth
        lineWidthAnimation.toValue = 0.6

        let animationGroup = CAAnimationGroup()
        animationGroup.animations = [pathAnimation, opacityAnimation, lineWidthAnimation]
        animationGroup.beginTime = startTime + delay
        animationGroup.duration = duration
        animationGroup.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animationGroup.isRemovedOnCompletion = false
        animationGroup.fillMode = .forwards
        rippleLayer.add(animationGroup, forKey: "collapseRipple")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + duration) {
            rippleLayer.removeFromSuperlayer()
        }
    }

    private func circularMaskedIcon(from image: NSImage?) -> NSImage? {
        guard let image else {
            return nil
        }

        let diameter = WebAppWindowController.WindowMetrics.floatingIconDiameter
        let size = NSSize(width: diameter, height: diameter)
        let rendered = NSImage(size: size)
        rendered.lockFocus()

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let clipPath = NSBezierPath(ovalIn: NSRect(origin: .zero, size: size))
        clipPath.addClip()
        image.draw(in: NSRect(origin: .zero, size: size))

        rendered.unlockFocus()
        return rendered
    }

    private func fallbackIconImage(for appName: String) -> NSImage? {
        let letter = appName.first(where: \.isLetter).map { String($0).uppercased() } ?? "#"
        let size = NSSize(
            width: WebAppWindowController.WindowMetrics.floatingIconDiameter,
            height: WebAppWindowController.WindowMetrics.floatingIconDiameter
        )
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(
                ofSize: WebAppWindowController.WindowMetrics.floatingIconDiameter * 0.53,
                weight: .semibold
            ),
            .foregroundColor: NSColor.labelColor
        ]
        let textSize = letter.size(withAttributes: attributes)
        let textOrigin = CGPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2
        )
        letter.draw(at: textOrigin, withAttributes: attributes)

        image.unlockFocus()
        return image
    }
}
