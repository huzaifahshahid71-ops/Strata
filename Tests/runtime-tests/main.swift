import Foundation
let local = StrataRuntimeSelection.Candidate(folder: "LiveExec32.app", identifier: "com.kdt.LiveExec32", shared: false)
let shared = StrataRuntimeSelection.Candidate(folder: "SharedRuntime.app", identifier: "custom", shared: true)
precondition(StrataRuntimeSelection.choose(preferred: "deleted.app", defaultRuntime: "old.app", candidates: [shared, local]) == local)
precondition(StrataRuntimeSelection.choose(preferred: shared.folder, defaultRuntime: local.folder, candidates: [local, shared]) == shared)
precondition(StrataRuntimeSelection.choose(preferred: nil, defaultRuntime: shared.folder, candidates: [local, shared]) == shared)
precondition(StrataRuntimeSelection.choose(preferred: "../bad.app", defaultRuntime: nil, candidates: []) == nil)
precondition(!StrataRuntimeSelection.validFolder("../engine.app") && !StrataRuntimeSelection.validFolder("/tmp/engine.app"))
print("PASS: valid selections preserved; stale runtime settings recover; invalid paths and missing runtimes rejected.")
