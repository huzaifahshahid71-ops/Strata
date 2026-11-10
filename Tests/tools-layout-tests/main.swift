import Foundation
let ids = ["interface", "refresh", "sources", "tweaks", "storage", "memory"]
var layout = StrataToolsLayout()
assert(layout.visible(available: ids) == ids)
layout.move("refresh", to: "interface", available: ids)
assert(layout.visible(available: ids).prefix(2) == ["refresh", "interface"])
layout.remove("refresh"); assert(!layout.visible(available: ids).contains("refresh"))
layout.add("refresh", available: ids); assert(layout.visible(available: ids).last == "refresh")
assert(StrataToolsLayout(saved: layout.encoded) == layout)
for id in ids { layout.remove(id) }; assert(layout.visible(available: ids).isEmpty)
for id in ids { layout.add(id, available: ids) }; assert(Set(layout.visible(available: ids)) == Set(ids))
layout.order = ["missing", "memory", "memory"]
assert(layout.visible(available: ids) == ["memory", "interface", "refresh", "sources", "tweaks", "storage"])
assert(layout.visible(available: ids + ["new-tool"]).last == "new-tool")
assert(StrataToolsLayout(saved: "invalid").visible(available: ids) == ids)
print("Tools layout: reorder, removal, restoration, empty page recovery, persistence and new-card migration passed")
