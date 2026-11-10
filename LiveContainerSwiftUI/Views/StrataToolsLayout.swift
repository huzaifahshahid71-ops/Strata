import Foundation

struct StrataToolsLayout: Codable, Equatable {
    var order: [String] = []
    var hidden: [String] = []
    init() {}
    init(saved: String) { self = (try? JSONDecoder().decode(Self.self, from: Data(saved.utf8))) ?? Self() }
    var encoded: String { String(data: (try? JSONEncoder().encode(self)) ?? Data(), encoding: .utf8) ?? "{}" }
    func visible(available: [String]) -> [String] {
        var seen = Set<String>()
        let valid = Set(available), excluded = Set(hidden)
        return (order + available).filter { valid.contains($0) && !excluded.contains($0) && seen.insert($0).inserted }
    }
    mutating func remove(_ id: String) { if !hidden.contains(id) { hidden.append(id) } }
    mutating func add(_ id: String, available: [String]) {
        guard available.contains(id) else { return }
        var current = visible(available: available).filter { $0 != id }
        hidden.removeAll { $0 == id }; current.append(id); order = current
    }
    mutating func move(_ id: String, to target: String, available: [String]) {
        var current = visible(available: available)
        guard id != target, let source = current.firstIndex(of: id), let destination = current.firstIndex(of: target) else { return }
        current.remove(at: source); current.insert(id, at: destination); order = current
    }
}
