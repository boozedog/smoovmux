#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="$TMP_DIR/bin"
BUILD_DIR="$TMP_DIR/release"
mkdir -p "$FAKE_BIN"

record() {
  printf '%s\n' "$*" >> "$TMP_DIR/calls.log"
}

cat > "$FAKE_BIN/xcodebuild" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >> "${SMOOVMUX_TEST_XCODEBUILD_ARGS:?}"
printf '\n' >> "$SMOOVMUX_TEST_XCODEBUILD_ARGS"
ARCHIVE=""
CONFIG=""
while [ $# -gt 0 ]; do
  case "$1" in
    -archivePath)
      ARCHIVE="$2"
      shift 2
      ;;
    -configuration)
      CONFIG="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
if [ "$CONFIG" != "Release" ]; then
  echo "expected Release configuration, got '$CONFIG'" >&2
  exit 1
fi
APP="$ARCHIVE/Products/Applications/smoovmux.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>smoovmux</string>
  <key>CFBundleDisplayName</key>
  <string>smoovmux</string>
  <key>CFBundleIdentifier</key>
  <string>dog.booze.smoovmux</string>
</dict>
</plist>
PLIST
SH
chmod +x "$FAKE_BIN/xcodebuild"

cat > "$FAKE_BIN/codesign" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'codesign %q ' "$@" >> "${SMOOVMUX_TEST_CALLS:?}"
printf '\n' >> "$SMOOVMUX_TEST_CALLS"
SH
chmod +x "$FAKE_BIN/codesign"

cat > "$FAKE_BIN/spctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'spctl %q ' "$@" >> "${SMOOVMUX_TEST_CALLS:?}"
printf '\n' >> "$SMOOVMUX_TEST_CALLS"
SH
chmod +x "$FAKE_BIN/spctl"

cat > "$FAKE_BIN/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'xcrun %q ' "$@" >> "${SMOOVMUX_TEST_CALLS:?}"
printf '\n' >> "$SMOOVMUX_TEST_CALLS"
SH
chmod +x "$FAKE_BIN/xcrun"

cat > "$FAKE_BIN/hdiutil" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'hdiutil %q ' "$@" >> "${SMOOVMUX_TEST_CALLS:?}"
printf '\n' >> "$SMOOVMUX_TEST_CALLS"
OUT="${@: -1}"
mkdir -p "$(dirname "$OUT")"
printf 'fake dmg\n' > "$OUT"
SH
chmod +x "$FAKE_BIN/hdiutil"

cat > "$FAKE_BIN/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'gh %q ' "$@" >> "${SMOOVMUX_TEST_CALLS:?}"
printf '\n' >> "$SMOOVMUX_TEST_CALLS"
SH
chmod +x "$FAKE_BIN/gh"

export PATH="$FAKE_BIN:$PATH"
export SMOOVMUX_TEST_XCODEBUILD_ARGS="$TMP_DIR/xcodebuild.args"
export SMOOVMUX_TEST_CALLS="$TMP_DIR/calls.log"

"$REPO_ROOT/scripts/release.sh" \
  --version 0.0.1 \
  --build-dir "$BUILD_DIR" \
  --notary-profile smoovmux-notary \
  --signing-identity "Developer ID Application: BuserNet Consulting LLC (T6RPYRHYEV)" \
  --team-id T6RPYRHYEV

ARTIFACT="$BUILD_DIR/smoovmux-0.0.1-macos-universal.zip"
DMG="$BUILD_DIR/smoovmux-0.0.1-macos-universal.dmg"
if [ ! -f "$ARTIFACT" ]; then
  echo "expected artifact at $ARTIFACT" >&2
  exit 1
fi
if [ ! -f "$DMG" ]; then
  echo "expected dmg at $DMG" >&2
  exit 1
fi

if ! grep -q -- '-configuration Release' "$SMOOVMUX_TEST_XCODEBUILD_ARGS"; then
  echo "expected Release archive" >&2
  exit 1
fi
if ! grep -q -- 'PRODUCT_BUNDLE_IDENTIFIER=dog.booze.smoovmux' "$SMOOVMUX_TEST_XCODEBUILD_ARGS"; then
  echo "expected production bundle id override" >&2
  exit 1
fi
if ! grep -q -- 'DEVELOPMENT_TEAM=T6RPYRHYEV' "$SMOOVMUX_TEST_XCODEBUILD_ARGS"; then
  echo "expected team id override" >&2
  exit 1
fi
if ! grep -q -- 'OTHER_CODE_SIGN_FLAGS=--timestamp' "$SMOOVMUX_TEST_XCODEBUILD_ARGS"; then
  echo "expected timestamped Developer ID signing" >&2
  exit 1
fi

NOTARY_SUBMITS="$(grep -c -- 'notarytool.*submit' "$TMP_DIR/calls.log" || true)"
if [ "$NOTARY_SUBMITS" -lt 2 ]; then
  echo "expected notarization submits for app zip and dmg" >&2
  exit 1
fi
if ! grep -q -- 'hdiutil' "$TMP_DIR/calls.log" || ! grep -q -- 'smoovmux-0.0.1-macos-universal.dmg' "$TMP_DIR/calls.log"; then
  echo "expected dmg creation" >&2
  exit 1
fi
if ! grep -q -- 'stapler' "$TMP_DIR/calls.log" || ! grep -q -- 'staple' "$TMP_DIR/calls.log"; then
  echo "expected stapling" >&2
  exit 1
fi
if ! grep -q -- 'release' "$TMP_DIR/calls.log" || ! grep -q -- 'create' "$TMP_DIR/calls.log" || ! grep -q -- 'v0.0.1' "$TMP_DIR/calls.log"; then
  echo "expected GitHub release creation" >&2
  exit 1
fi
if ! grep -q -- 'smoovmux-0.0.1-macos-universal.zip' "$TMP_DIR/calls.log" || ! grep -q -- 'smoovmux-0.0.1-macos-universal.dmg' "$TMP_DIR/calls.log"; then
  echo "expected GitHub release to attach zip and dmg" >&2
  exit 1
fi
if ! grep -q -- '--draft' "$TMP_DIR/calls.log"; then
  echo "expected GitHub release to default to draft" >&2
  exit 1
fi

printf 'release-tests: ok\n'
