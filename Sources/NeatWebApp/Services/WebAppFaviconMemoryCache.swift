import AppKit
import Foundation

/// 网站图标的有界内存缓存。磁盘仍是权威来源；本缓存可在系统压力下整表丢掉。
final class WebAppFaviconMemoryCache: @unchecked Sendable {
    /// 单图标按规范化画布估算 cost（RGBA 字节近似）。
    private static let costPerNormalizedIcon =
        Int(WebAppFaviconImagePreparing.normalizedCanvasPoints
            * WebAppFaviconImagePreparing.normalizedCanvasPoints
            * 4)

    /// 约可容纳 64 枚规范化图标；超出由 NSCache 自行淘汰。
    private static let totalCostLimit = costPerNormalizedIcon * 64

    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.totalCostLimit = Self.totalCostLimit
        cache.countLimit = 128
    }

    func image(for appID: String) -> NSImage? {
        cache.object(forKey: appID as NSString)
    }

    func store(_ image: NSImage, for appID: String) {
        let cost = max(Self.costPerNormalizedIcon, estimatedCost(of: image))
        cache.setObject(image, forKey: appID as NSString, cost: cost)
    }

    func remove(for appID: String) {
        cache.removeObject(forKey: appID as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    private func estimatedCost(of image: NSImage) -> Int {
        guard let representation = image.representations.first as? NSBitmapImageRep else {
            return Self.costPerNormalizedIcon
        }

        let bytesPerRow = max(representation.bytesPerRow, 0)
        let pixelHeight = max(representation.pixelsHigh, 0)
        return max(bytesPerRow * pixelHeight, Self.costPerNormalizedIcon)
    }
}
