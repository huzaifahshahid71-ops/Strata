import Foundation
let builtin = "bundled-universal"
precondition(StrataJITScriptPolicy.resolve(mode: .automatic, identifier: "dev.espressu.EspressU", imported: nil, universal: builtin) == builtin)
precondition(StrataJITScriptPolicy.resolve(mode: .automatic, identifier: "com.kdt.LiveExec32", imported: nil, universal: builtin) == builtin)
precondition(StrataJITScriptPolicy.resolve(mode: .automatic, identifier: "unknown.app", imported: nil, universal: builtin) == nil)
precondition(StrataJITScriptPolicy.resolve(mode: .automatic, identifier: "dev.espressu.EspressU", imported: "custom", universal: builtin) == "custom")
precondition(StrataJITScriptPolicy.resolve(mode: .universal, identifier: "unknown.app", imported: "custom", universal: builtin) == builtin)
precondition(StrataJITScriptPolicy.resolve(mode: .custom, identifier: "dev.espressu.EspressU", imported: "custom", universal: builtin) == "custom")
precondition(StrataJITScriptPolicy.resolve(mode: .custom, identifier: "dev.espressu.EspressU", imported: nil, universal: builtin) == nil)
precondition(StrataJITScriptPolicy.resolve(mode: .automatic, identifier: "fake.EspressU", imported: nil, universal: builtin) == nil)
print("PASS: verified automatic selection, unknown-app rejection, imported precedence and explicit Universal/Custom overrides.")
