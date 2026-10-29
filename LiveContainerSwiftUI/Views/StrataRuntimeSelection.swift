import Foundation

struct StrataRuntimeSelection {
    struct Candidate: Equatable {
        let folder: String
        let identifier: String
        let shared: Bool
    }
    static func validFolder(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && name.lowercased().hasSuffix(".app")
    }
    static func choose(preferred: String?, defaultRuntime: String?, candidates: [Candidate]) -> Candidate? {
        let valid = candidates.filter { validFolder($0.folder) }.sorted { !$0.shared && $1.shared }
        for name in [preferred, defaultRuntime].compactMap({ $0 }) where validFolder(name) {
            if let selected = valid.first(where: { $0.folder == name }) { return selected }
        }
        return valid.first { $0.identifier == "com.kdt.LiveExec32" } ?? valid.first
    }
}
