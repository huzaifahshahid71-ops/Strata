import Foundation
struct StrataControlsRequest {
    let id: String
    let pid: Int32
    let action: String
    init?(_ object: [String: Any], now: TimeInterval, previousID: String) {
        guard let id = object["id"] as? String, UUID(uuidString: id) != nil, id != previousID,
              let timestamp = object["timestamp"] as? Double, abs(now - timestamp) < 5,
              let rawPID = object["pid"] as? Int, let pid = Int32(exactly: rawPID), pid > 0,
              let action = object["action"] as? String, ["close", "minimize", "library"].contains(action) else { return nil }
        self.id = id; self.pid = pid; self.action = action
    }
}
