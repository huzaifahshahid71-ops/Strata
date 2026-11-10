import SwiftUI
import BackgroundTasks
import Network

@MainActor final class StrataAutoRefresh: ObservableObject {
    static let shared = StrataAutoRefresh()
    static let identifier = "com.strata.sidestore.refresh"
    private let defaults = LCUtils.appGroupUserDefault
    @Published var showReminder = false
    @Published private(set) var reminderMessage = ""
    private var lastPrompt: Date?
    var installedExpiry: Date? { StrataRefreshExpiry.installedExpiry() }
    @Published private(set) var busy = false
    @Published private(set) var status: String
    private var token: UUID?
    private var watchdog: Task<Void, Never>?
    private var backgroundTask: BGTask?
    private let network = NWPathMonitor()
    private var path: NWPath?
    var enabled: Bool { defaults.object(forKey: "StrataAutoRefreshEnabled") as? Bool ?? true }
    var days: Int { StrataRefreshPolicy.intervalDays(defaults.object(forKey: "StrataAutoRefreshDays") as? Int ?? 3) }
    var lastSuccess: Date? { defaults.object(forKey: "StrataRefreshLastSuccess") as? Date }
    var nextDue: Date { StrataRefreshPolicy.due(lastSuccess: lastSuccess, days: days) }
    private var lastAttempt: Date? { defaults.object(forKey: "StrataRefreshLastAttempt") as? Date }
    private init() {
        let previous = LCUtils.appGroupUserDefault.string(forKey: "StrataRefreshStatus") ?? "No refresh attempted yet."
        status = previous.hasPrefix("Refreshing through") ? "The previous refresh did not return a result. Check SideStore's expiry date or refresh again." : previous
        network.pathUpdateHandler = { [weak self] path in Task { @MainActor in self?.path = path } }
        network.start(queue: DispatchQueue(label: "Strata.Refresh.Network"))
    }
    func register() {
        // Previous builds requested background refresh. This release prompts in the foreground.
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { task in task.setTaskCompleted(success: false) }
    }
    func settingsChanged() {
        objectWillChange.send()
        if enabled { schedule(); checkDue() }
        else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
            if busy { cancel(message: "Automatic refresh was turned off.") }
        }
    }
    func reloadStatus() {
        if let value = defaults.string(forKey: "StrataRefreshStatus"), !busy { status = value }
        objectWillChange.send()
    }
    func checkDue() {
        reloadStatus()
        guard enabled, !busy, !showReminder, UserDefaults.sideStoreExist(),
              !DataManager.shared.model.isJITModalOpen,
              defaults.double(forKey: "StrataShortcutRefreshRunningUntil") < Date().timeIntervalSince1970,
              Date().timeIntervalSince(lastPrompt ?? .distantPast) > 6 * 3600,
              defaults.double(forKey: "StrataRefreshSnoozedUntil") < Date().timeIntervalSince1970 else { return }
        let expiry = installedExpiry
        guard StrataRefreshExpiry.shouldRemind(now: Date(), expiry: expiry, lastSuccess: lastSuccess, intervalDays: days) else { return }
        if let expiry {
            let hours = max(0, Int(expiry.timeIntervalSinceNow / 3600))
            reminderMessage = hours < 48 ? "Strata's current signing expires in approximately \(hours) hours. Refresh now to keep it available." : "Your refresh interval is due. Strata's current signing expires \(expiry.formatted())."
        } else {
            reminderMessage = "Your refresh interval is due. The installed expiry could not be read; check SideStore's expiry date."
        }
        reminderMessage += defaults.bool(forKey: "StrataVPNAutomationSetupConfirmed") ? " Refresh runs Set VPN to connect LocalDevVPN and refresh through bundled SideStore." : " Set up the supplied Set VPN Shortcut once, then Refresh can connect LocalDevVPN and refresh through SideStore."
        lastPrompt = Date(); showReminder = true
    }
    func snooze() { defaults.set(Date().addingTimeInterval(6 * 3600).timeIntervalSince1970, forKey: "StrataRefreshSnoozedUntil") }
    func launchRefreshShortcut() {
        showReminder = false
        guard defaults.bool(forKey: "StrataVPNAutomationSetupConfirmed") else {
            setStatus("Set up Set VPN in Refresh settings, then tap Refresh now.")
            NotificationCenter.default.post(name: Notification.Name("StrataOpenRefreshSetup"), object: nil)
            return
        }
        let url = URL(string: "shortcuts://run-shortcut?name=Set%20VPN")!
        UIApplication.shared.open(url, options: [:]) { success in
            if !success { Task { @MainActor in self.setStatus("Could not open Shortcuts. Check that Set VPN is installed.") } }
        }
    }
    func schedule() { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier) }
    func run(manual: Bool) {
        guard manual else { checkDue(); return }
        guard !busy else { return }
        guard defaults.double(forKey: "StrataShortcutRefreshRunningUntil") < Date().timeIntervalSince1970 else {
            setStatus("A scheduled Shortcut refresh is already active."); return
        }
        guard #available(iOS 17, *), UserDefaults.sideStoreExist() else {
            finishWithoutStarting("Install Strata + SideStore with all extensions on iOS 17 or newer."); return
        }
        if !manual && Date() < nextDue { finishWithoutStarting("Next refresh is not due yet."); return }
        defaults.set(Date(), forKey: "StrataRefreshLastAttempt")
        if defaults.bool(forKey: "StrataAutoRefreshCellular") == false, path?.usesInterfaceType(.cellular) == true {
            finishWithoutStarting("Waiting for Wi-Fi. Enable cellular attempts to use mobile data."); return
        }
        busy = true
        defaults.set(Date().timeIntervalSince1970 + 150, forKey: "StrataNativeRefreshRunningUntil")
        let current = UUID(); token = current
        setStatus("Refreshing through bundled SideStore… Keep LocalDevVPN connected.")
        watchdog = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 120_000_000_000) } catch { return }
            guard self.token == current else { return }
            self.cancel(message: "SideStore refresh timed out. Check VPN, pairing and your SideStore account, then retry.")
        }
        LCUtils.strataRefreshSideStore { error in
            Task { @MainActor in
                guard self.token == current else { return }
                self.complete(error: error)
            }
        }
    }
    func cancel(message: String) {
        guard busy else { return }
        // Clear our token before cancellation can deliver a late completion.
        complete(error: message)
        LCUtils.strataCancelSideStoreRefresh()
    }
    private func complete(error: String?) {
        token = nil; watchdog?.cancel(); watchdog = nil; busy = false
        defaults.removeObject(forKey: "StrataNativeRefreshRunningUntil")
        if let error { setStatus(error) }
        else { defaults.set(Date(), forKey: "StrataRefreshLastSuccess"); setStatus("SideStore reported that all apps refreshed successfully.") }
        let task = backgroundTask; backgroundTask = nil
        task?.expirationHandler = nil
        task?.setTaskCompleted(success: error == nil)
        schedule()
    }
    private func finishWithoutStarting(_ message: String) {
        setStatus(message)
        let task = backgroundTask; backgroundTask = nil
        task?.expirationHandler = nil
        task?.setTaskCompleted(success: false)
        schedule()
    }
    private func setStatus(_ value: String) { status = value; defaults.set(value, forKey: "StrataRefreshStatus") }
}

