import SwiftUI
import StosSign_API
import StosSign_Auth
import StosSign_Common
import StosSign_Anisette

/// Own credentials entered by the user remain in memory for this sheet's session only.
@MainActor final class StrataMemoryCapabilities: ObservableObject {
    @Published var appleID = ""
    @Published var password = ""
    @Published var code = ""
    @Published var needsCode = false
    @Published var status = ""
    @Published private(set) var busy = false
    @Published private(set) var signedIn = false
    @Published private(set) var registrations: [AppID] = []
    @Published var selectedHost = ""
    @Published var selectedGuest = ""
    @Published private(set) var expectedHost = ""
    @Published private(set) var expectedGuest = ""
    private var registeredTargets: Set<String>? {
        StrataMemoryRequestPolicy.selectedTargets(host: selectedHost, guest: selectedGuest, registered: Set(registrations.map(\.identifier)))
    }
    var canApply: Bool { signedIn && !busy && registeredTargets != nil }
    private var session: AppleAPISession?
    private var team: Team?
    private var anisette: AnisetteManager?
    private var verification: ((String?) -> Void)?
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func signIn(server: String, signingTeam: String, hostID: String, guestID: String) {
        guard !busy else { return }
        guard let url = URL(string: server), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else {
            status = "Enter the HTTPS anisette server you use with SideStore."; return
        }
        guard !appleID.isEmpty, !password.isEmpty, !signingTeam.isEmpty, !hostID.isEmpty, !guestID.isEmpty else {
            status = "Enter your signing Apple ID and password. This installation must have a valid signing team."; return
        }
        expectedHost = hostID; expectedGuest = guestID
        registrations = []; selectedHost = ""; selectedGuest = ""
        busy = true; status = "Connecting…"
        let operation = UUID(); generation = operation
        let manager = AnisetteManager(); anisette = manager
        let email = appleID, secret = password
        task = Task {
            defer { if generation == operation { password = ""; code = ""; busy = false; task = nil } }
            do {
                let data = try await manager.getAnisetteData(anisetteURL: url)
                try Task.checkCancellation()
                let (account, authenticated) = try await AppleAPI.shared.authenticate(appleID: email, password: secret, anisetteData: data.anisette) { [weak self] callback in
                    await MainActor.run {
                        guard let self, self.generation == operation, !Task.isCancelled else { callback(nil); return }
                        self.verification = callback; self.code = ""; self.needsCode = true
                    }
                }
                try Task.checkCancellation()
                let teams = try await AppleAPI.shared.fetchTeamsForAccount(account: account, session: authenticated)
                guard let currentTeam = teams.first(where: { $0.identifier == signingTeam }) else {
                    throw NSError(domain: "StrataMemory", code: 1, userInfo: [NSLocalizedDescriptionKey: "This account does not contain Strata's signing team. Use the same Apple ID as SideStore."])
                }
                let registered = try await AppleAPI.shared.fetchAppIDsForTeam(team: currentTeam, session: authenticated)
                try Task.checkCancellation()
                guard generation == operation else { return }
                session = authenticated; team = currentTeam
                registrations = registered.sorted { $0.bundleIdentifier.localizedStandardCompare($1.bundleIdentifier) == .orderedAscending }
                selectedHost = registered.first(where: { $0.bundleIdentifier == hostID })?.identifier ?? ""
                selectedGuest = registered.first(where: { $0.bundleIdentifier == guestID })?.identifier ?? ""
                signedIn = true
                var missing: [String] = []
                if selectedHost.isEmpty { missing.append("Strata: " + hostID) }
                if selectedGuest.isEmpty { missing.append("Guest process: " + guestID) }
                if registered.isEmpty {
                    status = "Apple returned no registered App IDs for this signing team. Check SideStore's Apple ID and team. Refreshing cannot fix an account mismatch."
                } else if missing.isEmpty {
                    status = "Matching registrations found. Review both selections before applying."
                } else {
                    status = "No exact registration matched: " + missing.joined(separator: "; ") + ". Select the corresponding IDs shown in SideStore's App IDs list below. No capability has been changed."
                }
            } catch {
                if generation == operation { status = error is CancellationError ? "Cancelled." : error.localizedDescription }
            }
        }
    }
    func submitCode() {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count == 6, value.allSatisfy(\.isNumber), let callback = verification else { return }
        verification = nil; needsCode = false; callback(value); code = ""
    }
    func apply() {
        guard !busy, let session, let team, let selected = registeredTargets else { return }
        let requested = registrations.filter { selected.contains($0.identifier) }
        guard requested.count == selected.count else { return }
        busy = true; status = "Requesting capability…"
        let operation = UUID(); generation = operation
        task = Task {
            defer { if generation == operation { busy = false; task = nil } }
            var completed = 0
            do {
                let capabilities = StrataMemoryRequestPolicy.capabilities
                for appID in requested {
                    try Task.checkCancellation()
                    _ = try await AppleAPI.shared.updateAppID(appID, capabilities: capabilities, team: team, session: session)
                    completed += 1
                }
                if generation == operation { status = "Apple accepted the capability requests. Reimport and install the current Strata IPA through SideStore, keeping all extensions. A refresh alone may not retain the entitlement. Then check Installed memory permissions; this message does not confirm extra memory is active." }
            } catch {
                if generation == operation { status = "Completed \(completed) of \(requested.count) requests. " + error.localizedDescription }
            }
        }
    }
    func cancel() {
        generation = UUID(); task?.cancel(); task = nil
        let callback = verification; verification = nil; needsCode = false; callback?(nil)
        anisette?.cancel(); anisette = nil
        password = ""; code = ""; busy = false; status = "Cancelled."
    }
    func signOut() { cancel(); session = nil; team = nil; registrations = []; selectedHost = ""; selectedGuest = ""; appleID = ""; signedIn = false; status = "Signed out." }
}

