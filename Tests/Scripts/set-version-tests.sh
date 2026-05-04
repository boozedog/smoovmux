#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PLIST="$TMP_DIR/Info.plist"
cp "$REPO_ROOT/App/Info.plist" "$PLIST"

"$REPO_ROOT/scripts/set-version.sh" --version 1.2.3 --build 45 --plist "$PLIST"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
if [ "$VERSION" != "1.2.3" ]; then
  echo "expected version 1.2.3, got '$VERSION'" >&2
  exit 1
fi
if [ "$BUILD" != "45" ]; then
  echo "expected build 45, got '$BUILD'" >&2
  exit 1
fi

if "$REPO_ROOT/scripts/set-version.sh" --version nope --plist "$PLIST" >/dev/null 2>&1; then
  echo "expected invalid semantic version to fail" >&2
  exit 1
fi

printf 'set-version-tests: ok\n'
