import Foundation

extension LCAppModel {
    private var scriptModeKey: String { "StrataJITScriptMode:" + (uiIsShared ? "shared:" : "local:") + (appInfo.relativeBundlePath ?? bundleIdentifier) }
    var strataJITScriptMode: StrataJITScriptMode {
        get { StrataJITScriptMode(rawValue: LCUtils.appGroupUserDefault.string(forKey: scriptModeKey) ?? "") ?? .automatic }
        set { objectWillChange.send(); LCUtils.appGroupUserDefault.set(newValue.rawValue, forKey: scriptModeKey) }
    }
    var resolvedJITScript: String? {
        StrataJITScriptPolicy.resolve(mode: strataJITScriptMode, identifier: bundleIdentifier, imported: jitLaunchScriptJs, universal: LCUtils.base64EncodedUniversalJITScript())
    }
}
