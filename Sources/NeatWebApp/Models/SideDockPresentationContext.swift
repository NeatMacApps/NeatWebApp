import CoreGraphics
import Foundation

enum SideDockEdge: String, CaseIterable, Codable, Sendable {
    case left
    case right
    case bottom

    var title: String {
        switch self {
        case .left:
            String(localized: "sidedock.edge.left")
        case .right:
            String(localized: "sidedock.edge.right")
        case .bottom:
            String(localized: "sidedock.edge.bottom")
        }
    }

    var isSide: Bool { self != .bottom }
}

struct SideDockPresentationContext: Equatable {
    struct Layout: Equatable, Sendable {
        static let thickness: CGFloat = 47
        static let iconSlotSize: CGFloat = 33
        static let iconSize: CGFloat = 28
        static let iconSpacing: CGFloat = 6
        // The end slot and capsule share a center: 33 / 2 + 7 = 47 / 2.
        static let padding: CGFloat = (thickness - iconSlotSize) / 2

        let edge: SideDockEdge
        let length: CGFloat
        let shouldScroll: Bool

        var panelSize: CGSize {
            edge.isSide
                ? CGSize(width: Self.thickness, height: length)
                : CGSize(width: length, height: Self.thickness)
        }
    }

    let apps: [WebAppDefinition]
    let edge: SideDockEdge
    let screenFrame: CGRect
    let visibleFrame: CGRect
    let verticalPosition: CGFloat
    var floatingPosition: CGPoint? = nil
    var isCompact = false

    var layout: Layout {
        let availableLength = edge.isSide ? visibleFrame.height : visibleFrame.width
        let maximumLength = max(
            availableLength - SideDockPlacementResolver.edgeMargin * 2,
            Layout.thickness
        )
        let slotCount = isCompact ? 1 : apps.count + 1
        let naturalLength = Layout.padding * 2
            + CGFloat(slotCount) * Layout.iconSlotSize
            + CGFloat(max(slotCount - 1, 0)) * Layout.iconSpacing
        return Layout(
            edge: edge,
            length: min(naturalLength, maximumLength),
            shouldScroll: naturalLength > maximumLength
        )
    }

    var panelFrame: CGRect {
        SideDockPlacementResolver.panelFrame(
            position: floatingPosition ?? SideDockPlacementResolver.initialPosition(
                edge: edge, legacyPosition: verticalPosition
            ),
            visibleFrame: visibleFrame,
            panelSize: layout.panelSize
        )
    }
}

enum SideDockPlacementResolver {
    static let defaultVerticalPosition: CGFloat = 0.72
    static let edgeMargin: CGFloat = 12

    static func recommendedDefaultEdge(screenFrame: CGRect, visibleFrame: CGRect) -> SideDockEdge {
        let leftInset = max(visibleFrame.minX - screenFrame.minX, 0)
        let rightInset = max(screenFrame.maxX - visibleFrame.maxX, 0)
        return rightInset > leftInset + 2 ? .left : .right
    }

    static func initialPosition(edge: SideDockEdge, legacyPosition: CGFloat) -> CGPoint {
        let position = clamped(legacyPosition)
        switch edge {
        case .left: return CGPoint(x: 0, y: position)
        case .right: return CGPoint(x: 1, y: position)
        case .bottom: return CGPoint(x: position, y: 0)
        }
    }

    static func panelFrame(position: CGPoint, visibleFrame: CGRect, panelSize: CGSize) -> CGRect {
        let bounds = originBounds(visibleFrame: visibleFrame, panelSize: panelSize)
        return CGRect(
            x: bounds.minX + bounds.width * clamped(position.x),
            y: bounds.minY + bounds.height * clamped(position.y),
            width: panelSize.width,
            height: panelSize.height
        )
    }

    static func normalizedPosition(panelFrame: CGRect, visibleFrame: CGRect) -> CGPoint {
        let bounds = originBounds(visibleFrame: visibleFrame, panelSize: panelFrame.size)
        return CGPoint(
            x: bounds.width > 0 ? clamped((panelFrame.minX - bounds.minX) / bounds.width) : 0.5,
            y: bounds.height > 0 ? clamped((panelFrame.minY - bounds.minY) / bounds.height) : 0.5
        )
    }

    private static func originBounds(visibleFrame: CGRect, panelSize: CGSize) -> CGRect {
        // Keep oversized panels centered on the axis with no remaining travel.
        let xTravel = max(visibleFrame.width - panelSize.width - edgeMargin * 2, 0)
        let yTravel = max(visibleFrame.height - panelSize.height - edgeMargin * 2, 0)
        return CGRect(
            x: xTravel > 0 ? visibleFrame.minX + edgeMargin : visibleFrame.midX - panelSize.width / 2,
            y: yTravel > 0 ? visibleFrame.minY + edgeMargin : visibleFrame.midY - panelSize.height / 2,
            width: xTravel,
            height: yTravel
        )
    }

    static func clamped(_ value: CGFloat) -> CGFloat {
        value.isFinite ? min(max(value, 0), 1) : 0.5
    }
}
