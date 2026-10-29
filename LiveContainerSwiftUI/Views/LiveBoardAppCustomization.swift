import SwiftUI

/// Shared launcher names/icons; never alters guest metadata or executable bundles.
@MainActor final class LiveBoardAppCustomization: ObservableObject {
    static let shared = LiveBoardAppCustomization()
    @Published private(set) var revision = 0
    private let cache = NSCache<NSString, UIImage>()
    private let defaults = LCUtils.appGroupUserDefault
    private var names: [String: String] { defaults.dictionary(forKey: "StrataAppNames") as? [String: String] ?? [:] }
    private var icons: [String: String] { defaults.dictionary(forKey: "StrataAppIcons") as? [String: String] ?? [:] }
    private var directory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Strata/Icons") }
    private var cachedLegacy = ""
    private var legacyAliases: [String: String] = [:]
    func name(_ app: LCAppModel) -> String {
        let key = liveBoardAppKey(app)
        if let name = names[key] { return name }
        let encoded = defaults.string(forKey: "LiveBoardHomeLayout") ?? ""
        if encoded != cachedLegacy { cachedLegacy = encoded; legacyAliases = LiveBoardHomeLayout.decode(encoded).aliases }
        return legacyAliases[key] ?? app.displayName
    }
    func rename(_ app: LCAppModel, to value: String) {
        let key = liveBoardAppKey(app); var map = names
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        map[key] = name.isEmpty ? nil : String(name.prefix(100))
        defaults.set(map, forKey: "StrataAppNames")
        // Clear a previous Home-only alias so resetting the name also restores the original.
        var layout = LiveBoardHomeLayout.decode(defaults.string(forKey: "LiveBoardHomeLayout") ?? "")
        if layout.aliases.removeValue(forKey: key) != nil { defaults.set(layout.encoded, forKey: "LiveBoardHomeLayout") }
        revision += 1
    }
    func image(_ app: LCAppModel) -> UIImage? {
        guard let file = icons[liveBoardAppKey(app)] else { return nil }
        if let image = cache.object(forKey: file as NSString) { return image }
        guard let image = UIImage(contentsOfFile: directory.appendingPathComponent(file).path) else { return nil }
        cache.setObject(image, forKey: file as NSString)
        return image
    }
    func saveIcon(_ image: UIImage, app: LCAppModel) throws {
        guard image.size.width > 0, image.size.height > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let side: CGFloat = 512
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let result = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let scale = side / min(image.size.width, image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (side - size.width)/2, y: (side - size.height)/2, width: size.width, height: size.height))
        }
        guard let data = result.pngData() else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = UUID().uuidString + ".png"
        try data.write(to: directory.appendingPathComponent(file), options: .atomic)
        var map = icons; let old = map.updateValue(file, forKey: liveBoardAppKey(app))
        defaults.set(map, forKey: "StrataAppIcons")
        if let old { try? FileManager.default.removeItem(at: directory.appendingPathComponent(old)) }
        cache.setObject(result, forKey: file as NSString)
        revision += 1
    }
    func resetIcon(_ app: LCAppModel) {
        var map = icons
        if let file = map.removeValue(forKey: liveBoardAppKey(app)) { try? FileManager.default.removeItem(at: directory.appendingPathComponent(file)) }
        defaults.set(map, forKey: "StrataAppIcons"); revision += 1
    }
}

struct LiveBoardAppearanceSelection: Identifiable {
    let app: LCAppModel
    var id: String { liveBoardAppKey(app) }
}

struct LiveBoardAppAppearance: View {
    let app: LCAppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var customization = LiveBoardAppCustomization.shared
    @State private var name = ""
    @State private var choosingIcon = false
    @State private var error: String?
    var body: some View {
        NavigationView {
            Form {
                Section("App name") {
                    TextField("Name", text: $name).accessibilityIdentifier("appearance.name")
                        .submitLabel(.done).onSubmit { customization.rename(app, to: name); UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                    Button("Save name") { customization.rename(app, to: name); name = customization.name(app) }.accessibilityIdentifier("appearance.saveName")
                    Button("Restore original name") { customization.rename(app, to: ""); name = customization.name(app) }
                }
                Section("App icon") {
                    LiveBoardIconImage(app: app, dark: false).frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 16))
                    Button("Choose image from Photos") { choosingIcon = true }.accessibilityIdentifier("appearance.chooseIcon")
                    Button("Restore original icon") { customization.resetIcon(app) }
                    Text("Names and icons appear in all three interfaces. Console cover artwork stays separate.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("App appearance")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.navigationViewStyle(.stack)
        .onAppear { name = customization.name(app) }
        .sheet(isPresented: $choosingIcon) {
            LiveBoardWallpaperPicker { image in
                if let image { do { try customization.saveIcon(image, app: app) } catch { self.error = error.localizedDescription } }
                choosingIcon = false
            }
        }
    }
}
