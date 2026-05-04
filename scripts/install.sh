#!/usr/bin/env bash
# scripts/install.sh — Release install build.
#
# Builds a production-identity app bundle and installs it to /Applications by
# default. Unlike scripts/reload.sh, this never applies a dev tag: macOS should
# see this bundle as plain "smoovmux" with bundle id "dog.booze.smoovmux".
#
# Usage:
#   ./scripts/install.sh [--install-dir /Applications] [--launch]

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

INSTALL_DIR="/Applications"
LAUNCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --install-dir)
      INSTALL_DIR="${2:-}"
      shift 2 || { echo "error: --install-dir needs an argument" >&2; exit 2; }
      ;;
    --launch)
      LAUNCH=1
      shift
      ;;
    -h|--help)
      sed -n '2,9p' "$0"
      exit 0
      ;;
    *)
      echo "error: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

log() { printf '[install] %s\n' "$*"; }

DERIVED="${SMOOVMUX_INSTALL_DERIVED:-/tmp/smoovmux-install-derived}"
BUNDLE_ID="dog.booze.smoovmux"
DISPLAY_NAME="smoovmux"
APP_NAME="smoovmux.app"
BUILT_APP="$DERIVED/Build/Products/Release/$APP_NAME"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME"

# Regenerate project if project.yml is newer than the .xcodeproj.
if [ ! -d "$REPO_ROOT/smoovmux.xcodeproj" ] || [ "$REPO_ROOT/project.yml" -nt "$REPO_ROOT/smoovmux.xcodeproj" ]; then
  log "regenerating smoovmux.xcodeproj (project.yml changed)"
  if command -v mise >/dev/null && mise current xcodegen >/dev/null 2>&1; then
    ( cd "$REPO_ROOT" && mise exec -- xcodegen generate )
  else
    ( cd "$REPO_ROOT" && xcodegen generate )
  fi
fi

log "building Release (DerivedData=$DERIVED)"
XCODE_TOOLCHAIN="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain"
xcodebuild \
  -project smoovmux.xcodeproj \
  -scheme smoovmux \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  LD="$XCODE_TOOLCHAIN/usr/bin/clang" \
  build 2>&1 | tail -80

if [ ! -d "$BUILT_APP" ]; then
  echo "error: built app not found at $BUILT_APP" >&2
  exit 1
fi

# Be explicit even though Release/project.yml should already produce these.
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName '$DISPLAY_NAME'" "$BUILT_APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string '$DISPLAY_NAME'" "$BUILT_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName '$DISPLAY_NAME'" "$BUILT_APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleName string '$DISPLAY_NAME'" "$BUILT_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier '$BUNDLE_ID'" "$BUILT_APP/Contents/Info.plist"

mkdir -p "$INSTALL_DIR"
log "installing $INSTALLED_APP"
rm -rf "$INSTALLED_APP"
ditto "$BUILT_APP" "$INSTALLED_APP"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f -R "$INSTALLED_APP"
fi

INSTALLED_DISPLAY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$INSTALLED_APP/Contents/Info.plist")"
INSTALLED_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALLED_APP/Contents/Info.plist")"
if [ "$INSTALLED_DISPLAY_NAME" != "$DISPLAY_NAME" ]; then
  echo "error: installed CFBundleDisplayName is '$INSTALLED_DISPLAY_NAME', expected '$DISPLAY_NAME'" >&2
  exit 1
fi
if [ "$INSTALLED_BUNDLE_ID" != "$BUNDLE_ID" ]; then
  echo "error: installed CFBundleIdentifier is '$INSTALLED_BUNDLE_ID', expected '$BUNDLE_ID'" >&2
  exit 1
fi

printf '\nInstalled app: %s\n' "$INSTALLED_APP"
printf 'Bundle id: %s\n' "$BUNDLE_ID"
printf 'Display name: %s\n' "$DISPLAY_NAME"

if [ "$LAUNCH" -eq 1 ]; then
  log "launching"
  open "$INSTALLED_APP"
fi
