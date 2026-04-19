#!/usr/bin/env bash
# scripts/build-tmux.sh — build tmux and install it into App/Resources/bin/tmux
# for bundling in the .app.
#
# Per the runtime resolution order in #19:
#   1. Settings override
#   2. User login-shell PATH
#   3. **Bundled** (Contents/Resources/bin/tmux)  ← what this script produces
#
# Strategy:
#   - Pin tmux to a known version (sha256-verified).
#   - Statically link against `pkgsStatic.libevent` provided by devenv.nix.
#     macOS does not ship libevent; the static .a lives in the nix store but
#     the linker copies the symbols into the tmux binary, so the shipped
#     binary has no /nix/store/ runtime references (verified post-build with
#     `otool -L`).
#   - arm64-only for now (#22 phase 1). Universal (arm64+x86_64) is a
#     follow-up; pkgsStatic.libevent on a different arch needs pkgsCross.
#   - Ad-hoc sign so it runs locally. Release re-signs under Developer ID —
#     see App/Resources/bin/BUILD.md.
#
# Run from the devenv shell (autoconf/automake/libtool/pkg-config/bison and
# pkgsStatic.libevent are all pinned there):
#
#   make bundle-tmux

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

# -- Pinned versions ----------------------------------------------------------
TMUX_VERSION="3.6a"
TMUX_SHA256="b6d8d9c76585db8ef5fa00d4931902fa4b8cbe8166f528f44fc403961a3f3759"
TMUX_URL="https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz"

MIN_MACOS="15.0"
ARCH="arm64"

OUT_DIR="${REPO_ROOT}/App/Resources/bin"
WORK_DIR="${REPO_ROOT}/.build/tmux-bundle"

log() { printf '[build-tmux] %s\n' "$*"; }
die() { printf '[build-tmux] error: %s\n' "$*" >&2; exit 1; }

# -- Tooling sanity check -----------------------------------------------------
for tool in autoconf automake libtoolize pkg-config bison curl shasum codesign; do
  command -v "$tool" >/dev/null || die "$tool not on PATH (devenv shell active?)"
done

# Locate nix's static libevent. devenv.nix pins `pkgsStatic.libevent`; in some
# shell entry paths its pkg-config dir is not auto-propagated, so we resolve
# the .dev output explicitly and prepend to PKG_CONFIG_PATH.
if ! pkg-config --exists libevent_core 2>/dev/null; then
  command -v nix-build >/dev/null || die "pkgsStatic.libevent not on PKG_CONFIG_PATH and nix-build unavailable"
  LIBEVENT_DEV="$(nix-build '<nixpkgs>' -A pkgsStatic.libevent.dev --no-out-link)"
  export PKG_CONFIG_PATH="${LIBEVENT_DEV}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
  pkg-config --exists libevent_core || die "libevent_core still not found after locating ${LIBEVENT_DEV}"
fi
LIBEVENT_PREFIX="$(pkg-config --variable=prefix libevent_core)"
log "libevent: ${LIBEVENT_PREFIX}"

mkdir -p "$WORK_DIR" "$OUT_DIR"

# -- Fetch + verify -----------------------------------------------------------
TARBALL="${WORK_DIR}/tmux-${TMUX_VERSION}.tar.gz"
if [ -f "$TARBALL" ] && [ "$(shasum -a 256 "$TARBALL" | awk '{print $1}')" = "$TMUX_SHA256" ]; then
  log "cached: $TARBALL"
else
  log "fetching $TMUX_URL"
  curl -fsSL "$TMUX_URL" -o "$TARBALL.tmp"
  got="$(shasum -a 256 "$TARBALL.tmp" | awk '{print $1}')"
  [ "$got" = "$TMUX_SHA256" ] || { rm -f "$TARBALL.tmp"; die "tmux sha256 mismatch: expected $TMUX_SHA256, got $got"; }
  mv "$TARBALL.tmp" "$TARBALL"
fi

# -- Build tmux ---------------------------------------------------------------
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
CFLAGS_BASE="-isysroot ${SDK_PATH} -mmacosx-version-min=${MIN_MACOS} -arch ${ARCH} -O2"
LDFLAGS_BASE="-isysroot ${SDK_PATH} -mmacosx-version-min=${MIN_MACOS} -arch ${ARCH}"

BUILD_DIR="${WORK_DIR}/${ARCH}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
( cd "$BUILD_DIR" && tar -xzf "$TARBALL" )

log "configuring tmux"
# Force the Xcode toolchain end-to-end — nix-shell can put its own clang/cpp
# first on PATH, but those don't know about the macOS SDK or libSystem.
XCODE_CC="$(xcrun --find clang)"
( cd "${BUILD_DIR}/tmux-${TMUX_VERSION}" \
  && CC="$XCODE_CC" \
     CPP="$XCODE_CC -E" \
     CFLAGS="$CFLAGS_BASE" \
     CPPFLAGS="-isysroot $SDK_PATH -mmacosx-version-min=${MIN_MACOS}" \
     LDFLAGS="$LDFLAGS_BASE" \
     LIBEVENT_CORE_CFLAGS="$(pkg-config --cflags libevent_core)" \
     LIBEVENT_CORE_LIBS="$(pkg-config --libs --static libevent_core)" \
     ./configure --disable-utf8proc >/dev/null )

log "compiling"
( cd "${BUILD_DIR}/tmux-${TMUX_VERSION}" \
  && make -j"$(sysctl -n hw.ncpu)" tmux >/dev/null )

cp "${BUILD_DIR}/tmux-${TMUX_VERSION}/tmux" "${OUT_DIR}/tmux"

# -- Verify no /nix/store/ runtime deps slipped in ---------------------------
if otool -L "${OUT_DIR}/tmux" | grep -q "/nix/store/"; then
  otool -L "${OUT_DIR}/tmux" >&2
  die "binary has /nix/store/ runtime deps — static link of libevent failed"
fi

log "ad-hoc signing"
codesign --force --sign - "${OUT_DIR}/tmux"

# -- Manifest -----------------------------------------------------------------
cat > "${OUT_DIR}/VERSION" <<EOF
tmux ${TMUX_VERSION}
libevent $(pkg-config --modversion libevent_core) (statically linked from nixpkgs pkgsStatic)
built $(date -u +%Y-%m-%dT%H:%M:%SZ)
arch ${ARCH}
min-macos ${MIN_MACOS}
EOF

log "done: $("${OUT_DIR}/tmux" -V)"
log "binary: ${OUT_DIR}/tmux"
log "manifest: ${OUT_DIR}/VERSION"
log ""
log "linkage:"
otool -L "${OUT_DIR}/tmux" | sed 's/^/  /'
