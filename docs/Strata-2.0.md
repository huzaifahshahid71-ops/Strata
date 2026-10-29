# Strata 2.0 — release based on development revision 25

Install as an update through bundled SideStore, keeping all extensions and the current installation/data. Pairing, working VPN settings, RAM setup, guest apps and artwork are retained.

## Home paging and dots

Home uses a native paged scroll view. Scroll position updates only the dock, backdrop and small page dots during movement; it does not rebuild all guest icons for every scrolling frame. The dock moves continuously off the edge as Tools or App Library enters. A prepared blurred wallpaper layer crossfades as App Library enters, avoiding an abrupt end-of-page blur switch. Actual physical 120 Hz pacing still needs phone verification.

Dots represent Home pages only, excluding Tools and App Library. Swipe to reach those edge sections. Drag across the dots to scrub through Home pages; the active dot follows the movement. Hold blank Home space to enter editing.

## Folders

Drag an app onto another app and drop to create a folder at the destination's original position. Folder opening/closing animates unless Reduce Motion is enabled. Open a folder and drag an icon onto blank space outside it to move it back to Home. Hold the folder and choose Remove Folder to dissolve it while keeping its apps. Rename and Move out of Folder actions remain available. Removing an icon from Home does not uninstall the guest. Folder nesting is rejected. These are iOS-inspired gestures, not a claim to reproduce every SpringBoard hover timing or animation.

## One app switcher

Three-finger tap uses the same native component inside Strata and inside guests. It shows running apps, the current guest, and optional pinned shortcuts. Closed, unpinned apps are excluded. Tap an icon to open/restore it; hold for Close where supported and Pin/Unpin. The chevron or another three-finger tap hides it. Touches outside the strip pass through to the app.

Configure pins from Customize → App Switcher → Running and pinned apps, or hold any launcher app and choose Pin to app switcher. Host and guest rendering share one implementation rather than separate SwiftUI/UIKit designs.

Normal in-process guests cannot remain independently suspended while another main-process guest runs. Returning/closing them uses LiveContainer's existing host relaunch. Separate JIT/multitasking guests retain their independent window/process lifecycle. Switch requests still resolve through the actual guest registry, lock authentication and launch preflight.

## Metal HUD

Hold an app on Home or a console rail and choose Launch with Metal HUD. The guest starts fresh with a one-shot request consumed by the existing bootstrap. It uses Apple's MTL_HUD_ENABLED environment option and MetalForceHudEnabled defaults option before guest runtime startup. Normal launch does not persistently force the overlay on or override global Developer HUD preferences. Close an already-running guest before changing its launch mode.

The overlay requires a supported Metal rendering path and OS. This is an enablement request, not proof the overlay appeared; physical JSAB and a JIT guest test remain pending. Apple documents the options here: https://developer.apple.com/videos/play/tech-talks/110339/

## Game Mode limitation

The old label incorrectly implied that Strata could force per-guest OS Game Mode. It now says Request Game Mode. The action declares guest support, signs it, and requests fullscreen, but iOS controls actual activation for the registered host/process. Automatic host/wrapper support remains disabled so the launcher does not request Game Mode itself. A reliable documented per-guest force switch under this shared signed identity is NOT implemented. Automatically eligible games can still behave as before. No fake enabled indicator or RAM increase is claimed. Apple describes system activation here: https://support.apple.com/105118

## Validation

- Release iPhone build passed.
- Four Home simulator tests passed: actual drag-to-create → close/reopen → drag out → remove folder; wallpaper/Photos picker and five category open/close cycles with stable sizes; Home-only dots, dot scrubbing and blank-space long-press; generated video import/persistence.
- Three native switcher tests passed: launcher, normal portrait guest and separate landscape guest; running/pinned entries present, closed unpinned entry absent, long-press actions, Open and hide behavior, bounds.
- Folder model tests passed destination preservation, membership, drag out, dissolution, invalid nesting and conservation of apps.
- Fixture launch/relaunch is stubbed: physical process switching, JIT and Metal HUD still need phone tests. Simulator animation waits during wobble made the removal test slow; it completed successfully. A slower drag/dwell was required for reliable XCTest drag targeting.
- Package verification checks preserved original SideStore files, core exports/imports, identity and memory entitlement requests. CPU translation backend is unchanged; JIT-free LiveExec32/AOT is still not implemented.

Phone checks: install R25 keeping extensions; swipe from Home to App Library and compare dock/blur; scrub dots; create/remove a folder; launch/minimize a guest and compare its three-finger menu to the launcher's; pin/unpin one app; launch JSAB using Metal HUD, then test a JIT app. Leave the working LocalDevVPN configuration unchanged.
