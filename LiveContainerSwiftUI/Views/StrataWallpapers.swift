import SwiftUI
import PhotosUI
import AVFoundation
import AVKit
import UniformTypeIdentifiers

struct StrataWallpaper: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let file: String
    let thumbnail: String
    let live: Bool
}
@MainActor final class StrataWallpapers: ObservableObject {
    static let shared = StrataWallpapers()
    @Published private(set) var items: [StrataWallpaper] = []
    private let cache = NSCache<NSString, UIImage>()
    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Artwork/Wallpapers", isDirectory: true)
    init() {
        cache.countLimit = 16; cache.totalCostLimit = 48 * 1024 * 1024
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
        let old = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LiveBoard/wallpaper.jpg")
        if items.isEmpty, FileManager.default.fileExists(atPath: old.path), let image = UIImage(contentsOfFile: old.path), let item = try? add(image: image, name: "Your photo") {
            if LCUtils.appGroupUserDefault.string(forKey: "LiveBoardWallpaperStyle") == "photo" { LCUtils.appGroupUserDefault.set(item.id, forKey: "StrataSelectedWallpaper") }
        }
    }
    func reload() { if let data = try? Data(contentsOf: directory.appendingPathComponent("Wallpapers.json")), let value = try? JSONDecoder().decode([StrataWallpaper].self, from: data) { items = value.filter { safe($0.file) && safe($0.thumbnail) } } }
    private func safe(_ file: String) -> Bool { !file.isEmpty && file == URL(fileURLWithPath: file).lastPathComponent && !file.contains("..") }
    func url(_ item: StrataWallpaper) -> URL { directory.appendingPathComponent(item.file) }
    func image(_ item: StrataWallpaper) -> UIImage? {
        if let image = cache.object(forKey: item.thumbnail as NSString) { return image }
        guard let image = UIImage(contentsOfFile: directory.appendingPathComponent(item.thumbnail).path) else { return nil }
        cache.setObject(image, forKey: item.thumbnail as NSString, cost: Int(image.size.width * image.size.height * 4)); return image
    }
    private func commit(_ item: StrataWallpaper) throws {
        let next = items + [item]
        try JSONEncoder().encode(next).write(to: directory.appendingPathComponent("Wallpapers.json"), options: .atomic)
        items = next
    }
    @discardableResult func add(image: UIImage, name: String = "Photo") throws -> StrataWallpaper {
        let id = UUID().uuidString
        let size = image.size; let factor = min(1, 2400 / max(1, max(size.width, size.height)))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let resized = UIGraphicsImageRenderer(size: CGSize(width: max(1, size.width * factor), height: max(1, size.height * factor)), format: format).image { _ in image.draw(in: CGRect(x: 0, y: 0, width: size.width * factor, height: size.height * factor)) }
        guard let data = resized.jpegData(compressionQuality: 0.92) else { throw CocoaError(.fileReadCorruptFile) }
        let item = StrataWallpaper(id: id, name: name, file: id + ".jpg", thumbnail: id + ".jpg", live: false)
        try data.write(to: url(item), options: .atomic); try commit(item); return item
    }
    @discardableResult func add(video source: URL) async throws -> StrataWallpaper {
        let id = UUID().uuidString
        let ext = ["mov", "mp4", "m4v"].contains(source.pathExtension.lowercased()) ? source.pathExtension.lowercased() : "mov"
        let item = StrataWallpaper(id: id, name: source.deletingPathExtension().lastPathComponent, file: id + "." + ext, thumbnail: id + "-preview.jpg", live: true)
        let target = url(item)
        try await Task.detached(priority: .userInitiated) { try FileManager.default.copyItem(at: source, to: target) }.value
        do {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url(item)))
            generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 720, height: 1280)
            let cg: CGImage
            if #available(iOS 16.0, *) { cg = try await generator.image(at: .zero).image }
            else { cg = try await withCheckedThrowingContinuation { continuation in
                generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { _, image, _, _, error in
                    if let image { continuation.resume(returning: image) } else { continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile)) }
                }
            } }
            guard let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.85) else { throw CocoaError(.fileReadCorruptFile) }
            try data.write(to: directory.appendingPathComponent(item.thumbnail), options: .atomic)
            try commit(item); return item
        } catch { try? FileManager.default.removeItem(at: url(item)); throw error }
    }
}

final class StrataPlayerSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
struct StrataLiveWallpaper: UIViewRepresentable {
    let url: URL
    var playing: Bool
    var fit = false
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView { StrataPlayerSurface() }
    func updateUIView(_ view: UIView, context: Context) {
        guard let surface = view as? StrataPlayerSurface else { return }
        context.coordinator.configure(url: url, surface: surface)
        surface.playerLayer.videoGravity = fit ? .resizeAspect : .resizeAspectFill
        if playing { context.coordinator.player?.play() } else { context.coordinator.player?.pause() }
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.player?.pause(); coordinator.player = nil; coordinator.looper = nil }
    final class Coordinator {
        var url: URL?; var player: AVQueuePlayer?; var looper: AVPlayerLooper?
        func configure(url: URL, surface: StrataPlayerSurface) {
            guard self.url != url else { return }
            player?.pause(); self.url = url
            let player = AVQueuePlayer(); player.isMuted = true; player.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url)); self.player = player
            surface.playerLayer.player = player
        }
    }
}

/// Copy provider-owned temporary videos before the provider callback returns.
struct StrataWallpaperMediaPicker: UIViewControllerRepresentable {
    let completion: (UIImage?, URL?, String?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(); config.filter = .any(of: [.images, .videos]); config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config); picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: (UIImage?, URL?, String?) -> Void
        init(_ completion: @escaping (UIImage?, URL?, String?) -> Void) { self.completion = completion }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else { completion(nil, nil, nil); return }
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { source, error in
                    do {
                        guard let source else { throw error ?? CocoaError(.fileReadUnknown) }
                        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
                        try FileManager.default.copyItem(at: source, to: target)
                        DispatchQueue.main.async { self.completion(nil, target, nil) }
                    } catch { DispatchQueue.main.async { self.completion(nil, nil, error.localizedDescription) } }
                }
            } else {
                provider.loadObject(ofClass: UIImage.self) { image, error in DispatchQueue.main.async { self.completion(image as? UIImage, nil, error?.localizedDescription) } }
            }
        }
    }
}
