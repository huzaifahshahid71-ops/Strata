import SwiftUI

final class StrataPhoneAppInfo: LCAppInfo {
    let entryID: UUID
    let phoneBundleIdentifier: String?
    let phoneName: String
    init(entry: StrataPhoneAppEntry, path: String) {
        entryID = entry.id
        phoneBundleIdentifier = entry.bundleIdentifier
        phoneName = entry.name
        super.init(bundlePath: path)
    }
    override func iconIsDarkIcon(_ isDarkIcon: Bool) -> UIImage! {
        if let custom = UIImage(contentsOfFile: URL(fileURLWithPath: bundlePath()).appendingPathComponent("Icon.png").path) { return custom }
        return StrataPhoneApps.icon(for: phoneBundleIdentifier, name: phoneName)
    }
}

@MainActor final class StrataPhoneApps: ObservableObject {
    static let shared = StrataPhoneApps()
    @Published private(set) var revision = 0
    @Published private(set) var entries: [StrataPhoneAppEntry] = []
    @Published private(set) var models: [LCAppModel] = []
    private let defaults = LCUtils.appGroupUserDefault
    private let root = LCPath.docPath.appendingPathComponent("Strata3/LauncherEntries", isDirectory: true)
    private init() {
        if let data = defaults.data(forKey: "StrataPhoneApps"), let saved = try? JSONDecoder().decode([StrataPhoneAppEntry].self, from: data) {
            entries = saved
        }
        rebuild()
    }
    static func launchURL(_ entry: StrataPhoneAppEntry) -> URL? { StrataPhoneAppPolicy.launchURL(entry) }

    // MARK: Icons and app links from the paired-Mac export
    nonisolated(unsafe) private static let iconCache = NSCache<NSString, UIImage>()  // NSCache is thread-safe
    private static var catalogCache: (date: Date, schemes: [String: [String]])?
    nonisolated static var iconDirectory: URL { LCPath.docPath.appendingPathComponent("Strata3/PhoneAppIcons", isDirectory: true) }
    private static var catalogURL: URL { LCPath.docPath.appendingPathComponent("Strata3/PhoneAppsCatalog.json") }

    /// Real app icon when available (exported from a paired Mac, or provided by iOS), else a readable letter tile.
    nonisolated static func icon(for bundleIdentifier: String?, name: String) -> UIImage {
        let key = ((bundleIdentifier ?? "") + "|" + name) as NSString
        if let cached = iconCache.object(forKey: key) { return cached }
        var image: UIImage?
        if let id = bundleIdentifier, StrataPhoneAppPolicy.validBundleIdentifier(id) {
            image = UIImage(contentsOfFile: iconDirectory.appendingPathComponent(id + ".png").path)
            if image == nil { image = LCUtils.strataPhoneApplicationIcon(id) }
        }
        let result = image ?? letterTile(name.isEmpty ? (bundleIdentifier ?? "?") : name)
        iconCache.setObject(result, forKey: key)
        return result
    }
    static func invalidateIcons() { iconCache.removeAllObjects(); catalogCache = nil }
    nonisolated private static func letterTile(_ name: String) -> UIImage {
        let hue = CGFloat(abs(name.hashValue % 360)) / 360
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 180, height: 180), format: format).image { context in
            let colors = [UIColor(hue: hue, saturation: 0.55, brightness: 0.85, alpha: 1).cgColor, UIColor(hue: hue, saturation: 0.7, brightness: 0.55, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 180), options: [])
            }
            let letter = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased() as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 92, weight: .semibold), .foregroundColor: UIColor.white]
            let size = letter.size(withAttributes: attributes)
            letter.draw(at: CGPoint(x: (180 - size.width) / 2, y: (180 - size.height) / 2), withAttributes: attributes)
        }
    }
    static func schemes(for bundleIdentifier: String) -> [String] {
        let date = (try? catalogURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        if catalogCache?.date != date {
            let apps = (try? Data(contentsOf: catalogURL)).flatMap { try? JSONDecoder().decode([StrataInstalledPhoneApp].self, from: $0) } ?? []
            catalogCache = (date, Dictionary(apps.map { ($0.id, StrataPhoneAppPolicy.validSchemes($0.schemes ?? [])) }, uniquingKeysWith: { first, _ in first }))
        }
        return catalogCache?.schemes[bundleIdentifier] ?? []
    }
    func save(_ entry: StrataPhoneAppEntry, image: UIImage?) throws {
        guard !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, (entry.bundleIdentifier.map(StrataPhoneAppPolicy.validBundleIdentifier) ?? (Self.launchURL(entry) != nil)) else { throw "Enter a name and valid app URL or Shortcut name." }
        if let identifier = entry.bundleIdentifier, entries.contains(where: { $0.bundleIdentifier == identifier && $0.id != entry.id }) { return }
        let folder = root.appendingPathComponent(entry.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let image {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let icon = UIGraphicsImageRenderer(size: CGSize(width: 180, height: 180), format: format).image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 180, height: 180)) }
            try icon.pngData()?.write(to: folder.appendingPathComponent("Icon.png"), options: .atomic)
        }
        var next = entries
        if let index = next.firstIndex(where: { $0.id == entry.id }) { next[index] = entry } else { next.append(entry) }
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: "StrataPhoneApps"); entries = next; rebuild()
    }
    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        defaults.set(try? JSONEncoder().encode(entries), forKey: "StrataPhoneApps")
        models.removeAll { ($0.appInfo as? StrataPhoneAppInfo)?.entryID == id }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(id.uuidString))
    }
    func reloadIcons() { Self.invalidateIcons(); rebuild() }
    private func rebuild() {
        LiveBoardIconStore.invalidate(); revision += 1
        models = entries.compactMap { entry in
            let folder = root.appendingPathComponent(entry.id.uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let info: [String: Any] = ["CFBundleIdentifier": "com.strata.phone." + entry.id.uuidString, "CFBundleDisplayName": entry.name, "CFBundleName": entry.name, "CFBundleShortVersionString": "Shortcut", "CFBundleExecutable": "ExternalApp"]
                try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: folder.appendingPathComponent("Info.plist"), options: .atomic)
                return LCAppModel(appInfo: StrataPhoneAppInfo(entry: entry, path: folder.path))
            } catch { return nil }
        }
    }
    func open(_ id: UUID) async throws {
        guard let entry = entries.first(where: { $0.id == id }) else { throw "This iPhone app entry is no longer available." }
        if let bundleID = entry.bundleIdentifier {
            guard StrataPhoneAppPolicy.validBundleIdentifier(bundleID) else { throw "Invalid iPhone app selection." }
            let error: String? = await withCheckedContinuation { continuation in
                LCUtils.strataOpenPhoneApplication(bundleID) { continuation.resume(returning: $0) }
            }
            guard let error else { return }
            // Free-signed builds are usually refused direct opening (LaunchServices error 115).
            // Fall back to the app's own registered link, which is public API.
            let schemes = Self.schemes(for: bundleID)
            for scheme in schemes {
                if let url = URL(string: scheme + "://"), await UIApplication.shared.open(url) { return }
            }
            NSLog("[Strata] direct open of %@ refused: %@", bundleID, error)
            throw schemes.isEmpty
                ? "iOS doesn’t let Strata open this app directly, and no app link is known for it. Re-export the app list from your Mac (it now includes app links and icons), or set an App URL or Shortcut for it under Settings → iPhone Apps → Advanced."
                : "iOS doesn’t let Strata open this app directly, and its app link didn’t respond. Set an App URL or Shortcut for it under Settings → iPhone Apps → Advanced."

        }
        guard let url = Self.launchURL(entry) else { throw "Invalid app URL or Shortcut name." }
        let opened = await UIApplication.shared.open(url)
        if !opened { throw "iOS could not open this app. Check its URL, or create a Shortcut with Open App and use that Shortcut's name." }
    }
}

