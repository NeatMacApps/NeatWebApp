import AppKit
import Foundation
import ImageIO

/// 网站图标解码前的尺寸上限：侧边栏 / 启动器最大约 40pt，按 2× 视网膜再留一点余量。
/// 先压源图再做圆形规范化，避免超大 apple-touch-icon 全尺寸进内存做逐像素分析。
enum WebAppFaviconImagePreparing {
    static let maxSourcePixelDimension = 256
    static let normalizedCanvasPoints: CGFloat = 128

    static func image(from data: Data, maxPixelDimension: Int = maxSourcePixelDimension) -> NSImage? {
        guard let downsampled = downsampleCGImage(data: data, maxPixelDimension: maxPixelDimension) else {
            return NSImage(data: data)
        }

        return NSImage(cgImage: downsampled, size: NSSize(width: downsampled.width, height: downsampled.height))
    }

    static func downsampleCGImage(data: Data, maxPixelDimension: Int) -> CGImage? {
        guard maxPixelDimension > 0 else {
            return nil
        }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
