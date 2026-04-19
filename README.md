# smoovmux

Native macOS tmux-first terminal multiplexer, built on [libghostty](https://github.com/ghostty-org/ghostty).

**Status:** M0 scaffold. Nothing user-facing works yet.

## Stack

- Swift 6 · AppKit (hot paths) · SwiftUI (chrome)
- libghostty via `GhosttyKit.xcframework` (our fork, vendored as a submodule)
- SwiftData · tmux control mode (`-CC`)
- macOS 15+

## Dev quickstart

```sh
git clone --recurse-submodules https://github.com/boozedog/smoovmux.git
cd smoovmux
mise install                          # pins zig + xcodegen
./scripts/setup.sh                    # builds GhosttyKit.xcframework
xcodegen                              # generates smoovmux.xcodeproj
./scripts/reload.sh --tag dev --launch
```

## Contributing

Read [CLAUDE.md](./CLAUDE.md) first — it covers the load-bearing rules (tmux mandatory, no native NSWindow tabs, privacy constraints, git signing, build tagging).

Milestones and issues: <https://github.com/boozedog/smoovmux/issues>
