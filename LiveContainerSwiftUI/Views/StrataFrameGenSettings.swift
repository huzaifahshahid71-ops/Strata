import SwiftUI

struct StrataFrameGenSettings: View {
    let apps: [LCAppModel]
    var selected: LCAppModel? = nil
    @State private var sample: [String: Any] = [:]
    var body: some View {
        Form {
            Section {
                Text("Experimental 2× optical-flow frame generation for compatible Metal surfaces. Other rendering paths continue normally. Restart a guest after changing its settings.")
                Text("Displayed mode requests a doubled cadence within the screen limit. Uncapped benchmark computes extra frames offscreen and counts completed GPU work; it does not disable iOS display synchronization or make a 120 Hz screen show 240 distinct frames.").font(.footnote).foregroundStyle(.secondary)
            }
            if let selected { StrataFrameGenAppOptions(app: selected) }
            else {
                Section("Games & apps") {
                    ForEach(apps.filter { !($0.appInfo is BuiltInSideStoreAppInfo) }, id: \.self) { app in
                        NavigationLink { StrataFrameGenSettings(apps: apps, selected: app) } label: { Text(app.displayName) }
                    }
                }
            }
            Section("Latest guest measurement") {
                if let status = sample["status"] as? String {
                    Text(status)
                    Text("Native GPU: \(number("nativeGPUFPS")) FPS\nGenerated GPU: \(number("generatedGPUFPS")) FPS\nComputed total: \(number("computedFPS")) FPS\nPresented: \(number("presentedFPS")) FPS")
                        .font(.system(.footnote, design: .monospaced))
                    if let stamp = sample["sampledAt"] as? Double { Text(Date(timeIntervalSince1970: stamp), style: .relative).font(.caption).foregroundStyle(.secondary) }
                    Text("Latest sample across guests; presented counts use Metal presentation callbacks. This is not a panel scanout measurement.").font(.caption).foregroundStyle(.secondary)
                } else { Text("Launch an enabled guest to collect measurements. Non-Metal or unsupported presentation paths do not generate frames.").foregroundStyle(.secondary) }
            }
            Section { Link("MetalFG — upstream project", destination: URL(string: "https://github.com/dnullptr/MetalFG")!) }
        }
        .navigationTitle(selected?.displayName ?? "Frame Generation").navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                if let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: LCSharedUtils.appGroupID() ?? ""),
                   let data = try? Data(contentsOf: root.appendingPathComponent("Library/StrataFrameGen/latest.json")),
                   let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { sample = report }
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            }
        }
    }
    private func number(_ key: String) -> String { String(format: "%.1f", (sample[key] as? NSNumber)?.doubleValue ?? 0) }
}
private struct StrataFrameGenAppOptions: View {
    let app: LCAppModel
    @AppStorage("StrataFrameGenApps", store: LCUtils.appGroupUserDefault) private var saved = "{}"
    private var all: [String: [String: String]] { (try? JSONDecoder().decode([String: [String: String]].self, from: Data(saved.utf8))) ?? [:] }
    private var key: String { liveBoardAppKey(app) }
    var body: some View {
        Section("Frame generation") {
            Picker("Mode", selection: Binding(get: { all[key]?["mode"] ?? "off" }, set: { set("mode", $0) })) {
                Text("Off").tag("off"); Text("2× displayed (experimental)").tag("2x"); Text("Uncapped 2× GPU benchmark").tag("benchmark")
            }
            Picker("Source cadence request", selection: Binding(get: { all[key]?["sourceFPS"] ?? "0" }, set: { set("sourceFPS", $0) })) {
                Text("Use game setting").tag("0")
                Text("30 → 60").tag("30"); Text("45 → 90").tag("45"); Text("60 → 120").tag("60")
                Text("120 → 240 computed (benchmark)").tag("120")
            }
            Text("Cadence requests apply to CADisplayLink-based loops and may be ignored by a game's own renderer. Actual rates depend on GPU headroom, thermal conditions and the display. Offscreen benchmark frames are not displayed.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func set(_ field: String, _ value: String) {
        var config = all; var entry = config[key] ?? [:]; entry[field] = value; config[key] = entry
        if let data = try? JSONEncoder().encode(config), let string = String(data: data, encoding: .utf8) { saved = string }
    }
}
