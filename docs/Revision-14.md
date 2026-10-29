# Strata revision 14

Small widgets are square and medium widgets share their reduced height. Home row spacing is reduced from 99 to 93 points (editing: 92 to 88) to follow the supplied native Home screenshot more closely.

Widget backgrounds now offer Dark Gradient (opaque charcoal-to-black, default) and Liquid Glass in both Add Widget and Edit Widget. Existing revision 13 widgets migrate to the gradient default without losing their IDs, photos, sizes or page assignments. Tap a widget to change its background. Photo content remains an owned image copy.

Release arm64 build passes. Existing Home model regression checks and new old-widget migration/background persistence checks pass. This focused update did not rerun the simulator UI suite or claim pixel-identical screenshot verification. The prior separate JIT runtime lookup issue remains pending.

Install Strata+SideStore-3.8.11-r14.ipa through the existing SideStore as an update, keeping all extensions.
