import Foundation

/// Runs debugger work outside the target process, serially. Pairing data never enters logs.
enum StrataJITWorker {
    private static let lock = NSLock()
    private static var tokens = Set<String>()
    static let queue = DispatchQueue(label: "Strata.JIT.helper")
    static func handle(_ context: NSExtensionContext) -> Bool {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let input = item.userInfo, input["strataJIT"] as? Bool == true else { return false }
        guard let token = input["token"] as? String, UUID(uuidString: token) != nil,
              let pid = input["pid"] as? Int32, pid > 0,
              let data = input["pairing"] as? Data, data.count < 2_000_000,
              let group = input["group"] as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            context.cancelRequest(withError: NSError(domain: "StrataJIT", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JIT request."]))
            return true
        }
        lock.lock()
        let inserted = tokens.insert(token).inserted
        lock.unlock()
        guard inserted else { return true }
        queue.async {
            defer { lock.lock(); tokens.remove(token); lock.unlock() }
            let fm = FileManager.default
            let status = container.appendingPathComponent("Library/StrataJIT/\(token).json")
            func report(_ message: String, done: Bool = false, success: Bool = false) {
                let object: [String: Any] = ["message": message, "done": done, "success": success]
                try? fm.createDirectory(at: status.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let encoded = try? JSONSerialization.data(withJSONObject: object) { try? encoded.write(to: status, options: .atomic) }
            }
            report("JIT helper connected.")
            let pairing = fm.temporaryDirectory.appendingPathComponent("\(token).plist")
            defer { try? fm.removeItem(at: pairing) }
            do {
                try data.write(to: pairing, options: [.atomic, .completeFileProtection])
                let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                let paths = DDIPaths.default(in: library.appendingPathComponent("StrataJIT"))
                let operation = input["operation"] as? String ?? "enable"
                if operation == "reset" {
                    try StikJIT.resetCachedDDI(at: paths)
                    report("Developer disk image cache reset.", done: true, success: true)
                    context.completeRequest(returningItems: nil)
                    return
                }
                let address = input["deviceAddress"] as? String ?? "10.7.0.1"
                let port = input["remotePairPort"] as? Int ?? 49152
                let octets = address.split(separator: ".", omittingEmptySubsequences: false)
                guard octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }), let endpointPort = UInt16(exactly: port), endpointPort > 0 else {
                    throw NSError(domain: "StrataJIT", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid device endpoint."])
                }
                let config = StikJIT.Configuration(deviceAddress: address, rsdPort: endpointPort)
                report("Connecting to device at \(address):\(endpointPort)…")
                let readiness = StikJIT.prepareDevice(pairingFile: pairing, paths: paths, configuration: config) { stage in
                    report(String(describing: stage))
                }
                switch readiness {
                case .unreachable(let reason), .preparationFailed(let reason): throw NSError(domain: "StrataJIT", code: 2, userInfo: [NSLocalizedDescriptionKey: reason])
                case .ready(let state):
                    if operation == "prepare" {
                        let txm = state.isTXMPresent.map { $0 ? "present" : "not present" } ?? "unknown"
                        report("Device ready. TXM/SPTM: " + txm, done: true, success: true)
                        context.completeRequest(returningItems: nil)
                        return
                    }
                    guard let txm = state.isTXMPresent else { throw NSError(domain: "StrataJIT", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot determine device JIT requirements."]) }
                    let script = input["script"] as? String ?? ""
                    if txm && script.isEmpty { throw NSError(domain: "StrataJIT", code: 4, userInfo: [NSLocalizedDescriptionKey: "This guest needs a compatible iOS JIT script. Configure its JIT script in app settings before launching."]) }
                    report("Connecting debugger…")
                    // Preserve the guest's existing protocol; never substitute a universal script for an arbitrary engine.
                    try StikJIT.enableJIT(targetPID: pid, pairingFile: pairing, ddiPaths: paths, configuration: config,
                        script: script.isEmpty ? .universal : .customBase64(script), progress: { report($0) })
                    report("JIT request completed.", done: true, success: true)
                }
            } catch { report(error.localizedDescription, done: true) }
            context.completeRequest(returningItems: nil)
        }
        return true
    }
}

/// Request entry point used before a share view is created.
@objc(StrataJITRequestHandler)
final class StrataJITRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) { _ = StrataJITWorker.handle(context) }
    @objc(begin:)
    static func begin(_ context: NSExtensionContext) { _ = StrataJITWorker.handle(context) }
}
