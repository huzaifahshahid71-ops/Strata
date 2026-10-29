import Foundation

/// Storage and resumable migration for user-visible, per-mode artwork.
struct LiveBoardArtworkFiles {
    let directory: URL
    let legacyDirectory: URL
    private let fm = FileManager.default

    func prepare() throws {
        for mode in ["Cinematic", "Big Picture"] {
            for kind in ["Covers", "Portraits", "Backgrounds"] {
                try fm.createDirectory(at: directory.appendingPathComponent(mode).appendingPathComponent(kind), withIntermediateDirectories: true)
            }
        }
        let help = "Imported artwork is stored here separately for Cinematic and Big Picture. Each interface has Covers, Portraits and Backgrounds. Artwork Index.json lists the app assignments managed by Strata. Keep filenames and folders unchanged to retain those assignments. Replacing an assigned image with the same filename is picked up when you return to Strata. New files must be assigned through the app's artwork picker."
        try help.write(to: directory.appendingPathComponent("About Artwork.txt"), atomically: true, encoding: .utf8)
    }
    func visibleURL(_ filename: String) -> URL? {
        let pieces = filename.split(separator: "/", omittingEmptySubsequences: false)
        guard !pieces.isEmpty, pieces.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") }) else { return nil }
        return directory.appendingPathComponent(filename)
    }
    func existingURL(_ filename: String) -> URL? {
        if let url = visibleURL(filename), fm.fileExists(atPath: url.path) { return url }
        guard !filename.contains("/"), !filename.contains("\\"), filename != ".", filename != ".." else { return nil }
        let old = legacyDirectory.appendingPathComponent(filename)
        return fm.fileExists(atPath: old.path) ? old : nil
    }
    static func folder(mode: String, kind: String) -> String? {
        guard ["cinematic", "bigPicture"].contains(mode), ["cover", "portrait", "background"].contains(kind) else { return nil }
        let interface = mode == "cinematic" ? "Cinematic" : "Big Picture"
        let type = kind == "cover" ? "Covers" : kind == "portrait" ? "Portraits" : "Backgrounds"
        return interface + "/" + type
    }
    static func filename(key: String) -> String {
        let clean = key.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" }
        return String(String(clean).prefix(72)) + "-" + UUID().uuidString + ".jpg"
    }
    func migrate(_ mappings: [String: String]) throws -> [String: String] {
        try prepare()
        var updated = mappings
        for (id, filename) in mappings {
            // Entries already migrated remain assigned even if the user removes a file in Files.
            guard !filename.contains("/"), let source = existingURL(filename) else { continue }
            let parts = id.split(separator: ":", maxSplits: 2).map(String.init)
            let modern = parts.count == 3 && ["cinematic", "bigPicture"].contains(parts[0])
            let mode = modern ? parts[0] : "bigPicture"
            let kind = modern ? parts[1] : parts.first ?? ""
            let key = modern ? parts[2] : String(id.dropFirst(kind.count + 1))
            guard let folder = Self.folder(mode: mode, kind: kind) else { continue }
            let relative = folder + "/" + Self.filename(key: key)
            guard let target = visibleURL(relative) else { continue }
            // Keep the private original as a recovery copy; commit a mapping only after copy succeeds.
            do { try fm.copyItem(at: source, to: target); updated[id] = relative }
            catch { continue } // A failed entry keeps its existing mapping and private source.
        }
        return updated
    }
}