struct StrataMemorySettings: View {
    @StateObject private var capability = StrataMemoryCapabilities()
    @AppStorage("StrataAnisetteServer", store: LCUtils.appGroupUserDefault) private var server = ""
    @State private var snapshot: [String: Any] = [:]
    private var signingTeam: String { snapshot["teamID"] as? String ?? "" }
    private var hostIdentity: String {
        StrataMemoryRequestPolicy.bundleIdentity(signedID: snapshot["hostSignedID"] as? String ?? "", team: signingTeam, fallback: Bundle.main.bundleIdentifier ?? "")
    }
    private var guestIdentity: String {
        StrataMemoryRequestPolicy.bundleIdentity(signedID: snapshot["guestSignedID"] as? String ?? "", team: signingTeam, fallback: snapshot["guestID"] as? String ?? "")
    }
    var body: some View {
        Form {
            Section("Installed memory permissions") {
                Label(snapshot["hostMemory"] as? Bool == true ? "Strata: extra memory allowed" : "Strata: standard memory permission", systemImage: "memorychip")
                Label(snapshot["guestMemory"] as? Bool == true ? "Guest process: extra memory requested in signature" : "Guest process: standard memory signature", systemImage: "app.connected.to.app.below.fill")
                Text("Available to Strata now: \(snapshot["availableMB"] as? UInt64 ?? (snapshot["availableMB"] as? NSNumber)?.uint64Value ?? 0) MB")
                Button("Refresh status") { snapshot = LCUtils.strataMemoryStatus() as? [String: Any] ?? [:] }
            }
            Section("Latest running-app memory sample") {
                if let sample = snapshot["guestSample"] as? [String: Any],
                   let timestamp = sample["sampledAt"] as? Double,
                   let guest = sample["guest"] as? String {
                    Text(guest).font(.headline)
                    Text("PID: \(sample["pid"] as? Int ?? 0)").font(.caption)
                    let inProcess = sample["executionMode"] as? String == "inProcess"
                    Text(inProcess ? "Normal launch: runs inside Strata's process" : "Runs in a separate guest process").font(.caption)
                    Label(sample["increasedMemoryEntitlement"] as? Bool == true ? "Running process: extra memory entitlement present" : "Running process: standard memory entitlement", systemImage: "memorychip")
                    if sample["availableReported"] as? Bool == true, let bytes = sample["availableBytes"] as? NSNumber {
                        Text("Available to running app at sample: \(bytes.uint64Value / 1_048_576) MB")
                    } else { Text("iOS did not report memory headroom for this process.") }
                    if sample["footprintReported"] as? Bool == true, let bytes = sample["footprintBytes"] as? NSNumber {
                        Text("Running app memory used at sample: \(bytes.uint64Value / 1_048_576) MB")
                    }
                    Text("Sampled: " + Date(timeIntervalSince1970: timestamp).formatted(date: .abbreviated, time: .standard)).font(.caption)
                    Button("Copy app memory report") {
                        if let data = try? JSONSerialization.data(withJSONObject: sample, options: [.prettyPrinted, .sortedKeys]) {
                            UIPasteboard.general.string = String(data: data, encoding: .utf8)
                        }
                    }
                    Text("This is a saved sample from the process running the app, not a live reservation or a fixed memory limit. Samples update every five seconds while that process can run.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Launch an app with R20, let it run briefly, then return here and tap Refresh status. Normal and Launch with JIT launches are both measured.")
                }
            }
            Section {
                if !capability.signedIn {
                    TextField("SideStore anisette server (HTTPS)", text: $server).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Signing Apple ID", text: $capability.appleID).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                    SecureField("Password", text: $capability.password)
                    Button("Sign in to Apple") { capability.signIn(server: server, signingTeam: signingTeam, hostID: hostIdentity, guestID: guestIdentity) }.disabled(capability.busy)
                } else {
                    Text("Signed Strata ID: " + capability.expectedHost).font(.footnote).textSelection(.enabled)
                    Text("Signed guest ID: " + capability.expectedGuest).font(.footnote).textSelection(.enabled)
                    Picker("Strata registration", selection: $capability.selectedHost) {
                        Text("Choose registration").tag("")
                        ForEach(capability.registrations, id: \.identifier) { registration in
                            Text(registration.name + " — " + registration.bundleIdentifier).tag(registration.identifier)
                        }
                    }
                    Picker("Guest-process registration", selection: $capability.selectedGuest) {
                        Text("Choose registration").tag("")
                        ForEach(capability.registrations, id: \.identifier) { registration in
                            Text(registration.name + " — " + registration.bundleIdentifier).tag(registration.identifier)
                        }
                    }
                    Text("Select only the Strata and LiveProcess IDs belonging to your SideStore installation. If SideStore uses one shared registration for both, select it in both fields. No IDs are created or changed until you tap Apply.").font(.footnote).foregroundStyle(.secondary)
                    Button("Apply extra memory to selected registrations") { capability.apply() }.disabled(!capability.canApply)
                    Button("Sign out") { capability.signOut() }
                }
                if capability.busy { ProgressView("Working…"); Button("Cancel") { capability.cancel() } }
                if !capability.status.isEmpty { Text(capability.status).font(.footnote).textSelection(.enabled) }
            } header: { Text("Enable extra memory") } footer: {
                Text("Use the same Apple ID and trusted anisette server as SideStore. Credentials stay in memory for this session. After applying, reinstall through SideStore and keep all extensions. iOS decides the memory available on your device.")
            }
        }
        .navigationTitle("Memory").navigationBarTitleDisplayMode(.inline)
        .onAppear { snapshot = LCUtils.strataMemoryStatus() as? [String: Any] ?? [:] }
        .onDisappear { capability.signOut() }
        .alert("Apple verification code", isPresented: $capability.needsCode) {
            TextField("6-digit code", text: $capability.code).keyboardType(.numberPad)
            Button("Continue") { capability.submitCode() }
            Button("Cancel", role: .cancel) { capability.cancel() }
        } message: { Text("Enter the verification code Apple sent to your trusted device.") }
    }
}
