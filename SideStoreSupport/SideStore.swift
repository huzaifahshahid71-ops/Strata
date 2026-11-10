//
//  SideStore.swift
//  SideStoreSupport
//
//  Created by s s on 2025/7/20.
//

import Foundation
import AppIntents
import UserNotifications

@available(iOS 17.0, *)
func performIntentRefresh(identifier: String, mangledTypeName: String, intentProgress: Progress) async throws {
    intentProgress.totalUnitCount = 100
    if UserDefaults.isSideStore() {
        try await SideStoreIntentCaller.shared.callRefreshIntent(mangledTypeName: mangledTypeName)
    } else {
        RefreshHandler.shared.progress = intentProgress
        try await RefreshHandler.shared.startRefresh(identifier: identifier, mangledName: mangledTypeName)
    }
}

@available(iOS 17.0, *)
public struct RefreshAllAppsWidgetIntent: AppIntent, ProgressReportingIntent
{
    public static var title: LocalizedStringResource { "Refresh Apps via Widget" }
    public static var isDiscoverable: Bool { false } // Don't show in Shortcuts or Spotlight.
    
    public init() {}
    
    public func perform() async throws -> some IntentResult
    {
        try await performIntentRefresh(identifier: "RefreshAllAppsWidgetIntent", mangledTypeName: "9SideStore26RefreshAllAppsWidgetIntentV", intentProgress: progress)
        return .result()
    }
}

@available(iOS 17.0, *)
public struct RefreshAllAppsIntent: AppIntent, CustomIntentMigratedAppIntent, PredictableIntent, ProgressReportingIntent, ForegroundContinuableIntent
{
    public static let intentClassName = "RefreshAllIntent"
    
    public static var title: LocalizedStringResource = "Refresh All Apps"
    public static var description = IntentDescription("Refreshes your sideloaded apps to prevent them from expiring.")
    
    public init() {}
    
    public static var parameterSummary: some ParameterSummary {
        Summary("Refresh All Apps")
    }
    
    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction {
            DisplayRepresentation(
                title: "Refresh All Apps",
                subtitle: ""
            )
        }
    }
    
    public func perform() async throws -> some IntentResult & ProvidesDialog
    {
        let preferences = UserDefaults(suiteName: LCSharedUtils.appGroupID()) ?? .standard
        preferences.set(Date(), forKey: "StrataRefreshLastAttempt")
        do {
            try await performIntentRefresh(identifier: "RefreshAllIntent", mangledTypeName: "9SideStore20RefreshAllAppsIntentV", intentProgress: progress)
            preferences.set(Date(), forKey: "StrataRefreshLastSuccess")
            preferences.set("SideStore confirmed all apps refreshed successfully.", forKey: "StrataRefreshStatus")
            return .result(dialog: "All apps have been refreshed.")
        } catch {
            preferences.set("Refresh failed: " + error.localizedDescription, forKey: "StrataRefreshStatus")
            throw error
        }
    }
    
}


class RefreshHandler: NSObject, RefreshServer {
    var c: UnsafeContinuation<(), any Error>? = nil
    var launchContinuation: UnsafeContinuation<(), any Error>? = nil
    var progress: Progress? = nil
    var listener: NSXPCListener? = nil
    var sideStorePid: Int32 = 0
    var client: RefreshClient? = nil
    var ext: NSExtension? = nil
    private var launchID: UUID?
    private var connected: NSXPCConnection?
    private var hasFinishedLaunching = false
    
    static var shared = RefreshHandler()
    
