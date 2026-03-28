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
