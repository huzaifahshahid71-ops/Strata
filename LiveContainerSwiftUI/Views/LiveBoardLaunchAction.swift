import Foundation

// Shared UI preflight extracted from LCAppBannerViewController. The runtime stays in runApp.
extension LCAppModel {
    @MainActor
    func launchFromLibrary(multitask: Bool? = nil, reuseExistingWindow: Bool = true, forceJIT: Bool = false, gameMode: Bool = false, metalHUD: Bool = false) async throws {
        if (gameMode || metalHUD), #available(iOS 16.0, *), let folder = uiSelectedContainer?.folderName, MultitaskManager.isUsing(container: folder) {
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
        if gameMode {
            try appInfo.enableGameModeSupport()
            try await signApp(force: true)
        }
        var hud = LCUtils.appGroupUserDefault.dictionary(forKey: "StrataMetalHUDApps") as? [String: Bool] ?? [:]
        hud[liveBoardAppKey(self)] = metalHUD
        LCUtils.appGroupUserDefault.set(hud, forKey: "StrataMetalHUDApps")
        do { try await runApp(multitask: gameMode ? false : multitask, forceJIT: forceJIT ? true : nil) }
        catch {
            var pending = LCUtils.appGroupUserDefault.dictionary(forKey: "StrataMetalHUDApps") as? [String: Bool] ?? [:]
            pending.removeValue(forKey: liveBoardAppKey(self)); LCUtils.appGroupUserDefault.set(pending, forKey: "StrataMetalHUDApps")
            throw error
        }
    }
}
