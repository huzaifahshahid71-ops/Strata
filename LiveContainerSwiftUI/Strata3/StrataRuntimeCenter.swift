import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

@available(iOS 16.0, *)
struct StrataRuntimeCenter: View {
    let apps: [LCAppModel]
    let launch: (LCAppModel) -> Void
    let manage: (LCAppModel) -> Void
    @EnvironmentObject private var sharedModel: SharedModel
    private var guests: [LCAppModel] { apps.filter { !($0.appInfo is BuiltInSideStoreAppInfo) && (!($0.uiIsHidden) || sharedModel.isHiddenAppUnlocked) }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending } }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Strata 3.0").font(.largeTitle.bold())
                    Text("Runtime & data management").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
            Section("Execution engines") {
                Label("LiveContainer · Ready", systemImage: "shippingbox.fill")
                Text("Existing iOS launch, guest-extension JIT and multitasking paths are retained.").font(.caption).foregroundStyle(.secondary)
                if let runtime = guests.first(where: { $0.uiIs32bitEmulator }) {
                    NavigationLink("LiveExec32 · Installed") { StrataGuestDetail(app: runtime, launch: launch, manage: manage) }
                } else { Text("LiveExec32 · prepared on first 32-bit launch").foregroundStyle(.secondary) }
                NavigationLink("HostJIT-InProcess · Experimental") {
                    Form {
                        Section { Text("An opt-in cold-start host attachment is included in Strata 3.0. The supplied IPA's unknown binaries were not merged. Enable the experiment per guest below, prepare the device in JIT setup, then use Launch with JIT.")
                            Text("The comparison screenshot reports different host and extension memory budgets. It does not demonstrate in-process JIT. JIT permission is process-specific; attaching to a helper does not grant it to the host.") }
                        Section("Current fallback") { Text("The existing guest-extension path remains the default and is always used for Multitask. Experimental host startup waits at most 12 seconds for debugger attachment, then returns to the launcher on failure. EspressoU/Pong has verified in-process recompiler operation with a reported 6 GiB budget on the test iPhone 15 Pro. Other guests and devices still require testing.") }
                    }.navigationTitle("HostJIT")
                }
            }
            Section("Management") {
                NavigationLink { StrataIdentitySettings() } label: { Label("LocalSigner · Signing Identity", systemImage: "signature") }
                NavigationLink { StrataDiagnosticsView(apps: guests) } label: { Label("Runtime Diagnostics", systemImage: "waveform.path.ecg") }
            }
            Section("Guests · Files & Backups") {
                ForEach(guests, id: \.self) { app in
                    NavigationLink { StrataGuestDetail(app: app, launch: launch, manage: manage) } label: {
                        HStack { Image(uiImage: app.appInfo.iconIsDarkIcon(false) ?? UIImage()).resizable().scaledToFill().frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 9)); VStack(alignment: .leading) { Text(app.displayName); Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary).lineLimit(1) } }
                    }
                }
                if guests.isEmpty { Text("Installed guest apps will appear here.").foregroundStyle(.secondary) }
            }
        }.navigationTitle("Runtime Manager").navigationBarTitleDisplayMode(.inline)
    }
}

