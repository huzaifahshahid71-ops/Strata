import Foundation

/// Presentation preferences only. No executable paths or guest runtime state are changed.
struct LiveBoardHomeLayout: Codable, Equatable {
    struct Folder: Codable, Identifiable, Equatable {
        var id: String
        var name: String
        var apps: [String]
    }
    struct Widget: Codable, Identifiable, Equatable {
        enum Kind: String, Codable, CaseIterable { case photo, clock, calendar, battery }
        enum Size: String, Codable, CaseIterable {
            case small, medium
            var columns: Int { self == .small ? 2 : 4 }
            var rows: Int { 2 }
        }
        var id = "widget:" + UUID().uuidString
        var kind: Kind
        var size: Size = .small
        var photo: String? = nil
        enum Appearance: String, Codable, CaseIterable { case gradient, glass }
        var appearance: Appearance = .gradient
        init(kind: Kind, size: Size = .small, photo: String? = nil, appearance: Appearance = .gradient) {
            self.kind = kind; self.size = size; self.photo = photo; self.appearance = appearance
        }
        enum CodingKeys: String, CodingKey { case id, kind, size, photo, appearance }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            kind = try c.decode(Kind.self, forKey: .kind)
            size = try c.decodeIfPresent(Size.self, forKey: .size) ?? .small
            photo = try c.decodeIfPresent(String.self, forKey: .photo)
            appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? .gradient
        }
    }
    static let capacity = 24
    var initialized = false
    var pages: [[String?]] = [Array(repeating: nil, count: capacity)]
    var dock: [String] = []
    var folders: [Folder] = []
    var hidden: [String] = []
    var aliases: [String: String] = [:]
    var widgets: [Widget] = []

    init() { }
    enum CodingKeys: String, CodingKey { case initialized, pages, dock, folders, hidden, aliases, widgets }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        initialized = try c.decodeIfPresent(Bool.self, forKey: .initialized) ?? false
        pages = try c.decodeIfPresent([[String?]].self, forKey: .pages) ?? [Array(repeating: nil, count: Self.capacity)]
        dock = try c.decodeIfPresent([String].self, forKey: .dock) ?? []
        folders = try c.decodeIfPresent([Folder].self, forKey: .folders) ?? []
        hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? []
        aliases = try c.decodeIfPresent([String: String].self, forKey: .aliases) ?? [:]
        widgets = (try? c.decodeIfPresent([Widget].self, forKey: .widgets)) ?? []
    }
    static func decode(_ value: String) -> Self {
        (try? JSONDecoder().decode(Self.self, from: Data(value.utf8))) ?? Self()
    }
    var encoded: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    func cells(for key: String, at slot: Int) -> Set<Int> {
        guard (0..<Self.capacity).contains(slot) else { return [] }
        guard let widget = widgets.first(where: { $0.id == key }) else { return [slot] }
        let column = slot % 4, row = slot / 4
        guard column + widget.size.columns <= 4, row + widget.size.rows <= 6 else { return [] }
        return Set((0..<widget.size.rows).flatMap { y in (0..<widget.size.columns).map { slot + y * 4 + $0 } })
    }
    func occupyingKey(page: Int, slot: Int) -> String? {
        guard pages.indices.contains(page) else { return nil }
        for (anchor, key) in pages[page].enumerated() {
            if let key, cells(for: key, at: anchor).contains(slot) { return key }
        }
        return nil
    }
    private func available(_ key: String, page: Int, slot: Int) -> Bool {
        let needed = cells(for: key, at: slot)
        return !needed.isEmpty && needed.allSatisfy { occupyingKey(page: page, slot: $0) == nil }
    }
    mutating func reconcile(_ keys: [String], favorites: [String]) {
        let known = Set(keys)
        var seen = Set<String>()
        hidden = hidden.filter { known.contains($0) && seen.insert($0).inserted }
        dock = Array(dock.filter { known.contains($0) && seen.insert($0).inserted }.prefix(4))
        for index in folders.indices { folders[index].apps = folders[index].apps.filter { known.contains($0) && seen.insert($0).inserted } }
        folders.removeAll { $0.apps.isEmpty }
        var unique = Set<String>()
        widgets = widgets.filter { $0.id.hasPrefix("widget:") && unique.insert($0.id).inserted }
        let folderIDs = Set(folders.map { $0.id }), widgetIDs = Set(widgets.map { $0.id })
        let oldPages = pages.isEmpty ? [Array<String?>(repeating: nil, count: Self.capacity)] : pages
        pages = oldPages.map { _ in Array(repeating: nil, count: Self.capacity) }
        if !initialized && !keys.isEmpty {
            var selected = Set<String>()
            dock = Array(favorites.filter { known.contains($0) && selected.insert($0).inserted }.prefix(4))
            if dock.isEmpty { dock = Array(keys.prefix(4)) }
            seen.formUnion(dock)
            initialized = true
        }
        var pending: [(String, Int)] = []
        for (p, slots) in oldPages.enumerated() {
            for (slot, key) in slots.prefix(Self.capacity).enumerated() {
                guard let key, known.contains(key) || folderIDs.contains(key) || widgetIDs.contains(key), seen.insert(key).inserted else { continue }
                if available(key, page: p, slot: slot) { pages[p][slot] = key }
                else { pending.append((key, p)) }
            }
        }
        for (key, p) in pending { place(key, on: p) }
        for key in keys where !seen.contains(key) { place(key, on: max(0, pages.count - 1)) }
        for id in folders.map(\.id) + widgets.map(\.id) where !seen.contains(id) { place(id, on: 0) }
    }
    mutating func removePlacement(_ key: String) {
        for p in pages.indices { for s in pages[p].indices where pages[p][s] == key { pages[p][s] = nil } }
        dock.removeAll { $0 == key }
        hidden.removeAll { $0 == key }
        for i in folders.indices { folders[i].apps.removeAll { $0 == key } }
    }
    mutating func place(_ key: String, on page: Int, slot: Int? = nil) {
        removePlacement(key)
        var p = max(0, page)
        while pages.count <= p { pages.append(Array(repeating: nil, count: Self.capacity)) }
        if let slot, (0..<Self.capacity).contains(slot) {
            let widget = widgets.first { $0.id == key }
            let column = min(slot % 4, 4 - (widget?.size.columns ?? 1))
            let row = min(slot / 4, 6 - (widget?.size.rows ?? 1))
            let anchor = row * 4 + column
            let covered = cells(for: key, at: anchor)
            var displaced: [String] = []
            for (s, other) in pages[p].enumerated() {
                if let other, !cells(for: other, at: s).isDisjoint(with: covered) { displaced.append(other) }
            }
            for other in displaced { removePlacement(other) }
            pages[p][anchor] = key
            for other in displaced { place(other, on: p) }
            return
        }
        while true {
            while pages.count <= p { pages.append(Array(repeating: nil, count: Self.capacity)) }
            if let free = (0..<Self.capacity).first(where: { available(key, page: p, slot: $0) }) {
                pages[p][free] = key; return
            }
            p += 1
        }
    }
    mutating func addWidget(_ widget: Widget, on page: Int) { widgets.append(widget); place(widget.id, on: page) }
    mutating func resizeWidget(_ id: String, to size: Widget.Size) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        let page = pages.firstIndex { $0.contains(id) } ?? 0
        let slot = pages[page].firstIndex(of: id)
        widgets[index].size = size
        place(id, on: page, slot: slot)
    }
    mutating func removeWidget(_ id: String) { removePlacement(id); widgets.removeAll { $0.id == id } }
    /// Match Home Screen removal: apps return to the library, rather than being uninstalled.
    @discardableResult mutating func removePage(at page: Int) -> [Widget] {
        guard pages.count > 1, pages.indices.contains(page) else { return [] }
        let contents = pages.remove(at: page).compactMap { $0 }
        var removed: [Widget] = []
        for key in contents {
            if let widget = widgets.first(where: { $0.id == key }) { removed.append(widget); removeWidget(key) }
            else if let folder = folders.first(where: { $0.id == key }) {
                folders.removeAll { $0.id == key }
                for app in folder.apps { hide(app) }
            } else { hide(key) }
        }
        return removed
    }
    mutating func hide(_ key: String) { removePlacement(key); hidden.append(key) }
    mutating func putInDock(_ key: String) {
        guard dock.count < 4, !key.hasPrefix("folder:"), !key.hasPrefix("widget:") else { return }
        removePlacement(key); dock.append(key)
    }
    mutating func put(_ key: String, in folderID: String) {
        guard !key.hasPrefix("folder:"), !key.hasPrefix("widget:"), folders.contains(where: { $0.id == folderID }) else { return }
        removePlacement(key)
        if let index = folders.firstIndex(where: { $0.id == folderID }) { folders[index].apps.append(key) }
    }
    /// Preserve the destination's exact page/slot when an app is dropped on another.
    @discardableResult mutating func merge(_ source: String, onto target: String) -> String? {
        guard source != target, !source.hasPrefix("folder:"), !source.hasPrefix("widget:"),
              !target.hasPrefix("folder:"), !target.hasPrefix("widget:") else { return nil }
        guard let p = pages.firstIndex(where: { $0.contains(target) }), let slot = pages[p].firstIndex(of: target) else { return nil }
        removePlacement(source); removePlacement(target)
        let id = "folder:" + UUID().uuidString
        folders.append(Folder(id: id, name: "Apps", apps: [target, source])); pages[p][slot] = id
        return id
    }
    mutating func createFolder(name: String, app: String) {
        removePlacement(app)
        let id = "folder:" + UUID().uuidString
        folders.append(Folder(id: id, name: name, apps: [app]))
        place(id, on: 0)
    }
    mutating func dissolveFolder(_ id: String) {
        let contents = folders.first(where: { $0.id == id })?.apps ?? []
        removePlacement(id); folders.removeAll { $0.id == id }
        for key in contents { place(key, on: 0) }
    }
}
