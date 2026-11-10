import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct LiveBoardModeLibrary: Codable, Equatable {
    var categories = ["Games", "Ports", "Tools"]
    var assignments: [String: String] = [:]
    var hidden: Set<String> = []
    mutating func addCategory(_ value: String) -> Bool {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 30,
              !(["Library", "Favorites", "All"] + categories).contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return false }
        categories.append(name); return true
    }
    mutating func removeCategory(_ name: String) {
        categories.removeAll { $0 == name }; assignments = assignments.filter { $0.value != name }
    }
}

@MainActor enum LiveBoardLibraryCache {
    private static var encoded = ""
    private static var value: [String: LiveBoardModeLibrary] = [:]
    static func decode(_ text: String) -> [String: LiveBoardModeLibrary] {
        if text != encoded {
            value = (try? JSONDecoder().decode([String: LiveBoardModeLibrary].self, from: Data(text.utf8))) ?? [:]
            encoded = text
        }
        return value
    }
}

/// Optional universal categories: one category list and app assignments shared by Cinematic, Big Picture,
/// Switchboard and iOS Home. Hidden apps stay per mode. Seeded from the existing per-mode setups.
@MainActor enum LiveBoardSharedCategories {
    static let enabledKey = "StrataUniversalCategories"
    static let sharedKey = "_universal"
    private static var defaults: UserDefaults { LCUtils.appGroupUserDefault }
    static var enabled: Bool { defaults.object(forKey: enabledKey) as? Bool ?? true }

    static func library(_ all: [String: LiveBoardModeLibrary], mode: String) -> LiveBoardModeLibrary {
        var state = all[mode] ?? .init()
        guard enabled else { return state }
        let shared = all[sharedKey] ?? seed(all)
        state.categories = shared.categories; state.assignments = shared.assignments
        // Hidden apps follow the shared library too: hidden in one interface means hidden in all of them.
        state.hidden = all.values.reduce(into: shared.hidden) { $0.formUnion($1.hidden) }
        return state
    }
    static func store(_ state: LiveBoardModeLibrary, mode: String, into all: inout [String: LiveBoardModeLibrary]) {
        guard enabled else { all[mode] = state; return }
        var shared = all[sharedKey] ?? seed(all)
        shared.categories = state.categories; shared.assignments = state.assignments; shared.hidden = state.hidden
        all[sharedKey] = shared
        for name in Array(all.keys) where name != sharedKey { all[name]?.hidden = [] }
        mirrorToHome(shared)
    }
    /// Union of every mode's categories; assignments prefer Cinematic, then Big Picture, Switchboard, iOS Home.
    static func seed(_ all: [String: LiveBoardModeLibrary]) -> LiveBoardModeLibrary {
        var result = LiveBoardModeLibrary(); result.categories = []; result.assignments = [:]
        let home = homeLibrary()
        for state in ["cinematic", "bigPicture", "switchboard"].compactMap({ all[$0] }) + [home] {
            for name in state.categories where !result.categories.contains(name) { result.categories.append(name) }
            for (key, value) in state.assignments where result.assignments[key] == nil { result.assignments[key] = value }
        }
        if result.categories.isEmpty { result.categories = LiveBoardModeLibrary().categories }
        return result
    }
    /// Category for automatic Game Mode and other mode-independent decisions.
    static func category(forKey key: String) -> String? {
        let all = LiveBoardLibraryCache.decode(defaults.string(forKey: "LiveBoardModeLibraries") ?? "{}")
        if enabled { return library(all, mode: "cinematic").assignments[key] }
        for mode in ["cinematic", "bigPicture", "switchboard"] { if let value = all[mode]?.assignments[key] { return value } }
        return homeLibrary().assignments[key]
    }
    static func setEnabled(_ value: Bool) {
        if value {
            var all = LiveBoardLibraryCache.decode(defaults.string(forKey: "LiveBoardModeLibraries") ?? "{}")
            if all[sharedKey] == nil { all[sharedKey] = seed(all) }
            if let data = try? JSONEncoder().encode(all), let text = String(data: data, encoding: .utf8) { defaults.set(text, forKey: "LiveBoardModeLibraries") }
            if let shared = all[sharedKey] { mirrorToHome(shared) }
        }
        defaults.set(value, forKey: enabledKey)
    }
    /// iOS Home keeps its own keys; keep them equal to the shared library while universal is on.
    static func homeLibrary() -> LiveBoardModeLibrary {
        var state = LiveBoardModeLibrary()
        if let data = defaults.string(forKey: "LiveBoardHomeCategories")?.data(using: .utf8), let list = try? JSONDecoder().decode([String].self, from: data) { state.categories = list }
        if let data = defaults.string(forKey: "LiveBoardCategories")?.data(using: .utf8), let map = try? JSONDecoder().decode([String: String].self, from: data) { state.assignments = map }
        return state
    }
    static func mirrorToHome(_ shared: LiveBoardModeLibrary) {
        if let data = try? JSONEncoder().encode(shared.categories), let text = String(data: data, encoding: .utf8), defaults.string(forKey: "LiveBoardHomeCategories") != text { defaults.set(text, forKey: "LiveBoardHomeCategories") }
        if let data = try? JSONEncoder().encode(shared.assignments), let text = String(data: data, encoding: .utf8), defaults.string(forKey: "LiveBoardCategories") != text { defaults.set(text, forKey: "LiveBoardCategories") }
    }
    /// Called when iOS Home edits its own keys.
    static func importFromHome() {
        guard enabled else { return }
        var all = LiveBoardLibraryCache.decode(defaults.string(forKey: "LiveBoardModeLibraries") ?? "{}")
        let home = homeLibrary()
        var shared = all[sharedKey] ?? seed(all)
        guard shared.categories != home.categories || shared.assignments != home.assignments else { return }
        shared.categories = home.categories; shared.assignments = home.assignments; all[sharedKey] = shared
        if let data = try? JSONEncoder().encode(all), let text = String(data: data, encoding: .utf8) { defaults.set(text, forKey: "LiveBoardModeLibraries") }
    }
}

