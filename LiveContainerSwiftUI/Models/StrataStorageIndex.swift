import Foundation

/// Thread-safe running count of filesystem items visited, for on-screen progress.
final class StrataStorageProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func set(_ count: Int) { lock.lock(); value = count; lock.unlock() }
    var scanned: Int { lock.lock(); defer { lock.unlock() }; return value }
}

/// One filesystem walk supplies all per-app and category subtree totals.
/// The walk is shared by every caller (Home tools tile, Storage screen) regardless of their app-list key,
/// is reused for a few minutes, and keeps totals for directories only, so memory stays proportional to
/// the number of folders rather than the number of files.
actor StrataStorageIndex {
    static let shared = StrataStorageIndex()
    nonisolated let progress = StrataStorageProgress()
    private var roots: [String] = []
    private(set) var skippedEntries = 0
    private var totals: [String: Int64] = [:]
    private var preparedAt: Date?
    private var running: (roots: [String], task: Task<([String: Int64], Int), Error>)?

    func prepare(_ urls: [URL], maxAge: TimeInterval = 300) async throws {
        let scanRoots = Self.collapse(urls)
        if let preparedAt, roots == scanRoots, Date().timeIntervalSince(preparedAt) < maxAge { return }
        let task: Task<([String: Int64], Int), Error>
        if let running, running.roots == scanRoots { task = running.task }
        else {
            running?.task.cancel()
            let progress = progress
            task = Task.detached(priority: .utility) { try Self.walk(scanRoots, progress: progress) }
            running = (scanRoots, task)
        }
        // Awaiting a Task's value does not cancel it when this caller goes away: the walk keeps going for the next caller.
        let values = try await task.value
        if running?.task == task { running = nil }
        roots = scanRoots; totals = values.0; skippedEntries = values.1; preparedAt = Date()
        try Task.checkCancellation()
    }

    func size(_ url: URL) -> Int64? {
        let path = url.standardizedFileURL.path
        guard roots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else { return nil }
        return totals[path] ?? 0
    }

    private static func collapse(_ urls: [URL]) -> [String] {
        let paths = Array(Set(urls.map { $0.standardizedFileURL.path })).sorted { $0.count < $1.count }
        var selected: [String] = []
        for path in paths where !selected.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { selected.append(path) }
        return selected.sorted()
    }

    /// Depth-first walk using the enumerator's level: a stack of open directories accumulates sizes and
    /// each directory's total is recorded when the walk leaves it. Symlinks are never followed.
    nonisolated static func walk(_ roots: [String], progress: StrataStorageProgress) throws -> ([String: Int64], Int) {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        let keySet = Set(keys)
        var totals: [String: Int64] = [:]
        var skipped = 0
        var count = 0
        for root in roots {
            try Task.checkCancellation()
            var stack: [(path: String, bytes: Int64)] = [(root, 0)]
            func close(to depth: Int) {
                while stack.count > max(depth, 0) {
                    let finished = stack.removeLast()
                    totals[finished.path, default: 0] += finished.bytes
                    if !stack.isEmpty { stack[stack.count - 1].bytes += finished.bytes }
                }
            }
            guard let iterator = manager.enumerator(at: URL(fileURLWithPath: root, isDirectory: true), includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in skipped += 1; return true }) else { continue }
            while let url = iterator.nextObject() as? URL {
                count += 1
                if count & 2047 == 0 { try Task.checkCancellation(); progress.set(count) }
                // An item at level L sits directly inside the L-th open directory.
                close(to: iterator.level)
                guard !stack.isEmpty else { break }
                guard let resource = try? url.resourceValues(forKeys: keySet) else { skipped += 1; continue }
                if resource.isSymbolicLink == true { continue }
                if resource.isDirectory == true {
                    stack.append((stack[stack.count - 1].path + "/" + url.lastPathComponent, 0))
                } else if resource.isRegularFile == true {
                    stack[stack.count - 1].bytes += Int64(resource.totalFileAllocatedSize ?? resource.fileAllocatedSize ?? resource.fileSize ?? 0)
                }
            }
            close(to: 0)
        }
        progress.set(count)
        return (totals, skipped)
    }
}
