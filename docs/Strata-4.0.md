# Strata 4.0

Strata is a controller-friendly launcher built on LiveContainer, bundled with SideStore. This release includes the six interfaces and library features from Strata 3.0, with runtime, switching and performance updates.

## Install or update

Open `Strata-4.0+SideStore.ipa` in your bundled SideStore and install as an **update**, choosing **Keep All Extensions**. Keep the existing Strata installation to preserve its identity and data. The IPA needs signing; it is not an App Store installation.

Free-account users still need the separate LocalDevVPN app for refresh and JIT. Personal, device-bound VPN shortcuts are intentionally excluded from the public package; configure the shortcut on your own device.

## New in 4.0

- **Updated LiveContainer runtime:** integrated nightly revision `9d6ea09`, including the per-app **Helper processes support** option and background-processing infrastructure. RAM-donor behavior with particular emulators is not yet verified.
- **Settings app:** searchable settings with quick tiles, available as a built-in launcher entry across interfaces.
- **App switcher:** an iOS-style deck with recent apps and snapshots, swipe-up to close, and an experimental live preview of the foreground app in seamless mode. Closing the current app keeps the deck open on the tested separate-process path.
- **Seamless switching:** eligible apps open in full-screen hosted windows. Switching and dismissal use transitions and snapshots. Built-in SideStore, HostJIT and other incompatible launch paths retain their own handling.
- **Memory overlay:** optional per-process usage, reported limit and peak readings in Settings → Performance.
- **iPhone app entries:** App Store search can help add entries. Actual opening still depends on iOS permissions or a supported app link; apps without a usable link may need a manual URL or Shortcut.
- **Frame generation:** experimental 2×, 3× and 4× modes for compatible Metal games, with phase-aware interpolation, status/skip diagnostics and direct-presentation hooks. Presentation stays constrained by display refresh and available GPU time.
- **Defaults:** reopening a game after iOS closes Strata defaults off. Optional background keep-alive remains available.

## Experimental features and known limits

- Latest development baseline is **r57**. It passed package checks; selected earlier switcher flows were tested on-device, including the r53 swipe-up close behavior. This public package has not undergone a complete device regression test.
- Latest live previews, memory overlay, helper/RAM-donor behavior and full-display SDK stamping have not been validated on all target devices. Background app cards may show snapshots rather than live content.
- Frame generation is opt-in and is not guaranteed to work in every Metal game. Simulator tests exercised 4× command-buffer and 2× direct-present generation. **The 4× direct-present test has a known native/generated counter discrepancy**; do not treat that counter as proof of performance. The r57 direct-present changes are not yet device-tested. Artifacts, extra GPU load and latency are possible. Native rendering remains the fallback.
- RAM permissions do not guarantee a particular memory allowance or bypass. Increased Debugging Memory Limit needs an eligible paid developer account and debugger attachment. Free accounts may be refused; no universal allowance above 6 GiB is claimed.
- No embedded VPN for free accounts and no arbitrary guest app-extension registration. iOS controls Game Mode and native-app confirmation prompts.
- Poppy Playtime Chapters 3 and 4 remain unresolved; no crash fix is claimed.

## Credits and source

Built on [LiveContainer](https://github.com/LiveContainer/LiveContainer), bundled with SideStore. The switcher incorporates work from [ryC0](https://github.com/Sami-Wali/ryC0); frame generation incorporates MetalFG. StosSign is included with the maintainer's permission. See `THIRD_PARTY_NOTICES.md` and included licences.

Source, locked submodule revisions, verification metadata and SHA-256 checksums are attached to this release. Preserve the existing app when updating.
