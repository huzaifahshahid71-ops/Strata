import Foundation
let now = Date(timeIntervalSince1970: 1_800_000_000)
for days in 1...5 {
 assert(StrataAutomationPolicy.due(enabled: true, days: days, success: now.addingTimeInterval(-Double(days) * 86400), attempt: nil, runningUntil: 0, now: now))
 assert(!StrataAutomationPolicy.due(enabled: true, days: days, success: now, attempt: nil, runningUntil: 0, now: now))
}
assert(!StrataAutomationPolicy.due(enabled: false, days: 1, success: nil, attempt: nil, runningUntil: 0, now: now))
assert(!StrataAutomationPolicy.due(enabled: true, days: 1, success: nil, attempt: now, runningUntil: 0, now: now))
assert(!StrataAutomationPolicy.due(enabled: true, days: 1, success: nil, attempt: nil, runningUntil: now.timeIntervalSince1970 + 5, now: now))
assert(StrataAutomationPolicy.mayDisconnect(jitProcessAlive: false, jitUntil: 0, refreshUntil: 0, now: now))
assert(!StrataAutomationPolicy.mayDisconnect(jitProcessAlive: true, jitUntil: 0, refreshUntil: 0, now: now))
assert(!StrataAutomationPolicy.mayDisconnect(jitProcessAlive: false, jitUntil: now.timeIntervalSince1970 + 5, refreshUntil: 0, now: now))
assert(!StrataAutomationPolicy.mayDisconnect(jitProcessAlive: false, jitUntil: 0, refreshUntil: now.timeIntervalSince1970 + 5, now: now))
print("Automation policy passed: 1–5 days, disabled/not due/retry/active refresh, cleanup guards including suspended live JIT owner")
