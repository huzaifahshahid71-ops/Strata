import Foundation

/// Attachment permits presentation; only successful script completion confirms JIT readiness.
struct StrataJITHandoff {
    let pid: Int32
    let token: String?
    private(set) var attached = false
    mutating func accept(_ record: [String: Any]) -> Bool {
        guard !attached, let token, UUID(uuidString: token) != nil,
              record["token"] as? String == token,
              (record["pid"] as? NSNumber)?.int32Value == pid,
              record["stage"] as? String == "attached" else { return false }
        attached = true
        return true
    }
}
