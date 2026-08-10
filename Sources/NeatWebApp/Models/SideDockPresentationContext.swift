import CoreGraphics
import Foundation

enum SideDockEdge: String, CaseIterable, Codable, Sendable {
    case left
    case right
    case bottom

    var title: String {
        switch self {
        case .left:
            "左侧"
        case .right:
            "右侧"
        case .bottom:
            "底部"
        }
    }

    var attachedShapeEdge: ScreenAttachedEdge {
        switch self {
        case .left:
            .left
        case .right:
            .right
        case .bottom:
            .bottom
        }
    }

    /// 该边缘是否属于左右两侧（区别于屏幕底边）。
    var isSide: Bool {
        self != .bottom
    }
}

struct SideDockPresentationContext: Equatable {
    struct Layout: Equatable, Sendable {
        // 整套尺寸按原始设计的 88% 等比缩小。
        static let thickness: CGFloat = 47
        static let minimumLength: CGFloat = 65
        static let edgeTransitionDepth: CGFloat = 9
        static let iconSlotSize: CGFloat = 33
        static let iconSize: CGFloat = 28
        static let iconSpacing: CGFloat = 6
        // 内容留白加上点击区内的图标留白，
        // 让图标到边缘的视觉距离与左右视觉距离一致。
        static let verticalPadding: CGFloat = 7
        static let cornerRadius: CGFloat = 15

        let edge: SideDockEdge
        let length: CGFloat
        let shouldScroll: Bool

        var panelSize: CGSize {
            if edge.isSide {
                CGSize(width: Self.thickness, height: length)
            } else {
                CGSize(width: length, height: Self.thickness)
            }
        }
    }

    let apps: [WebAppDefinition]
    let edge: SideDockEdge
    let screenFrame: CGRect
    let visibleFrame: CGRect
    let verticalPosition: CGFloat

    var layout: Layout {
        let availableScreenLength = edge.isSide
            ? visibleFrame.height
            : visibleFrame.width
        let maximumLength = max(
            availableScreenLength - (SideDockPlacementResolver.edgeMargin * 2),
            Layout.minimumLength
        )
        let naturalLength = (Layout.edgeTransitionDepth * 2)
            + (Layout.verticalPadding * 2)
            + (CGFloat(apps.count) * Layout.iconSlotSize)
            + (CGFloat(max(apps.count - 1, 0)) * Layout.iconSpacing)
        let length = min(max(naturalLength, Layout.minimumLength), maximumLength)

        return Layout(
            edge: edge,
            length: length,
            shouldScroll: naturalLength > maximumLength
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

    /// Dock 上下两端不再额外留白，可以一路拖到贴住屏幕边缘。
    /// 贴的是 `visibleFrame`：底部有系统程序坞时仍然停在它内侧，不会压住程序坞。
    static let edgeMargin: CGFloat = 0

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

        switch edge {
        case .left:
            let availableTravel = max(visibleFrame.height - panelSize.height - (edgeMargin * 2), 0)
            let y = visibleFrame.minY + edgeMargin + (availableTravel * clampedPosition)
            return CGRect(origin: CGPoint(x: visibleFrame.minX, y: y), size: panelSize)
        case .right:
            let availableTravel = max(visibleFrame.height - panelSize.height - (edgeMargin * 2), 0)
            let y = visibleFrame.minY + edgeMargin + (availableTravel * clampedPosition)
            return CGRect(
                origin: CGPoint(x: visibleFrame.maxX - panelSize.width, y: y),
                size: panelSize
            )
        case .bottom:
            let availableTravel = max(visibleFrame.width - panelSize.width - (edgeMargin * 2), 0)
            let x = visibleFrame.minX + edgeMargin + (availableTravel * clampedPosition)
            return CGRect(
                origin: CGPoint(x: x, y: visibleFrame.minY),
                size: panelSize
            )
        }
    }

    static func normalizedVerticalPosition(
        panelMidY: CGFloat,
        visibleFrame: CGRect,
        panelHeight: CGFloat
    ) -> CGFloat {
        let availableTravel = max(visibleFrame.height - panelHeight - (edgeMargin * 2), 0)
        guard availableTravel > 0 else {
            return 0.5
        }

        let panelMinY = panelMidY - (panelHeight / 2)
        return min(max((panelMinY - visibleFrame.minY - edgeMargin) / availableTravel, 0), 1)
    }

    /// 底部边缘时归一化的是水平位置。
    static func normalizedPosition(
        edge: SideDockEdge,
        panelMidX: CGFloat,
        visibleFrame: CGRect,
        panelWidth: CGFloat
    ) -> CGFloat {
        let availableTravel = max(visibleFrame.width - panelWidth - (edgeMargin * 2), 0)
        guard availableTravel > 0 else {
            return 0.5
        }

        let panelMinX = panelMidX - (panelWidth / 2)
        return min(max((panelMinX - visibleFrame.minX - edgeMargin) / availableTravel, 0), 1)
    }
}

enum SideDockDragResolver {
    static let repositionDeadZone: CGFloat = 18
    static let closeThreshold: CGFloat = 64

    /// 光标相对起点朝屏幕中轴方向的位移。
    /// 用屏幕坐标而不是窗口内坐标：Dock 会跟着光标移动，窗口内坐标系本身在动，量不出真实位移。
    /// 左右边缘时是水平位移，底部边缘时是垂直位移。
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
        case .bottom:
            max(currentLocation.y - startLocation.y, 0)
        }
    }

    /// 光标相对起点沿屏幕边缘方向的位移：左右边缘时是垂直位移，底部边缘时是水平位移。
    static func alongEdgeTravel(
        edge: SideDockEdge,
        startLocation: CGPoint,
        currentLocation: CGPoint
    ) -> CGFloat {
        edge.isSide
            ? abs(currentLocation.y - startLocation.y)
            : abs(currentLocation.x - startLocation.x)
    }

    /// 只有朝屏幕中轴方向为主的拖动才算关闭手势。
    /// 沿边缘方向的移动占主导时一律当作调整位置，否则沿边缘拖动时的抖动会误关 WebApp。
    static func isClosingGesture(
        startedOnApp: Bool,
        inwardDistance: CGFloat,
        alongEdgeTravel: CGFloat
    ) -> Bool {
        startedOnApp
            && inwardDistance >= repositionDeadZone
            && inwardDistance >= alongEdgeTravel
    }

    static func closeProgress(inwardDistance: CGFloat, alongEdgeTravel: CGFloat) -> CGFloat {
        guard inwardDistance >= alongEdgeTravel else {
            return 0
        }

        return min(inwardDistance / closeThreshold, 1)
    }

    static func shouldClose(
        startedOnApp: Bool,
        inwardDistance: CGFloat,
        alongEdgeTravel: CGFloat
    ) -> Bool {
        startedOnApp
            && inwardDistance >= closeThreshold
            && inwardDistance >= alongEdgeTravel
    }
}
