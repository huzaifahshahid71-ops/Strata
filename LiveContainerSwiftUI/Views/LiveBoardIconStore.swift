import UIKit
import CoreImage

/// Separate presentation cache: never reuse or rewrite upstream's bordered icon files.
@MainActor enum LiveBoardIconStore {
    private static let icons = NSCache<NSString, UIImage>()
    private static let backgrounds = NSCache<NSString, UIImage>()
    private static let context = CIContext(options: [.cacheIntermediates: false])
    static func invalidate() { icons.removeAllObjects(); backgrounds.removeAllObjects() }
    static func image(_ app: LCAppModel, dark: Bool) -> UIImage? {
        if let custom = LiveBoardAppCustomization.shared.image(app) { return custom }
        if app.bundleIdentifier.caseInsensitiveCompare("com.EduAlexxis.MusicManager") == .orderedSame,
           let replacement = UIImage(named: "LiveBoardByeTunes", in: .main, compatibleWith: nil) {
            return replacement
        }
        let key = (app.appInfo.bundlePath() + (dark ? ":dark" : ":light") + ":" + String(LiveBoardAppCustomization.shared.revision)) as NSString
        if let image = icons.object(forKey: key) { return image }
        if let phone = app.appInfo as? StrataPhoneAppInfo, let image = phone.iconIsDarkIcon(dark) { icons.setObject(image, forKey: key); return image }
        guard let image = UIImage.generateIcon(forBundleURL: URL(fileURLWithPath: app.appInfo.bundlePath()), style: dark ? .Dark : .Light, hasBorder: false) else { return nil }
        let cleaned = LiveBoardIconEdges.clean(image)
        icons.setObject(cleaned, forKey: key)
        return cleaned
    }
    static func background(_ app: LCAppModel, dark: Bool) -> UIImage? {
        let key = (app.appInfo.bundlePath() + (dark ? ":dark" : ":light") + ":" + String(LiveBoardAppCustomization.shared.revision)) as NSString
        if let image = backgrounds.object(forKey: key) { return image }
        guard let source = image(app, dark: dark) else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160), format: format).image { _ in source.draw(in: CGRect(x: 0, y: 0, width: 160, height: 160)) }
        guard let input = CIImage(image: small), let filter = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: input.clampedToExtent(), kCIInputRadiusKey: 18]), let output = filter.outputImage, let cg = context.createCGImage(output, from: input.extent) else { return small }
        let result = UIImage(cgImage: cg); backgrounds.setObject(result, forKey: key)
        return result
    }
}
