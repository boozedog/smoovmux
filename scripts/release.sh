#!/usr/bin/env bash
# scripts/release.sh — signed, notarized GitHub release build.
#
# Creates a notarized zip containing smoovmux.app, then creates a draft GitHub
# release with that zip attached.
#
# Usage:
#   ./scripts/release.sh [--version 0.0.1] [--notary-profile smoovmux-notary]

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

APP_NAME="smoovmux.app"
BUNDLE_ID="dog.booze.smoovmux"
DISPLAY_NAME="smoovmux"
TEAM_ID="T6RPYRHYEV"
SIGNING_IDENTITY="Developer ID Application: BuserNet Consulting LLC (T6RPYRHYEV)"
NOTARY_PROFILE="smoovmux-notary"
BUILD_DIR="build/release"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Info.plist)"
CREATE_GITHUB=1
DRAFT=1

while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2 || { echo "error: --version needs an argument" >&2; exit 2; }
      ;;
    --build-dir)
      BUILD_DIR="${2:-}"
      shift 2 || { echo "error: --build-dir needs an argument" >&2; exit 2; }
      ;;
    --notary-profile)
      NOTARY_PROFILE="${2:-}"
      shift 2 || { echo "error: --notary-profile needs an argument" >&2; exit 2; }
      ;;
    --signing-identity)
      SIGNING_IDENTITY="${2:-}"
      shift 2 || { echo "error: --signing-identity needs an argument" >&2; exit 2; }
      ;;
    --team-id)
      TEAM_ID="${2:-}"
      shift 2 || { echo "error: --team-id needs an argument" >&2; exit 2; }
      ;;
    --skip-github)
      CREATE_GITHUB=0
      shift
      ;;
    --publish)
      DRAFT=0
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

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)?$ ]]; then
  echo "error: version must look like 0.0.1, got '$VERSION'" >&2
  exit 2
fi

TAG="v$VERSION"
ARCHIVE_PATH="$BUILD_DIR/smoovmux.xcarchive"
ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME"
NOTARY_ZIP="$BUILD_DIR/smoovmux-$VERSION-notary-submit.zip"
ARTIFACT="$BUILD_DIR/smoovmux-$VERSION-macos-universal.zip"

log() { printf '[release:%s] %s\n' "$VERSION" "$*"; }
need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

need xcodebuild
need codesign
need xcrun
need ditto
need shasum
if [ "$CREATE_GITHUB" -eq 1 ]; then
  need gh
fi

if [ ! -d "$REPO_ROOT/smoovmux.xcodeproj" ] || [ "$REPO_ROOT/project.yml" -nt "$REPO_ROOT/smoovmux.xcodeproj" ]; then
  log "regenerating smoovmux.xcodeproj (project.yml changed)"
  if command -v mise >/dev/null && mise current xcodegen >/dev/null 2>&1; then
    ( cd "$REPO_ROOT" && mise exec -- xcodegen generate )
  else
    ( cd "$REPO_ROOT" && xcodegen generate )
  fi
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

log "archiving Release app"
XCODE_TOOLCHAIN="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain"
xcodebuild \
  -project smoovmux.xcodeproj \
  -scheme smoovmux \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  LD="$XCODE_TOOLCHAIN/usr/bin/clang" \
  archive 2>&1 | tail -120

if [ ! -d "$ARCHIVED_APP" ]; then
  echo "error: archived app not found at $ARCHIVED_APP" >&2
  exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName '$DISPLAY_NAME'" "$ARCHIVED_APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string '$DISPLAY_NAME'" "$ARCHIVED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName '$DISPLAY_NAME'" "$ARCHIVED_APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleName string '$DISPLAY_NAME'" "$ARCHIVED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier '$BUNDLE_ID'" "$ARCHIVED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString '$VERSION'" "$ARCHIVED_APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string '$VERSION'" "$ARCHIVED_APP/Contents/Info.plist"

log "verifying Developer ID signature"
codesign --verify --deep --strict --verbose=4 "$ARCHIVED_APP"
codesign -dv --verbose=4 "$ARCHIVED_APP"

log "submitting to Apple notary service"
ditto -c -k --keepParent "$ARCHIVED_APP" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

log "stapling notarization ticket"
xcrun stapler staple "$ARCHIVED_APP"
xcrun stapler validate "$ARCHIVED_APP"

log "creating final zip"
rm -f "$ARTIFACT"
ditto -c -k --keepParent "$ARCHIVED_APP" "$ARTIFACT"
SHA256="$(shasum -a 256 "$ARTIFACT" | awk '{print $1}')"

log "assessing Gatekeeper status"
spctl --assess --type execute --verbose=4 "$ARCHIVED_APP"

if [ "$CREATE_GITHUB" -eq 1 ]; then
  log "creating draft GitHub release $TAG"
  GH_ARGS=(release create "$TAG" "$ARTIFACT" --title "$TAG" --notes "smoovmux $VERSION")
  if [ "$DRAFT" -eq 1 ]; then
    GH_ARGS+=(--draft)
  fi
  gh "${GH_ARGS[@]}"
fi

printf '\nRelease artifact: %s\n' "$ARTIFACT"
printf 'Git tag: %s\n' "$TAG"
printf 'SHA256: %s\n' "$SHA256"
