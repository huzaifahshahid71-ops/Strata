# Strata 3.0

Strata is a controller-friendly launcher built on LiveContainer, bundled with SideStore. Version 3.0 is a large update to V2.0.

## Install

- **Updating from Strata V2.0:** open the IPA in your bundled SideStore and install it as an **update**, choosing **Keep All Extensions**. Do not uninstall first, or you lose your installed apps' identity and data.
- **New install:** install `Strata-3.0+SideStore.ipa` with your usual sideloading tool, the same way as V2.0.
- Free Apple ID signing still needs the separate LocalDevVPN app for refresh and JIT.

## What's new

### Interfaces
Six launcher interfaces, chosen from **Interface**:
- **iOS Home**: a familiar, compact app grid.
- **Cinematic**: large artwork with a cover carousel.
- **Big Picture**: a cover library with posters.
- **Switchboard**: one edge-to-edge row of large square tiles. The selected tile stays toward the left, with a background tinted by the game.
- **Shelf**: a full-screen grid of posters, 8 per row, tinted by the selected game.
- **Arcade**: a full-screen grid of rounded tiles, 8 per row, with category tabs, tinted by the selected game.

All console-style interfaces support game controllers (D-pad or stick to move, A to play, X for options, B for the Interface menu, shoulder buttons to change category) and have navigation sounds. Backgrounds cross-fade without flicker. Artwork is decoded in the background, with neighbouring artwork loaded ahead of time.

### Library organisation
- **Shared categories** (on by default): one set of categories and app assignments across every interface. Hidden apps are hidden everywhere, and empty categories aren't shown.
- **Arranging:** long-press and drag a tile onto another, or use the **Move** menu (To Start, Left, Right, To End, Place After). One order is shared by all interfaces.
- Per-interface artwork: backgrounds, covers and posters. Interfaces that don't store artwork of their own reuse what you've set elsewhere.

### iPhone apps
- Add regular iPhone apps to the launcher by name, with their real icons (Settings → iPhone Apps).
- When iOS doesn't allow Strata to open an app directly, Strata opens it through the app's own link. iOS shows its normal "Open in…" confirmation. Apps that register no link need a URL or Shortcut under Advanced.
- An optional Mac helper, `tools/export-strata-phone-apps.py`, exports your app list with icons and links from a paired iPhone. The list stays on your devices.

### Games and Game Mode
- Strata declares itself a game with controller support, so iOS can apply Game Mode and list Strata in the Games app.
- Apps in the **Games** and **Ports** categories always launch full screen through the Game Mode path.

### Reliability
- **Returning from the app switcher:** if iOS closed Strata while a game was in the background, Strata reopens that game when you come back. The game restarts; progress it hadn't saved can't be recovered.
- **Keep the running app alive in the background** (optional, Interface menu): Strata plays silent audio while you're in another app, so iOS doesn't suspend the game and you return to it as you left it. Uses more battery, and iOS can still close very large games when memory is low.
- **Storage management:** a much faster single scan with a live item count, shared between screens and reused for five minutes.
- No loading spinner at launch.

### Memory
- Extra-memory permission setup remains (Settings → Memory and signing permissions). On a free Apple ID the measured ceiling is **6 GB** on an 8 GB iPhone.
- **RAM bypass (experimental):** requests Apple's *Increased Debugging Memory Limit*. It applies only while a debugger is attached (Launch with JIT). **Apple grants it only to paid Apple Developer Program accounts.** Free accounts get an error and stay at the regular limit. The amount above 6 GB has not been measured.

## Known limits
- Game Mode applies to Strata as a whole while it is full screen, Tools apps included. iOS has no per-app control for apps running inside another app.
- The "Open in…" prompt for iPhone apps is shown by iOS and can't be turned off.
- No embedded VPN for free accounts, no arbitrary guest app-extension registration, and frame generation stays experimental and opt-in (2×).
- Poppy Playtime Chapters 3 and 4 still exit shortly after starting; no fix is claimed.
- Testing: every build passed packaging checks and simulator UI tests of the launcher interfaces. Storage calculation and opening iPhone apps were confirmed on an iPhone 16 Pro. The newest items (drag reordering, keep-alive, Shelf and Arcade layouts, RAM bypass) have not yet been checked on a device.

## Credits
Built on [LiveContainer](https://github.com/LiveContainer/LiveContainer) and bundled with SideStore. StosSign is included with the maintainer's permission. Third-party licences are in `THIRD_PARTY_NOTICES.md`.
