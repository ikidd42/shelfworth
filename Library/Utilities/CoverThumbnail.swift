import UIKit
import ImageIO

/// Downsampled cover bitmaps, decoded off the main thread and cached.
///
/// Cover data is stored at capture/download resolution (camera shots can be
/// 4000px); decoding and scaling that on every grid cell render is the main
/// scrolling cost in a large library. ImageIO thumbnailing decodes directly
/// to the target size without materializing the full image.
nonisolated enum CoverThumbnail {

    /// NSCache is thread-safe; safe to touch from any isolation domain.
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    /// `maxPixel` is the longest edge in pixels the bitmap needs on screen.
    static func image(data: Data, cacheKey: String, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(cacheKey)-\(Int(maxPixel))" as NSString
        if let hit = cache.object(forKey: key) { return hit }

        let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let options = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
                return nil
            }
            let thumbOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else {
                return nil
            }
            return UIImage(cgImage: cg)
        }.value

        if let decoded { cache.setObject(decoded, forKey: key) }
        return decoded
    }
}
