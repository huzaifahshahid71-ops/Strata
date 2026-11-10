import Foundation
import Darwin

/// Cross-process exclusion with the shared lock held by a running 3.0 guest.
/// Kernel releases the lock after a crash; there is no stale preference lease.
final class StrataGuestDataLease {
    private var descriptor: Int32 = -1
    init(container: String, groupRoot: URL) throws {
        guard !container.isEmpty, container == (container as NSString).lastPathComponent, container != ".", container != ".." else { throw StrataPortableBackup.failure("Invalid guest data container.") }
        let directory = groupRoot.appendingPathComponent("Library/StrataDataLocks")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(container + ".lock")
        descriptor = open(file.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw StrataPortableBackup.failure("Cannot open the guest data lock.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor); descriptor = -1
            throw StrataPortableBackup.failure("The guest or another data operation is using this container. Close it and retry.")
        }
    }
    func release() { if descriptor >= 0 { close(descriptor); descriptor = -1 } }
    deinit { release() }
}
