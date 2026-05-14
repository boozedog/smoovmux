# smoovmux

Native macOS terminal workspace, built on [libghostty](https://github.com/ghostty-org/ghostty).

**Status:** M1 prototype. One terminal pane renders and accepts input.

## Installation (Homebrew)

```bash
brew tap boozedog/tap
brew install --cask smoovmux
```

Or in one command:

```bash
brew install --cask boozedog/tap/smoovmux
```

Upgrade later with:

```bash
brew upgrade smoovmux
```

To remove (including user data):

```bash
brew uninstall --cask --zap smoovmux
```

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
./scripts/reload.sh --tag dev --launch # tagged dev build: "smoovmux DEV dev"
./scripts/install.sh --launch          # Release install to /Applications: "smoovmux"
```

## Release

Run releases from a clean `master` checkout with signing/notarization credentials available:

```sh
./scripts/release.sh --version 0.0.7
```

The helper script:

- updates `App/Info.plist` with the marketing version and an incremented build number
- commits and pushes the release version bump
- creates and pushes the `v0.0.7` git tag
- archives, signs, notarizes, and staples the app
- creates ZIP and DMG artifacts under `build/release/`
- creates a draft GitHub release with both artifacts attached
- bumps the Homebrew cask in `../homebrew-tap` when the tap/cask is available (cloning if needed)

Pass `--build <n>` to override the auto-incremented build number, and `--publish` to create a non-draft GitHub release.

## Contributing

Read [CLAUDE.md](./CLAUDE.md) first — it covers the load-bearing rules (no native NSWindow tabs, privacy constraints, git signing, build tagging).

Milestones and issues: <https://github.com/boozedog/smoovmux/issues>
