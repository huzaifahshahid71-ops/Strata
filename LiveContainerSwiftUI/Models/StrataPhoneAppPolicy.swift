import Foundation

struct StrataPhoneAppEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var target: String
    var shortcut: Bool
    var bundleIdentifier: String? = nil
}

enum StrataPhoneAppPolicy {
    static func validBundleIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 255 && value.contains(".") && value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0) }
    }
    /// Keeps plausible custom URL schemes only; never web, file or Strata's own schemes.
    static func validSchemes(_ values: [String]) -> [String] {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-.")
        let blocked: Set<String> = ["http", "https", "file", "data", "javascript", "livecontainer", "itms-services", "sidestore", "mailto", "tel", "sms"]
        var seen = Set<String>()
        return values.filter { value in
            let lower = value.lowercased()
            return !value.isEmpty && value.count <= 64 && value.unicodeScalars.first.map(CharacterSet.letters.contains) == true
                && value.unicodeScalars.allSatisfy(allowed.contains) && !blocked.contains(lower) && !lower.hasPrefix("livecontainer") && seen.insert(lower).inserted
        }.prefix(12).map { $0 }
    }
    static func launchURL(_ entry: StrataPhoneAppEntry) -> URL? {
        guard entry.bundleIdentifier == nil else { return nil }
        let target = entry.target.trimmingCharacters(in: .whitespacesAndNewlines)
        if entry.shortcut {
            guard !target.isEmpty else { return nil }
            var url = URLComponents(); url.scheme = "shortcuts"; url.host = "run-shortcut"
            url.queryItems = [URLQueryItem(name: "name", value: target)]
            return url.url
        }
        guard let url = URL(string: target), let scheme = url.scheme?.lowercased(),
              !["file", "data", "javascript", "livecontainer", "itms-services"].contains(scheme) else { return nil }
        return url
    }
}
