# Strata revision 12 — guest JIT startup gate

## Fix

A built-in JIT launch now explicitly requests a gate in the guest extension before entering LiveContainerMain. The original bootstrap rejects a 32-bit guest without active JIT, so starting it before debugger attachment can terminate it prematurely. Normal launches and other JIT providers retain their existing startup path.

The guest publishes its own getpid() under a fresh launch UUID and waits for its actual CS_DEBUGGED status. The host correlates that UUID and PID with the current extension request before handing it to the JIT helper. The wait is bounded at 360 seconds. Invalid/mismatched acknowledgements fail rather than attaching to another process. Scene presentation is deferred until attachment so a synchronous scene request cannot block the guest gate. Startup errors complete the PID callback once, preventing a stranded launch continuation.

The gate releases on debugger attachment, allowing the existing runtime and LiveExec32 universal script handshake to proceed; it does not wait for script completion, which would deadlock the handshake. It does not claim that attachment alone completes TXM JIT preparation. Existing script success still requires confirmed detach.

## Diagnostics

Documents/StrataJIT/last-status.json now includes revision, target PID, timestamp and recent guest startup messages. Matching per-launch records live under the shared group's Library/StrataJITGuest directory and report waiting, attached, timeout or extension cancellation. Pairing records and credentials are not logged.

## Package

The supplied LiveContainerShared execution framework, SideStore binary and its original extensions remain unchanged. Unlike revision 11, revision 12 updates the LiveProcess entry executable to add the gate, preserving the original extension Info.plist, bundle identity and entitlements for SideStore re-signing. The package also updates the presentation framework and JIT helper. Matching shared-framework imports and original file preservation are verified.

## Validation and limits

The production gate and acknowledgement checks pass local tests for delayed attachment, own-PID reporting, wrong/stale PID rejection, failed guests, timeout, status-read failure, invalid requests and unchanged normal launches. Release arm64 build passes. Physical guest JIT and Angry Birds execution remain pending the user's phone test. The older dyld fit32 crash has not been reproduced or patched based solely on its old report.

## Install and test

Install Strata+SideStore-3.8.11-r12.ipa from Files → On My iPhone → Strata using the existing bundled SideStore as an update. Keep all app extensions and keep the current installation/data. Connect LocalDevVPN, select Angry Birds → Launch with JIT, and leave it until a result appears. Revision 12 is experimental; report the resulting status tomorrow. Fresh diagnostics can then be collected locally.

GitHub remains at published revision 11. Revision 12 is a local test build and has not been uploaded as a new public release.
