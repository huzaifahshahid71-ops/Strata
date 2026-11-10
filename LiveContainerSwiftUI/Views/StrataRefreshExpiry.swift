import Foundation

enum StrataRefreshExpiry {
    static func decode(_ data: Data) -> Date? {
        guard data.count < 4_000_000,
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let dictionary = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil) as? [String: Any] else { return nil }
        return dictionary["ExpirationDate"] as? Date
    }
    static func installedExpiry() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"), let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }
    static func shouldRemind(now: Date, expiry: Date?, lastSuccess: Date?, intervalDays: Int) -> Bool {
        let interval = TimeInterval(max(1, min(5, intervalDays)) * 86400)
        if let expiry, expiry.timeIntervalSince(now) <= 48 * 3600 { return true }
        if let lastSuccess { return now.timeIntervalSince(lastSuccess) >= interval }
        // A new installation has no refresh history: use the profile's expiry instead of guessing.
        return expiry == nil
    }
}
