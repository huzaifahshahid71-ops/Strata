import Foundation

// Shared UI preflight extracted from LCAppBannerViewController. The runtime stays in runApp.
extension LCAppModel {
    /// Shared-defaults key holding one-shot Metal HUD requests consumed by LCBootstrap on the next guest launch.
    private static let metalHUDRequestsKey = "StrataMetalHUDApps"

    /// Launches the app from the library.
    /// The stored per-app preferences ("Launch with JIT", "Launch with Game Mode", "Launch with Metal HUD")
    /// are always applied. `forceJIT`, `gameMode` and `metalHUD` are quick overrides from the context menus
    /// and are combined with the stored preferences, so every enabled option takes effect together.
    @MainActor
    func launchFromLibrary(multitask: Bool? = nil, reuseExistingWindow: Bool = true, forceJIT: Bool = false, gameMode: Bool = false, metalHUD: Bool = false) async throws {
        let isBuiltInSideStore = appInfo is BuiltInSideStoreAppInfo
        let useGameMode = gameMode || (!isBuiltInSideStore && appInfo.launchWithGameMode)
        let useMetalHUD = metalHUD || (!isBuiltInSideStore && appInfo.launchWithMetalHUD)
        let requiresFreshLaunch = gameMode || metalHUD

        // Game Mode / Metal HUD overrides need a fresh guest process; a normal launch simply brings the running window back.
        if requiresFreshLaunch, #available(iOS 16.0, *), let folder = uiSelectedContainer?.folderName, MultitaskManager.isUsing(container: folder) {
            throw "Close this running app from Strata controls, then choose the launch option again."
        }
        if #available(iOS 16.0, *), reuseExistingWindow,
           let folder = uiSelectedContainer?.folderName,
           MultitaskManager.isUsing(container: folder) {
            var found = false
            if #available(iOS 16.1, *) {
                found = MultitaskWindowManager.openExistingAppWindow(dataUUID: folder)
            }
            if !found { found = MultitaskDockManager.shared.bringMultitaskViewToFront(uuid: folder) }
            if found { return }
        }
        if appInfo.isLocked && !DataManager.shared.model.isHiddenAppUnlocked {
            guard try await LCUtils.authenticateUser() else { return }
        }
        // Declaring Game Mode support edits Info.plist, so re-sign only when the keys are not present yet.
        if useGameMode && !appInfo.isGameModeSupportDeclared {
            try appInfo.enableGameModeSupport()
            try await signApp(force: true)
        }
        if useMetalHUD {
            setMetalHUDRequest(true)
        } else {
            setMetalHUDRequest(nil)
        }
        do {
            // Game Mode requests a fullscreen launch; JIT keeps following the stored preference unless forced.
            try await runApp(multitask: useGameMode ? false : multitask, forceJIT: forceJIT ? true : nil)
        } catch {
            if useMetalHUD { setMetalHUDRequest(nil) }
            throw error
        }
    }

    /// Stores (or clears when `nil`) the one-shot Metal HUD request for this app without writing when already unset.
    private func setMetalHUDRequest(_ enabled: Bool?) {
        let defaults = LCUtils.appGroupUserDefault
        let key = liveBoardAppKey(self)
        var requests = defaults.dictionary(forKey: Self.metalHUDRequestsKey) as? [String: Bool] ?? [:]
        if enabled == true {
            requests[key] = true
            defaults.set(requests, forKey: Self.metalHUDRequestsKey)
        } else if requests[key] != nil {
            requests.removeValue(forKey: key)
            defaults.set(requests, forKey: Self.metalHUDRequestsKey)
        }
    }
}
