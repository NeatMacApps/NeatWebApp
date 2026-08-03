import CoreGraphics
import Foundation

enum SideDockEdge: String, CaseIterable, Codable, Sendable {
    case left
    case right

    var title: String {
        switch self {
        case .left:
            "左侧"
        case .right:
            "右侧"
        }
    }

    var attachedShapeEdge: ScreenAttachedEdge {
        switch self {
        case .left:
            .left
        case .right:
            .right
        }
    }
}

struct SideDockPresentationContext: Equatable {
    struct Layout: Equatable, Sendable {
        // 整套尺寸按原始设计的 88% 等比缩小。
        static let width: CGFloat = 47
        static let minimumHeight: CGFloat = 65
        static let edgeTransitionDepth: CGFloat = 9
        static let iconSlotSize: CGFloat = 33
        static let iconSize: CGFloat = 28
        static let iconSpacing: CGFloat = 6
        // 内容留白加上点击区内的图标留白，
        // 让图标到底边的视觉距离与左右视觉距离一致。
        static let verticalPadding: CGFloat = 7
        static let cornerRadius: CGFloat = 15

        let height: CGFloat
        let shouldScroll: Bool

        var panelSize: CGSize {
            CGSize(width: Self.width, height: height)
        }
    }

    let apps: [WebAppDefinition]
    let edge: SideDockEdge
    let screenFrame: CGRect
    let visibleFrame: CGRect
    let verticalPosition: CGFloat

    var layout: Layout {
        let maximumHeight = max(visibleFrame.height - 32, Layout.minimumHeight)
        let naturalHeight = (Layout.edgeTransitionDepth * 2)
            + (Layout.verticalPadding * 2)
            + (CGFloat(apps.count) * Layout.iconSlotSize)
            + (CGFloat(max(apps.count - 1, 0)) * Layout.iconSpacing)
        let height = min(max(naturalHeight, Layout.minimumHeight), maximumHeight)

        return Layout(
            height: height,
            shouldScroll: naturalHeight > maximumHeight
        )
    }

    var panelFrame: CGRect {
        SideDockPlacementResolver.panelFrame(
            edge: edge,
            verticalPosition: verticalPosition,
            visibleFrame: visibleFrame,
            panelSize: layout.panelSize
        )
    }
}

enum SideDockPlacementResolver {
    static let defaultVerticalPosition: CGFloat = 0.72

    static func recommendedDefaultEdge(screenFrame: CGRect, visibleFrame: CGRect) -> SideDockEdge {
        let leftInset = max(visibleFrame.minX - screenFrame.minX, 0)
        let rightInset = max(screenFrame.maxX - visibleFrame.maxX, 0)

        if rightInset > leftInset + 2 {
            return .left
        }

        if leftInset > rightInset + 2 {
            return .right
        }

        return .right
    }

    static func panelFrame(
        edge: SideDockEdge,
        verticalPosition: CGFloat,
        visibleFrame: CGRect,
        panelSize: CGSize
    ) -> CGRect {
        let clampedPosition = min(max(verticalPosition, 0), 1)
        let availableTravel = max(visibleFrame.height - panelSize.height - 32, 0)
        let y = visibleFrame.minY + 16 + (availableTravel * clampedPosition)
        let x = edge == .left
            ? visibleFrame.minX
            : visibleFrame.maxX - panelSize.width

        return CGRect(origin: CGPoint(x: x, y: y), size: panelSize)
    }

    static func normalizedVerticalPosition(
        panelMidY: CGFloat,
        visibleFrame: CGRect,
        panelHeight: CGFloat
    ) -> CGFloat {
        let availableTravel = max(visibleFrame.height - panelHeight - 32, 0)
        guard availableTravel > 0 else {
            return 0.5
        }

        let panelMinY = panelMidY - (panelHeight / 2)
        return min(max((panelMinY - visibleFrame.minY - 16) / availableTravel, 0), 1)
    }
}

enum SideDockDragResolver {
    static let repositionDeadZone: CGFloat = 18
    static let closeThreshold: CGFloat = 64

    /// 光标相对起点朝屏幕中轴方向的水平位移。
    /// 用屏幕坐标而不是窗口内坐标：Dock 会跟着光标移动，窗口内坐标系本身在动，量不出真实位移。
    static func inwardDistance(
        edge: SideDockEdge,
        startLocation: CGPoint,
        currentLocation: CGPoint
    ) -> CGFloat {
        switch edge {
        case .left:
            max(currentLocation.x - startLocation.x, 0)
        case .right:
            max(startLocation.x - currentLocation.x, 0)
        }
    }

    static func verticalTravel(startLocation: CGPoint, currentLocation: CGPoint) -> CGFloat {
        abs(currentLocation.y - startLocation.y)
    }

    /// 只有朝屏幕中轴方向为主的拖动才算关闭手势。
    /// 上下移动占主导时一律当作调整位置，否则沿边缘上下拖动时的横向抖动会误关 WebApp。
    static func isClosingGesture(
        startedOnApp: Bool,
        inwardDistance: CGFloat,
        verticalTravel: CGFloat
    ) -> Bool {
        startedOnApp
            && inwardDistance >= repositionDeadZone
            && inwardDistance >= verticalTravel
    }

    static func closeProgress(inwardDistance: CGFloat, verticalTravel: CGFloat) -> CGFloat {
        guard inwardDistance >= verticalTravel else {
            return 0
        }

        return min(inwardDistance / closeThreshold, 1)
    }

    static func shouldClose(
        startedOnApp: Bool,
        inwardDistance: CGFloat,
        verticalTravel: CGFloat
    ) -> Bool {
        startedOnApp
            && inwardDistance >= closeThreshold
            && inwardDistance >= verticalTravel
    }
}
