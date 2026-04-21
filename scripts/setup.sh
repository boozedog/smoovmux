#!/usr/bin/env bash
# scripts/setup.sh — idempotent bootstrap.
#
# Run once after clone. Safe to rerun.
#
#   1. git submodule update --init --recursive
#   2. Verify zig + xcodegen are on PATH (devenv shell must be active).
#   3. Build GhosttyKit.xcframework if stale.
#   4. Generate Xcode project via XcodeGen if missing.
#
# Tooling pins live in devenv.nix. Activate the shell first:
#   direnv allow                # one-time, then auto on cd
# or:
#   devenv shell -- ./scripts/setup.sh
#
# Exits non-zero on any failure.

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

log() { printf '[setup] %s\n' "$*"; }
die() { printf '[setup] error: %s\n' "$*" >&2; exit 1; }

# --- Tooling sanity check ----------------------------------------------------

command -v zig      >/dev/null || die "zig not on PATH. Run 'direnv allow' or 'devenv shell' first."
command -v xcodegen >/dev/null || die "xcodegen not on PATH. Run 'direnv allow' or 'devenv shell' first."

log "using zig $(zig version)"

# --- Submodules --------------------------------------------------------------

log "initialising submodules"
git submodule update --init --recursive

# --- GhosttyKit.xcframework --------------------------------------------------

XCFRAMEWORK="$REPO_ROOT/GhosttyKit.xcframework"
GHOSTTY_HEAD="$(git -C "$REPO_ROOT/ghostty" rev-parse HEAD)"
STAMP="$XCFRAMEWORK/.smoovmux-ghostty-sha"

needs_build=0
if [ ! -d "$XCFRAMEWORK" ]; then
  needs_build=1
elif [ ! -f "$STAMP" ] || [ "$(cat "$STAMP")" != "$GHOSTTY_HEAD" ]; then
  needs_build=1
fi

if [ "$needs_build" -eq 1 ]; then
  log "building GhosttyKit.xcframework (ghostty @ ${GHOSTTY_HEAD:0:12})"
  # Ensure Apple's /usr/bin/libtool wins over nix's GNU libtool for this
  # invocation — zig's xcframework step runs `libtool -static -o …` which
  # is Apple-flavoured. Nix's libtool is only on PATH for autotools
  # (libtoolize) and rejects Apple flags.
  SHIM="$REPO_ROOT/.zig-bin-shim"
  rm -rf "$SHIM" && mkdir -p "$SHIM"
  ln -sfn /usr/bin/libtool "$SHIM/libtool"
  # -Demit-macos-app=false: we don't need ghostty's own .app here, only the
  # xcframework. ghostty defaults macos_app to true when emit-xcframework
  # is set, and that step invokes xcodebuild (requires full Xcode + extra
  # setup). Smoovmux only needs GhosttyKit.xcframework.
  ( cd "$REPO_ROOT/ghostty" \
    && PATH="$SHIM:$PATH" zig build \
      -Demit-xcframework=true \
      -Demit-macos-app=false \
      -Dxcframework-target=universal \
      -Doptimize=ReleaseFast )
  if [ -d "$REPO_ROOT/ghostty/macos/GhosttyKit.xcframework" ]; then
    rm -rf "$XCFRAMEWORK"
    cp -R "$REPO_ROOT/ghostty/macos/GhosttyKit.xcframework" "$XCFRAMEWORK"
  else
    die "zig build completed but GhosttyKit.xcframework not found under ghostty/macos/"
  fi
  printf '%s\n' "$GHOSTTY_HEAD" > "$STAMP"
else
  log "GhosttyKit.xcframework up to date"
fi

# --- Xcode project -----------------------------------------------------------

if [ ! -d "$REPO_ROOT/smoovmux.xcodeproj" ]; then
  log "generating smoovmux.xcodeproj via xcodegen"
  ( cd "$REPO_ROOT" && xcodegen generate )
else
  log "smoovmux.xcodeproj exists — rerun 'xcodegen generate' manually if project.yml changed"
fi

cat <<'EOF'

[setup] done.

Next:
  ./scripts/reload.sh --tag dev --launch

Or open smoovmux.xcodeproj in Xcode.
EOF
