import Foundation
import CryptoKit

/// Versioned streaming container archive. Only regular files/directories, never links.
/// It deliberately excludes Keychain and provisioning/certificate material outside guest data.
enum StrataPortableBackup {
    struct Entry: Codable { let path: String; let bytes: UInt64; let sha256: String; let directory: Bool }
    struct Manifest: Codable { let schema: Int; let bundleID: String; let created: Date; let entries: [Entry] }
    static let magic = Data("STRATABACKUP1\n".utf8)
    static let maximumManifest = 16 * 1024 * 1024
    static func failure(_ text: String) -> NSError { NSError(domain: "StrataBackup", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") &&
        path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    static func confined(_ url: URL, to root: URL) throws -> URL {
        let rawBase = root.standardizedFileURL
        guard try rawBase.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw failure("The guest root cannot be a symbolic link.") }
        let base = rawBase.resolvingSymlinksInPath()
        let rawTarget = url.standardizedFileURL
        let target: URL
        if rawTarget.path == rawBase.path { target = base }
        else if rawTarget.path.hasPrefix(rawBase.path + "/") { target = base.appendingPathComponent(String(rawTarget.path.dropFirst(rawBase.path.count + 1))) }
        else { target = rawTarget }
        guard target.path == base.path || target.path.hasPrefix(base.path + "/") else { throw failure("This path is outside the guest container.") }
        // Every ancestor must be a real directory, including the root.
        var check = target
        while true {
            let values = try check.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw failure("Symbolic links are not opened or backed up.") }
            if check == base { break }
            check.deleteLastPathComponent()
        }
        return target
    }
    static func hash(_ url: URL) throws -> String {
        let f = try FileHandle(forReadingFrom: url); defer { try? f.close() }
        var digest = SHA256()
        while let data = try f.read(upToCount: 1024 * 1024), !data.isEmpty { try Task.checkCancellation(); digest.update(data: data) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func create(root: URL, bundleID: String, destination: URL) throws {
        let root = try confined(root, to: root)
        let fm = FileManager.default
        var enumerationError: Error?
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [], errorHandler: { _, error in enumerationError = error; return false }) else { throw failure("Cannot enumerate the guest container.") }
        var entries: [Entry] = []
        var portableNames = Set<String>()
        for case let rawURL as URL in enumerator {
            let url = rawURL.standardizedFileURL
            try Task.checkCancellation()
            let value = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard value.isSymbolicLink != true else { throw failure("The container includes a symbolic link. Back up its source separately.") }
            let path = String(url.path.dropFirst(root.path.count + 1))
            guard safePath(path) else { throw failure("Invalid container path.") }
            guard portableNames.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw failure("This container has filenames that differ only by letter case or Unicode normalization. They cannot be stored in this portable backup format.") }
            if value.isDirectory == true { entries.append(Entry(path: path, bytes: 0, sha256: "", directory: true)) }
            else if value.isRegularFile == true {
                entries.append(Entry(path: path, bytes: UInt64(value.fileSize ?? 0), sha256: try hash(url), directory: false))
            } else { throw failure("Unsupported file type in guest container.") }
            guard entries.count <= 100_000 else { throw failure("This container has too many files for this backup format.") }
        }
        if let enumerationError { throw enumerationError }
        let manifest = try JSONEncoder().encode(Manifest(schema: 1, bundleID: bundleID, created: Date(), entries: entries))
        guard manifest.count <= maximumManifest else { throw failure("The backup manifest is too large.") }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial")
        defer { try? fm.removeItem(at: temporary) }
        guard fm.createFile(atPath: temporary.path, contents: nil) else { throw failure("Cannot create backup.") }
        let out = try FileHandle(forWritingTo: temporary); defer { try? out.close() }
        try out.write(contentsOf: magic)
        var size = UInt64(manifest.count).bigEndian
        try withUnsafeBytes(of: &size) { try out.write(contentsOf: $0) }
        try out.write(contentsOf: manifest)
        for entry in entries where !entry.directory {
            let url = try confined(root.appendingPathComponent(entry.path), to: root)
            let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
            var copied: UInt64 = 0; var digest = SHA256()
            while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty {
                try Task.checkCancellation(); copied += UInt64(data.count)
                guard copied <= entry.bytes else { throw failure("Guest data changed during backup. Close the guest and retry.") }
                digest.update(data: data); try out.write(contentsOf: data)
            }
            guard copied == entry.bytes, digest.finalize().map({ String(format: "%02x", $0) }).joined() == entry.sha256 else { throw failure("Guest data changed during backup. Close the guest and retry.") }
        }
        try out.synchronize(); try out.close()
        guard !fm.fileExists(atPath: destination.path) else { throw failure("A backup already exists at this destination.") }
        try fm.moveItem(at: temporary, to: destination)
    }
    static func readExactly(_ input: FileHandle, _ count: Int) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let data = try input.read(upToCount: count - result.count), !data.isEmpty else { throw failure("The backup is truncated.") }
            result.append(data)
        }
        return result
    }
    static func restore(archive: URL, root: URL, bundleID: String) throws {
        let fm = FileManager.default
        let root = try confined(root, to: root)
        let input = try FileHandle(forReadingFrom: archive); defer { try? input.close() }
        guard try readExactly(input, magic.count) == magic else { throw failure("This is not a Strata backup.") }
        let lengthData = try readExactly(input, 8)
        let count = lengthData.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard count > 0, count <= UInt64(maximumManifest) else { throw failure("Invalid backup manifest length.") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: readExactly(input, Int(count)))
        guard manifest.schema == 1, manifest.bundleID == bundleID, manifest.entries.count <= 100_000 else { throw failure("This backup belongs to another app or unsupported format.") }
        var names = Set<String>()
        for entry in manifest.entries {
            guard safePath(entry.path), names.insert(entry.path.precomposedStringWithCanonicalMapping.lowercased()).inserted, (!entry.directory || entry.bytes == 0), (entry.directory || entry.sha256.count == 64) else { throw failure("Invalid or duplicate backup entry.") }
        }
        var expected = UInt64(magic.count + 8) + count
        for entry in manifest.entries {
            let (sum, overflow) = expected.addingReportingOverflow(entry.bytes)
            guard !overflow else { throw failure("Invalid backup size.") }; expected = sum
        }
        let actual = try fm.attributesOfItem(atPath: archive.path)[.size] as? NSNumber
        guard actual?.uint64Value == expected else { throw failure("Backup length does not match its manifest.") }
        let stage = root.deletingLastPathComponent().appendingPathComponent(".strata-restore-\(UUID().uuidString)")
        let rollback = root.deletingLastPathComponent().appendingPathComponent(".strata-rollback-\(UUID().uuidString)")
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stage) }
        for entry in manifest.entries {
            try Task.checkCancellation()
            let target = stage.appendingPathComponent(entry.path)
            if entry.directory { try fm.createDirectory(at: target, withIntermediateDirectories: true); continue }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: target.path, contents: nil) else { throw failure("Cannot restore file.") }
            let output = try FileHandle(forWritingTo: target); defer { try? output.close() }
            var remaining = entry.bytes; var digest = SHA256()
            while remaining > 0 {
                try Task.checkCancellation()
                let data = try readExactly(input, Int(min(remaining, 1024 * 1024)))
                digest.update(data: data); try output.write(contentsOf: data); remaining -= UInt64(data.count)
            }
            guard digest.finalize().map({ String(format: "%02x", $0) }).joined() == entry.sha256 else { throw failure("A backup file failed its integrity check. Nothing was replaced.") }
        }
        guard (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw failure("The backup contains unexpected trailing data.") }
        // Keep this installation's container registration and Keychain mapping.
        let metadata = root.appendingPathComponent("LCContainerInfo.plist")
        if fm.fileExists(atPath: metadata.path) {
            let target = stage.appendingPathComponent(metadata.lastPathComponent)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: metadata, to: target)
        }
        try Task.checkCancellation()
        try fm.moveItem(at: root, to: rollback)
        do { try fm.moveItem(at: stage, to: root) }
        catch { try? fm.moveItem(at: rollback, to: root); throw error }
        // Retain the original alongside the restored container until explicitly removed in Files.
        // A recovery copy is preferable to deleting user data during the first 3.0 restore.
    }
}
