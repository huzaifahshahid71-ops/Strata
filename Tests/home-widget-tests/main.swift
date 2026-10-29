import Foundation
func assertValid(_ layout: LiveBoardHomeLayout, keys: [String]) {
    var all: [String] = layout.dock + layout.hidden + layout.folders.flatMap(\.apps)
    for p in layout.pages.indices {
        var occupied = Set<Int>()
        for (slot, key) in layout.pages[p].enumerated() {
            guard let key else { continue }
            let cells = layout.cells(for: key, at: slot)
            precondition(!cells.isEmpty && occupied.isDisjoint(with: cells), "Overlapping widget/app")
            occupied.formUnion(cells)
            if !key.hasPrefix("folder:") && !key.hasPrefix("widget:") { all.append(key) }
        }
    }
    precondition(all.count == Set(all).count && Set(all) == Set(keys), "Lost or duplicated guest")
}
let keys = (0..<60).map { "local:app\($0)" }
var layout = LiveBoardHomeLayout()
layout.reconcile(keys, favorites: [])
let legacy = layout.encoded
var object = try JSONSerialization.jsonObject(with: Data(legacy.utf8)) as! [String: Any]
object.removeValue(forKey: "widgets")
let migrated = LiveBoardHomeLayout.decode(String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!)
precondition(migrated.pages == layout.pages && migrated.dock == layout.dock && migrated.widgets.isEmpty)
let photo = LiveBoardHomeLayout.Widget(kind: .photo, photo: UUID().uuidString + ".jpg")
layout.addWidget(photo, on: 0)
assertValid(layout, keys: keys)
layout.place(photo.id, on: 0, slot: 23) // fit at bottom edge, displacing/reflowing other items
precondition(layout.pages[0][18] == photo.id)
assertValid(layout, keys: keys)
layout.resizeWidget(photo.id, to: .medium)
precondition(layout.pages[0][16] == photo.id)
assertValid(layout, keys: keys)
layout.place(keys[5], on: 0, slot: 17) // drop an app onto the covered half of a widget
assertValid(layout, keys: keys)
layout.reconcile(keys, favorites: [])
assertValid(layout, keys: keys)
precondition(LiveBoardHomeLayout.decode(layout.encoded) == layout)
layout.createFolder(name: "Games", app: keys[10])
let folder = layout.folders.last!
layout.put(keys[11], in: folder.id)
layout.place(folder.id, on: 1, slot: 0)
let clock = LiveBoardHomeLayout.Widget(kind: .clock)
layout.addWidget(clock, on: 1)
layout.place(clock.id, on: 1, slot: 4)
let before = layout
let removedKeys = layout.pages[1].compactMap { $0 }
let removed = layout.removePage(at: 1)
precondition(layout.pages.count == before.pages.count - 1)
precondition(layout.pages[0] == before.pages[0] && layout.dock == before.dock)
precondition(layout.hidden.contains(keys[10]) && layout.hidden.contains(keys[11]))
precondition(!layout.folders.contains { $0.id == folder.id })
for key in removedKeys where key.hasPrefix("widget:") { precondition(removed.contains { $0.id == key }) }
layout.reconcile(keys, favorites: [])
assertValid(layout, keys: keys)
while layout.pages.count > 1 { layout.removePage(at: layout.pages.count - 1) }
let single = layout
layout.removePage(at: 0)
precondition(layout == single)
// Random moves/resizes/reconciliation must never lose an app or overlap occupied cells.
var random = LiveBoardHomeLayout(); random.reconcile(keys, favorites: [])
for kind in LiveBoardHomeLayout.Widget.Kind.allCases { random.addWidget(.init(kind: kind), on: 0) }
for i in 0..<150 {
    if i % 3 == 0, let w = random.widgets.first { random.resizeWidget(w.id, to: i % 2 == 0 ? .medium : .small) }
    else { random.place(keys[i % keys.count], on: (i / 11) % random.pages.count, slot: i % 24) }
    random.reconcile(keys, favorites: [])
    assertValid(random, keys: keys)
}
print("PASS: legacy migration, widget occupancy/reflow/resize, page deletion without uninstalling or losing apps, folder handling, persistence and repeated moves.")

var legacyWidgets = try JSONSerialization.jsonObject(with: Data(layout.encoded.utf8)) as! [String: Any]
legacyWidgets["widgets"] = [["id": "widget:legacy", "kind": "clock", "size": "small"]]
let upgraded = LiveBoardHomeLayout.decode(String(data: try JSONSerialization.data(withJSONObject: legacyWidgets), encoding: .utf8)!)
precondition(upgraded.widgets.count == 1 && upgraded.widgets[0].appearance == .gradient)
var glass = upgraded; glass.widgets[0].appearance = .glass
precondition(LiveBoardHomeLayout.decode(glass.encoded).widgets[0].appearance == .glass)
print("PASS: existing widgets migrate without loss; gradient/glass preference persists.")
