import Foundation
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("StrataArtworkTest-" + UUID().uuidString)
defer { try? fm.removeItem(at: root) }
let legacy = root.appendingPathComponent("Legacy")
try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
let bytes = Data([1, 8, 19, 255])
try bytes.write(to: legacy.appendingPathComponent("old.jpg"))
let files = LiveBoardArtworkFiles(directory: root.appendingPathComponent("Documents/Artwork"), legacyDirectory: legacy)
let input = ["cinematic:cover:local:AngryBirds.app": "old.jpg", "bigPicture:portrait:local:AngryBirds.app": "old.jpg", "cover:local:Legacy.app": "old.jpg", "bigPicture:background:local:Missing.app": "missing.jpg"]
let output = try files.migrate(input)
precondition(output.count == input.count)
precondition(output["cinematic:cover:local:AngryBirds.app"]!.hasPrefix("Cinematic/Covers/"))
precondition(output["bigPicture:portrait:local:AngryBirds.app"]!.hasPrefix("Big Picture/Portraits/"))
precondition(output["cover:local:Legacy.app"]!.hasPrefix("Big Picture/Covers/"))
precondition(output["bigPicture:background:local:Missing.app"] == "missing.jpg")
for (key, file) in output where key != "bigPicture:background:local:Missing.app" {
    let read = try Data(contentsOf: files.existingURL(file)!)
    precondition(read == bytes)
}
precondition(fm.fileExists(atPath: legacy.appendingPathComponent("old.jpg").path))
let repeated = try files.migrate(output)
precondition(repeated == output, "Migration must be idempotent")
precondition(files.visibleURL("../escape.jpg") == nil)
precondition(files.visibleURL("/escape.jpg") == nil)
precondition(files.existingURL("../old.jpg") == nil)
precondition(LiveBoardArtworkFiles.folder(mode: "ios", kind: "cover") == nil)
print("PASS: artwork migration preserves bytes and mode assignments, legacy fallback, missing files, recovery copies, repeat migration and path containment.")
