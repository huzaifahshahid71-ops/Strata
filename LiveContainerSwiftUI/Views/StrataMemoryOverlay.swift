import SwiftUI
import UIKit

/// Floating memory readout above everything (including full-screen apps). Touches pass through.
/// Rows come from per-process samples written by StrataStartMemoryOverlaySampler.
@MainActor final class StrataMemoryOverlay {
    static let shared = StrataMemoryOverlay()
    static let key = "StrataMemoryOverlay"
    private var window: UIWindow?
    func apply() {
        let enabled = LCUtils.appGroupUserDefault.bool(forKey: Self.key)
        if !enabled { window?.isHidden = true; window = nil; return }
        guard window == nil, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let overlay = UIWindow(windowScene: scene)
        overlay.windowLevel = .alert + 3
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = .clear
        let host = UIHostingController(rootView: StrataMemoryOverlayView())
        host.view.backgroundColor = .clear
        overlay.rootViewController = host
        overlay.isHidden = false
        window = overlay
    }
}

private struct StrataMemorySample: Identifiable {
    let pid: Int
    let role: String
    let name: String
    let footprint: UInt64
    let available: UInt64
    var id: Int { pid }
    var limit: UInt64 { footprint + available }
}

struct StrataMemoryOverlayView: View {
    @State private var samples: [StrataMemorySample] = []
    @State private var peaks: [Int: UInt64] = [:]
    @State private var peakTotal: UInt64 = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(samples) { sample in
                HStack(spacing: 6) {
                    Circle().fill(color(sample.role)).frame(width: 6, height: 6)
                    Text(label(sample)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text("\(mb(sample.footprint)) / \(mb(sample.limit))").monospacedDigit()
                    Text("pk \(mb(peaks[sample.pid] ?? sample.footprint))").monospacedDigit().foregroundStyle(.white.opacity(0.6))
                }
            }
            Divider().overlay(Color.white.opacity(0.3))
            HStack {
                Text("Total").bold()
                Spacer()
                Text(mb(samples.reduce(0) { $0 + $1.footprint })).monospacedDigit().bold()
                Text("pk \(mb(peakTotal))").monospacedDigit().foregroundStyle(.white.opacity(0.6))
            }
            if samples.isEmpty { Text("Waiting for samples…").foregroundStyle(.white.opacity(0.7)) }
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundStyle(.white)
        .padding(8)
        .frame(width: 250)
        .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.top, 44).padding(.leading, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(timer) { _ in refresh() }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        guard let group = LCSharedUtils.appGroupID(), let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return }
        let directory = root.appendingPathComponent("Library/StrataDiagnostics/Live", isDirectory: true)
        let now = Date().timeIntervalSince1970
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var next: [StrataMemorySample] = []
        for file in files where file.lastPathComponent.hasPrefix("proc-") {
            guard let data = try? Data(contentsOf: file), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = value["pid"] as? Int, let time = value["time"] as? Double else { continue }
            if now - time > 4 { try? FileManager.default.removeItem(at: file); continue }   // process gone
            next.append(StrataMemorySample(pid: pid, role: value["role"] as? String ?? "process", name: value["name"] as? String ?? "",
                                           footprint: (value["footprint"] as? NSNumber)?.uint64Value ?? 0, available: (value["available"] as? NSNumber)?.uint64Value ?? 0))
        }
        let order = ["Strata": 0, "Strata + app": 0, "app": 1, "helper": 2]
        samples = next.sorted { (order[$0.role] ?? 3, $0.pid) < (order[$1.role] ?? 3, $1.pid) }
        for sample in samples { peaks[sample.pid] = max(peaks[sample.pid] ?? 0, sample.footprint) }
        peakTotal = max(peakTotal, samples.reduce(0) { $0 + $1.footprint })
    }
    private func label(_ s: StrataMemorySample) -> String {
        switch s.role {
        case "helper": return "Helper · " + s.name
        case "app": return s.name.isEmpty ? "App" : s.name
        default: return s.name.isEmpty || s.name == "Strata" ? "Strata" : "Strata · " + s.name
        }
    }
    private func color(_ role: String) -> Color { role == "helper" ? .orange : role == "app" ? .green : .cyan }
    private func mb(_ bytes: UInt64) -> String { bytes >= 1 << 30 ? String(format: "%.2f GB", Double(bytes) / 1_073_741_824) : "\(bytes >> 20) MB" }
}
