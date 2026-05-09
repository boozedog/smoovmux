#!/usr/bin/env bash
# scripts/release.sh — signed, notarized GitHub release build.
#
# Creates notarized zip and dmg artifacts containing smoovmux.app, then creates
# a draft GitHub release with both artifacts attached.
#
# Optionally bumps the Homebrew tap cask if --tap-repo is specified.
#
# Usage:
#   ./scripts/release.sh [--version 0.0.1] [--notary-profile smoovmux-notary] [--tap-repo boozedog/homebrew-tap]

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
VERSION=""  # extracted from git tag or --version argument
CREATE_GITHUB=1
DRAFT=1
TAP_REPO="boozedog/homebrew-tap"
TAP_REPO_PATH=""  # local path to tap repo; defaults to ../homebrew-tap

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
    --tap-repo)
      TAP_REPO="${2:-}"
      shift 2 || { echo "error: --tap-repo needs an argument (e.g., boozedog/homebrew-tap)" >&2; exit 2; }
      ;;
    --tap-repo-path)
      TAP_REPO_PATH="${2:-}"
      shift 2 || { echo "error: --tap-repo-path needs an argument" >&2; exit 2; }
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
      sed -n '2,10p' "$0"
      exit 0
      ;;
    *)
      echo "error: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

# If version not provided via --version, extract from current git tag
if [ -z "$VERSION" ]; then
  if TAG_NAME=$(git describe --tags --exact-match 2>/dev/null); then
    # Strip leading 'v' from tag (v0.0.6 -> 0.0.6)
    VERSION="${TAG_NAME#v}"
    log "extracted version $VERSION from git tag $TAG_NAME"
  else
    echo "error: not on a git tag. either:" >&2
    echo "  1. create a tag first: git tag -a v0.0.6 -m 'Release 0.0.6'" >&2
    echo "  2. or provide --version: ./scripts/release.sh --version 0.0.6" >&2
    exit 2
  fi
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)?$ ]]; then
  echo "error: version must look like 0.0.1, got '$VERSION'" >&2
  exit 2
fi

TAG="v$VERSION"
ARCHIVE_PATH="$BUILD_DIR/smoovmux.xcarchive"
ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME"
NOTARY_ZIP="$BUILD_DIR/smoovmux-$VERSION-notary-submit.zip"
ARTIFACT="$BUILD_DIR/smoovmux-$VERSION-macos-universal.zip"
DMG_ARTIFACT="$BUILD_DIR/smoovmux-$VERSION-macos-universal.dmg"

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
need hdiutil
need shasum
need git
if [ "$CREATE_GITHUB" -eq 1 ]; then
  need gh
fi

# Update Info.plist with version from git tag
log "updating Info.plist with version $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString '$VERSION'" "$REPO_ROOT/App/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string '$VERSION'" "$REPO_ROOT/App/Info.plist"

# Create tag if it doesn't exist (happens when --version was provided)
if [ -d "$REPO_ROOT/.git" ]; then
  if git rev-parse "$TAG" >/dev/null 2>&1; then
    # Check if tag points to current commit
    TAG_COMMIT=$(git rev-parse "$TAG^{commit}")
    HEAD_COMMIT=$(git rev-parse HEAD)
    if [ "$TAG_COMMIT" != "$HEAD_COMMIT" ]; then
      echo "error: git tag $TAG exists but points to different commit" >&2
      echo "  tag commit: $TAG_COMMIT" >&2
      echo "  HEAD commit: $HEAD_COMMIT" >&2
      echo "either:" >&2
      echo "  1. delete and recreate the tag: git tag -d $TAG && git push --delete origin $TAG" >&2
      echo "  2. or checkout the tag: git checkout $TAG" >&2
      exit 2
    fi
    log "git tag $TAG already exists on current commit"
  else
    log "creating git tag $TAG"
    git -C "$REPO_ROOT" tag -a "$TAG" -m "Release $VERSION"
  fi

  # Push tag to origin if not already pushed
  if ! git ls-remote --tags origin "$TAG" | grep -q "$TAG"; then
    log "pushing git tag $TAG to origin"
    git -C "$REPO_ROOT" push origin "$TAG"
  else
    log "git tag $TAG already on origin"
  fi
