import AppKit
import CoreGraphics

/// 计算窗口还有多少面积真正露在屏幕上。
///
/// 系统 `occlusionState` 只区分「还有一个像素可见」和「完全看不见」，
/// 不能满足「八成被挡住就收起」。这里用窗口列表做矩形差集：
/// 先去掉飞出屏幕的部分，再扣掉位于前面、同层级、足够不透明的窗口。
/// 调度中心、菜单栏这类高层级浮层不参与遮挡，避免瞬时系统界面把窗口收走。
enum WindowVisibleCoverage {
    /// 看不见的面积达到这个比例就收起。
    static let collapseHiddenFraction: CGFloat = 0.8
    /// 透明度低于此值的窗口当看不见，不计入遮挡。
    static let opaqueAlphaThreshold: CGFloat = 0.9

    struct Record: Equatable, Sendable {
        let windowID: CGWindowID
        let frame: CGRect
        let layer: Int
        let alpha: CGFloat
    }

    static func shouldCollapse(hiddenFraction: CGFloat) -> Bool {
        hiddenFraction >= collapseHiddenFraction
    }

    /// `screenBounds` 为空时不裁切屏幕外面积，方便单测只验证遮挡。
    static func hiddenFraction(
        of targetID: CGWindowID,
        windowsFrontToBack: [Record],
        screenBounds: [CGRect]
    ) -> CGFloat {
        guard let targetIndex = windowsFrontToBack.firstIndex(where: { $0.windowID == targetID }) else {
            // 当前桌面的窗口列表里找不到它：在别的桌面，或已经离开屏幕。
            return 1
        }

        let target = windowsFrontToBack[targetIndex]
        let originalArea = target.frame.width * target.frame.height
        guard originalArea > 0 else {
            return 1
        }

        var visible = VisibleRegion(rect: target.frame)
        if !screenBounds.isEmpty {
            var onScreen = VisibleRegion()
            for screen in screenBounds {
                let piece = target.frame.intersection(screen)
                if !piece.isNull, !piece.isEmpty {
                    onScreen.add(piece)
                }
            }
            visible = onScreen
        }

        for occluder in windowsFrontToBack.prefix(targetIndex) {
            guard occluder.layer == target.layer, occluder.alpha >= opaqueAlphaThreshold else {
                continue
            }
            visible.subtract(occluder.frame)
        }

        return max(0, min(1, 1 - visible.area / originalArea))
    }

    static func cgBounds(fromAppKitFrame frame: CGRect, primaryDisplayHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: primaryDisplayHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    /// 当前桌面窗口列表里找不到它时：系统也说看不见才当成完全挡住（切桌面、被全屏占掉）。
    /// 系统还说看得见，多半是刚显示出来、列表还没跟上，不能立刻收起。
    static func hiddenFractionWhenMissingFromScreenList(systemReportsVisible: Bool) -> CGFloat {
        systemReportsVisible ? 0 : 1
    }

    @MainActor
    static func hiddenFraction(of window: NSWindow) -> CGFloat {
        let systemReportsVisible = window.occlusionState.contains(.visible)
        let windowNumber = window.windowNumber
        guard windowNumber > 0 else {
            return hiddenFractionWhenMissingFromScreenList(systemReportsVisible: systemReportsVisible)
        }

        guard let windowsFrontToBack = captureOnScreenWindows() else {
            // 读不到窗口列表时退回系统全遮挡判定，避免永远不收起。
            return hiddenFractionWhenMissingFromScreenList(systemReportsVisible: systemReportsVisible)
        }

        let targetID = CGWindowID(windowNumber)
        guard windowsFrontToBack.contains(where: { $0.windowID == targetID }) else {
            return hiddenFractionWhenMissingFromScreenList(systemReportsVisible: systemReportsVisible)
        }

        let primaryHeight = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 0
        let screenBounds = NSScreen.screens.map {
            cgBounds(fromAppKitFrame: $0.frame, primaryDisplayHeight: primaryHeight)
        }

        return hiddenFraction(
            of: targetID,
            windowsFrontToBack: windowsFrontToBack,
            screenBounds: screenBounds
        )
    }

    @MainActor
    static func captureOnScreenWindows() -> [Record]? {
        guard let rawList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        return rawList.compactMap(parseRecord(from:))
    }

    private static func parseRecord(from dict: [String: Any]) -> Record? {
        guard let windowID = cgWindowID(from: dict[kCGWindowNumber as String]),
              let bounds = dict[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds),
              frame.width > 0,
              frame.height > 0 else {
            return nil
        }

        let layer = (dict[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        let alpha = CGFloat((dict[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
        return Record(windowID: windowID, frame: frame, layer: layer, alpha: alpha)
    }

    private static func cgWindowID(from value: Any?) -> CGWindowID? {
        if let number = value as? NSNumber {
            return number.uint32Value
        }
        return value as? CGWindowID
    }
}

/// 不重叠矩形拼成的可见区域。遮挡窗口彼此重叠时，差集不会把重叠部分算两次。
private struct VisibleRegion {
    private(set) var rectangles: [CGRect]

    init() {
        rectangles = []
    }

    init(rect: CGRect) {
        if rect.isEmpty || rect.isNull || rect.isInfinite {
            rectangles = []
        } else {
            rectangles = [rect]
        }
    }

    var area: CGFloat {
        rectangles.reduce(0) { $0 + $1.width * $1.height }
    }

    mutating func add(_ rect: CGRect) {
        guard !rect.isEmpty, !rect.isNull, !rect.isInfinite else {
            return
        }
        rectangles.append(rect)
    }

    mutating func subtract(_ rect: CGRect) {
        guard !rect.isEmpty, !rect.isNull, !rect.isInfinite else {
            return
        }
        rectangles = rectangles.flatMap { $0.pieces(afterSubtracting: rect) }
    }
}

private extension CGRect {
    func pieces(afterSubtracting other: CGRect) -> [CGRect] {
        let overlap = intersection(other)
        guard !overlap.isNull, !overlap.isEmpty else {
            return [self]
        }
        if other.contains(self) {
            return []
        }

        var pieces: [CGRect] = []
        if overlap.minY > minY {
            pieces.append(CGRect(x: minX, y: minY, width: width, height: overlap.minY - minY))
        }
        if overlap.maxY < maxY {
            pieces.append(CGRect(x: minX, y: overlap.maxY, width: width, height: maxY - overlap.maxY))
        }
        if overlap.minX > minX {
            pieces.append(CGRect(x: minX, y: overlap.minY, width: overlap.minX - minX, height: overlap.height))
        }
        if overlap.maxX < maxX {
            pieces.append(CGRect(x: overlap.maxX, y: overlap.minY, width: maxX - overlap.maxX, height: overlap.height))
        }
        return pieces.filter { !$0.isEmpty }
    }
}