/// One custom app order shared by every launcher mode, including added iPhone apps.
@MainActor enum StrataLauncherOrder {
    static let key = "StrataLauncherOrder"
    static func keys(_ text: String) -> [String] { (try? JSONDecoder().decode([String].self, from: Data(text.utf8))) ?? [] }
    static func apply(_ apps: [LCAppModel], order text: String) -> [LCAppModel] {
        let order = keys(text)
        guard !order.isEmpty else { return apps }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return apps.enumerated().sorted { lhs, rhs in
            let l = rank[liveBoardAppKey(lhs.element)] ?? Int.max, r = rank[liveBoardAppKey(rhs.element)] ?? Int.max
            return l != r ? l < r : lhs.offset < rhs.offset
        }.map(\.element)
    }
    /// Swaps an app with its neighbour in the list the user sees; the full order is preserved around it.
    static func move(_ app: LCAppModel, by offset: Int, visible: [LCAppModel], all: [LCAppModel]) {
        let defaults = LCUtils.appGroupUserDefault
        let current = apply(all, order: defaults.string(forKey: key) ?? "[]").map(liveBoardAppKey)
        let shown = visible.map(liveBoardAppKey)
        let appKey = liveBoardAppKey(app)
        guard let index = shown.firstIndex(of: appKey) else { return }
        let target = offset == Int.min ? 0 : offset == Int.max ? shown.count - 1 : index + offset
        guard shown.indices.contains(target), target != index else { return }
        var order = current
        guard let from = order.firstIndex(of: appKey), let to = order.firstIndex(of: shown[target]) else { return }
        order.remove(at: from)
        order.insert(appKey, at: to)
        if let data = try? JSONEncoder().encode(order), let text = String(data: data, encoding: .utf8) { defaults.set(text, forKey: key) }
    }
    /// Places `appKey` directly before (or after) `target` in the shared order. Used by drag and drop and "Place after".
    static func place(_ appKey: String, relativeTo target: String, after: Bool, all: [LCAppModel]) {
        guard appKey != target else { return }
        let defaults = LCUtils.appGroupUserDefault
        var order = apply(all, order: defaults.string(forKey: key) ?? "[]").map(liveBoardAppKey)
        guard let from = order.firstIndex(of: appKey), order.contains(target) else { return }
        order.remove(at: from)
        guard let to = order.firstIndex(of: target) else { return }
        order.insert(appKey, at: after ? to + 1 : to)
        if let data = try? JSONEncoder().encode(order), let text = String(data: data, encoding: .utf8) { defaults.set(text, forKey: key) }
    }
}

extension LiveBoardModeLibrary {
    /// Categories that still contain at least one app shown in this interface.
    func visibleCategories(_ apps: [LCAppModel]) -> [String] {
        let used = Set(apps.compactMap { app -> String? in
            let key = liveBoardAppKey(app)
            return hidden.contains(key) ? nil : assignments[key]
        })
        return categories.filter(used.contains)
    }
}

/// Category and Move dropdowns shared by every interface's long-press menu.
struct StrataArrangeMenus: View {
    let app: LCAppModel
    let visible: [LCAppModel]
    let all: [LCAppModel]
    let categories: [String]
    let current: String?
    let assign: (String?) -> Void
    var body: some View {
        Menu {
            Button { assign(nil) } label: { if current == nil { Label("None", systemImage: "checkmark") } else { Text("None") } }
            ForEach(categories, id: \.self) { value in
                Button { assign(value) } label: { if current == value { Label(value, systemImage: "checkmark") } else { Text(value) } }
            }
        } label: { Label("Category", systemImage: "tag") }
        Menu {
            Button("To Start", systemImage: "arrow.left.to.line") { StrataLauncherOrder.move(app, by: Int.min, visible: visible, all: all) }
            Button("Left", systemImage: "arrow.left") { StrataLauncherOrder.move(app, by: -1, visible: visible, all: all) }
            Button("Right", systemImage: "arrow.right") { StrataLauncherOrder.move(app, by: 1, visible: visible, all: all) }
            Button("To End", systemImage: "arrow.right.to.line") { StrataLauncherOrder.move(app, by: Int.max, visible: visible, all: all) }
            Menu("Place After") {
                ForEach(visible.filter { $0 != app }.prefix(60), id: \.self) { other in
                    Button(LiveBoardAppCustomization.shared.name(other)) { StrataLauncherOrder.place(liveBoardAppKey(app), relativeTo: liveBoardAppKey(other), after: true, all: all) }
                }
            }
        } label: { Label("Move", systemImage: "arrow.left.arrow.right") }
    }
}

