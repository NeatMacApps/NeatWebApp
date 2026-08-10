import CoreGraphics

struct LauncherPresentationContext: Equatable, Sendable {
    struct Layout: Equatable, Sendable {
        let barSize: CGSize
        let topInsetHeight: CGFloat
        let iconRowHeight: CGFloat
        let iconBottomPadding: CGFloat
        let visibleAppCount: Int
        let shouldScroll: Bool
        let iconSize: CGFloat
        let iconSpacing: CGFloat
        let iconHorizontalPadding: CGFloat
        let iconFontSize: CGFloat
        let panelBottomPadding: CGFloat
        let backgroundCornerRadius: CGFloat

        var panelSize: CGSize {
            CGSize(
                width: barSize.width,
                height: barSize.height + panelBottomPadding
            )
        }
    }

    let geometry: ScreenNotchGeometry
    let apps: [WebAppDefinition]

    var layout: Layout {
        let launcherItemCount = max(apps.count + 1, 1)
        let notchWidth = geometry.notchRect.width
        let notchHeight = geometry.notchRect.height
        let preferredIconSize = min(max(notchHeight * 0.54, 28), 40)
        let minimumIconSize = max(min(notchHeight * 0.44, preferredIconSize), 24)
        let minimumSpacing = max(min(notchHeight * 0.16, 14), 8)
        let iconBottomPadding = max(min(notchHeight * 0.15, 12), 8)
        let maximumVisibleAppCount = max(
            Int(floor((notchWidth - minimumSpacing) / (preferredIconSize + minimumSpacing))),
            1
        )
        let visibleAppCount = min(launcherItemCount, maximumVisibleAppCount)
        let shouldScroll = launcherItemCount > maximumVisibleAppCount
        let iconSize = min(
            preferredIconSize,
            max(
                (notchWidth - (CGFloat(visibleAppCount + 1) * minimumSpacing)) / CGFloat(visibleAppCount),
                minimumIconSize
            )
        )
        let iconSpacing = visibleAppCount > 1 ? minimumSpacing : 0
        let iconRowHeight = iconSize + iconBottomPadding
        let barHeight = notchHeight + iconRowHeight
        let panelBottomPadding: CGFloat = 0

        return Layout(
            barSize: CGSize(width: notchWidth, height: barHeight),
            topInsetHeight: notchHeight,
            iconRowHeight: iconRowHeight,
            iconBottomPadding: iconBottomPadding,
            visibleAppCount: visibleAppCount,
            shouldScroll: shouldScroll,
            iconSize: iconSize,
            iconSpacing: iconSpacing,
            iconHorizontalPadding: minimumSpacing,
            iconFontSize: max(iconSize * 0.42, 14),
            panelBottomPadding: panelBottomPadding,
            backgroundCornerRadius: min(iconRowHeight * 0.5, 24)
        )
    }

    var panelSize: CGSize {
        layout.panelSize
    }

    var panelFrame: CGRect {
        let size = panelSize

        return CGRect(
            x: geometry.notchRect.minX,
            y: geometry.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

/// 启动器图标行左右拖动换位的纯数学：把横向位移折算成图标槽位数，
/// 再推算出目标下标与「贴住光标」的视觉偏移，独立出来便于单测。
enum LauncherRowReorder {
    /// 拖动后的目标下标：从起始下标按整槽位移偏移，并夹在有效范围内。
    static func targetIndex(
        startIndex: Int,
        translationX: CGFloat,
        slotWidth: CGFloat,
        itemCount: Int
    ) -> Int {
        guard slotWidth > 0, itemCount > 0 else {
            return startIndex
        }

        let slotShift = Int((translationX / slotWidth).rounded())
        return min(max(startIndex + slotShift, 0), itemCount - 1)
    }

    /// 拖动中的图标相对它当前所在槽位的贴手偏移：
    /// 真实位移减去「换位造成的新槽位平移」，图标才跟得上光标而不跳变。
    static func offset(
        translationX: CGFloat,
        targetIndex: Int,
        startIndex: Int,
        slotWidth: CGFloat
    ) -> CGFloat {
        guard slotWidth > 0 else {
            return translationX
        }

        return translationX - CGFloat(targetIndex - startIndex) * slotWidth
    }
}
