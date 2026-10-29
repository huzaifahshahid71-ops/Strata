import Foundation
var layout = LiveBoardHomeLayout()
let apps = (0..<15).map { "local:\($0).app" }
layout.reconcile(apps, favorites: [])
let source = apps[5], target = apps[6]
let page = layout.pages.firstIndex { $0.contains(target) }!
let slot = layout.pages[page].firstIndex(of: target)!
let id = layout.merge(source, onto: target)!
assert(layout.pages[page][slot] == id)
assert(layout.folders.first { $0.id == id }!.apps == [target, source])
layout.reconcile(apps, favorites: [])
assert(layout.folders.count == 1)
assert(layout.merge(source, onto: id) == nil)
assert(layout.merge(target, onto: target) == nil)
layout.place(source, on: page)
layout.reconcile(apps, favorites: [])
assert(layout.folders.first { $0.id == id }!.apps == [target])
layout.dissolveFolder(id); layout.reconcile(apps, favorites: [])
assert(layout.folders.isEmpty)
let flattened = layout.pages.flatMap { $0.compactMap { $0 } } + layout.dock + layout.hidden
assert(Set(flattened) == Set(apps)); assert(flattened.count == apps.count)
print("Folder merge, drag-out, dissolve and invalid nesting tests passed")
