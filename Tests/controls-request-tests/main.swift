import Foundation
let id = UUID().uuidString
let valid: [String: Any] = ["id":id, "pid":1234, "action":"close", "timestamp":1000.0]
precondition(StrataControlsRequest(valid, now:1001, previousID:"")?.pid == 1234)
precondition(StrataControlsRequest(valid, now:1010, previousID:"") == nil)
precondition(StrataControlsRequest(valid, now:1001, previousID:id) == nil)
for (key, value) in [("pid", -1 as Any), ("pid", Int64.max as Any), ("action", "launch-arbitrary" as Any), ("id", "bad" as Any)] {
    var invalid = valid; invalid[key] = value
    precondition(StrataControlsRequest(invalid, now:1001, previousID:"") == nil)
}
for action in ["library","minimize","close"] {
    var request = valid; request["action"] = action
    precondition(StrataControlsRequest(request, now:1001, previousID:"")?.action == action)
}
print("PASS: fresh explicit controls commands accepted; stale/duplicate/invalid PID and unknown commands rejected.")