struct StrataPhoneAppsView: View {
    @ObservedObject private var store = StrataPhoneApps.shared
    @State private var adding = false
    @State private var browsing = false
    @State private var addedQuery = ""
    private var visibleEntries: [StrataPhoneAppEntry] { store.entries.filter { addedQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(addedQuery) } }
    var body: some View {
        List {
            Section {
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Added app name", text: $addedQuery).autocapitalization(.none).disableAutocorrection(true).submitLabel(.search) }
            }
            if addedQuery.isEmpty { Section {
                Text("Choose the iPhone apps you want in Strata. They open normally in iOS; guest JIT, RAM and multitasking options do not apply.").font(.footnote)
                Button { browsing = true } label: { Label("Choose installed apps", systemImage: "plus.circle.fill") }
                Button("Advanced: App URL or Shortcut") { adding = true }
            }
            }
            Section("Added apps") {
                ForEach(visibleEntries) { entry in
                    NavigationLink { StrataPhoneAppEditor(entry: entry) } label: {
                        VStack(alignment: .leading) { Text(entry.name); Text(entry.bundleIdentifier != nil ? "iPhone app" : entry.shortcut ? "Shortcut · \(entry.target)" : entry.target).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }.onDelete { offsets in let ids = offsets.map { visibleEntries[$0].id }; ids.forEach(store.remove) }
            }
            Section { Text("Only apps you select are added. Removing an entry never uninstalls the iPhone app. Advanced URL and Shortcut entries remain available for apps that cannot open directly.").font(.footnote) }
        }.navigationTitle("iPhone Apps")
        .onAppear { store.reloadIcons() }

        .onSubmit { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        .sheet(isPresented: $browsing) { NavigationView { StrataInstalledAppPicker() } }
        .sheet(isPresented: $adding) { NavigationView { StrataPhoneAppEditor(entry: .init(name: "", target: "", shortcut: true)) } }
    }
}

private struct StrataPhoneAppEditor: View {
    @State var entry: StrataPhoneAppEntry
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var choosingImage = false
    @State private var error: String?
    var body: some View {
        Form {
            Section("Launcher entry") {
                TextField("App name", text: $entry.name)
                if entry.bundleIdentifier == nil {
                Picker("Open using", selection: $entry.shortcut) { Text("Shortcut").tag(true); Text("App URL").tag(false) }
                TextField(entry.shortcut ? "Exact Shortcut name" : "App URL, e.g. music://", text: $entry.target).autocapitalization(.none).disableAutocorrection(true)
                } else { Text("Opens the selected app directly in iOS.").font(.footnote).foregroundStyle(.secondary) }
                Button("Choose icon from Photos") { choosingImage = true }
                if let image { Image(uiImage: image).resizable().scaledToFit().frame(height: 80) }
                Button("Save") {
                    do { try StrataPhoneApps.shared.save(entry, image: image); dismiss() } catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("phoneApp.save")
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle(entry.name.isEmpty ? "Add iPhone App" : entry.name)
        .sheet(isPresented: $choosingImage) { LiveBoardWallpaperPicker { image in self.image = image; choosingImage = false } }
    }
}
