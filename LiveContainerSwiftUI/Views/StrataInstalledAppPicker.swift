import SwiftUI
import UniformTypeIdentifiers

struct StrataInstalledPhoneApp: Codable, Identifiable {
    let id: String
    let name: String
    /// URL schemes the app registers (from the paired-Mac export). Used when iOS refuses direct opening.
    var schemes: [String]? = nil
}

struct StrataInstalledAppPicker: View {
    @ObservedObject private var store = StrataPhoneApps.shared
    @Environment(\.dismiss) private var dismiss
    @State private var apps: [StrataInstalledPhoneApp] = []
    @State private var loading = true
    @State private var query = ""
    @State private var importing = false
    @State private var error: String?
    @State private var importedCatalog = false
    private let catalog = LCPath.docPath.appendingPathComponent("Strata3/PhoneAppsCatalog.json")
    private var filtered: [StrataInstalledPhoneApp] { apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        List {
            Section {
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("App name", text: $query).autocapitalization(.none).disableAutocorrection(true).submitLabel(.search) }
            }
            if query.isEmpty { Section {
                Text("Tap an app to add it to Strata. No Shortcut is created.").font(.footnote)
                if importedCatalog { Text("Showing the last app list imported from your Mac. Apps that have since been removed may no longer open.").font(.caption).foregroundStyle(.secondary) }
                if loading { ProgressView("Reading installed apps…") }
                if !loading && apps.isEmpty {
                    Text("iOS has restricted the installed-app list. Import an app list from a paired Mac to choose apps by name.").font(.footnote)
                }
            }
            }
            Section("Apps") {
                ForEach(filtered) { app in
                    let added = store.entries.contains { $0.bundleIdentifier == app.id }
                    Button {
                        do { try store.save(.init(name: app.name, target: "", shortcut: false, bundleIdentifier: app.id), image: nil) }
                        catch { self.error = error.localizedDescription }
                    } label: {
                        HStack { StrataPhoneAppIconView(bundleIdentifier: app.id); Text(app.name); Spacer(); Image(systemName: added ? "checkmark.circle.fill" : "plus.circle").foregroundStyle(added ? .green : .blue) }
                    }.disabled(added).accessibilityValue(added ? "Added" : "Not added").accessibilityIdentifier("installedApp." + app.id)
                }
            }
            Section {
                Button("Reload installed apps") { Task { await reload() } }
                Button("Import app list from Mac") { importing = true }
            }
        }.navigationTitle("Choose iPhone Apps")

        .onSubmit { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await reload() }
        .alert("iPhone Apps", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0 && size <= 1_000_000 else { throw "The app list is empty or too large." }
                let values = try Self.validated(Data(contentsOf: url))
                try FileManager.default.createDirectory(at: catalog.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(values).write(to: catalog, options: .atomic)
                apps = values; importedCatalog = true; loading = false
            } catch { self.error = error.localizedDescription }
        }
    }
    private func reload() async {
        loading = true
        let result = await Task.detached(priority: .userInitiated) { LCUtils.strataPhoneApplications() }.value
        let values = (result?["apps"] as? [[String: String]] ?? []).compactMap { value -> StrataInstalledPhoneApp? in
            guard let id = value["id"], let name = value["name"], StrataPhoneAppPolicy.validBundleIdentifier(id), id != Bundle.main.bundleIdentifier else { return nil }
            return .init(id: id, name: String(name.prefix(120)))
        }
        let imported = (try? Data(contentsOf: catalog)).flatMap { try? Self.validated($0) } ?? []
        var merged = Dictionary(imported.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for app in values { merged[app.id] = app }
        apps = merged.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let nativeIDs = Set(values.map(\.id))
        importedCatalog = imported.contains { !nativeIDs.contains($0.id) }
        loading = false
    }
    private static func validated(_ data: Data) throws -> [StrataInstalledPhoneApp] {
        guard data.count <= 1_000_000 else { throw "The app list is too large." }
        let entries = try JSONDecoder().decode([StrataInstalledPhoneApp].self, from: data)
        guard entries.count <= 2000 else { throw "Too many app entries." }
        var seen = Set<String>()
        return entries.map { var app = $0; app.schemes = app.schemes.map(StrataPhoneAppPolicy.validSchemes); return app }
            .filter { StrataPhoneAppPolicy.validBundleIdentifier($0.id) && !$0.name.isEmpty && $0.name.count <= 120 && $0.id != Bundle.main.bundleIdentifier && seen.insert($0.id).inserted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private struct StrataPhoneAppIconView: View {
    let bundleIdentifier: String
    var body: some View {
        Image(uiImage: StrataPhoneApps.icon(for: bundleIdentifier, name: ""))
            .resizable().frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
