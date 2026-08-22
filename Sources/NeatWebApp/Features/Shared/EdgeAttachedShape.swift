import SwiftUI

enum ScreenAttachedEdge: Sendable {
    case top
    case left
    case right
    case bottom
}

struct EdgeAttachedShape: InsettableShape {
    var edge: ScreenAttachedEdge
    var cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> EdgeAttachedShape {
        EdgeAttachedShape(edge: edge, cornerRadius: cornerRadius, insetAmount: insetAmount + amount)
    }

    func path(in rect: CGRect) -> Path {
        let rect = drawingRect(from: rect)
        let connectionDepth = min(10, rect.width / 4, rect.height / 4)
        let sideBodyLength = max(rect.height - (connectionDepth * 2), 0)
        let radius = min(cornerRadius, rect.width / 2, sideBodyLength / 2)
        var path = Path()

        switch edge {
        case .top:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
        case .bottom:
            // 底部形状是左侧贴边形状旋转后的镜像：顶部两角保持外侧圆角，
            // 底部两角沿用贴边收束弧，因此能平滑过渡到屏幕边缘而不会变成药丸。
            let bottomRadius = min(
                cornerRadius,
                rect.height / 2,
                max(rect.width - (connectionDepth * 2), 0) / 2
            )

            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addCurve(
                to: CGPoint(x: rect.minX + connectionDepth, y: rect.maxY - connectionDepth),
                control1: CGPoint(x: rect.minX + (connectionDepth * 0.65), y: rect.maxY),
                control2: CGPoint(x: rect.minX + connectionDepth, y: rect.maxY - (connectionDepth * 0.35))
            )
            path.addLine(to: CGPoint(x: rect.minX + connectionDepth, y: rect.minY + bottomRadius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + connectionDepth + bottomRadius, y: rect.minY),
                control: CGPoint(x: rect.minX + connectionDepth, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX - connectionDepth - bottomRadius, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - connectionDepth, y: rect.minY + bottomRadius),
                control: CGPoint(x: rect.maxX - connectionDepth, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX - connectionDepth, y: rect.maxY - connectionDepth))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control1: CGPoint(x: rect.maxX - connectionDepth, y: rect.maxY - (connectionDepth * 0.35)),
                control2: CGPoint(x: rect.maxX - (connectionDepth * 0.65), y: rect.maxY)
            )
        case .left:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.minX + connectionDepth, y: rect.minY + connectionDepth),
                control1: CGPoint(x: rect.minX, y: rect.minY + (connectionDepth * 0.65)),
                control2: CGPoint(x: rect.minX + (connectionDepth * 0.35), y: rect.minY + connectionDepth)
            )
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY + connectionDepth))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + connectionDepth + radius),
                control: CGPoint(x: rect.maxX, y: rect.minY + connectionDepth)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - connectionDepth - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY - connectionDepth),
                control: CGPoint(x: rect.maxX, y: rect.maxY - connectionDepth)
            )
            path.addLine(to: CGPoint(x: rect.minX + connectionDepth, y: rect.maxY - connectionDepth))
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY),
                control1: CGPoint(x: rect.minX + (connectionDepth * 0.35), y: rect.maxY - connectionDepth),
                control2: CGPoint(x: rect.minX, y: rect.maxY - (connectionDepth * 0.65))
            )
        case .right:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.maxX - connectionDepth, y: rect.minY + connectionDepth),
                control1: CGPoint(x: rect.maxX, y: rect.minY + (connectionDepth * 0.65)),
                control2: CGPoint(x: rect.maxX - (connectionDepth * 0.35), y: rect.minY + connectionDepth)
            )
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY + connectionDepth))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.minY + connectionDepth + radius),
                control: CGPoint(x: rect.minX, y: rect.minY + connectionDepth)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - connectionDepth - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.maxY - connectionDepth),
                control: CGPoint(x: rect.minX, y: rect.maxY - connectionDepth)
            )
            path.addLine(to: CGPoint(x: rect.maxX - connectionDepth, y: rect.maxY - connectionDepth))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control1: CGPoint(x: rect.maxX - (connectionDepth * 0.35), y: rect.maxY - connectionDepth),
                control2: CGPoint(x: rect.maxX, y: rect.maxY - (connectionDepth * 0.65))
            )
        }

        path.closeSubpath()
        return path
    }

    /// 玻璃会向内收缩形状。贴边那一侧不能跟着缩，否则底板会离开屏幕边缘，
    /// 看起来像一块浮着的圆角矩形，四周还可能露出宿主视图的浅色底。
    private func drawingRect(from rect: CGRect) -> CGRect {
        let inset = insetAmount
        guard inset != 0 else {
            return rect
        }

        switch edge {
        case .top:
            return CGRect(
                x: rect.minX + inset,
                y: rect.minY,
                width: max(rect.width - (inset * 2), 0),
                height: max(rect.height - inset, 0)
            )
        case .bottom:
            return CGRect(
                x: rect.minX + inset,
                y: rect.minY + inset,
                width: max(rect.width - (inset * 2), 0),
                height: max(rect.height - inset, 0)
            )
        case .left:
            return CGRect(
                x: rect.minX,
                y: rect.minY + inset,
                width: max(rect.width - inset, 0),
                height: max(rect.height - (inset * 2), 0)
            )
        case .right:
            return CGRect(
                x: rect.minX + inset,
                y: rect.minY + inset,
                width: max(rect.width - inset, 0),
                height: max(rect.height - (inset * 2), 0)
            )
        }
    }
}