else
  log "warning: not a git repo, skipping tag operations"
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

log "creating signed dmg"
rm -f "$DMG_ARTIFACT"
hdiutil create \
  -volname "smoovmux" \
  -srcfolder "$ARCHIVED_APP" \
  -ov \
  -format UDZO \
  "$DMG_ARTIFACT"
codesign --sign "$SIGNING_IDENTITY" --timestamp "$DMG_ARTIFACT"

log "submitting dmg to Apple notary service"
xcrun notarytool submit "$DMG_ARTIFACT" --keychain-profile "$NOTARY_PROFILE" --wait

log "stapling dmg notarization ticket"
xcrun stapler staple "$DMG_ARTIFACT"
xcrun stapler validate "$DMG_ARTIFACT"
DMG_SHA256="$(shasum -a 256 "$DMG_ARTIFACT" | awk '{print $1}')"

log "assessing Gatekeeper status"
spctl --assess --type execute --verbose=4 "$ARCHIVED_APP"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_ARTIFACT"

if [ "$CREATE_GITHUB" -eq 1 ]; then
  if gh release view "$TAG" >/dev/null 2>&1; then
    log "updating existing GitHub release $TAG"
    gh release edit "$TAG" --title "$TAG" --notes "smoovmux $VERSION"
    gh release upload "$TAG" "$ARTIFACT" "$DMG_ARTIFACT" --clobber
  else
    log "creating draft GitHub release $TAG"
    GH_ARGS=(release create "$TAG" "$ARTIFACT" "$DMG_ARTIFACT" --title "$TAG" --notes "smoovmux $VERSION")
    if [ "$DRAFT" -eq 1 ]; then
      GH_ARGS+=(--draft)
    fi
    gh "${GH_ARGS[@]}"
  fi
fi

printf '\nRelease zip: %s\n' "$ARTIFACT"
printf 'Zip SHA256: %s\n' "$SHA256"
printf 'Release dmg: %s\n' "$DMG_ARTIFACT"
printf 'DMG SHA256: %s\n' "$DMG_SHA256"
printf 'Git tag: %s\n' "$TAG"

# Bump Homebrew tap cask if requested
if [ -n "$TAP_REPO" ]; then
  if [ -z "$TAP_REPO_PATH" ]; then
    TAP_REPO_PATH="$REPO_ROOT/../homebrew-tap"
  fi

  log "bumping Homebrew tap cask in $TAP_REPO"

  if [ ! -d "$TAP_REPO_PATH/.git" ]; then
    log "cloning tap repo $TAP_REPO to $TAP_REPO_PATH"
    git clone "https://github.com/$TAP_REPO.git" "$TAP_REPO_PATH" || {
      log "failed to clone tap repo; skipping tap bump"
      exit 0
    }
  fi

  CASK_FILE="$TAP_REPO_PATH/Casks/smoovmux.rb"
  if [ ! -f "$CASK_FILE" ]; then
    log "cask file not found at $CASK_FILE; skipping tap bump"
    log "(create the tap repo and initial cask first)"
    exit 0
  fi

  # Update version and sha256 in the cask
  log "updating cask at $CASK_FILE"
  sed -i.bak -E "s/^(  version )\"[0-9]+\.[0-9]+\.[0-9]+[^\"]*\"/\1\"$VERSION\"/" "$CASK_FILE"
  sed -i.bak -E "s/^(  sha256 )\"[a-f0-9]{64}\"/\1\"$SHA256\"/" "$CASK_FILE"
  rm -f "$CASK_FILE.bak"

  (cd "$TAP_REPO_PATH" && \
    git add Casks/smoovmux.rb && \
    git commit -m "bump smoovmux to $VERSION" && \
    git push) || {
    log "tap bump failed (possibly no changes or network issue)"
    exit 0
  }

  log "tap bumped successfully: $TAP_REPO updated to $VERSION"
fi
