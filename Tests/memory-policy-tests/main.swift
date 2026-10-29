import Foundation
let ids: Set<String> = ["com.example.strata", "com.example.strata.LiveProcess"]
precondition(StrataMemoryRequestPolicy.matchingTargets(registered: ["unrelated.app"] + Array(ids), allowed: ids) == ids)
precondition(StrataMemoryRequestPolicy.matchingTargets(registered: ["com.example.strata"], allowed: ids) == nil)
precondition(StrataMemoryRequestPolicy.matchingTargets(registered: ["other.account.app"], allowed: ids) == nil)
precondition(StrataMemoryRequestPolicy.matchingTargets(registered: ["com.example.strata"], allowed: ["com.example.strata"]) == nil)
precondition(StrataMemoryRequestPolicy.capabilities == ["INCREASED_MEMORY_LIMIT"])
print("PASS: capability plan includes only current host/guest App IDs; missing IDs rejected; unrelated apps untouched.")

precondition(StrataMemoryRequestPolicy.bundleIdentity(signedID: "TEAM.com.example.strata", team: "TEAM", fallback: "wrong") == "com.example.strata")
precondition(StrataMemoryRequestPolicy.bundleIdentity(signedID: "OTHER.com.example.strata", team: "TEAM", fallback: "installed") == "installed")
precondition(StrataMemoryRequestPolicy.bundleIdentity(signedID: "", team: "TEAM", fallback: "installed") == "installed")
precondition(StrataMemoryRequestPolicy.selectedTargets(host: "host-record", guest: "guest-record", registered: ["host-record", "guest-record", "unrelated"]) == ["host-record", "guest-record"])
precondition(StrataMemoryRequestPolicy.selectedTargets(host: "shared-record", guest: "shared-record", registered: ["shared-record"]) == ["shared-record"])
precondition(StrataMemoryRequestPolicy.selectedTargets(host: "host-record", guest: "", registered: ["host-record"]) == nil)
precondition(StrataMemoryRequestPolicy.selectedTargets(host: "host-record", guest: "foreign-record", registered: ["host-record"]) == nil)
print("PASS: signed identity normalization, wrong-team fallback, explicit selection, shared registration, missing/foreign registration rejection.")
