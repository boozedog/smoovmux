# smoovmux

Native macOS terminal workspace, built on [libghostty](https://github.com/ghostty-org/ghostty).

**Status:** M1 prototype. One terminal pane renders and accepts input.

## Stack

- Swift 6 · AppKit (hot paths) · SwiftUI (chrome)
- libghostty via `GhosttyKit.xcframework` (our fork, vendored as a submodule)
- SwiftData
- macOS 15+

## Dev quickstart

```sh
git clone --recurse-submodules https://github.com/boozedog/smoovmux.git
cd smoovmux

# One-time: install patched zig 0.15.2 (macOS 26 needs a libSystem.tbd fix
# that only exists in Homebrew's formula — see CLAUDE.md "Dev environment").
brew tap-new --no-git boozedog/zig015
brew extract --version=0.15.2 zig boozedog/zig015
brew install boozedog/zig015/zig@0.15.2

direnv allow                          # activates devenv (xcodegen, swiftlint, …)
./scripts/setup.sh                    # builds GhosttyKit.xcframework
./scripts/reload.sh --tag dev --launch
```

## Contributing

Read [CLAUDE.md](./CLAUDE.md) first — it covers the load-bearing rules (no native NSWindow tabs, privacy constraints, git signing, build tagging).

Milestones and issues: <https://github.com/boozedog/smoovmux/issues>
