# Focused regression checks

Run from the repository root on macOS with Xcode command-line tools installed. These checks do not launch guest apps or prove successful device JIT.

```sh
swiftc LiveContainerSwiftUI/Views/LiveBoardHomeLayout.swift Tests/home-widget-tests/main.swift -o /tmp/strata-home-check
/tmp/strata-home-check
swiftc -framework JavaScriptCore ShareExtension/StrataJITScriptSafety.swift Tests/jit-script-tests/main.swift -o /tmp/strata-script-check
/tmp/strata-script-check
clang -fobjc-arc -fblocks -framework Foundation -I LiveProcess -I MultitaskSupport LiveProcess/StrataJITGuestGate.m Tests/guest-gate-tests/main.m -o /tmp/strata-gate-check
/tmp/strata-gate-check
```

The Home checks cover preference migration, widget occupancy and reflow, resizing, page removal with app-library preservation, folders, persistence, and repeated rearrangement. The source release's validation report also records targeted simulator checks; the local UI harness uses fixture icons and no guest execution.
