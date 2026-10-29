import SwiftUI

struct StrataAboutView: View {
    private let profile = URL(string: "https://github.com/huzaifahshahid71-ops")!
    private let repository = URL(string: "https://github.com/huzaifahshahid71-ops/Strata")!
    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    if let icon = UIImage(contentsOfFile: Bundle.main.bundleURL.appendingPathComponent("AppIcon60x60@2x.png").path) {
                        Image(uiImage: icon).resizable().frame(width: 80, height: 80).clipShape(RoundedRectangle(cornerRadius: 19))
                    }
                    Text("Strata").font(.largeTitle.bold())
                    Text("Version 2.0").font(.subheadline).foregroundStyle(.secondary)
                    Text("Your apps. Your interface.").font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            Section("Created by") {
                Link(destination: profile) { Label("@huzaifahshahid71-ops", systemImage: "person.crop.circle") }.accessibilityIdentifier("strata.about.profile")
            }
            Section("Strata on GitHub") {
                Link(destination: repository) { Label("Source code & project", systemImage: "chevron.left.forwardslash.chevron.right") }.accessibilityIdentifier("strata.about.repository")
                Link(destination: repository.appendingPathComponent("releases")) { Label("Releases & updates", systemImage: "arrow.down.circle") }
                Link(destination: repository.appendingPathComponent("issues")) { Label("Report an issue", systemImage: "ladybug") }
            }
            Section("Upstream credits") {
                Link("LiveContainer", destination: URL(string: "https://github.com/LiveContainer/LiveContainer")!)
                Link("SideStore", destination: URL(string: "https://github.com/SideStore/SideStore")!)
                Link("StikJIT", destination: URL(string: "https://github.com/StikDebug/StikJIT")!)
                Link("LiveExec32", destination: URL(string: "https://github.com/LiveContainer/LiveExec32")!)
                Link("StosSign", destination: URL(string: "https://github.com/stossy11/StosSign")!)
                Link("Licenses & third-party notices", destination: repository.appendingPathComponent("blob/main/THIRD_PARTY_NOTICES.md"))
            }
        }.navigationTitle("About Strata").navigationBarTitleDisplayMode(.inline)
    }
}

struct StrataCreditsButton: View {
    var location = "strata.about.button"
    @State private var showingAbout = false
    var body: some View {
        Button { showingAbout = true } label: {
            Label("About Strata & GitHub", systemImage: "info.circle").frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityIdentifier(location)
        .sheet(isPresented: $showingAbout) {
            NavigationView {
                StrataAboutView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingAbout = false } } }
            }.navigationViewStyle(.stack)
        }
    }
}
