#!/usr/bin/env bash
# scripts/set-version.sh — update app marketing/build versions.
#
# Usage:
#   ./scripts/set-version.sh --version 0.0.1 [--build 1]

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=""
BUILD=""
PLIST="App/Info.plist"
while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2 || { echo "error: --version needs an argument" >&2; exit 2; }
      ;;
    --build)
      BUILD="${2:-}"
      shift 2 || { echo "error: --build needs an argument" >&2; exit 2; }
      ;;
    --plist)
      PLIST="${2:-}"
      shift 2 || { echo "error: --plist needs an argument" >&2; exit 2; }
      ;;
    -h|--help)
      sed -n '2,5p' "$0"
      exit 0
      ;;
    *)
      echo "error: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$VERSION" ]; then
  echo "error: --version is required" >&2
  exit 2
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)?$ ]]; then
  echo "error: version must look like 0.0.1, got '$VERSION'" >&2
  exit 2
fi
if [ -n "$BUILD" ] && ! [[ "$BUILD" =~ ^[0-9]+$ ]]; then
  echo "error: build must be an integer, got '$BUILD'" >&2
  exit 2
fi
if [ ! -f "$PLIST" ]; then
  echo "error: plist not found: $PLIST" >&2
  exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString '$VERSION'" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string '$VERSION'" "$PLIST"

if [ -n "$BUILD" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion '$BUILD'" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string '$BUILD'" "$PLIST"
fi

printf 'Version: %s\n' "$VERSION"
if [ -n "$BUILD" ]; then
  printf 'Build: %s\n' "$BUILD"
fi
printf 'Plist: %s\n' "$PLIST"
