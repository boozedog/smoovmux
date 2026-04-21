{ pkgs, lib, ... }:

# devenv shell + git-hooks for smoovmux. Single source of truth for dev tooling.
#
# Activation: `direnv allow` (uses .envrc) or `devenv shell` directly.
#
# Pinned tools:
#   - xcodegen    → for regenerating smoovmux.xcodeproj from project.yml
#   - swiftlint   → linting (see .swiftlint.yml)
#   - gitleaks    → secret scanning
#   - gnumake     → for the Makefile (qa, fmt, lint targets)
#   - autoconf, automake, libtool, pkg-config, bison
#                 → required by scripts/build-tmux.sh (#22) to build the
#                   bundled tmux from source
#   - libevent    → tmux's hard event-loop dep. macOS doesn't ship it; we
#                   statically link nix's build into the bundled tmux so the
#                   shipped binary has no /nix/store/ runtime references.
#                   arm64-only for now (#22 phase 1)
#
# NOT pinned here (intentional):
#   - `swift format` → ships with Swift 6 toolchain (xcrun swift-format)
#   - Xcode itself   → managed by user / xcode-install / Apple
#   - ghostty source → currently a git submodule; tracked by #27 to move to nix
#   - zig           → Homebrew (`zig@0.15.2` from the `boozedog/zig015` tap,
#                     which carries the Xcode-26 patch from homebrew-core that
#                     isn't in any nix-zig build). Upstream bug:
#                     ghostty-org/ghostty#11991, codeberg.org/ziglang/zig#31658.
#                     See README.md / CLAUDE.md for the setup commands.

{
  packages = with pkgs; [
    xcodegen
    swiftlint
    gitleaks
    gnumake
    autoconf
    automake
    libtool
    pkg-config
    bison
    gettext # msgfmt — ghostty's zig build compiles .po translations
    pkgsStatic.libevent
  ];

  # All hooks call `make <target>` so there is one source of truth.
  # See Makefile for what each target does.
  git-hooks.hooks = {
    swift-format-check = {
      enable = true;
      name = "swift format (lint mode)";
      entry = "make fmt-check";
      language = "system";
      pass_filenames = false;
      files = "\\.swift$";
    };

    swiftlint-check = {
      enable = true;
      name = "swiftlint";
      entry = "make lint";
      language = "system";
      pass_filenames = false;
      files = "\\.swift$";
    };

    gitleaks-staged = {
      enable = true;
      name = "gitleaks (staged)";
      entry = "${pkgs.gitleaks}/bin/gitleaks protect --staged --redact --verbose";
      language = "system";
      pass_filenames = false;
      stages = [ "pre-commit" ];
    };

    gitleaks-full = {
      enable = true;
      name = "gitleaks (full repo)";
      entry = "${pkgs.gitleaks}/bin/gitleaks detect --redact --verbose";
      language = "system";
      pass_filenames = false;
      stages = [ "pre-push" ];
    };
  };

  enterShell = ''
    # devenv on macOS auto-provisions pkgs.apple-sdk (14.4 as of writing),
    # exporting SDKROOT / DEVELOPER_DIR for the nix SDK. That SDK is older
    # than the system Swift toolchain (6.x), so `swift build` / `swift test`
    # against it fail with "no such module 'SwiftShims'". Prefer the user's
    # Xcode install when present so SPM picks up a matching SDK; zig-based
    # ghostty builds don't need SDKROOT, so clearing it is safe.
    if [ -d /Applications/Xcode.app/Contents/Developer ]; then
      export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
      unset SDKROOT
    fi

    # Put Homebrew's patched zig@0.15.2 at the front of PATH. We can't
    # pin zig through nix because the zig-overlay / nixpkgs 0.15.2 builds
    # don't carry the Xcode 26.4 libSystem.tbd patch. See devenv.nix
    # header for links, and README.md for the install command.
    if [ -x /opt/homebrew/opt/zig@0.15.2/bin/zig ]; then
      export PATH="/opt/homebrew/opt/zig@0.15.2/bin:$PATH"
    fi

    if command -v zig >/dev/null 2>&1; then
      echo "smoovmux dev shell — zig $(zig version), xcodegen $(xcodegen --version 2>&1 | head -1)"
    else
      echo "smoovmux dev shell — zig NOT FOUND (run 'brew install boozedog/zig015/zig@0.15.2')"
    fi
    echo "Run 'make help' for available targets."
  '';
}
