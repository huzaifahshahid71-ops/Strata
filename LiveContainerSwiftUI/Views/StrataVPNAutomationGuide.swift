import SwiftUI

struct StrataVPNAutomationGuide: View {
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tested = false
    var body: some View {
        NavigationView {
            Form {
                Section("One-time setup") {
                    Text("Install LocalDevVPN and connect it once to add its VPN configuration. Keep its working addresses unchanged.")
                    Text("Add your Set VPN shortcut, optionally create the automation below. It uses the native Set VPN action and the existing Refresh All Apps action. Review the selected VPN and app before first use.")
                    if #available(iOS 16, *), let url = premadeURL {
                        ShareLink(item: url) { Label("Add premade Shortcut", systemImage: "plus.app") }
                        Text("Choose Shortcuts from the share sheet, then Add Shortcut. A daily Personal Automation is optional. If an action is unavailable, use the manual recipe below.").font(.caption).foregroundStyle(.secondary)
                    }
                    Link("Open Shortcuts", destination: URL(string: "shortcuts://")!)
                }
                Section("Simple shortcut") {
                    step(1, "Connect to LocalDevVPN", "Use the native Set VPN action with Connect.")
                    step(2, "Wait 5 seconds", "Let the VPN route settle.")
                    step(3, "Refresh All Apps", "Choose Strata's bundled SideStore action. Its source waits for the refresh result before returning.")
                    step(4, "Wait 5 seconds", "Retained from your supplied shortcut.")
                    step(5, "Disconnect LocalDevVPN", "If refresh errors or iOS interrupts the shortcut, this action may not run. Disconnect manually afterward if necessary.")
                }
                Section("Optional daily automation") {
                    Text("Create a daily Time of Day Personal Automation. Add Is Strata Refresh Due? → If Yes → Run Shortcut: Set VPN → End If. Choose Run Immediately where available. This outer check applies your selected 1–5 day interval; Set VPN itself stays simple.")
                    Link("Apple's automation instructions", destination: URL(string: "https://support.apple.com/guide/shortcuts/apdfbdbd7123/ios")!)
                    Link("Run Set VPN", destination: URL(string: "shortcuts://run-shortcut?name=Set%20VPN")!)
                }
                Section("Before enabling") {
                    Text("The simple shortcut disconnects LocalDevVPN at the end without checking for other users. If a JIT session or another app still needs the VPN, omit Disconnect or wait until that session finishes.")
                    Text("If iOS interrupts Shortcuts, requires unlocking, or replaces Strata during its own refresh, cleanup may not run and the VPN can remain connected. Check the result and expiry date. An app-open automation alone does not schedule refreshes.")
                    Toggle("I added and checked the Set VPN Shortcut", isOn: $tested).accessibilityIdentifier("vpn.setup.confirmed")
                    Button("Finish setup") { confirm() }.disabled(!tested).accessibilityIdentifier("vpn.setup.enable")
                }
            }
            .navigationTitle("VPN Shortcut").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
    private var premadeURL: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Automation/Set VPN.shortcut")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text("\(number). \(title)").font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary) }.padding(.vertical, 4)
    }
}
