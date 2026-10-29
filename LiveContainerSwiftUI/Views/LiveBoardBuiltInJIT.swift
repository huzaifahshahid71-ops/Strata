import Foundation
import Combine

@MainActor
enum LiveBoardBuiltInJIT {
    private static var busy = false
    static var pairingURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StrataJIT/pairingFile.plist")
    }
    static func importPairing(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        try StrataPairingRecord.validate(data)
        try FileManager.default.createDirectory(at: pairingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: pairingURL, options: [.atomic, .completeFileProtection])
    }
    static func enable(pid: Int32 = getpid(), script: String?, operation: String = "enable", onGuestAttached: (() -> Void)? = nil, progress: @escaping (String) -> Void) async -> Bool {
        var recentMessages: [String] = []
        var guestAttached = false
        var jitComplete = false
        let report: (String) -> Void = { message in
            progress(message)
            UserDefaults.standard.set(message, forKey: "StrataJITLastStatus")
            recentMessages.append(String(message.prefix(1024)))
            recentMessages = Array(recentMessages.suffix(40))
            let status: [String: Any] = ["message": message, "operation": operation, "recentMessages": recentMessages,
                                       "guestAttached": guestAttached, "jitComplete": jitComplete,
                                       "revision": Bundle.main.object(forInfoDictionaryKey: "StrataRevision") as? Int ?? 15, "targetPID": pid, "timestamp": Date().timeIntervalSince1970]
            let file = pairingURL.deletingLastPathComponent().appendingPathComponent("last-status.json")
            if let data = try? JSONSerialization.data(withJSONObject: status) { try? data.write(to: file, options: .atomic) }
        }
        guard !busy else { report("Another JIT operation is already running."); return false }
        guard ["enable", "prepare", "reset"].contains(operation), operation != "enable" || (pid > 0 && pid != getpid()) else {
            report("JIT requires a separate guest process."); return false
        }
        busy = true
        defer { busy = false }
        guard #available(iOS 17.4, *) else { report("Built-in JIT requires iOS 17.4 or later."); return false }
        guard LCUtils.strataCanDebug() else { report("This installation lacks debugging permission (get-task-allow). Re-sign using a compatible signing method."); return false }
        guard let data = try? Data(contentsOf: pairingURL) else { report("Import your pairing file in JIT setup first."); return false }
        do { try StrataPairingRecord.validate(data) } catch { report(error.localizedDescription); return false }
        guard let group = LCSharedUtils.appGroupID(), let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { report("The shared app container is unavailable."); return false }
        let preferences = LCUtils.appGroupUserDefault
        let rawAddress = preferences.string(forKey: "StrataJITDeviceAddress") ?? "10.7.0.1"
        let address = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "/")[0]
        let octets = address.split(separator: ".", omittingEmptySubsequences: false)
        let portText = preferences.string(forKey: "StrataJITRemotePairPort") ?? "49152"
        guard octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }),
              let port = UInt16(portText.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0 else {
            report("Enter a valid Device IP and remote pairing port in JIT setup."); return false
        }
        let guestStatus = root.appendingPathComponent("Library/StrataJITGuest/\(pid).json")
        let acknowledgement = (try? Data(contentsOf: guestStatus)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let expectedToken = (acknowledgement?["pid"] as? NSNumber)?.int32Value == pid ? acknowledgement?["token"] as? String : nil
        var handoff = StrataJITHandoff(pid: pid, token: expectedToken)
        let token = UUID().uuidString
        let status = root.appendingPathComponent("Library/StrataJIT/\(token).json")
        var helper: NSObject?
        defer {
            if let helper { LCUtils.strataStopJITHelper(helper) }
            try? FileManager.default.removeItem(at: status)
        }
        do {
            if operation == "enable" { report("Guest startup acknowledged: PID \(pid). Waiting guest will enter its runtime after debugger attachment.") }
            helper = try LCUtils.strataStartJITHelper(["strataJIT": true, "group": group, "operation": operation, "token": token, "pid": pid, "pairing": data, "script": script ?? "", "deviceAddress": address, "remotePairPort": Int(port)])
            guard helper != nil else { report("JIT helper unavailable. Reinstall keeping app extensions."); return false }
            report("Preparing device. Keep LocalDevVPN connected and Developer Mode enabled.")
            var lastMessage = ""
            let started = Date()
            let deadline = started.addingTimeInterval(300)
            var receivedStatus = false
            var lastGuestMessage = ""
            while Date() < deadline || handoff.attached {
                if handoff.attached, kill(pid, 0) != 0, errno == ESRCH {
                    report("Guest process exited; debugger session closed.")
                    return false
                }
                try Task.checkCancellation()
                if operation == "enable", let bytes = try? Data(contentsOf: guestStatus),
                   let record = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                   record["token"] as? String == expectedToken,
                   (record["pid"] as? NSNumber)?.int32Value == pid {
                    if let message = record["message"] as? String, message != lastGuestMessage {
                        report("Guest: " + message); lastGuestMessage = message
                    }
                    if handoff.accept(record) {
                        guestAttached = true
                        report("Debugger attached. Opening the app while JIT preparation continues.")
                        onGuestAttached?()
                    }
                }
                if let bytes = try? Data(contentsOf: status), let result = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
                    receivedStatus = true
                    let message = result["message"] as? String ?? ""
                    if message != lastMessage { report(message); lastMessage = message }
                    if result["done"] as? Bool == true {
                        let succeeded = result["success"] as? Bool == true
                        jitComplete = operation == "enable" && succeeded
                        report(message)
                        return succeeded
                    }
                }
                if !receivedStatus && Date().timeIntervalSince(started) > 12 {
                    report("The JIT helper did not start. Confirm this update was installed with all extensions kept, then retry. No device connection was attempted.")
                    return false
                }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            report("JIT timed out. Check LocalDevVPN, pairing and Wi-Fi, then retry.")
        } catch is CancellationError { report("JIT cancelled.") }
        catch { report(error.localizedDescription) }
        return false
    }
}

/// Owns preparation independently of the setup sheet's lifetime.
@MainActor final class LiveBoardJITSession: ObservableObject {
    static let shared = LiveBoardJITSession()
    @Published var message = UserDefaults.standard.string(forKey: "StrataJITLastStatus") ?? ""
    @Published private(set) var busy = false
    @Published private(set) var success: Bool?
    private var task: Task<Void, Never>?
    func start(_ operation: String) {
        guard !busy else { return }
        busy = true; success = nil; message = "Starting…"
        task = Task {
            success = await LiveBoardBuiltInJIT.enable(script: nil, operation: operation) { [weak self] in self?.message = $0 }
            busy = false
            task = nil
        }
    }
    /// Retain the helper after its progress sheet goes away. Some runtimes prepare
    /// executable regions only when the user starts a game inside the guest UI.
    func startLaunch(pid: Int32, script: String?, onGuestAttached: @escaping () -> Void,
                     progress: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) -> Bool {
        guard !busy else { return false }
        busy = true; success = nil; message = "Starting…"
        task = Task {
            let result = await LiveBoardBuiltInJIT.enable(pid: pid, script: script, onGuestAttached: onGuestAttached) { [weak self] line in
                self?.message = line
                progress(line)
            }
            success = result; busy = false; task = nil
            if !Task.isCancelled { completion(result) }
        }
        return true
    }
    func cancel() { task?.cancel() }
}
