import AppKit

enum WebAppIconNormalizer {
    static func normalizedLauncherIcon(from image: NSImage, canvasSize: CGFloat = 256) -> NSImage? {
        guard
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let analysis = analyze(cgImage)
        else {
            return nil
        }

        let canvas = NSSize(width: canvasSize, height: canvasSize)
        let output = NSImage(size: canvas)

        output.lockFocus()
        defer { output.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else {
            return nil
        }

        let bounds = CGRect(origin: .zero, size: canvas)
        let circleBounds = bounds.insetBy(dx: 1, dy: 1)
        let renderedImage = croppedImage(from: cgImage, rect: analysis.visibleRect) ?? cgImage
        let imageSize = CGSize(width: renderedImage.width, height: renderedImage.height)

        context.setAllowsAntialiasing(true)
        context.interpolationQuality = .high

        context.saveGState()
        context.addPath(CGPath(ellipseIn: circleBounds, transform: nil))
        context.clip()
        context.setFillColor(analysis.backgroundColor.cgColor)
        context.fill(bounds)

        let imageRect = if analysis.isFullBleed {
            aspectFillRect(for: imageSize, in: bounds)
        } else {
            aspectFitRect(for: imageSize, in: bounds.insetBy(dx: canvasSize * 0.18, dy: canvasSize * 0.18))
        }
        context.draw(renderedImage, in: imageRect)
        context.restoreGState()

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
        context.setLineWidth(max(1, canvasSize / 128))
        context.strokeEllipse(in: circleBounds.insetBy(dx: 0.5, dy: 0.5))

        return output
    }

    private static func analyze(_ cgImage: CGImage) -> IconAnalysis? {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else {
            return nil
        }

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        var opaquePixelCount = 0
        var edgeOpaquePixelCount = 0
        var edgePixelCount = 0
        var averageAccumulator = ColorAccumulator()
        var edgeAccumulator = ColorAccumulator()

        let alphaThreshold: CGFloat = 0.08
        let edgeInsetX = max(1, width / 10)
        let edgeInsetY = max(1, height / 10)

        for y in 0 ..< height {
            for x in 0 ..< width {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }

                let alpha = color.alphaComponent
                let isOpaque = alpha > alphaThreshold
                let isInEdgeRing = x < edgeInsetX || x >= width - edgeInsetX || y < edgeInsetY || y >= height - edgeInsetY

                if isInEdgeRing {
                    edgePixelCount += 1
                    if isOpaque {
                        edgeOpaquePixelCount += 1
                        edgeAccumulator.add(color, weight: alpha)
                    }
                }

                guard isOpaque else {
                    continue
                }

                opaquePixelCount += 1
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                averageAccumulator.add(color, weight: alpha)
            }
        }

        guard opaquePixelCount > 0, maxX >= minX, maxY >= minY else {
            return nil
        }

        let visibleRect = CGRect(
            x: max(minX - 1, 0),
            y: max(minY - 1, 0),
            width: min(maxX - minX + 3, width - max(minX - 1, 0)),
            height: min(maxY - minY + 3, height - max(minY - 1, 0))
        )

        let widthCoverage = visibleRect.width / CGFloat(width)
        let heightCoverage = visibleRect.height / CGFloat(height)
        let edgeOpacity = edgePixelCount > 0 ? CGFloat(edgeOpaquePixelCount) / CGFloat(edgePixelCount) : 0
        guard let averageColor = averageAccumulator.color else {
            return nil
        }

        let edgeColor = edgeAccumulator.color ?? averageColor
        let averageLuminance = averageColor.relativeLuminance
        let isFullBleed = widthCoverage > 0.82 && heightCoverage > 0.82 && edgeOpacity > 0.48

        let backgroundColor: NSColor
        if isFullBleed {
            backgroundColor = edgeColor
        } else if averageLuminance > 0.84 {
            backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1)
        } else {
            backgroundColor = NSColor(calibratedWhite: 0.97, alpha: 1)
        }

        return IconAnalysis(
            visibleRect: visibleRect,
            isFullBleed: isFullBleed,
            backgroundColor: backgroundColor
        )
    }

    private static func croppedImage(from image: CGImage, rect: CGRect) -> CGImage? {
        let integralRect = rect.integral
        guard integralRect.width > 0, integralRect.height > 0 else {
            return nil
        }

        return image.cropping(to: integralRect)
    }

    private static func aspectFitRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return bounds
        }

        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func aspectFillRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return bounds
        }

        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

private struct IconAnalysis {
    let visibleRect: CGRect
    let isFullBleed: Bool
    let backgroundColor: NSColor
}

private struct ColorAccumulator {
    private var red: CGFloat = 0
    private var green: CGFloat = 0
    private var blue: CGFloat = 0
    private var alpha: CGFloat = 0
    private var totalWeight: CGFloat = 0

    mutating func add(_ color: NSColor, weight: CGFloat) {
        red += color.redComponent * weight
        green += color.greenComponent * weight
        blue += color.blueComponent * weight
        alpha += color.alphaComponent * weight
        totalWeight += weight
    }

    var color: NSColor? {
        guard totalWeight > 0 else {
            return nil
        }

        return NSColor(
            calibratedRed: red / totalWeight,
            green: green / totalWeight,
            blue: blue / totalWeight,
            alpha: alpha / totalWeight
        )
    }
}

private extension NSColor {
    var relativeLuminance: CGFloat {
        0.2126 * redComponent + 0.7152 * greenComponent + 0.0722 * blueComponent
    }
}
