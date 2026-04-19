{ pkgs, lib, inputs, ... }:

# devenv shell + git-hooks for smoovmux. Single source of truth for dev tooling.
#
# Activation: `direnv allow` (uses .envrc) or `devenv shell` directly.
#
# Pinned tools:
#   - zig 0.15.2  → must match ghostty/build.zig.zon .minimum_zig_version
#   - xcodegen    → for regenerating smoovmux.xcodeproj from project.yml
#   - swiftlint   → linting (see .swiftlint.yml)
#   - gitleaks    → secret scanning
#   - gnumake     → for the Makefile (qa, fmt, lint targets)
#
# NOT pinned here (intentional):
#   - `swift format` → ships with Swift 6 toolchain (xcrun swift-format)
#   - Xcode itself   → managed by user / xcode-install / Apple
#   - ghostty source → currently a git submodule; tracked by #27 to move to nix

let
  zigPinned = inputs.zig.packages.${pkgs.stdenv.hostPlatform.system}."0.15.2";
in
{
  packages = with pkgs; [
    zigPinned
    xcodegen
    swiftlint
    gitleaks
    gnumake
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

    echo "smoovmux dev shell — zig $(zig version), xcodegen $(xcodegen --version 2>&1 | head -1)"
    echo "Run 'make help' for available targets."
  '';
}
