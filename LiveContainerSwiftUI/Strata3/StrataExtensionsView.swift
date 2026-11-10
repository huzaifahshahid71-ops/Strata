import SwiftUI

struct StrataExtensionsView: View {
    let apps: [LCAppModel]
    @State private var rows: [ExtensionRow] = []
    @State private var loading = true
    private struct ExtensionRow: Identifiable, Sendable {
        let id: String
        let app: String
        let name: String
        let point: String
    }
    var body: some View {
        List {
            Section("Strata integration") {
                Label("Share and import files into Strata", systemImage: "square.and.arrow.down")
                Text("Use Share → Strata from Files or Safari for supported imports. Keep Strata's extensions when signing the update.").font(.footnote)
            }
            Section("Imported app extensions") {
                Text("Guest extensions are listed for inspection. They are not registered with iOS by importing a guest app, so system widgets, Safari extensions and guest Share actions are not enabled here.").font(.footnote).foregroundStyle(.secondary)
                if loading { ProgressView() }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 5) { Text(row.name); Text(row.app).font(.caption); Text(row.point).font(.caption2).foregroundStyle(.secondary) }
                }
                if !loading && rows.isEmpty { Text("No embedded extensions found in the visible, unlocked apps.").foregroundStyle(.secondary) }
            }
        }.navigationTitle("App Extensions")
        .task {
            let inputs = apps.filter { !$0.uiIsLocked && !$0.uiIsHidden && !($0.appInfo is BuiltInSideStoreAppInfo) }.compactMap { app -> (String, String)? in
                guard let path = app.appInfo.bundlePath() else { return nil }; return (app.displayName, path)
            }
            rows = await Task.detached(priority: .utility) {
                var result: [ExtensionRow] = []
                for (name, path) in inputs {
                    let root = URL(fileURLWithPath: path).appendingPathComponent("PlugIns")
                    for folder in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? [] where folder.pathExtension == "appex" {
                        guard (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                              let data = try? Data(contentsOf: folder.appendingPathComponent("Info.plist")), data.count < 1_000_000,
                              let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { continue }
                        let extensionInfo = info["NSExtension"] as? [String: Any]
                        result.append(.init(id: folder.path, app: name, name: info["CFBundleDisplayName"] as? String ?? folder.deletingPathExtension().lastPathComponent, point: extensionInfo?["NSExtensionPointIdentifier"] as? String ?? "Unknown extension point"))
                    }
                }
                return result.sorted { $0.app.localizedStandardCompare($1.app) == .orderedAscending }
            }.value
            loading = false
        }
    }
}
