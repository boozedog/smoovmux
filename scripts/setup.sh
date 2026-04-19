#!/usr/bin/env bash
# scripts/setup.sh — idempotent bootstrap.
#
# Run once after clone. Safe to rerun.
#
#   1. git submodule update --init --recursive
#   2. Resolve Zig (prefer mise pin, fall back to PATH).
#   3. Build GhosttyKit.xcframework if stale.
#   4. Generate Xcode project via XcodeGen if missing.
#
# Exits non-zero on any failure.

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

log() { printf '[setup] %s\n' "$*"; }
die() { printf '[setup] error: %s\n' "$*" >&2; exit 1; }

log "initialising submodules"
git submodule update --init --recursive

# --- Zig ---------------------------------------------------------------------

if command -v mise >/dev/null && mise current zig >/dev/null 2>&1; then
  ZIG="mise exec -- zig"
  log "using mise-pinned zig ($(mise current zig))"
else
  if ! command -v zig >/dev/null; then
    die "zig not found. Install mise and run 'mise install', or put zig on PATH."
  fi
  printf '[setup] warning: mise not pinning zig — using PATH zig (%s)\n' "$(zig version)" >&2
  ZIG="zig"
fi

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
  ( cd "$REPO_ROOT/ghostty" \
    && $ZIG build \
      -Demit-xcframework=true \
      -Dxcframework-target=universal \
      -Doptimize=ReleaseFast )
  # ghostty emits to macos/GhosttyKit.xcframework — link or copy into repo root.
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
  if command -v mise >/dev/null && mise current xcodegen >/dev/null 2>&1; then
    log "generating smoovmux.xcodeproj via xcodegen (mise)"
    ( cd "$REPO_ROOT" && mise exec -- xcodegen generate )
  elif command -v xcodegen >/dev/null; then
    log "generating smoovmux.xcodeproj via xcodegen (PATH)"
    ( cd "$REPO_ROOT" && xcodegen generate )
  else
    die "xcodegen not found. Install mise + run 'mise install', or 'brew install xcodegen'."
  fi
else
  log "smoovmux.xcodeproj exists — rerun 'xcodegen generate' manually if project.yml changed"
fi

cat <<'EOF'

[setup] done.

Next:
  ./scripts/reload.sh --tag dev --launch

Or open smoovmux.xcodeproj in Xcode.
EOF
