import CoreGraphics

struct LauncherPresentationContext: Equatable, Sendable {
    struct Layout: Equatable, Sendable {
        let notchSize: CGSize
        let barSize: CGSize
        let topInsetHeight: CGFloat
        let iconRowHeight: CGFloat
        let iconSize: CGFloat
        let iconCornerRadius: CGFloat
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
        let appCount = max(apps.count, 1)
        let notchWidth = geometry.notchRect.width
        let notchHeight = geometry.notchRect.height
        let slotWidth = notchWidth / CGFloat(appCount)
        let iconSize = max(min(slotWidth - 8, 40), 24)
        let iconVerticalPadding: CGFloat = 10
        let iconRowHeight = iconSize + iconVerticalPadding * 2
        let barHeight = notchHeight + iconRowHeight
        let panelBottomPadding: CGFloat = 8

        return Layout(
            notchSize: CGSize(width: notchWidth, height: notchHeight),
            barSize: CGSize(width: notchWidth, height: barHeight),
            topInsetHeight: notchHeight,
            iconRowHeight: iconRowHeight,
            iconSize: iconSize,
            iconCornerRadius: max(iconSize * 0.24, 10),
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
