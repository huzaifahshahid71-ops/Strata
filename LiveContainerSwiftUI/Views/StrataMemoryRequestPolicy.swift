import Foundation

enum StrataMemoryRequestPolicy {
    /// Only the two bundle IDs read from this installed app may be changed.
    static func matchingTargets(registered: [String], allowed: Set<String>) -> Set<String>? {
        guard allowed.count == 2, !allowed.contains("") else { return nil }
        let found = Set(registered).intersection(allowed)
        return found == allowed ? found : nil
    }
    /// Strip only the verified team prefix, never arbitrary dot-separated components.
    static func bundleIdentity(signedID: String, team: String, fallback: String) -> String {
        let prefix = team + "."
        guard !team.isEmpty, signedID.hasPrefix(prefix) else { return fallback }
        let identity = String(signedID.dropFirst(prefix.count))
        return identity.isEmpty ? fallback : identity
    }
    /// Selections must be explicit registrations returned by the authenticated team's API.
    /// A shared wildcard registration can legitimately cover both executables.
    static func selectedTargets(host: String, guest: String, registered: Set<String>) -> Set<String>? {
        guard !host.isEmpty, !guest.isEmpty, registered.contains(host), registered.contains(guest) else { return nil }
        return [host, guest]
    }
    static let capabilities = ["INCREASED_MEMORY_LIMIT"]
}
