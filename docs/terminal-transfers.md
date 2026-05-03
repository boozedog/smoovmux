# Terminal transfers

smoovmux supports terminal copy, paste, and drag/drop without logging terminal bytes, selected text, clipboard contents, paths, or image bytes.

## Paste and drop

- Plain-text paste is sent through Ghostty's text/paste path.
- Dropping local files inserts shell-quoted path(s), separated by spaces.
- Pasting or dropping image data without a file URL writes the image to `~/Library/Caches/smoovmux/dropped-images/<uuid>.<ext>` and inserts the shell-quoted path.
- Dropped image cache files older than 24 hours are removed on app launch.

Transfer precedence:

- Drop: file URLs, then image data, then text/URL.
- Paste: text/file URLs, then image data.

## Copy

- `⌘C` copies a cleaned version of the active terminal selection: common prompt prefixes are stripped, trailing whitespace is trimmed, and runs of three or more blank lines collapse to two.
- `⌘⇧C` / Edit → Copy Raw copies the exact selected terminal text returned by Ghostty.

## Select all

Select All remains disabled for now because terminal scrollback-aware selection needs explicit support from libghostty before it can behave correctly.

## OSC 52 and terminal clipboard protocols

Terminal-initiated clipboard reads and writes are intentionally blocked by default. Direct user paste still works via smoovmux's AppKit paste handler, but OSC 52 clipboard access is not allowed until there is an explicit user-facing permission/config model.
