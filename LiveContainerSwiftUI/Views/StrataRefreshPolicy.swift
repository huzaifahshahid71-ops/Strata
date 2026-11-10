import Foundation

enum StrataRefreshPolicy {
    static let retryInterval: TimeInterval = 3_600
    static func intervalDays(_ value: Int) -> Int { max(1, min(5, value)) }
    static func due(lastSuccess: Date?, days: Int) -> Date {
        lastSuccess?.addingTimeInterval(Double(intervalDays(days)) * 86_400) ?? .distantPast
    }
    static func shouldAttempt(now: Date, lastSuccess: Date?, lastAttempt: Date?, days: Int) -> Bool {
        now >= due(lastSuccess: lastSuccess, days: days) && (lastAttempt.map { now.timeIntervalSince($0) >= retryInterval } ?? true)
    }
    static func requestedDate(now: Date, lastSuccess: Date?, lastAttempt: Date?, days: Int) -> Date {
        max(due(lastSuccess: lastSuccess, days: days), (lastAttempt ?? .distantPast).addingTimeInterval(retryInterval), now.addingTimeInterval(60))
    }
}
