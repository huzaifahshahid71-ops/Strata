# R15: JIT, 32-bit execution and memory

## Implemented

Built-in LocalDevVPN JIT is the default on a fresh setup. Existing provider selections remain intact. All LCAppModel launches of a 32-bit app now validate and sign a readable translation runtime, repair stale selected paths, and install the bundled LiveExec32 if no usable runtime exists. The universal script is assigned only for LiveExec32 and only when no custom script is set.

The guest receives a security-scoped bookmark for the separate runtime bundle. A shared Foundation path resolver checks private and shared Applications roots independently of the guest's own location. It validates a relative .app folder, readable executable and translation-layer marker. The guest checks runtime access before its JIT gate. The existing gate still correlates the real guest PID with the extension request and resumes only after debugger attachment. Repeated taps cannot prepare the same guest twice concurrently.

Memory and signing permissions is available from Settings and JIT setup. It reports kernel entitlement state for the host, the guest executable's signed entitlement, and current OS-reported available memory. Its Apple account workflow uses StosSign's authenticate, team lookup, App ID lookup and INCREASED_MEMORY_LIMIT request. Only this installed host and LiveProcess App IDs are eligible; both must exist in the matching signing team. Login credentials and sessions are held in memory, raw upstream response prints are removed, and anisette networking is ephemeral. The user supplies the trusted HTTPS anisette server from SideStore, signs in locally, handles Apple's verification code, applies the requests, then reinstalls the IPA through SideStore with extensions kept. A successful request is not described as an already-active memory grant.

## Not implemented: JIT-free ARMv7 / AOT

The current upstream LiveExec32 HEAD was checked on 26 October 2026 and remains c94c040018bab39aaceee71786c5b452f3e9f5b6, matching the bundled runtime. It uses Dynarmic JIT. InterpreterFallback halts execution and reports SIGILL. No AOT backend was found in this implementation.

A real JIT-free implementation needs either a complete ARMv7/Thumb interpreter (including the floating-point/vector instructions used by target apps), or a signed ahead-of-time translation pipeline and runtime dispatch for indirect branches, ABI/framework bridges and guest exceptions. Merely caching Dynarmic code or setting an entitlement does not provide this. R15 does not disable the actual JIT requirement or advertise nonfunctional AOT controls. This part of the user's final goal is unfulfilled and remains a separate engine task.

## Validation and limits

Release arm64 build and focused runtime-selection, actual bundle-path and memory-request scoping checks pass. The rebuilt shared framework retains every exported symbol from the supplied original framework; bundle identity and original SideStore components are retained. The shared framework is updated specifically for the runtime lookup fix, so it is no longer byte-identical to the original.

Actual game execution after the lookup fix and Apple's account/capability response require a phone test. The agent does not sign in with or collect the user's Apple password or pairing file. An increased memory entitlement is requested already by the supplied host/guest executables, but the signing App ID/profile and device must authorize it; iOS decides the actual available memory. Full guest JIT and a working RAM capability grant are not claimed verified from a build alone.

References: https://github.com/LiveContainer/LiveExec32 ; https://github.com/hugeBlack/GetMoreRam ; https://github.com/stossy11/StosSign ; https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit

StosSign integration source is pinned at f8075577623707bd7899a884f31f2c4674af18d4. Local patches expose AnisetteResponse fields, add cancellation with single-resume continuation protection, use ephemeral networking, and remove raw diagnostic prints. This is a local test build. New dependency licensing/provenance must be reviewed before a new public release; GitHub remains revision 11.
