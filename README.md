# Strata 2.0

A customizable launcher built on [LiveContainer](https://github.com/LiveContainer/LiveContainer), with three interfaces and bundled SideStore support.

<p align="center"><img src="Resources/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png" width="160" alt="Strata icon"></p>

## Three interfaces

- **iOS Home Screen:** portrait layout, custom icons and names, static/video wallpapers, widgets, folders, scrubbable page dots, dock favorites, search and a categorized App Library.
- **Cinematic:** landscape console-style app rail, artwork, categories, adjustable Play controls and controller navigation.
- **Big Picture:** landscape library with independent portrait artwork, categories, layout sizing and controller navigation.

Artwork, categories and hidden-app choices are independent between interfaces. Imported artwork and wallpapers are available in Files → On My iPhone → Strata → Artwork.

## What's new in 2.0

- Built-in JIT preparation using a device pairing record and LocalDevVPN, plus automatic/Universal/imported per-app script choices.
- Integrated RAM capability account setup and actual host/guest memory reports. Entitlements remain subject to Apple's signing profiles and iOS limits.
- One three-finger app switcher inside the launcher and guests, showing running apps and optional pins. Open, restore, minimize or close supported guests without a permanent floating arrow.
- Native paged scrolling, continuous dock/backdrop transitions and Home-only page dots with scrubbing.
- Drag-to-create folders, drag apps out, dissolve folders while retaining apps, and hold blank Home space to edit.
- Launch with Metal HUD for supported Metal apps.

## Download and install

Get **Strata-2.0+SideStore.ipa** from [Releases](https://github.com/huzaifahshahid71-ops/Strata/releases/tag/v2.0.0). Sign and install with SideStore. When updating a compatible combined installation, **keep the current app and choose Keep App Extensions**, using the same account and identity to preserve data. Back up important guest data first.

Strata 2.0 is the product release name; this build uses the LiveContainer **3.8.11** base and development revision **25**. The underlying bundle version/identity are retained for update compatibility. The IPA does not contain personal signing credentials or pairing records.

## JIT and RAM setup

Import your own pairing record on the device, keep your working LocalDevVPN configuration, enable Developer Mode, and use JIT → Prepare device. Launch with JIT uses the existing guest runtime and a headless StikJIT helper. Script compatibility varies: Universal is selected automatically only for verified IDs; custom imports and per-app overrides remain available.

RAM capability setup signs into Apple's service to request the increased-memory capability for the installed host and guest App IDs. Reinstall/refresh with an authorized signing profile afterward. Credentials are handled in memory, and the memory reports distinguish actual guest measurements from the launcher's reading. A request is not a guarantee that iOS granted a particular amount of memory.

## Limits and testing

- **LiveExec32 still requires JIT.** There is no working JIT-free ARMv7 interpreter/AOT backend in this release.
- **Game Mode is controlled by iOS.** Request Game Mode declares guest support and requests fullscreen; it cannot reliably force a separate OS Game Mode state for every guest under the shared host identity.
- Metal HUD requires a supported Metal rendering path. Physical HUD verification and 120 Hz frame-pacing measurements for this final build remain pending.
- Normal in-process guests cannot stay independently suspended while another main-process guest runs; switching uses the existing host relaunch. Separate JIT/multitasking guests retain independent lifecycles.
- Earlier development builds were tested on an iPhone 15 Pro: Angry Birds ran with built-in JIT, and a normal JSAB guest reported an approximately 6 GiB footprint/headroom total with the memory entitlement. These results do not establish compatibility for every guest.
- The release build and package checks pass. Seven simulator UI tests cover Home gestures, folder create/drag-out/removal, categories, wallpapers, and consistent running/pinned switchers; focused folder model checks also pass. Final phone smoothness, HUD and process-switching checks remain user tests.

## Build from source

```sh
git clone --recurse-submodules https://github.com/huzaifahshahid71-ops/Strata.git
cd Strata
python3 Scripts/fetch-bundled-dependencies.py
xcodebuild -project LiveContainer.xcodeproj -scheme LiveContainer \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Use a compatible Xcode 26 or newer installation with the iPhoneOS SDK. The target remains named LiveContainer. The postbuild step embeds the JIT helper and runtime. The combined download preserves original SideStore components; a fresh source build is not byte-identical to that assembly. Sign unsigned builds before installation.

## Credits and permissions

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), the retained [LiveContainer license](LICENSE), dependency notices and pinned provenance. StosSign redistribution permission for this Strata release was confirmed by the project maintainer on 29 October 2026; no general upstream license is asserted. Strata is not affiliated with Apple, Sony or Valve.
