# Kalam vs Apple (iPhone 17 simulator, iOS 27.0)

Each sheet shows four screenshots, left to right: Apple light, Kalam light, Apple dark, Kalam dark. They were taken in the same host field as `../` (the harness app), with a Release build of Kalam, so there is no Debug overlay.

What to look for:

- Keys, gaps, corners, colors and label sizes match Apple's within about 1 pt.
- Kalam sits about 7 pt higher, with a panel about 7 pt taller. iOS 27 gives third-party keyboards a 75 pt globe strip at the bottom (Apple's own is 58 pt), so Kalam's rows can't go as low as Apple's.
- Kalam's bar is empty for now (Phase 5 fills it), the EN/AR key replaces the emoji key, and the top row carries small digit hints.
- Popups can't rise above the keyboard in a third-party keyboard, so top-row popups (`popup-e`, `keypress-q`) are pushed down over the top row. `keypress-q` shows Kalam's long-press strip, because the capture held q long enough to open it.

To recapture, use `../harness/UITests/Kalam.swift` with the harness described in `../README.md` (`testEnableFullAccess` once, then `testPages` per appearance).