struct StrataAutoRefreshSettings: View {
    @ObservedObject private var refresh = StrataAutoRefresh.shared
    @AppStorage("StrataAutoRefreshEnabled", store: LCUtils.appGroupUserDefault) private var enabled = true
    @AppStorage("StrataAutoRefreshDays", store: LCUtils.appGroupUserDefault) private var days = 3
    @AppStorage("StrataAutoRefreshCellular", store: LCUtils.appGroupUserDefault) private var cellular = false
    @AppStorage("StrataVPNAutomationSetupConfirmed", store: LCUtils.appGroupUserDefault) private var automationReady = false
    @State private var setup = false
    var body: some View {
        Form {
            Section {
                Toggle("Remind me when refresh is due", isOn: Binding(get: { enabled }, set: { value in
                    enabled = value
                }))
                Button(automationReady ? "Edit VPN Shortcut setup" : "Set up VPN Shortcut") { setup = true }
                Picker("Refresh every", selection: $days) {
                    ForEach(1...5, id: \.self) { value in Text(value == 1 ? "1 day" : "\(value) days").tag(value) }
                }
                Toggle("Allow cellular attempts", isOn: $cellular)
            } footer: {
                Text("When Strata opens, it checks your signing expiry and selected interval. You choose Refresh or Later. Refresh uses the supplied Set VPN Shortcut; a daily automation is optional.")
            }
            Section("Refresh status") {
                Text(refresh.status).textSelection(.enabled).accessibilityIdentifier("refresh.status")
                if let date = refresh.installedExpiry { LabeledContentCompat(title: "Installed signing expires", date: date) }
                if let date = refresh.lastSuccess { LabeledContentCompat(title: "Last successful refresh", date: date) }
                if enabled { LabeledContentCompat(title: "Next requested refresh", date: max(refresh.nextDue, .now)) }
                Button(refresh.busy ? "Refreshing…" : "Refresh now") { refresh.launchRefreshShortcut() }.disabled(refresh.busy)
                if refresh.busy { Button("Cancel refresh", role: .cancel) { refresh.cancel(message: "Refresh cancelled.") } }
            }
            Section("Mobile data") {
                Text("Cellular attempts are passed to SideStore without a Wi-Fi restriction. SideStore's installed version and connection setup must support cellular refresh. Configure its Cellular Refresh feature and required Shortcuts in SideStore when available; this switch does not change those settings or your VPN addresses.")
            }
        }
        .navigationTitle("Refresh").navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh.reloadStatus() }
        .sheet(isPresented: $setup) { StrataVPNAutomationGuide {
            automationReady = true; enabled = true; refresh.settingsChanged(); setup = false
        } }
        .onChange(of: enabled) { _ in refresh.settingsChanged() }
        .onChange(of: days) { _ in refresh.settingsChanged() }
        .onChange(of: cellular) { _ in refresh.settingsChanged() }
    }
}
private struct LabeledContentCompat: View {
    let title: String
    let date: Date
    var body: some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.subheadline).foregroundStyle(.secondary); Text(date, style: .date); Text(date, style: .time) } }
}
