#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="$TMP_DIR/bin"
INSTALL_DIR="$TMP_DIR/Applications"
DERIVED="$TMP_DIR/DerivedData"
mkdir -p "$FAKE_BIN" "$INSTALL_DIR"

cat > "$FAKE_BIN/xcodebuild" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" > "${SMOOVMUX_TEST_XCODEBUILD_ARGS:?}"
printf '\n' >> "$SMOOVMUX_TEST_XCODEBUILD_ARGS"
DERIVED=""
CONFIG=""
while [ $# -gt 0 ]; do
  case "$1" in
    -derivedDataPath)
      DERIVED="$2"
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
APP="$DERIVED/Build/Products/Release/smoovmux.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>smoovmux</string>
  <key>CFBundleDisplayName</key>
  <string>wrong dev name</string>
  <key>CFBundleIdentifier</key>
  <string>wrong.bundle.id</string>
</dict>
</plist>
PLIST
SH
chmod +x "$FAKE_BIN/xcodebuild"

export PATH="$FAKE_BIN:$PATH"
export SMOOVMUX_TEST_XCODEBUILD_ARGS="$TMP_DIR/xcodebuild.args"
export SMOOVMUX_INSTALL_DERIVED="$DERIVED"

"$REPO_ROOT/scripts/install.sh" --install-dir "$INSTALL_DIR"

APP="$INSTALL_DIR/smoovmux.app"
if [ ! -d "$APP" ]; then
  echo "expected installed app at $APP" >&2
  exit 1
fi

DISPLAY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP/Contents/Info.plist")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
if [ "$DISPLAY_NAME" != "smoovmux" ]; then
  echo "expected CFBundleDisplayName=smoovmux, got '$DISPLAY_NAME'" >&2
  exit 1
fi
if [ "$BUNDLE_ID" != "pw.dbu.smoovmux" ]; then
  echo "expected CFBundleIdentifier=pw.dbu.smoovmux, got '$BUNDLE_ID'" >&2
  exit 1
fi

if ! grep -q -- '-configuration Release' "$SMOOVMUX_TEST_XCODEBUILD_ARGS"; then
  echo "expected xcodebuild to use Release configuration" >&2
  exit 1
fi
if grep -q -- 'smoovmux.dev' "$SMOOVMUX_TEST_XCODEBUILD_ARGS"; then
  echo "install build must not use dev bundle identifier" >&2
  exit 1
fi

printf 'install-build-tests: ok\n'
