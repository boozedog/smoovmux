# Bundled `tmux`

Per #16 we ship a `tmux` binary inside the .app so users never need
`brew install tmux`. The runtime resolver (#19) falls back to this binary when
neither the user's settings override nor their login-shell `PATH` provides one.

This directory holds the prebuilt binary plus a `VERSION` manifest. The binary
is committed to the repo (1–2 MB; LFS overhead would not pay off — see
`.gitattributes`).

## Pinned versions

| Component | Version | Source |
| --------- | ------- | ------ |
| tmux      | `3.6a`  | sha256 `b6d8d9c76585db8ef5fa00d4931902fa4b8cbe8166f528f44fc403961a3f3759`, downloaded from upstream releases |
| libevent  | `2.1.12-stable` | `pkgsStatic.libevent` from nixpkgs (statically linked) |

Bumping a version is a deliberate act: edit the pin in `scripts/build-tmux.sh`
(tmux) or update `devenv.nix` (libevent), rerun `make bundle-tmux`, commit
the new binary + `VERSION` manifest, and call out the bump in the PR / release
notes.

## Architecture

**arm64 only**, currently. Universal (`arm64 + x86_64`) is a follow-up — it
needs `pkgsCross.x86_64-darwin.libevent` (slow first build) or a separate
x86_64 libevent build path. The bundled-tmux fallback is primarily for users
without `brew install tmux`, who skew heavily M-series; Intel users typically
already have brew. Promote to universal if the data says otherwise.

## Building

The build is reproducible from the committed `scripts/build-tmux.sh`. It:

- fetches the tmux source tarball and verifies sha256
- locates `pkgsStatic.libevent` (via `pkg-config`, falling back to `nix-build`)
- forces the Xcode toolchain (`xcrun clang`) for compile + preprocess so the
  resulting binary links against the macOS SDK, not a nix-store libc
- configures tmux with `--disable-utf8proc` (built-in width tables)
- builds `tmux`
- verifies the output has no `/nix/store/...` runtime references via `otool -L`
- ad-hoc signs (`codesign --sign -`) so it runs locally

From the devenv shell:

```sh
make bundle-tmux
```

This produces:

- `App/Resources/bin/tmux` — arm64 binary, ad-hoc signed, libevent baked in
- `App/Resources/bin/VERSION` — pinned versions + build timestamp + arch

After a successful build, commit both files.

## Verifying linkage

The shipped binary must not depend on `/nix/store/`. The build script asserts
this, but to verify by hand:

```sh
otool -L App/Resources/bin/tmux
```

Expected output: only `/usr/lib/...` system frameworks (libSystem, libncurses,
libresolv).

## Release signing

The committed binary is ad-hoc signed (sufficient for local development and
CI). For a notarized release, the binary must be re-signed under the app's
Developer ID with hardened runtime — typically as part of the release pipeline,
not at build time:

```sh
codesign --force \
  --sign "Developer ID Application: <name>" \
  --options runtime \
  --timestamp \
  App/Resources/bin/tmux
```

This step is not run by `make bundle-tmux`; it lives in the (future) release
workflow.

## Bundling into the .app

`project.yml` declares `App/Resources/bin` as a folder reference resource, so
xcodegen wires the directory verbatim into the built `.app`'s
`Contents/Resources/bin/`. Whatever lands at `App/Resources/bin/tmux`
therefore lands at `Contents/Resources/bin/tmux` inside the app bundle.

## Acceptance check (per #22)

> Launch smoovmux on a machine with `PATH=/usr/bin:/bin`. It still works
> because it falls back to bundled.

This requires #19 (the resolver) to be implemented. Once it is, validate by
unsetting tmux from `PATH` and confirming the app uses `Contents/Resources/bin/tmux`.
