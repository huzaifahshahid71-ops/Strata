import Foundation

/// All views await the same scan. Cancelling a view's task does not abandon the shared operation.
@MainActor final class StrataStorageScanCoordinator<Value> {
    private struct Job { let key: String; let token: UUID; let task: Task<Value, Error> }
    private var active: Job?
    func run(key: String, operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        while let existing = active, existing.key != key {
            _ = try? await existing.task.value
            if active?.token == existing.token { active = nil }
        }
        let job: Job
        if let existing = active { job = existing }
        else {
            job = Job(key: key, token: UUID(), task: Task { try await operation() })
            active = job
        }
        defer { if active?.token == job.token { active = nil } }
        return try await job.task.value
    }
    func cancel() { active?.task.cancel() }
}
