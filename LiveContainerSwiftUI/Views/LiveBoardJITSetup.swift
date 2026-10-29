import SwiftUI
import UniformTypeIdentifiers

struct LiveBoardJITSetup: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("LCJITEnablerType", store: LCUtils.appGroupUserDefault) private var provider = JITEnablerType.BuiltIn.rawValue
    @AppStorage("StrataJITDeviceAddress", store: LCUtils.appGroupUserDefault) private var deviceAddress = "10.7.0.1"
    @AppStorage("StrataJITRemotePairPort", store: LCUtils.appGroupUserDefault) private var remotePairPort = "49152"
    @ObservedObject private var session = LiveBoardJITSession.shared
    @State private var importing = false
    @State private var hasPairing = FileManager.default.fileExists(atPath: LiveBoardBuiltInJIT.pairingURL.path)
    var body: some View {
        NavigationView {
            Form {
                Section("JIT method") {
                    Picker("Enable JIT using", selection: $provider) {
                        ForEach(JITEnablerType.allCases) { Text($0.displayName).tag($0.rawValue) }
                    }
                    Button("Use built-in JIT") { provider = JITEnablerType.BuiltIn.rawValue }
                }
                if provider == JITEnablerType.BuiltIn.rawValue {
                    Section("One-time setup") {
                        Label(hasPairing ? "Pairing file imported" : "Pairing file needed", systemImage: hasPairing ? "checkmark.circle" : "doc.badge.plus")
                        Button(hasPairing ? "Replace pairing file" : "Import remote pairing file") { importing = true }
                        if hasPairing {
                            Button("Remove pairing file", role: .destructive) {
                                do { try FileManager.default.removeItem(at: LiveBoardBuiltInJIT.pairingURL); hasPairing = false; session.message = "Pairing file removed." }
                                catch { session.message = error.localizedDescription }
                            }
                        }
                        Text("Enable Developer Mode in iPhone Settings. Connect LocalDevVPN and Wi-Fi before using Launch with JIT. The first launch may download a developer disk image.")
                        Label(LCUtils.strataCanDebug() ? "Debugging permission available" : "Re-signing required: debugging permission missing", systemImage: LCUtils.strataCanDebug() ? "checkmark.shield" : "exclamationmark.shield")
                        Text("Built-in JIT uses a guest process to keep its debugger connection alive. Normal launch requests open that guest full-screen. Keep app extensions when installing Strata. On newer iOS versions, the guest may also need a compatible JIT script in its app settings.").foregroundStyle(.secondary)
                    }
                    Section("Device connection") {
                        TextField("Device IP (without /32)", text: $deviceAddress)
                            .keyboardType(.decimalPad).autocorrectionDisabled()
                        TextField("Remote pairing port", text: $remotePairPort)
                            .keyboardType(.numberPad)
                        Text("Copy the Device IP/Endpoint and RemotePair Port from your working SideStore connection. This does not change VPN settings.").font(.footnote).foregroundStyle(.secondary)
                    }.disabled(session.busy)
                    Section("Connection check") {
                        Button("Prepare device") { perform("prepare") }.disabled(session.busy || !hasPairing)
                        Button("Reset developer disk image cache") { perform("reset") }.disabled(session.busy || !hasPairing)
                        if session.busy {
                            ProgressView("Working…")
                            Button("Cancel") { session.cancel() }
                        }
                        if let operationSucceeded = session.success {
                            Label(operationSucceeded ? "Completed" : "Could not complete", systemImage: operationSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(operationSucceeded ? .green : .orange)
                        }
                        if !session.message.isEmpty { Text(session.message).font(.footnote).textSelection(.enabled).accessibilityIdentifier("jit.status") }
                    }
                    Section("Launch") {
                        Text("Touch and hold an app, or open its console options, and choose Launch with JIT. Strata prepares the device and connects its helper automatically. Errors appear in the launch window.")
                    }
                } else {
                    Section("External provider") {
                        Text("Configure pairing and the required connection in your selected provider, then choose Launch with JIT on an app.")
                        NavigationLink("Provider settings") { LCSettingsView() }
                    }
                }
                if provider != JITEnablerType.BuiltIn.rawValue && !session.message.isEmpty { Section { Text(session.message) } }
                Section { NavigationLink("Memory and signing permissions") { StrataMemorySettings() } }
                Section { NavigationLink("JIT-less setup and diagnostics") { LCJITLessDiagnoseView() } }
            }.navigationTitle("JIT setup")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
                    do {
                        let url = try result.get()
                        try LiveBoardBuiltInJIT.importPairing(url)
                        hasPairing = true
                        session.message = "Pairing file imported. Connect LocalDevVPN, then launch an app with JIT."
                    } catch { session.message = error.localizedDescription }
                }
        }.navigationViewStyle(.stack)
    }
    private func perform(_ operation: String) { session.start(operation) }
}
