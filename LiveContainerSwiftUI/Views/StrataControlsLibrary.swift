import UIKit

/// A presentation snapshot only. Every launch is resolved against the live registry
/// by LCAppListView, which runs the existing lock authentication and launch preflight.
enum StrataControlsLibrary {
    static var root: URL? {
        guard let group = LCSharedUtils.appGroupID() else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("Library/StrataControls")
    }
    @MainActor private static var cachedApps: [LCAppModel] = []
    @MainActor static func refreshRunning() { if !cachedApps.isEmpty { publish(cachedApps) } }
    @MainActor static func publish(_ apps: [LCAppModel]) {
        cachedApps = apps
        guard let root else { return }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let entries: [[String: String]] = apps.map { app in
                let running: Bool
                if #available(iOS 16.0, *), let folder = app.uiSelectedContainer?.folderName { running = MultitaskManager.isUsing(container: folder) || MultitaskDockManager.shared.apps.contains(where: { $0.appUUID == folder }) }
                else { running = false }
                var entry = ["key": liveBoardAppKey(app), "name": LiveBoardAppCustomization.shared.name(app), "running": running ? "1" : "0"]
                if let image = LiveBoardIconStore.image(app, dark: false) {
                    let format = UIGraphicsImageRendererFormat(); format.scale = 1
                    let small = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120), format: format).image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 120, height: 120)) }
                    entry["icon"] = small.pngData()?.base64EncodedString()
                }
                return entry
            }
            try JSONSerialization.data(withJSONObject: entries).write(to: root.appendingPathComponent("library.json"), options: .atomic)
        } catch { NSLog("Strata controls snapshot: %@", error.localizedDescription) }
    }
    struct Entry: Identifiable { let id: String; let name: String; let icon: UIImage? }
    static func entries() -> [Entry] {
        guard let url = root?.appendingPathComponent("library.json"), let data = try? Data(contentsOf: url), let values = try? JSONSerialization.jsonObject(with: data) as? [[String:String]] else { return [] }
        return values.compactMap { value in
            guard let key = value["key"], let name = value["name"] else { return nil }
            let icon = value["icon"].flatMap { Data(base64Encoded: $0) }.flatMap { UIImage(data: $0) }
            return Entry(id: key, name: name, icon: icon)
        }
    }
    static func select(_ key: String, close: Bool = false) {
        guard let url = root?.appendingPathComponent("switch.json"), let data = try? JSONSerialization.data(withJSONObject: ["key":key, "close":close, "timestamp":Date().timeIntervalSince1970]) else { return }
        do { try data.write(to: url, options: .atomic); NotificationCenter.default.post(name: Notification.Name("StrataLaunchFromControls"), object: nil) } catch { NSLog("Strata controls selection: %@", error.localizedDescription) }
    }
    static func takeRequest(validKeys: [String]) -> (key: String, close: Bool)? {
        guard let url = root?.appendingPathComponent("switch.json"), let data = try? Data(contentsOf: url) else { return nil }
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let time = value["timestamp"] as? Double, abs(Date().timeIntervalSince1970 - time) < 90,
              let key = value["key"] as? String else { try? FileManager.default.removeItem(at: url); return nil }
        // Registry loading may finish after the first onAppear; don't lose that selection.
        guard validKeys.contains(key) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return (key, value["close"] as? Bool ?? false)
    }
}
