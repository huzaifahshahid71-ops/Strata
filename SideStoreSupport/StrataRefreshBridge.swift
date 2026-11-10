import Foundation

/// Reuses the same bundled SideStore path as LiveContainer's Refresh All shortcut.
/// No Apple credentials or signing state are copied into the launcher.
@objc(StrataSideStoreRefreshBridge)
@MainActor final class StrataSideStoreRefreshBridge: NSObject {
    private static var operation: Task<Void, Never>?
    @objc(refreshWithCompletion:)
    static func refresh(completion: @escaping (String?) -> Void) {
        guard #available(iOS 17, *) else { completion("Automatic refresh requires iOS 17 or newer."); return }
        guard operation == nil else { completion("A Strata refresh is already running."); return }
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                try Task.checkCancellation()
                try await performIntentRefresh(identifier: "RefreshAllAppsWidgetIntent", mangledTypeName: "9SideStore26RefreshAllAppsWidgetIntentV", intentProgress: Progress(totalUnitCount: 100))
                try Task.checkCancellation()
                completion(nil)
            } catch { completion(error.localizedDescription) }
        }
    }
    @objc static func cancel() {
        guard let operation else { return }
        operation.cancel()
        RefreshHandler.shared.abortStrataRefresh()
    }
}
