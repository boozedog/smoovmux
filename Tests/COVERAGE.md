# Test coverage notes

Current tests cover the production policy that can be exercised without launching AppKit or libghostty:

- `SessionCore`: binary resolution and PTY lifecycle basics.
- `WorkspaceTabs`: tab selection, addition, close behavior, fallback selection.
- `WorkspacePanes`: pane split/close tree policy used by `PaneController`, including decoded selection normalization.
- `WorkspaceState`: workspace persistence snapshots for tab order/selection, split trees, pane cwd, and window frame.
- `SmoovAppCommands`: command titles and shortcut collision/assignment policy.
- `SmoovLog`: sensitive key/value redaction policy.

Intentionally not unit-tested yet:

- `SmoovSurfaceView` direct libghostty calls, rendering, and input delivery. These need either a GhosttyKit test seam or UI/integration tests because behavior depends on real AppKit events and `ghostty_surface_t` state.
- `GhosttyApp` C callback trampolines. These are thin integration glue over libghostty callback ABI and should be covered by future app smoke/UI tests.
- SwiftUI tab chrome visuals. The backing tab policy is covered; visual regressions should be handled by future UI/snapshot tests if needed.

Before adding new features, prefer extracting pure policy into `Sources/*` targets first, then wiring AppKit/SwiftUI/Ghostty on top.