/// Drag a tile onto another to place it there in the shared order.
struct StrataReorderDropDelegate: DropDelegate {
    let targetKey: String
    let all: [LCAppModel]
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [UTType.plainText]) }
    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.plainText]).first else { return false }
        let target = targetKey, apps = all
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let key = object as? String else { return }
            DispatchQueue.main.async { StrataLauncherOrder.place(key, relativeTo: target, after: false, all: apps) }
        }
        return true
    }
}

extension View {
    /// Long-press-and-drag reordering for launcher tiles.
    func strataReorderable(_ key: String, all: [LCAppModel]) -> some View {
        onDrag { NSItemProvider(object: key as NSString) }
            .onDrop(of: [UTType.plainText], delegate: StrataReorderDropDelegate(targetKey: key, all: all))
    }
}

/// Two colours sampled from an app's artwork or icon, for backgrounds that follow the selected game.
@MainActor enum StrataGameColors {
    private static let cache = NSCache<NSString, NSArray>()
    static func colors(for key: String, image: UIImage?) -> [Color] {
        let fallback = [Color(white: 0.16), Color(white: 0.06)]
        guard let image else { return fallback }
        let cacheKey = (key + ":" + String(ObjectIdentifier(image).hashValue)) as NSString
        if let cached = cache.object(forKey: cacheKey) as? [UIColor] { return cached.map { Color($0) } }
        guard let sampled = sample(image) else { return fallback }
        cache.setObject(sampled as NSArray, forKey: cacheKey)
        return sampled.map { Color($0) }
    }
    /// Artwork first (background, poster, then cover from any interface); `pending` while assigned artwork
    /// is still decoding so callers keep their current colours instead of flashing the icon's.
    static func artworkSource(_ store: LiveBoardArtworkStore, key: String) -> (image: UIImage?, pending: Bool) {
        let sources: [(LiveBoardArtworkStore.Kind, [String])] = [(.background, ["cinematic", "bigPicture"]), (.portrait, ["bigPicture"]), (.cover, ["switchboard", "bigPicture", "cinematic"])]
        for (kind, modes) in sources { for mode in modes { if let image = store.image(for: key, kind: kind, mode: mode) { return (image, false) } } }
        for (kind, modes) in sources where modes.contains(where: { store.hasArtwork(for: key, kind: kind, mode: $0) }) { _ = kind; return (nil, true) }
        return (nil, false)
    }
    /// Colours for an app: from its artwork, or its icon only when it has no artwork. nil while artwork loads.
    static func gradient(_ store: LiveBoardArtworkStore, app: LCAppModel) -> [Color]? {
        let key = liveBoardAppKey(app)
        let source = artworkSource(store, key: key)
        if source.pending { return nil }
        return colors(for: key, image: source.image ?? LiveBoardIconStore.image(app, dark: false))
    }
    /// Averages the most saturated pixels of a 24×24 thumbnail; returns a vivid and a deep tone.
    private static func sample(_ image: UIImage) -> [UIColor]? {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let cg = image.cgImage, let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        var samples: [(h: CGFloat, s: CGFloat, b: CGFloat)] = []
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 3] > 200 {
            let color = UIColor(red: CGFloat(pixels[index]) / 255, green: CGFloat(pixels[index + 1]) / 255, blue: CGFloat(pixels[index + 2]) / 255, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            samples.append((h, s, b))
        }
        guard !samples.isEmpty else { return nil }
        let vivid = samples.sorted { $0.s * $0.b > $1.s * $1.b }.prefix(max(1, samples.count / 5))
        // Average hue on the colour wheel so reds near 0/1 don't average to cyan.
        var x: CGFloat = 0, y: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0
        for item in vivid { x += cos(item.h * 2 * .pi); y += sin(item.h * 2 * .pi); sat += item.s; bri += item.b }
        let count = CGFloat(vivid.count)
        var hue = atan2(y, x) / (2 * .pi); if hue < 0 { hue += 1 }
        let s = min(0.85, sat / count), b = bri / count
        if s < 0.15 { return [UIColor(white: min(0.32, b * 0.4), alpha: 1), UIColor(white: 0.05, alpha: 1)] }
        return [UIColor(hue: hue, saturation: s, brightness: min(0.62, max(0.35, b * 0.7)), alpha: 1),
                UIColor(hue: hue, saturation: min(1, s + 0.1), brightness: 0.12, alpha: 1)]
    }
}
