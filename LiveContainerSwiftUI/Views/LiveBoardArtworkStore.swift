import SwiftUI
import ImageIO

/// User-owned artwork stays outside executable guest bundles.
@MainActor final class LiveBoardArtworkStore: ObservableObject {
    enum Kind: String { case cover, portrait, background }
    @Published private(set) var revision = 0
    private let defaults = LCUtils.appGroupUserDefault
    private let cache = NSCache<NSString, UIImage>()
    private var requests: [String: UUID] = [:]
    private var missing = Set<String>()
    private var mappingCache: [String: String]?

    private var mappings: [String: String] {
        if let mappingCache { return mappingCache }
        let value = defaults.dictionary(forKey: "LiveBoardConsoleArtwork") as? [String: String] ?? [:]
        mappingCache = value; return value
    }
    private var files: LiveBoardArtworkFiles {
        LiveBoardArtworkFiles(
            directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Artwork", isDirectory: true),
            legacyDirectory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LiveBoard/Artwork", isDirectory: true))
    }
    init() { cache.totalCostLimit = 64 * 1024 * 1024; reloadFromDisk() }
    func reloadFromDisk() {
        mappingCache = nil
        if let migrated = try? files.migrate(mappings) {
            defaults.set(migrated, forKey: "LiveBoardConsoleArtwork"); mappingCache = migrated
        }
        writeIndex()
        cache.removeAllObjects(); requests.removeAll(); missing.removeAll(); revision += 1
    }
    private func writeIndex() {
        guard let data = try? JSONSerialization.data(withJSONObject: mappings, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: files.directory.appendingPathComponent("Artwork Index.json"), options: .atomic)
    }
    private func removeUnreferenced(_ filenames: [String], mappings: [String: String]) {
        let retained = Set(mappings.values)
        for filename in Set(filenames) where !retained.contains(filename) {
            if let url = files.existingURL(filename) { try? FileManager.default.removeItem(at: url) }
        }
    }
    func image(for key: String, kind: Kind, mode: String = "bigPicture") -> UIImage? {
        let id = mode + ":" + kind.rawValue + ":" + key
        if let cached = cache.object(forKey: id as NSString) { return cached }
        guard !missing.contains(id), requests[id] == nil else { return nil }
        guard let filename = mappings[id] ?? (mode == "bigPicture" ? mappings[kind.rawValue + ":" + key] : nil), let url = files.existingURL(filename) else { missing.insert(id); return nil }
        let token = UUID(); requests[id] = token
        let maximum = kind == .background ? 1600 : 640
        Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: maximum] as CFDictionary) else { return nil }
                return UIImage(cgImage: cg)
            }.value
            guard let self, self.requests[id] == token else { return }
            self.requests[id] = nil
            if let image { self.cache.setObject(image, forKey: id as NSString, cost: Int(image.size.width * image.size.height * 4)) }
            else { self.missing.insert(id) }
            self.revision += 1
        }
        return nil
    }

    /// Cache-only lookup; never starts a decode. Used for same-frame fallbacks.
    func cachedImage(for key: String, kind: Kind, mode: String = "bigPicture") -> UIImage? {
        cache.object(forKey: (mode + ":" + kind.rawValue + ":" + key) as NSString)
    }
    /// True when user artwork is assigned (and not known to be unreadable), even if it is still decoding.
    /// Lets the backdrop keep the outgoing image instead of flashing the icon-derived fallback.
    func hasArtwork(for key: String, kind: Kind, mode: String = "bigPicture") -> Bool {
        let id = mode + ":" + kind.rawValue + ":" + key
        if cache.object(forKey: id as NSString) != nil { return true }
        guard !missing.contains(id) else { return false }
        return mappings[id] != nil || (mode == "bigPicture" && mappings[kind.rawValue + ":" + key] != nil)
    }
    /// Starts background decodes so neighbouring selections are ready before the user reaches them.
    func prefetch(_ keys: [String], kinds: [Kind], mode: String = "bigPicture") {
        for key in keys { for kind in kinds { _ = image(for: key, kind: kind, mode: mode) } }
    }

    func save(_ image: UIImage, for key: String, kind: Kind, mode: String = "bigPicture") throws {
        let factor = min(1, 2400 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = resized.jpegData(compressionQuality: 0.9) else { throw CocoaError(.fileWriteUnknown) }
        try files.prepare()
        let id = mode + ":" + kind.rawValue + ":" + key
        guard let folder = LiveBoardArtworkFiles.folder(mode: mode, kind: kind.rawValue) else { throw CocoaError(.fileWriteInvalidFileName) }
        let filename = folder + "/" + LiveBoardArtworkFiles.filename(key: key)
        guard let url = files.visibleURL(filename) else { throw CocoaError(.fileWriteInvalidFileName) }
        try data.write(to: url, options: .atomic)
        var map = mappings
        var previousFiles = [map[id]].compactMap { $0 }
        if mode == "bigPicture", let legacy = map.removeValue(forKey: kind.rawValue + ":" + key) { previousFiles.append(legacy) }
        map[id] = filename; mappingCache = map; defaults.set(map, forKey: "LiveBoardConsoleArtwork")
        removeUnreferenced(previousFiles, mappings: map)
        writeIndex()
        requests[id] = nil; missing.remove(id); cache.setObject(resized, forKey: id as NSString, cost: Int(resized.size.width * resized.size.height * 4)); revision += 1
    }
    func remove(for key: String, kind: Kind, mode: String = "bigPicture") {
        let id = mode + ":" + kind.rawValue + ":" + key
        var map = mappings
        var removed = [map.removeValue(forKey: id)].compactMap { $0 }
        if mode == "bigPicture", let legacy = map.removeValue(forKey: kind.rawValue + ":" + key) { removed.append(legacy) }
        mappingCache = map
        defaults.set(map, forKey: "LiveBoardConsoleArtwork")
        removeUnreferenced(removed, mappings: map)
        writeIndex()
        requests[id] = nil; missing.remove(id); cache.removeObject(forKey: id as NSString); revision += 1
    }
}
