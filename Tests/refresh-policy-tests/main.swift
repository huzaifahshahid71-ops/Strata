import Foundation
let now = Date(timeIntervalSince1970: 1_800_000_000)
assert(StrataRefreshPolicy.intervalDays(0) == 1)
assert(StrataRefreshPolicy.intervalDays(8) == 5)
for days in 1...5 {
 let due = now.addingTimeInterval(Double(days) * 86_400)
 assert(StrataRefreshPolicy.due(lastSuccess: now, days: days) == due)
 assert(!StrataRefreshPolicy.shouldAttempt(now: due.addingTimeInterval(-1), lastSuccess: now, lastAttempt: nil, days: days))
 assert(StrataRefreshPolicy.shouldAttempt(now: due, lastSuccess: now, lastAttempt: nil, days: days))
 assert(!StrataRefreshPolicy.shouldAttempt(now: due, lastSuccess: now, lastAttempt: due.addingTimeInterval(-3599), days: days))
 assert(StrataRefreshPolicy.shouldAttempt(now: due, lastSuccess: now, lastAttempt: due.addingTimeInterval(-3600), days: days))
}
assert(StrataRefreshPolicy.shouldAttempt(now: now, lastSuccess: nil, lastAttempt: nil, days: 3))
assert(StrataRefreshPolicy.requestedDate(now: now, lastSuccess: nil, lastAttempt: now, days: 3) == now.addingTimeInterval(3600))
assert(StrataRefreshPolicy.requestedDate(now: now, lastSuccess: now, lastAttempt: nil, days: 5) == now.addingTimeInterval(5 * 86_400))
print("Refresh policy: intervals 1–5, due boundaries, retry throttling and first run passed")
