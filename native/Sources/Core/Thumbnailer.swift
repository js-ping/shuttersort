import AVFoundation
import Foundation
import ImageIO

/// 缩略图。
///
/// 这是原生版相对 Python 版最实在的一处改进：Python 版要靠 `sips` / `magick` /
/// `ffmpeg` 三个外部工具拼接，现在全部交给系统框架 ——
/// ImageIO 原生解 HEIC / HEIF / RAW / TIFF，AVFoundation 直接抽视频帧。
/// 用户什么都不用装。
enum Thumbnailer {

    private static let cache = NSCache<NSString, CGImageBox>()

    final class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    static func cached(_ url: URL, maxPixel: CGFloat) -> CGImage? {
        let key = "\(url.path)|\(Int(maxPixel))|\(fileStamp(url))" as NSString
        if let hit = cache.object(forKey: key) { return hit.image }
        guard let img = make(url: url, maxPixel: maxPixel) else { return nil }
        cache.setObject(CGImageBox(img), forKey: key)
        return img
    }

    private static func fileStamp(_ url: URL) -> Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        return Int(mtime) &+ size
    }

    static func make(url: URL, maxPixel: CGFloat) -> CGImage? {
        let ext = url.pathExtension.lowercased()
        if Scanner.videoExts.contains("." + ext) {
            return videoFrame(url: url, maxPixel: maxPixel)
        }
        return imageThumbnail(url: url, maxPixel: maxPixel)
    }

    /// 图片：ImageIO 一步出缩略图，HEIC / RAW / TIFF 全都认
    private static func imageThumbnail(url: URL, maxPixel: CGFloat) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// 视频：取第 0.5 秒那一帧（太靠前容易是黑场）
    private static func videoFrame(url: URL, maxPixel: CGFloat) -> CGImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let sem = DispatchSemaphore(value: 0)
        let box = ResultBox()
        gen.generateCGImageAsynchronously(for: CMTime(seconds: 0.5, preferredTimescale: 600)) {
            image, _, _ in
            box.image = image
            sem.signal()
        }
        // 视频在机械硬盘 / 网络盘上可能很慢，给够时间但也别无限等
        guard sem.wait(timeout: .now() + 10) == .success else { return nil }
        return box.image
    }

    /// 回调可能在任意线程写，用个小容器隔离
    private final class ResultBox: @unchecked Sendable {
        var image: CGImage?
    }
}
