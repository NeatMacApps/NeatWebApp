import SwiftUI

enum ScreenAttachedEdge: Sendable {
    case top
    case left
    case right
}

struct EdgeAttachedShape: Shape {
    let edge: ScreenAttachedEdge
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let connectionDepth = min(10, rect.width / 4, rect.height / 4)
        let sideBodyHeight = max(rect.height - (connectionDepth * 2), 0)
        let radius = min(cornerRadius, rect.width / 2, sideBodyHeight / 2)
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
}
