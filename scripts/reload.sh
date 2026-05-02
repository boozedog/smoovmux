#!/usr/bin/env bash
# scripts/reload.sh — tagged Debug build.
#
# Every debug build gets a --tag <slug>. That tag keys:
#   - DerivedData path  (/tmp/smoovmux-derived-<tag>)
#   - bundle id         (pw.dbu.smoovmux.dev.<tag>)
#   - display name      ("smoovmux DEV <tag>")
#   - log path           (/tmp/smoovmux-debug-<tag>.log)
#
# Multiple tagged builds coexist. An untagged build is rejected on purpose
# so bare `xcodebuild` or "smoovmux DEV.app" do not collide on bundle ids.
#
# Usage:
#   ./scripts/reload.sh --tag <slug> [--launch]

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

TAG=""
LAUNCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tag)
      TAG="${2:-}"
      shift 2 || { echo "error: --tag needs an argument" >&2; exit 2; }
      ;;
    --launch)
      LAUNCH=1
      shift
      ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *)
      echo "error: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$TAG" ]; then
  echo "error: --tag <slug> is required (never launch an untagged build)" >&2
  exit 2
fi
if ! [[ "$TAG" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
  echo "error: tag must match [a-z0-9][a-z0-9_-]*: '$TAG'" >&2
  exit 2
fi

log() { printf '[reload:%s] %s\n' "$TAG" "$*"; }

DERIVED="/tmp/smoovmux-derived-$TAG"
BUNDLE_ID="pw.dbu.smoovmux.dev.$TAG"
DISPLAY_NAME="smoovmux DEV $TAG"
LOG_PATH="/tmp/smoovmux-debug-$TAG.log"

# Kill any running instance with this tag.
if pgrep -f "smoovmux-derived-$TAG" >/dev/null; then
  log "killing previous tagged instance"
  pkill -f "smoovmux-derived-$TAG" || true
  sleep 0.3
fi

# Regenerate project if project.yml is newer than the .xcodeproj.
if [ ! -d "$REPO_ROOT/smoovmux.xcodeproj" ] || [ "$REPO_ROOT/project.yml" -nt "$REPO_ROOT/smoovmux.xcodeproj" ]; then
  log "regenerating smoovmux.xcodeproj (project.yml changed)"
  if command -v mise >/dev/null && mise current xcodegen >/dev/null 2>&1; then
    ( cd "$REPO_ROOT" && mise exec -- xcodegen generate )
  else
    ( cd "$REPO_ROOT" && xcodegen generate )
  fi
fi

log "building (DerivedData=$DERIVED)"
# LD=clang: Xcode 26 regression — the partial "Ld" step for SPM modules
# builds clang-driver flags (-isysroot, -iframework, -nostdlib,
# -fobjc-link-runtime) but invokes raw ld, which rejects them. Routing LD
# through clang lets the driver translate them. Command-line override
# propagates to SPM package targets; project.yml base settings do not.
# Remove once Apple fixes it.
XCODE_TOOLCHAIN="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain"
xcodebuild \
  -project smoovmux.xcodeproj \
  -scheme smoovmux \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  LD="$XCODE_TOOLCHAIN/usr/bin/clang" \
  INFOPLIST_PREPROCESS=YES \
  GCC_PREPROCESSOR_DEFINITIONS='$(inherited) SMOOVMUX_TAG='"\"$TAG\"" \
  build 2>&1 | tail -40

APP_PATH="$DERIVED/Build/Products/Debug/smoovmux.app"
if [ ! -d "$APP_PATH" ]; then
  echo "error: built app not found at $APP_PATH" >&2
  exit 1
fi

# Overlay display name into the built bundle's Info.plist so Dock/menu show the tag.
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName '$DISPLAY_NAME'" "$APP_PATH/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string '$DISPLAY_NAME'" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier '$BUNDLE_ID'" "$APP_PATH/Contents/Info.plist"

# Record latest log path for tooling.
printf '%s\n' "$LOG_PATH" > /tmp/smoovmux-last-debug-log-path

printf '\nApp path: %s\n' "$APP_PATH"
printf 'Bundle id: %s\n' "$BUNDLE_ID"
printf 'Log path: %s\n' "$LOG_PATH"

if [ "$LAUNCH" -eq 1 ]; then
  log "launching"
  SMOOVMUX_TAG="$TAG" \
  open -n "$APP_PATH" --stdout "$LOG_PATH" --stderr "$LOG_PATH"
fi
