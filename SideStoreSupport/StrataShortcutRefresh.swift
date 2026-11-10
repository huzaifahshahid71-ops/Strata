import Foundation
import AppIntents
import Network

@available(iOS 17, *)
private enum StrataShortcutRefreshState {
    static var defaults: UserDefaults { UserDefaults(suiteName: LCSharedUtils.appGroupID()) ?? .standard }
    static func due() -> Bool {
        let d = defaults, now = Date()
        return StrataAutomationPolicy.due(enabled: d.bool(forKey: "StrataAutoRefreshEnabled"),
            days: d.object(forKey: "StrataAutoRefreshDays") as? Int ?? 3,
            success: d.object(forKey: "StrataRefreshLastSuccess") as? Date,
            attempt: d.object(forKey: "StrataRefreshLastAttempt") as? Date,
            runningUntil: max(d.double(forKey: "StrataShortcutRefreshRunningUntil"), d.double(forKey: "StrataNativeRefreshRunningUntil")), now: now)
    }
}

@available(iOS 17, *)
public struct StrataRefreshDueIntent: AppIntent {
    public static var title: LocalizedStringResource = "Is Strata Refresh Due?"
    public static var description = IntentDescription("Checks the enabled 1–5 day schedule before your Shortcut connects LocalDevVPN.")
    public static var openAppWhenRun = false
    public init() {}
    public func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        guard StrataShortcutRefreshState.due() else { return .result(value: false) }
        let allowed = await StrataAutomationNetwork.allowed()
        return .result(value: allowed)
    }
}

@available(iOS 17, *)
public struct StrataScheduledRefreshIntent: AppIntent {
    public static var title: LocalizedStringResource = "Run Strata Scheduled Refresh"
    public static var description = IntentDescription("Waits for bundled SideStore to finish. Returns result text instead of throwing a signing error, so your Shortcut can run its VPN cleanup step. Connect LocalDevVPN first.")
    public static var openAppWhenRun = false
    public init() {}
    @MainActor public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let d = StrataShortcutRefreshState.defaults
        guard StrataShortcutRefreshState.due() else { return .result(value: "Skipped: Strata refresh is not due, disabled or recently attempted.") }
        guard await StrataAutomationNetwork.allowed() else { return .result(value: "Skipped: waiting for Wi-Fi; cellular attempts are disabled or network status is unavailable.") }
        guard StrataShortcutRefreshState.due() else { return .result(value: "Skipped: another refresh started while checking the network.") }
        guard UserDefaults.sideStoreExist() else { return .result(value: "Failed: bundled SideStore is unavailable.") }
        d.set(Date(), forKey: "StrataRefreshLastAttempt")
        d.set(Date().timeIntervalSince1970 + 360, forKey: "StrataShortcutRefreshRunningUntil")
        d.set("Refreshing through Shortcuts and bundled SideStore…", forKey: "StrataRefreshStatus")
        defer { d.removeObject(forKey: "StrataShortcutRefreshRunningUntil") }
        let run = UUID().uuidString
        d.set(run, forKey: "StrataShortcutRefreshToken")
        var timedOut = false
        let deadline = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 120_000_000_000) } catch { return }
            guard !Task.isCancelled, d.string(forKey: "StrataShortcutRefreshToken") == run else { return }
            timedOut = true
            RefreshHandler.shared.abortStrataRefresh()
        }
        defer { deadline.cancel(); if d.string(forKey: "StrataShortcutRefreshToken") == run { d.removeObject(forKey: "StrataShortcutRefreshToken") } }
        let result: String
        do {
            try await performIntentRefresh(identifier: "RefreshAllAppsWidgetIntent", mangledTypeName: "9SideStore26RefreshAllAppsWidgetIntentV", intentProgress: Progress(totalUnitCount: 100))
            try Task.checkCancellation()
            d.set(Date(), forKey: "StrataRefreshLastSuccess")
            result = "Refreshed: SideStore confirmed all apps refreshed successfully."
        } catch {
            result = timedOut ? "Failed: SideStore refresh timed out. Check VPN, pairing and account status." : "Failed: " + error.localizedDescription
        }
        d.set(result, forKey: "StrataRefreshStatus")
        return .result(value: result)
    }
}

