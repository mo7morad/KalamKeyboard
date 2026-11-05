# Kalam vs Apple (iPhone 17 simulator, iOS 27.0)

Each sheet shows four screenshots, left to right: Apple light, Kalam light, Apple dark, Kalam dark. They were taken in the same host field as `../apple/` (the harness app), with a Release build of Kalam, so there is no Debug overlay.

What to look for:

- Keys, gaps, corners, colors and label sizes match Apple's within about 1 pt.
- iOS 27 gives third-party keyboards a 75 pt globe strip at the bottom (Apple's own is 58 pt), and Kalam keeps a 4.5 pt touch band under its bottom row (device round 2), so Kalam's rows can't go as low as Apple's: in Phase 20's captures its cap rows start at 590.3 / 644.3 / 698.3 / 752.3 pt against Apple's 598.7 / 652.7 / 706.7 / 760.7, 8.4 pt higher with the same 54 pt pitch.
- Kalam's bar is empty for now (Phase 5 fills it), the EN/AR key replaces the emoji key, and the top row carries small digit hints.
- Popups can't rise above the keyboard in a third-party keyboard, so top-row popups (`popup-e`, `keypress-q`) are pushed down over the top row. `keypress-q` shows Kalam's long-press strip, because the capture held q long enough to open it.

The seven page sheets (`en-letters`, `en-shifted`, `en-123`, `en-symbols`, `ar-letters`, `ar-123`, `ar-symbols`) were retaken in Phase 20 (Apple's key sizes back) with a Release build. Measured from the PNGs: every cap is within 0.7 pt of Apple's in x, caps are the same height and the row pitch is 54 pt, and the whole keyboard sits 8.4 pt higher than Apple's (the taller globe strip plus the bottom touch band). The bar shows base predictions, since Phase 5 filled it. `popup-tashkeel-light.png` is Kalam's tashkeel strip, to compare with `../apple/popup-tashkeel-light.png` (`Tools/screenshot-harness/UITests/Round1.swift`).

To recapture, use `Tools/screenshot-harness/UITests/Kalam.swift` with the harness described in `../apple/README.md` (`testEnableFullAccess` once, then `testPages` per appearance).

## Suggestion bar (Phase 5, Debug build, light)

- `bar-en-typing.png`: "teh" typed. The pending autocorrect "the" is bold in the middle, the quoted literal on the left.
- `bar-en-predictions.png`: after the space that fixed it ("the "), three next-word predictions.
- `bar-ar-typing.png`: "انا" typed. The slots are mirrored (primary in the middle, alt1 on the right), and the variant أنا is offered as a suggestion.

They come from `Tools/screenshot-harness/UITests/Phase5.swift` (`testTypoUndoArabic`), which also checks the field text: "teh" + space gives "the ", and one backspace gives "teh" back. `testPickPunctuationBlock` checks a suggestion tap ("hel" -> "he "), punctuation spacing ("he, ") and the "Don’t suggest" overlay.

## Clipboard (SPEC 5.5, Debug build)

- `clip-chip-light.png`: after a copy, the clipboard button at the bar's left edge and the chip "📋 Meet me…" in the primary slot.
- `clip-panel-light.png`: the panel in place of the keys, three clips, newest first. The bar is its header: the selected button, "Clipboard", "Clear" and "ABC".
- `clip-panel-ar-dark.png`: the panel over the Arabic keyboard in dark mode, the Arabic tile right-aligned.

They come from `Tools/screenshot-harness/UITests/Clipboard.swift`: `testAllowPaste` sets Settings › Apps › Kalam › Paste from Other Apps to Allow (without it, iOS's "Allow Paste" prompt blocks the keyboard), and `testChipThenPanel` checks the chip paste, a tile paste with the panel staying open, Pin and Delete.

- `clip-panel-image-light.png`: an image clip's tile, its thumbnail filling the tile. From `testImage`, which also taps the tile, checks that the pasteboard holds `public.png` again and pastes it into the field (launched with `-images`, so it takes images).

## Autocorrect in the bar (Phase 19, Debug build)

The same states as `../apple/autocorrect-*`, light and dark, from `Tools/screenshot-harness/UITests/Autocorrect.swift` (`KalamAutocorrect`; it deletes nothing itself, so delete `personal.sqlite*` in the App Group container before each run, and set `autocorrectAR` to normal). Each word starts on a fresh launch, lowercase (shift tapped off).

- `autocorrect-en-pending`, `-en-recieve-pending`, `-ar-pending`: the capsule behind the primary slot, its text darker and regular weight, the dividers hidden, the literal quoted in alt1 (“teh”, "السلان" with straight quotes in Arabic).
- `autocorrect-*-offer` (Phase 22): right after the space, the original sits unquoted in alt1 (left in EN, right in AR) as the revert offer; primary and alt2 keep the predictions, the dividers are back.
- `autocorrect-*-offer-expired`: 3 s later, the offer has faded to the plain predictions.
- `autocorrect-en-offer-tapped`, `-ar-offer-tapped`: the offer tapped right after the space (`testOfferTap`, on its own fresh store since it records a rejection): the field reads "teh " and "teh السلان ", the space kept.
- `autocorrect-*-revert`: "ok " typed after the corrected word, then the cursor tapped back to its end. The original sits unquoted in alt1 (left in EN, right in AR), as Apple's offer does; a tap puts it back.
- `autocorrect-*-undo`: the typo typed again, space, one backspace. Kalam's backspace puts the literal back in the field (SPEC 8.5), so the bar shows the literal's plain candidates. Apple instead keeps the correction and offers the literal in alt1; that difference is behaviour, left as it is.
- `autocorrect-anim-pending-dark.png`: 16 frames at 60 fps while "e" makes "the" pending: the capsule and dividers switch in one frame, the slot text cross-fades over 0.2 s.

Differences from Apple's frames: Kalam's bar starts after its clipboard and emoji buttons, so its slots are 119 pt wide (Apple's 134), and the capsule follows the slot. Apple staggers the text fade letter by letter over about 0.4 s; Kalam fades the three slots together in 0.2 s (one layer animation).
