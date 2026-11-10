import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

/// Shared certificate front end. Signing consumers continue through LCUtils/LCSharedUtils.
@available(iOS 16.0, *)
struct StrataIdentitySettings: View {
    @State private var selecting = false
    @State private var pending: Data?
    @State private var password = ""
    @State private var askingPassword = false
    @State private var metadata: [String: Any] = [:]
    @State private var fingerprint = ""
    @State private var status = ""
    @State private var removing = false
    @State private var secured = false
    var body: some View {
        Form {
            Section("LocalSigner · Signing identity") {
                Text("One local signing identity for Strata's existing signer and future engine adapters. Certificates do not extend provisioning expiration or grant new permissions.").font(.footnote)
                if !fingerprint.isEmpty {
                    LabeledContent("Storage", value: secured ? "Shared device-only Keychain" : "Legacy preferences")
                    LabeledContent("Team", value: metadata["teamID"] as? String ?? "Unknown")
                    if let expiry = metadata["expires"] as? Date {
                        LabeledContent("Certificate expiry", value: expiry.formatted(date: .abbreviated, time: .omitted))
                        if expiry < Date() { Label("Expired — import a current identity", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    }
                    if metadata["expires"] == nil { Text("Certificate expiry could not be read by the native parser. Verify validity in SideStore before use.").font(.caption).foregroundStyle(.secondary) }
                    Text("Identity fingerprint\n\(fingerprint)").font(.caption.monospaced()).textSelection(.enabled)
                    if !secured { Button("Move existing identity to Keychain") { adoptExisting() } }
                    Button("Remove signing identity", role: .destructive) { removing = true }
                } else { Text("No signing identity imported.").foregroundStyle(.secondary) }
                Button("Import .p12 identity") { selecting = true }
                Text("Use the identity that signed the executing app. Passwords are kept exactly as entered, including empty passwords and spaces. The vault is not included in guest backups.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Provisioning") {
                Text("Apple account permissions and profile renewal remain in bundled SideStore. Local signing can reuse a valid identity; it cannot renew an expired profile offline.").font(.footnote)
            }
            if !status.isEmpty { Section { Text(status).accessibilityIdentifier("identity.status") } }
        }
        .navigationTitle("Signing Identity").navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
        .fileImporter(isPresented: $selecting, allowedContentTypes: [.data]) { result in
            do {
                let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard url.pathExtension.lowercased() == "p12", (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 16 * 1024 * 1024 else { throw StrataPortableBackup.failure("Select a .p12 file smaller than 16 MB.") }
                pending = try Data(contentsOf: url); password = ""; askingPassword = true
            } catch { status = error.localizedDescription }
        }
        .alert("Certificate password", isPresented: $askingPassword) {
            SecureField("Password (may be empty)", text: $password)
            Button("Import") { if let pending { store(pending, password) }; pending = nil; password = "" }
            Button("Cancel", role: .cancel) { pending = nil; password = "" }
        } message: { Text("The previous identity stays available if import fails.") }
        .confirmationDialog("Remove Strata's signing identity? Existing apps and data are kept.", isPresented: $removing, titleVisibility: .visible) {
            Button("Remove identity", role: .destructive) {
                do { try LCSharedUtils.strataRemoveSigningIdentity(); clearLegacy(); refresh(); status = "Signing identity removed." }
                catch { status = error.localizedDescription }
            }
        }
    }
    private func refresh() {
        secured = LCSharedUtils.strataSigningIdentity() != nil
        guard let data = LCUtils.certificateData(), let secret = LCSharedUtils.certificatePassword() else { metadata = [:]; fingerprint = ""; return }
        metadata = LCUtils.strataCertificateMetadata(data, password: secret) as? [String: Any] ?? [:]
        fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func adoptExisting() {
        guard let data = LCUtils.certificateData(), let secret = LCSharedUtils.certificatePassword() else { return }
        store(data, secret)
    }
    private func store(_ data: Data, _ secret: String) {
        do {
            guard let info = LCUtils.strataCertificateMetadata(data, password: secret) as? [String: Any],
                  let team = info["teamID"] as? String else { throw StrataPortableBackup.failure("The certificate or password could not be read.") }
            if let installedTeam = LCSharedUtils.teamIdentifier(), !installedTeam.isEmpty, team != installedTeam { throw StrataPortableBackup.failure("This identity belongs to another signing team. Import the identity used to install Strata.") }
            if let expiry = info["expires"] as? Date, expiry <= Date() { throw StrataPortableBackup.failure("This signing certificate has expired.") }
            try LCSharedUtils.strataStoreSigningIdentity(data, password: secret)
            clearLegacy(); refresh(); status = "Identity saved. Existing Strata signing now uses the shared Keychain vault."
        } catch { status = error.localizedDescription }
    }
    private func clearLegacy() {
        for defaults in [LCUtils.appGroupUserDefault, UserDefaults.standard] {
            defaults.removeObject(forKey: "LCCertificateData"); defaults.removeObject(forKey: "LCCertificatePassword")
        }
        LCUtils.appGroupUserDefault.set(Date(), forKey: "LCCertificateUpdateDate")
    }
}
