import Foundation
let token = UUID().uuidString
let pid: Int32 = 8123
func record(_ stage: String, token value: String = token, pid valuePID: Int32 = pid) -> [String: Any] {
    ["stage":stage, "token":value, "pid":NSNumber(value:valuePID)]
}
var state = StrataJITHandoff(pid: pid, token: token)
precondition(!state.accept(record("waiting")))
precondition(!state.accept(record("attached", token: UUID().uuidString)))
precondition(!state.accept(record("attached", pid: pid + 1)))
precondition(!state.accept(record("failed")))
precondition(!state.attached)
precondition(state.accept(record("attached")))
precondition(state.attached)
precondition(!state.accept(record("attached")), "Present once, even during repeated status polling")
var missing = StrataJITHandoff(pid: pid, token: nil)
precondition(!missing.accept(record("attached")))
var invalid = StrataJITHandoff(pid: pid, token: "not-a-uuid")
precondition(!invalid.accept(record("attached", token: "not-a-uuid")))
print("PASS: handoff requires matching launch token/PID and attached stage; stale, failed, missing and duplicate acknowledgements rejected.")
