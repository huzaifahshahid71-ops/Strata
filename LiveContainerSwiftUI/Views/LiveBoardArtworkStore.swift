import SwiftUI

/// User-owned artwork stays outside executable guest bundles.
final class LiveBoardArtworkStore: ObservableObject {
    enum Kind: String { case cover, portrait, background }
    @Published private(set) var revision = 0
    private let defaults = LCUtils.appGroupUserDefault
    private var cache: [String: UIImage] = [:]
    private var mappings: [String: String] { defaults.dictionary(forKey: "LiveBoardConsoleArtwork") as? [String: String] ?? [:] }
    private var files: LiveBoardArtworkFiles {
        LiveBoardArtworkFiles(
            directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Artwork", isDirectory: true),
            legacyDirectory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LiveBoard/Artwork", isDirectory: true))
    }
    init() { reloadFromDisk() }
    func reloadFromDisk() {
        if let migrated = try? files.migrate(mappings) {
            defaults.set(migrated, forKey: "LiveBoardConsoleArtwork")
        }
        writeIndex()
        cache.removeAll(); revision += 1
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
        if let cached = cache[id] { return cached }
        guard let filename = mappings[id] ?? (mode == "bigPicture" ? mappings[kind.rawValue + ":" + key] : nil), let url = files.existingURL(filename), let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache[id] = image; return image
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
        map[id] = filename; defaults.set(map, forKey: "LiveBoardConsoleArtwork")
        removeUnreferenced(previousFiles, mappings: map)
        writeIndex()
        cache[id] = resized; revision += 1
    }
    func remove(for key: String, kind: Kind, mode: String = "bigPicture") {
        let id = mode + ":" + kind.rawValue + ":" + key
        var map = mappings
        var removed = [map.removeValue(forKey: id)].compactMap { $0 }
        if mode == "bigPicture", let legacy = map.removeValue(forKey: kind.rawValue + ":" + key) { removed.append(legacy) }
        defaults.set(map, forKey: "LiveBoardConsoleArtwork")
        removeUnreferenced(removed, mappings: map)
        writeIndex()
        cache[id] = nil; revision += 1
    }
}
