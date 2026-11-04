# Kalam vs Apple (iPhone 17 simulator, iOS 27.0)

Each sheet shows four screenshots, left to right: Apple light, Kalam light, Apple dark, Kalam dark. They were taken in the same host field as `../` (the harness app), with a Release build of Kalam, so there is no Debug overlay.

What to look for:

- Keys, gaps, corners, colors and label sizes match Apple's within about 1 pt.
- Kalam sits about 7 pt higher, with a panel about 7 pt taller. iOS 27 gives third-party keyboards a 75 pt globe strip at the bottom (Apple's own is 58 pt), so Kalam's rows can't go as low as Apple's.
- Kalam's bar is empty for now (Phase 5 fills it), the EN/AR key replaces the emoji key, and the top row carries small digit hints.
- Popups can't rise above the keyboard in a third-party keyboard, so top-row popups (`popup-e`, `keypress-q`) are pushed down over the top row. `keypress-q` shows Kalam's long-press strip, because the capture held q long enough to open it.

To recapture, use `../harness/UITests/Kalam.swift` with the harness described in `../README.md` (`testEnableFullAccess` once, then `testPages` per appearance).

## Suggestion bar (Phase 5, Debug build, light)

- `bar-en-typing.png`: "teh" typed. The pending autocorrect "the" is bold in the middle, the quoted literal on the left.
- `bar-en-predictions.png`: after the space that fixed it ("the "), three next-word predictions.
- `bar-ar-typing.png`: "انا" typed. The slots are mirrored (primary in the middle, alt1 on the right), and the variant أنا is offered as a suggestion.

They come from `../harness/UITests/Phase5.swift` (`testTypoUndoArabic`), which also checks the field text: "teh" + space gives "the ", and one backspace gives "teh" back. `testPickPunctuationBlock` checks a suggestion tap ("hel" -> "he "), punctuation spacing ("he, ") and the "Don’t suggest" overlay.

## Clipboard (SPEC 5.5, Debug build)

- `clip-chip-light.png`: after a copy, the clipboard button at the bar's left edge and the chip "📋 Meet me…" in the primary slot.
- `clip-panel-light.png`: the panel in place of the keys, three clips, newest first. The bar is its header: the selected button, "Clipboard", "Clear" and "ABC".
- `clip-panel-ar-dark.png`: the panel over the Arabic keyboard in dark mode, the Arabic tile right-aligned.

They come from `../harness/UITests/Clipboard.swift`: `testAllowPaste` sets Settings › Apps › Kalam › Paste from Other Apps to Allow (without it, iOS's "Allow Paste" prompt blocks the keyboard), and `testChipThenPanel` checks the chip paste, a tile paste with the panel staying open, Pin and Delete.
