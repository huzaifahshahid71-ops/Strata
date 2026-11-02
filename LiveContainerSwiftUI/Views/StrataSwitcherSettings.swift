import SwiftUI
struct StrataSwitcherSettings: View {
    let apps: [LCAppModel]
    @State private var pinned: [String] = []
    @AppStorage("StrataFloatingHomeButton", store: LCUtils.appGroupUserDefault) private var floatingHomeButton = false
    var body: some View {
        Form {
            Section {
                Text("Three-finger tap shows running apps and your pinned shortcuts. The same app strip is used in Strata and inside guests.").font(.subheadline)
                Toggle("Enable Floating Home Button", isOn: $floatingHomeButton)
                Text("Shows a draggable quick-exit button while an app is running. Tap it to close the app and return to Strata.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Pinned apps") {
                ForEach(apps, id: \.self) { app in
                    Toggle(LiveBoardAppCustomization.shared.name(app), isOn: Binding(get: { pinned.contains(liveBoardAppKey(app)) }, set: { enabled in
                        let key = liveBoardAppKey(app)
                        pinned.removeAll { $0 == key }; if enabled { pinned.append(key) }
                        LCUtils.appGroupUserDefault.set(pinned, forKey: "StrataSwitcherPinnedApps")
                    }))
                }
            }
        }.navigationTitle("App Switcher").navigationBarTitleDisplayMode(.inline)
            .onAppear { pinned = LCUtils.appGroupUserDefault.stringArray(forKey: "StrataSwitcherPinnedApps") ?? [] }
    }
}

@MainActor extension LCAppModel {
    var strataSwitcherPinned: Bool {
        get { (LCUtils.appGroupUserDefault.stringArray(forKey: "StrataSwitcherPinnedApps") ?? []).contains(liveBoardAppKey(self)) }
        set {
            var values = LCUtils.appGroupUserDefault.stringArray(forKey: "StrataSwitcherPinnedApps") ?? []
            let key = liveBoardAppKey(self); values.removeAll { $0 == key }; if newValue { values.append(key) }
            LCUtils.appGroupUserDefault.set(values, forKey: "StrataSwitcherPinnedApps"); objectWillChange.send()
        }
    }
}
