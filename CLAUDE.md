# smoovmux — Claude context

Native macOS app. A tmux-first terminal multiplexer built on libghostty, with optional SSH.

## Core principles (load-bearing rules)

- **tmux is mandatory.** Every pane is a tmux pane. No non-tmux mode. (#16)
- **Never use native `NSWindow` tabs.** No `addTabbedWindow`, no `tabbingMode`. AeroSpace/yabai see native tabs as separate windows. Custom tab bar in a single NSWindow. (#2)
- **AppKit on hot paths, SwiftUI on chrome.** Terminal surface, window controller → AppKit. Settings, sidebar, palette → SwiftUI. (#1)
- **External binaries resolved via user's login-shell PATH**, not launchd's minimal env. (#19)

## Stack

- **Language:** Swift 6, strict concurrency on.
- **UI:** AppKit for terminal surface + window management; SwiftUI for settings, sidebar, command palette.
- **Rendering:** libghostty via `GhosttyKit.xcframework`, built from our `ghostty` submodule (fork of `ghostty-org/ghostty`).
- **Persistence:** SwiftData (macOS 15+). Schema decisions locked in #4.
- **tmux wire format:** `-CC` control mode. Decision in #3.
- **SSH:** TBD in #5. Assume system `ssh(1)` until decided.
- **Deployment target:** macOS 15 (required for cleaner SwiftData APIs).

## Modules (SPM, at repo root)

- `TmuxCC` — control-mode parser + layout types. Zero deps. Has unit tests.
- `SessionCore` — `Session` protocol + session-kind enums. No AppKit/SwiftUI deps.
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

Zig is pinned to `0.15.2` via `mitchellh/zig-overlay` to match `ghostty/build.zig.zon .minimum_zig_version`. Bump both together.

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
- `~/projects/iterm2` — canonical tmux-CC reference (`sources/Tmux*.m`).
- `~/projects/ghostty` — upstream, for `macos/Sources/` and `src/apprt/embedded.zig` C API.

## Milestones

M0 (scaffold) — this commit. Issues #7–#15.
M1 (one pane, typing works) — #20–#26.

See `https://github.com/boozedog/smoovmux/issues` for the full plan.
