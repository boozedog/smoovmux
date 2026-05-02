# smoovmux — Claude context

Native macOS terminal workspace built on libghostty, with optional SSH.

## Core principles (load-bearing rules)

- **tmux is just a terminal app.** Users who want tmux run it inside a normal smoovmux pane; smoovmux does not control tmux with `-CC`.
- **Never use native `NSWindow` tabs.** No `addTabbedWindow`, no `tabbingMode`. AeroSpace/yabai see native tabs as separate windows. Custom tab bar in a single NSWindow. (#2)
- **AppKit on hot paths, SwiftUI on chrome.** Terminal surface, window controller → AppKit. Settings, sidebar, palette → SwiftUI. (#1)
- **External binaries resolved via user's login-shell PATH**, not launchd's minimal env. (#19)

## Stack

- **Language:** Swift 6, strict concurrency on.
- **UI:** AppKit for terminal surface + window management; SwiftUI for settings, sidebar, command palette.
- **Rendering:** libghostty via `GhosttyKit.xcframework`, built from our `ghostty` submodule (fork of `ghostty-org/ghostty`).
- **Persistence:** SwiftData (macOS 15+). Schema decisions locked in #4.
- **SSH:** TBD in #5. Assume system `ssh(1)` until decided.
- **Deployment target:** macOS 15 (required for cleaner SwiftData APIs).

## Modules (SPM, at repo root)

- `SessionCore` — `Session` protocol, session-kind enums, PTY helpers, binary resolution. No AppKit/SwiftUI deps.
- `SmoovLog` — logging facade + `redact()`. Pure value types.

App target in `smoovmux.xcodeproj` depends on these via local SPM package reference.

## Privacy — enforce in code, not policy

- **Never log pane bytes.** Terminal I/O bytes are PII-grade. Logging facade must reject them.
- **Redact SSH config** in any log line: host aliases OK, hostnames/usernames/keys redacted.
- **Agent-only SSH auth.** No password prompts, no key files read by us — ssh-agent or bust.
- **No telemetry.** No Sentry, no analytics, no "anonymous usage" anything.
- **Crash reports are local-only.** Ship a crash viewer, don't phone home.

## Formatting & linting

Toolchain (all pinned in `devenv.nix`):

- **`swift format`** (Apple, ships with Swift 6 toolchain) — formatting. Config: `.swift-format`.
- **swiftlint** — safety + correctness lint (force-unwraps, concurrency footguns, etc.). Config: `.swiftlint.yml`. Formatting-style rules are disabled there to avoid conflict with `swift format`.
- **gitleaks** — secret scanning. Config: `.gitleaks.toml`. Pre-commit on staged, pre-push on full repo.

Commands (see `Makefile` for the full list):

- `make fmt` — autoformat in place
- `make lint` — swiftlint, no autofix
- `make qa` — what pre-commit hooks and CI run (fmt-check + lint)
- `make secrets` — gitleaks scan

Indent: spaces (swift-format default). **Never tabs in Swift** — projects/CLAUDE.md's tabs rule is Go-only.

Other languages:

- **Markdown:** 2-space indent.
- **Shell:** 2-space indent, `set -euo pipefail` at the top.

## Git — inherited rules, don't re-litigate

- **Never bypass GPG signing.** No `--no-gpg-sign`, no `-c commit.gpgsign=false`. If GPG times out, stop and tell the user.
- **Never `git stash`.** Saved us real pain in the Electron repo. Make a WIP branch/commit instead.
- **Never force-push `master`.** Ruleset in `.github/rulesets/master.json` blocks it server-side.
- **Worktrees:** `.worktrees/` at repo root, never `.claude/worktrees/`.
- **Squash-merge only.** Enforced by ruleset.

## Submodule safety

The `ghostty` submodule points at `boozedog/ghostty` (our fork of `ghostty-org/ghostty`).

- Before bumping the submodule pointer in this repo, **push the submodule commit to its remote `main` first.** Otherwise clones fail.
- Fork-sync workflow: rebase our fork's `main` onto upstream `main`, push, then update the pointer here.
- Don't edit ghostty sources from inside this repo's submodule checkout without committing and pushing to the fork — the pointer will go stale.

## Dev environment

**Nix is required.** All tooling (zig, xcodegen, swiftlint, gitleaks, gnumake) is pinned in `devenv.nix` and provided via `devenv shell`. After clone:

```sh
direnv allow      # one-time, then auto on cd
```

Or invoke setup via `devenv shell -- ./scripts/setup.sh`.

Zig is **not** pinned through nix. Ghostty's `build.zig.zon .minimum_zig_version = "0.15.2"`, and on macOS 26+ the Xcode SDK's `libSystem.tbd` drops standalone `arm64-macos` (keeps only `arm64e-macos`); Zig 0.15.2's LLD fork can't reconcile the two, so every link fails with `undefined symbol: _abort` etc. (ghostty-org/ghostty#11991, codeberg.org/ziglang/zig#31658.) The fix is a patch to `src/link/MachO/Dylib.zig` that only exists in the Homebrew formula — no nix-zig build carries it, and zig isn't backporting to 0.15.x. Install the patched build via the `boozedog/zig015` tap (one-time):

```sh
brew tap-new --no-git boozedog/zig015
brew extract --version=0.15.2 zig boozedog/zig015
brew install boozedog/zig015/zig@0.15.2
```

`devenv.nix` prepends `/opt/homebrew/opt/zig@0.15.2/bin` to `PATH` so `devenv shell` picks it up automatically. Bump both zig and ghostty's pin together when upstream lands 0.16 migration (ghostty-org/ghostty#12228).

## Build / reload

Two scripts, both at the repo root:

- `./scripts/setup.sh` — idempotent bootstrap: inits submodules, builds `GhosttyKit.xcframework`, generates the Xcode project. Requires the devenv shell to be active.
- `./scripts/reload.sh --tag <slug> [--launch]` — tagged Debug build. DerivedData, socket, bundle-id, and display-name are all keyed by `<tag>` so multiple tagged builds can coexist without stomping each other. Prints `App path: ...` absolute path. Writes a log path marker to `/tmp/smoovmux-last-debug-log-path`.

**Never run bare `xcodebuild`** and never launch an untagged `smoovmux DEV.app` — socket and bundle-id conflicts will bite.

## Testing

- Unit: `xcodebuild test -scheme smoovmux-unit` (or `swift test` for the SPM modules alone).
- UI/E2E: CI only for now.

## Typing-latency pitfalls (port from cmux as we hit them)

Reserved. Populate when we start wiring the surface view in M1. For now, the short list from `~/projects/cmux/CLAUDE.md`:

- Don't allocate on keystroke paths.
- Don't round-trip through SwiftUI for per-keystroke state.
- Don't re-layout the whole window on cursor moves.

## Reference clones on this machine

- `~/projects/cmux` — another libghostty-based macOS app; CLAUDE.md has a pitfall list worth skimming.
- `~/projects/ghostty` — upstream, for `macos/Sources/` and `src/apprt/embedded.zig` C API.

## Milestones

M0 (scaffold) — this commit. Issues #7–#15.
M1 (one pane, typing works) — #20–#26.

See `https://github.com/boozedog/smoovmux/issues` for the full plan.