@available(iOS 16.0, *)
struct StrataGuestDetail: View {
    @ObservedObject var app: LCAppModel
    let launch: (LCAppModel) -> Void
    let manage: (LCAppModel) -> Void
    @State private var authorized = false
    @State private var authError = ""
    @AppStorage("StrataHostJITApps", store: LCUtils.appGroupUserDefault) private var hostJITApps = "{}"
    private var hostEnabled: Binding<Bool> {
        Binding(get: { ((try? JSONDecoder().decode([String: Bool].self, from: Data(hostJITApps.utf8))) ?? [:])[liveBoardAppKey(app)] == true }, set: { value in
            var options = (try? JSONDecoder().decode([String: Bool].self, from: Data(hostJITApps.utf8))) ?? [:]
            options[liveBoardAppKey(app)] = value
            if let data = try? JSONEncoder().encode(options), let text = String(data: data, encoding: .utf8) { hostJITApps = text }
        })
    }
    var body: some View {
        Group {
            if !app.uiIsLocked || DataManager.shared.model.isHiddenAppUnlocked || authorized { content }
            else {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill").font(.largeTitle)
                    Button("Unlock guest management") {
                        Task { do { authorized = try await LCUtils.authenticateUser() } catch { authError = error.localizedDescription } }
                    }
                    if !authError.isEmpty { Text(authError).font(.caption) }
                }.navigationTitle("Locked guest")
            }
        }
    }
    private var content: some View {
        List {
            Section("Guest") {
                LabeledContent("Identifier", value: app.bundleIdentifier)
                LabeledContent("Version", value: app.appInfo.version() ?? "Unknown")
                LabeledContent("Architecture", value: app.uiIs32bit ? "32-bit · LiveExec32" : "64-bit · LiveContainer")
                Button("Launch") { launch(app) }
                Button("App settings & launch options") { manage(app) }
            }
            Section("Experimental execution") {
                Toggle("HostJIT-InProcess", isOn: hostEnabled)
                Text("Applies to Launch with JIT using the built-in provider. Prepare device first with LocalDevVPN connected. Host startup has a 12-second attachment deadline. Disable this to return to guest-extension JIT. Multitask always uses the existing extension path.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Data containers") {
                ForEach(app.uiContainers, id: \.self) { container in
                    NavigationLink(container.name) { StrataContainerManager(app: app, container: container) }
                }
                if app.uiContainers.isEmpty { Text("Launch this app once to create its data container.").foregroundStyle(.secondary) }
                Text("Backups contain this guest's selected data container. App-group data and Keychain are separate and are not included.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle(app.displayName).navigationBarTitleDisplayMode(.inline)
    }
}

@available(iOS 16.0, *)
struct StrataContainerManager: View {
    @ObservedObject var app: LCAppModel
    @ObservedObject var container: LCContainer
    @State private var backups: [URL] = []
    @State private var busy = false
    @State private var status = ""
    @State private var importing = false
    @State private var restoreURL: URL?
    @State private var confirming = false
    private var root: URL { container.containerURL.standardizedFileURL }
    private var backupRoot: URL {
        let key = SHA256.hash(data: Data(app.bundleIdentifier.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return LCPath.docPath.appendingPathComponent("Strata3/Backups/\(key)")
    }
    private var inUse: Bool { app.isAppRunning || MultitaskManager.isUsing(container: container.folderName) || LCSharedUtils.getContainerUsingLCScheme(withFolderName: container.folderName) != nil }
    var body: some View {
        List {
            if busy { ProgressView("Working…") }
            if !status.isEmpty { Text(status).font(.footnote).accessibilityIdentifier("backup.status") }
            Section("Files") {
                NavigationLink("Browse guest data") { StrataGuestFiles(root: root, directory: root, containerName: container.folderName) }
                    .disabled(busy || inUse)
                Text("Close the guest before browsing, importing or restoring data.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Portable backups") {
                Button("Create backup") { createBackup() }.disabled(busy || inUse)
                Button("Import backup to restore…") { importing = true }.disabled(busy || inUse)
                Text("Backups are stored in Files → Strata → Strata3 → Backups. Restoring keeps the previous container as a hidden .strata-rollback folder beside it for recovery.").font(.caption).foregroundStyle(.secondary)
                ForEach(backups, id: \.self) { url in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(url.lastPathComponent).font(.caption)
                        HStack { ShareLink("Export", item: url); Spacer(); Button("Restore…") { restoreURL = url; confirming = true }.disabled(busy || inUse) }
                    }
                }
            }
        }
        .navigationTitle(container.name).navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            do { restoreURL = try result.get(); confirming = true } catch { status = error.localizedDescription }
        }
        .confirmationDialog("Restore this backup? Current guest data will be replaced, with a recovery copy retained.", isPresented: $confirming, titleVisibility: .visible) {
            Button("Restore backup", role: .destructive) { if let restoreURL { restoreBackup(restoreURL) } }
        }
    }
    private func reload() { backups = ((try? FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "stratabackup" }.sorted { $0.lastPathComponent > $1.lastPathComponent } }
    private func createBackup() {
        guard !inUse, !busy else { status = "Close the guest first."; return }
        let source = root, id = app.bundleIdentifier
        let destination = backupRoot.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).stratabackup")
        guard let groupRoot = LCSharedUtils.appGroupPath() else { status = "Shared data directory unavailable."; return }
        let lease: StrataGuestDataLease
        do { lease = try StrataGuestDataLease(container: container.folderName, groupRoot: groupRoot) }
        catch { status = error.localizedDescription; return }
        busy = true; status = ""
        Task {
            defer { lease.release() }
            do {
                try await Task.detached(priority: .userInitiated) { try StrataPortableBackup.create(root: source, bundleID: id, destination: destination) }.value
                status = "Backup created and verified while copying."
            } catch { status = error.localizedDescription }
            busy = false; reload()
        }
    }
    private func restoreBackup(_ archive: URL) {
        guard !inUse, !busy else { status = "Close the guest first."; return }
        let destination = root, id = app.bundleIdentifier
        guard let groupRoot = LCSharedUtils.appGroupPath() else { status = "Shared data directory unavailable."; return }
        let lease: StrataGuestDataLease
        do { lease = try StrataGuestDataLease(container: container.folderName, groupRoot: groupRoot) }
        catch { status = error.localizedDescription; return }
        busy = true; status = ""
        Task {
            defer { lease.release() }
            let scoped = archive.startAccessingSecurityScopedResource(); defer { if scoped { archive.stopAccessingSecurityScopedResource() } }
            do {
                try await Task.detached(priority: .userInitiated) { try StrataPortableBackup.restore(archive: archive, root: destination, bundleID: id) }.value
                status = "Restored. The previous data container remains in its recovery folder."
            } catch { status = error.localizedDescription }
            busy = false; reload()
        }
    }
}

@available(iOS 16.0, *)
struct StrataGuestFiles: View {
    let root: URL
    let directory: URL
    let containerName: String
    @State private var entries: [URL] = []
    @State private var status = ""
    @State private var importing = false
    @State private var busy = false
    var body: some View {
        List {
            ForEach(entries, id: \.self) { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                if values?.isSymbolicLink == true { Label(url.lastPathComponent + " · link", systemImage: "link").foregroundStyle(.secondary) }
                else if values?.isDirectory == true {
                    NavigationLink { StrataGuestFiles(root: root, directory: url, containerName: containerName) } label: { Label(url.lastPathComponent, systemImage: "folder") }
                } else {
                    NavigationLink { StrataGuestFilePreview(root: root, file: url) } label: {
                        HStack { Label(url.lastPathComponent, systemImage: "doc"); Spacer(); Text(ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if !status.isEmpty { Text(status).font(.footnote) }
            if busy { ProgressView() }
        }
        .navigationTitle(directory == root ? "Guest files" : directory.lastPathComponent).navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Import file") { importing = true }.disabled(busy) }
        .onAppear { reload() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            do {
                let source = try result.get()
                let target = directory.appendingPathComponent(source.lastPathComponent)
                guard StrataPortableBackup.safePath(source.lastPathComponent), !FileManager.default.fileExists(atPath: target.path) else { throw StrataPortableBackup.failure("A file with this name already exists. Rename it before importing.") }
                _ = try StrataPortableBackup.confined(directory, to: root)
                guard let groupRoot = LCSharedUtils.appGroupPath() else { throw StrataPortableBackup.failure("Shared data directory unavailable.") }
                let lease = try StrataGuestDataLease(container: containerName, groupRoot: groupRoot)
                busy = true
                Task {
                    defer { lease.release() }
                    let scoped = source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                    do {
                        let sourceValues = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                        guard sourceValues.isRegularFile == true, sourceValues.isSymbolicLink != true else { throw StrataPortableBackup.failure("Import a regular file, not a link or directory.") }
                        try await Task.detached(priority: .userInitiated) { try FileManager.default.copyItem(at: source, to: target) }.value
                        status = "File imported."
                    } catch { status = error.localizedDescription }
                    busy = false; reload()
                }
            } catch { status = error.localizedDescription }
        }
    }
    private func reload() {
        do { _ = try StrataPortableBackup.confined(directory, to: root); entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending } }
        catch { entries = []; status = error.localizedDescription }
    }
}
@available(iOS 16.0, *)
private struct StrataGuestFilePreview: View {
    let root: URL
    let file: URL
    @State private var text = "Loading…"
    @State private var valid = false
    var body: some View {
        ScrollView { Text(text).font(.system(.footnote, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).padding().textSelection(.enabled) }
            .navigationTitle(file.lastPathComponent).navigationBarTitleDisplayMode(.inline)
            .toolbar { if valid { ShareLink("Export", item: file) } }
            .task {
                do {
                    _ = try StrataPortableBackup.confined(file, to: root)
                    let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
                    let bytes = try handle.read(upToCount: 256 * 1024) ?? Data()
                    text = String(data: bytes, encoding: .utf8) ?? "Binary file. Use Export to open it in another app."
                    if (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > bytes.count { text += "\n\nPreview limited to 256 KB." }
                    valid = true
                } catch { text = error.localizedDescription }
            }
    }
}

@available(iOS 16.0, *)
struct StrataDiagnosticsView: View {
    let apps: [LCAppModel]
    @State private var report: URL?
    @State private var message = ""
    var body: some View {
        Form {
            Section {
                Text("Exports current host memory, the latest saved guest memory/Metal sample and guest identifiers. Pairing files, signing identities, Apple credentials, arbitrary guest files and raw JIT logs are excluded.").font(.footnote)
                Button("Create diagnostic report") { create() }
                if let report { ShareLink("Export diagnostic report", item: report) }
                if !message.isEmpty { Text(message).font(.caption) }
            }
        }.navigationTitle("Runtime Diagnostics").navigationBarTitleDisplayMode(.inline)
    }
    private func create() {
        let raw = LCUtils.strataMemoryStatus() as? [String: Any] ?? [:]
        let allowed = ["usedMB", "availableMB", "hostMemory", "hostAddress", "physicalMB", "increasedMemoryEntitlement", "getTaskAllow", "hostSignedID", "guestSignedID"]
        var result: [String: Any] = ["schema": 1, "version": "3.0.0", "created": Date().timeIntervalSince1970,
            "host": raw.filter { allowed.contains($0.key) }, "guests": apps.map { ["name": $0.displayName, "bundleID": $0.bundleIdentifier, "is32bit": $0.uiIs32bit, "JITRequested": $0.uiIsJITNeeded] as [String: Any] },
            "features": ["guestExtensionJIT": "existing", "hostInProcessJIT": "experimentalOptInUnverified", "huskEmbeddedAOT": "notIntegrated", "sharedIdentityVault": "implemented", "frameGeneration": "experimental2x"]]
        if let guest = raw["guestSample"] as? [String: Any] {
            let fields = ["pid", "guest", "executionMode", "availableBytes", "footprintBytes", "sampledAt", "increasedMemoryEntitlement", "availableReported", "footprintReported", "jitEnabled", "debuggerAttached"]
            result["latestGuest"] = guest.filter { fields.contains($0.key) }
        }
        if let group = LCSharedUtils.appGroupPath(), let bytes = try? Data(contentsOf: group.appendingPathComponent("Library/StrataFrameGen/latest.json")), let fg = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
            let fields = ["pid", "sampledAt", "nativeGPUFPS", "generatedGPUFPS", "computedFPS", "presentedFPS", "displayMaximumHz", "benchmark", "revision"]
            result["latestMetal"] = fg.filter { fields.contains($0.key) }
        }
        if let group = LCSharedUtils.appGroupPath(), let data = try? Data(contentsOf: group.appendingPathComponent("Library/StrataDiagnostics/host-jit.json")), let hostJIT = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            result["hostJIT"] = hostJIT.filter { ["schema", "pid", "executionMode", "debuggerAttached", "codeSigningDebugged", "JITVerified", "sampledAt"].contains($0.key) }
        }
        do {
            let url = LCPath.docPath.appendingPathComponent("Strata3/Diagnostics/\(Int(Date().timeIntervalSince1970)).json")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
            report = url; message = "Saved in Files → Strata → Strata3 → Diagnostics. Guest measurements may be from an earlier launch; compare their timestamps."
        } catch { message = error.localizedDescription }
    }
}