@available(iOS 17, *)
public struct StrataVPNCanDisconnectIntent: AppIntent {
    public static var title: LocalizedStringResource = "Can Disconnect Strata VPN?"
    public static var description = IntentDescription("Checks whether Strata still has an active JIT or scheduled refresh session. Does not detect VPN use by other apps.")
    public static var openAppWhenRun = false
    public init() {}
    public func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let d = StrataShortcutRefreshState.defaults, now = Date().timeIntervalSince1970
        let owner = Int32(d.integer(forKey: "StrataJITVPNOwnerPID"))
        let alive = owner > 0 && (kill(owner, 0) == 0 || errno == EPERM)
        return .result(value: StrataAutomationPolicy.mayDisconnect(jitProcessAlive: alive,
            jitUntil: d.double(forKey: "StrataJITVPNActiveUntil"), refreshUntil: max(d.double(forKey: "StrataShortcutRefreshRunningUntil"), d.double(forKey: "StrataNativeRefreshRunningUntil")), now: Date(timeIntervalSince1970: now)))
    }
}

@available(iOS 17, *)
private final class StrataAutomationNetwork {
    private let lock = NSLock()
    private var finished = false
    private let monitor = NWPathMonitor()
    private let completion: (Bool) -> Void
    private init(completion: @escaping (Bool) -> Void) { self.completion = completion }
    private func finish(_ allowed: Bool) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true; lock.unlock()
        monitor.pathUpdateHandler = nil
        monitor.cancel(); completion(allowed)
    }
    static func allowed() async -> Bool {
        if StrataShortcutRefreshState.defaults.bool(forKey: "StrataAutoRefreshCellular") { return true }
        return await withCheckedContinuation { continuation in
            let check = StrataAutomationNetwork { continuation.resume(returning: $0) }
            check.monitor.pathUpdateHandler = { path in check.finish(path.status == .satisfied && !path.usesInterfaceType(.cellular)) }
            check.monitor.start(queue: DispatchQueue(label: "Strata.Automation.Network"))
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { check.finish(false) }
        }
    }
}

// Stable text gates avoid locale-dependent Boolean serialization in premade workflows.
@available(iOS 17, *)
public struct StrataRefreshTextGateIntent: AppIntent {
    public static var title: LocalizedStringResource = "Strata Refresh Gate (Text)"
    public static var openAppWhenRun = false
    public init() {}
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard StrataShortcutRefreshState.due() else { return .result(value: "SKIP") }
        return .result(value: await StrataAutomationNetwork.allowed() ? "RUN" : "SKIP")
    }
}
@available(iOS 17, *)
public struct StrataDisconnectTextGateIntent: AppIntent {
    public static var title: LocalizedStringResource = "Strata Disconnect Gate (Text)"
    public static var openAppWhenRun = false
    public init() {}
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let d = StrataShortcutRefreshState.defaults, now = Date().timeIntervalSince1970
        let owner = Int32(d.integer(forKey: "StrataJITVPNOwnerPID"))
        let alive = owner > 0 && (kill(owner, 0) == 0 || errno == EPERM)
        let safe = StrataAutomationPolicy.mayDisconnect(jitProcessAlive: alive, jitUntil: d.double(forKey: "StrataJITVPNActiveUntil"), refreshUntil: max(d.double(forKey: "StrataShortcutRefreshRunningUntil"), d.double(forKey: "StrataNativeRefreshRunningUntil")), now: Date(timeIntervalSince1970: now))
        return .result(value: safe ? "RUN" : "SKIP")
    }
}
