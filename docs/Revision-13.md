# Strata revision 13 — Home pages and widgets

## Home pages

Edit Home Screen → Edit → Manage pages now lists Home pages with add, show and remove controls. At least one Home page is retained. Removing a page asks for confirmation, returns its apps and folder contents to the App Library, and removes its widgets. Apps are not uninstalled, and other interface preferences are not changed. The fixed controls page is separate from the removable Home pages.

## Widgets

Edit Home Screen → Edit → Add widget offers Photos, Clock, Calendar and Batteries. Small (2×2) and medium (4×2) footprints reserve real grid cells. Widgets can be dragged, moved between pages, resized and removed. Tap a widget to edit its size/page, change a photo or remove it; long-press actions are also declared. Overlapping icons reflow into available cells instead of being lost. Existing saved Home layouts migrate without resetting their icons or dock.

Photo selection uses the existing native Photos picker. A resized JPEG copy (up to 2000 pixels) is saved in Application Support/Strata/Widgets under a generated UUID filename; the original Photos image is unchanged. Display thumbnails are bounded to 1024 pixels with a 32 MB memory cache. Removing a photo widget removes its owned copy. Clock and Calendar use the device's current time/date; Calendar does not request or display personal calendar events. Batteries reads the device battery level and charging state; the simulator may report an unavailable level.

## Theme assessment

The supplied archive is PS5ish 5.0.3 by David Griggs, a Playnite Fullscreen XAML theme. Its top navigation, horizontal rail, selected cover enlargement, art, transitions and controller actions can be recreated in SwiftUI. The 1920×1080 desktop canvas must be adapted to actual safe areas and aspect ratios. Playnite-specific services need real supported counterparts. See docs/PS5ish-Theme-Assessment.md for the mapping. Cinematic has not been replaced by this theme in revision 13.

## Verification

Release arm64 build passes. Pure model checks pass for old-layout migration, widget occupancy, placement/reflow/resize, page removal, app/folder preservation, persistence and 150 repeated moves. Targeted iPhone 15 Pro simulator checks pass for adding and editing a widget, resizing, adding/removing pages, relaunch persistence and widget removal; separate checks pass for photo/clock/calendar/battery layout and persistence, and existing Home folder/edit mode behavior. Screenshots were inspected. Native Photos selection on the physical phone and the real battery reading remain device checks.

The combined package retains the revision 12 JIT startup gate and original execution framework/SideStore components. The known LiveExec32 runtime-not-found problem from the revision 12 phone log remains unresolved in this UI update. This build does not claim working 32-bit guest execution.

Install through the current bundled SideStore as an update, keeping all extensions. GitHub remains on public experimental revision 11; this local revision has not been published as a release.
