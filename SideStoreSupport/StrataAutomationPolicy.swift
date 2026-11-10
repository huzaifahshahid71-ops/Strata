import Foundation

enum StrataAutomationPolicy {
    static func due(enabled: Bool, days: Int, success: Date?, attempt: Date?, runningUntil: TimeInterval, now: Date) -> Bool {
        guard enabled, runningUntil < now.timeIntervalSince1970 else { return false }
        if let success, now.timeIntervalSince(success) < Double(max(1, min(5, days))) * 86_400 { return false }
        if let attempt, now.timeIntervalSince(attempt) < 3600 { return false }
        return true
    }
    static func mayDisconnect(jitProcessAlive: Bool, jitUntil: TimeInterval, refreshUntil: TimeInterval, now: Date) -> Bool {
        !jitProcessAlive && jitUntil < now.timeIntervalSince1970 && refreshUntil < now.timeIntervalSince1970
    }
}