    @MainActor func startRefresh(identifier: String, mangledName: String) async throws {
        try Task.checkCancellation()
        if sideStorePid <= 0 || getpgid(sideStorePid) <= 0, let c {
            c.resume(throwing: NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Built-in SideStore quit unexpectedly"]))
            self.c = nil
        }
        
        if c != nil {
            throw NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Another refresh task is in progress."])
        }
        
        if listener == nil {
            guard let listener = startAnonymousListener(self) else {
                throw NSError(domain: "SideStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to create the SideStore refresh connection."])
            }
            self.listener = listener
        }
        guard let listener = self.listener else {
            throw NSError(domain: "SideStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "SideStore refresh connection is unavailable."])
        }

        // launch SideStore if it's not running
        if (sideStorePid <= 0 || getpgid(sideStorePid) <= 0) && launchContinuation == nil {
            let lcHome = String(cString:getenv("LC_HOME_PATH"))
            let sideStoreHomeURL = URL(fileURLWithPath: lcHome).appendingPathComponent("Documents/SideStore")
            let bookmarkData = bookmarkForURL(sideStoreHomeURL)!

            // start LiveProcess
            let extensionItem = NSExtensionItem()
            extensionItem.userInfo = [
                "selected": "builtinSideStore",
                "bookmarks": [bookmarkData],
                "endpoint": listener.endpoint
            ]

            guard let liveProcessURL = UserDefaults.lcMainBundle().builtInPlugInsURL?.appendingPathComponent("LiveProcess.appex"),
                  let liveProcessBundle = Bundle(url: liveProcessURL)
            else {
                NSLog("Unable to locate LiveProcess bundle")
                throw NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to locate LiveProcess bundle. To use the Refresh All Apps shortcut, reinstall LiveContainer+SideStore with LiveProcess installed. If you use SideStore, choose \"Keep App Extensions (Use Main Profile)\". If you use PlumeImpactor, choose \"Only Register Main Bundle\". For other sideloaders, select keep all extensions, i.e. DO NOT Remove any extension."])
            }
            
            var ext : NSExtension?
            do {
                ext = try NSExtension(identifier: liveProcessBundle.bundleIdentifier)
            } catch {
                NSLog("Failed to start extension \(error)")
                throw NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to start extension \(error). To use the Refresh All Apps shortcut, reinstall LiveContainer+SideStore with LiveProcess installed. If you use SideStore, choose \"Keep App Extensions (Use Main Profile)\". If you use Impactor, choose \"Only Register Main Bundle\". For other sideloaders, select keep all extensions, i.e. DO NOT Remove any extension."])
            }
            guard let ext else {
                throw NSError(domain: "SideStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "SideStore refresh extension is unavailable."])
            }
            self.ext = ext
            
            let currentLaunch = UUID(); launchID = currentLaunch; hasFinishedLaunching = false
            ext.setRequestInterruptionBlock { _ in
                DispatchQueue.main.async {
                    guard self.launchID == currentLaunch else { return }
                    let running = self.c, launching = self.launchContinuation
                    self.c = nil; self.launchContinuation = nil; self.sideStorePid = 0
                    self.launchID = nil; self.hasFinishedLaunching = false
                    self.connected?.invalidate(); self.connected = nil; self.client = nil
                    let error = NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Built-in SideStore quit unexpectedly"])
                    running?.resume(throwing: error)
                    launching?.resume(throwing: error)
                }
            }

            let uuid = await ext.beginRequest(withInputItems: [extensionItem])
            if Task.isCancelled { ext._kill(9); throw CancellationError() }
            sideStorePid = ext.pid(forRequestIdentifier: uuid)
            
            try Task.checkCancellation()
            try await withUnsafeThrowingContinuation { c in
                if self.hasFinishedLaunching { c.resume(); return }
                self.launchContinuation = c
                DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
                    if self.launchID == currentLaunch, let c = self.launchContinuation {
                        c.resume(throwing: NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Built-in SideStore failed to start in reasonable time"]))
                        self.launchContinuation = nil
                        ext._kill(9)
                    }
                }
            }
        }
        try Task.checkCancellation()
        guard let client = self.client else {
            throw NSError(domain: "SideStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "SideStore did not establish its refresh connection."])
        }
        try await withUnsafeThrowingContinuation { c in
            self.c = c
            client.refreshAllApps(withIdentifier: identifier, mangledTypeName: mangledName)
        }
        
    }
    
    @MainActor func abortStrataRefresh() {
        launchID = nil; hasFinishedLaunching = false
        connected?.invalidate(); connected = nil
        let launch = launchContinuation, running = c
        launchContinuation = nil; c = nil
        launch?.resume(throwing: CancellationError())
        running?.resume(throwing: CancellationError())
        ext?._kill(9)
        ext = nil; sideStorePid = 0; client = nil
    }

    func updateProgress(_ value: Double) {
        DispatchQueue.main.async { self.progress?.completedUnitCount = Int64(value * 100) }
    }

    func finish(_ error: String?) {
        DispatchQueue.main.async {
            let running = self.c; self.c = nil
            if let error {
                running?.resume(throwing: NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: error]))
            } else { running?.resume() }
        }
    }

    func onConnection(_ connection: NSXPCConnection!) {
        connection.remoteObjectInterface = NSXPCInterface(with: RefreshClient.self)
        DispatchQueue.main.async {
            guard self.launchID != nil, self.sideStorePid <= 0 || self.sideStorePid == connection.processIdentifier else { connection.invalidate(); return }
            self.connected = connection
            self.client = connection.remoteObjectProxy as? RefreshClient
        }
    }

    func finishedLaunching() {
        DispatchQueue.main.async {
            guard self.launchID != nil else { return }
            self.hasFinishedLaunching = true
            let launching = self.launchContinuation; self.launchContinuation = nil
            launching?.resume()
        }
    }

    func add(_ request: UNNotificationRequest) {
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Failed to add SideStore notification: \(error)")
            }
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
}
