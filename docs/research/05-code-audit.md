# Research 5: Kalam UX code audit (2026-11-04)

Read-only audit at HEAD `4abd9ab`, before commit `9e1a763` moved files by feature and before Phase 8 (`eb35259`). Paths and line numbers are from `4abd9ab`; find the moved file by name:
- `InputRules.swift` is now `Keyboard/TextContext.swift`;
- `KeyboardRules.swift` is now `Keyboard/KeyBehavior.swift`;
- extension files are under `Views/`, `Input/`, `Clipboard/`, `Feedback/`.

Phase 8 already covers the shift and 123 slide gaps.

## 1. What it does today

A UIKit keyboard with English and Arabic letters, 123 and #+= pages per language, and an EN/AR key.
- **Keys and touch:** keys drawn as layers, raw touches, two-thumb rollover, letters typed on release, hit areas tuned to Moe's taps.
- **Popups and feedback:** key bubbles, 0.35 s long-press strips (accents, top-row digits, tashkeel), a rigid haptic and Apple's three clicks.
- **Typing behavior:** shift for one letter or caps lock, auto-shift in English, backspace repeat switching to whole words, space-bar trackpad, double space types a period.
- **Bar and clipboard:** three suggestions, next-word prediction, autocorrect with one-backspace undo, plus a Gboard-style clipboard panel and clip chip.

## 2. Gaps versus Apple and Gboard

- **Backspace has no acceleration.** It repeats every 0.09 s, then after 15 repeats (about 1.8 s) deletes about 11 whole words per second at the same pace, which makes overshooting easy (`KeyboardRules.swift:66-72`, `KeyboardView.swift:258-265`).
- **Undo only works for a space-triggered autocorrect.** If return or punctuation triggered it, the undo is cleared at once (`InputController.swift:63,92`). There is no later revert, such as tapping a corrected word to get the original. A rejection is stored only for that exact pair (`Autocorrect.swift:24`, `Learner.swift:85-91`).
- **The space before punctuation is removed only after an autocorrect or a bar pick.** After a plain typed space it stays, so "hello ," stays "hello ," (`InputController.swift:85`, `InputRules.swift:85-90`). Apple probably removes it too; compare side by side.
- **Double space after auto-punctuation.** After an auto-space, "." inserts ". " by itself, so Moe's habit of hitting space next gives "the.  " (`InputRules.swift:87`; `typeSpace` at `InputController.swift:75-88` never checks `autoSpace`).
- **Quotes:**
  - An opening `"` or `'` after an auto-space deletes that space, giving `said"hi` (`InputRules.swift:88` treats them as closing only).
  - The keys show ” and ’ but type ASCII (`en-numbers.json`). There is no smart-quote logic.
- **Auto-capitals** work after a newline (`KeyboardRules.swift:50`), but not after `."` or `.)` followed by a space (`KeyboardRules.swift:52-53` only looks for `.!?`).
- **Shift:**
  - Holding shift while typing several letters capitalizes only the first, because `letterTyped` clears it (`KeyboardViewController.swift:320`).
  - Shift-slide is now covered by Phase 8.
  - With caps lock on, bar suggestions get only a capital first letter, not all caps (`InputController.swift:193`, `InputRules.swift:45-48`).
- **Bar taps:** one shared bubble layer (`PopupLayers.swift:7`), with top-row bubbles pushed down (`:45`). There is no press highlight, haptic or sound on bar slots, since the bar uses tap recognizers that fire on release (`SuggestionBar.swift:116,163`).
- **Trackpad:**
  - A fixed 9 pt per character, with no speed-up, no vertical movement and no selection (`KeyboardRules.swift:83-101`).
  - The RTL direction follows the layout language, not the text (`KeyboardView.swift:331`), so English text typed from the Arabic layout (or the reverse) moves the wrong way.
- **Suggestion bar edge cases:**
  - The typed word shows in quotes only while an autocorrect is pending; otherwise it can be missing (`InputRules.swift:76`).
  - The clip chip takes the main slot's prediction for 2 minutes (`KeyboardViewController.swift:362`, `SuggestionBar.swift:143`).
  - `documentContextAfterInput` is never read, so a suggestion picked with the cursor mid-word replaces only the part before the cursor and leaves the rest.
  - The sentence-start ranking favours news words (`docs/issues.md`).
- **Emoji:** no globe key on the iPhone 17 (`needsInputModeSwitchKey` is false), so emoji come only through the system strip, and the bar never suggests them. Phase 9 covers this.
- **Number row:** none. Digits come from the 0.35 s top-row long-press, and the hints show on English only since `4abd9ab` (`KeyboardView.swift:190`).
- **Arabic punctuation:** the Arabic letters page has no ، ؟ . keys, so all punctuation goes through 123 (`ar-letters.json`). Gboard has them on the letters page. Apple's layout doesn't, and D6 says to follow Apple.

## 3. Likely bugs and fragile spots in the touch path

1. **Invisible Arabic digits.** A long-press preselects the digit whenever a key has one (`KeyboardView.swift:284`: `press.selected = key.hint == nil ? ... : 0`), but Arabic no longer draws the hints (`:190`). A slow press on any Arabic top-row key types a digit Moe can't see. In English the same happens to e, u, i and o at 0.35 s. Orchestrator spot-checked this: confirmed.
2. **A slow space tap types nothing.** Holding space for 0.4 s starts the trackpad (`:268`), and a release in trackpad mode types no space (`release`: `case .space where press.trackpad != nil: break`). Rollover skips trackpad presses. Orchestrator spot-checked this: confirmed.
3. **Bar taps can type letters.** The top row takes the bar's bottom 12 pt (`:31,60`), so a bar tap aimed low types a top-row letter. The bar's effective target is 28 pt tall.
4. **System cancels drop letters.** A cancelled touch calls `finish(press)` without committing (`:343-348`), so edge gestures or banners can lose keystrokes (G1).
5. **Word delete with tashkeel.** Word-step deletion counts Swift Characters (`KeyboardRules.swift:75-79`) but calls `deleteBackward` once per count (`InputController.swift:242`). If a host deletes one mark per call, Arabic with tashkeel under-deletes. Device-only.
6. **First keystrokes after appear.** `open()` rebuilds the engines (`EngineClient.swift:157`). If the first word's result misses the 20 ms wait, its autocorrect is silently skipped (`:93`).
7. **The clipboard prompt freezes the keys.** The "Allow Paste" prompt blocks the main thread at `viewDidAppear` (`KeyboardViewController.swift:113`) until answered (an open checklist item).

## 4. Weakest eval metrics (`docs/eval-log.md`)

- **Arabic autocorrect, synthetic set:** gentle 20.8% and normal 30.7%, vs English 55.5%.
- **Keystroke savings:** Arabic 28.2% vs English 38.2% (synthetic); on Moe's chats, Arabic 27.0% vs English 38.7%.
- **Arabic next-word top-3:** 2.3% with base data only, 15.0% with Moe's data. English with Moe's data is 20.2%.
- **Arabic on Moe's chats:** normal gets 39 right and 12 wrong (about 24% wrong). Gentle gets 30 right and 3 wrong, but changes only 0.24% of words.
- **English:** false autocorrect went from 0.01% to 0.02% with normal theta 1.0, and normal makes one wrong "Yaaay → that".
- **Caveat:** all of Moe's numbers tap key centres; real thumb-slip behavior is unverified.

## 5. Open device-checklist items that matter most

All 78 boxes were unchecked at the time. In priority order:
1. Device round 1 fast typing: dropped or swapped letters in EN and AR vs Apple's baseline, edge keys (q/p, ض/ج), the tashkeel strip.
2. Latency under about 12 ms and never over 20 ms. Memory headroom above 10 MB after switching to Arabic, and less than 2 MB growth over 20 show/hide cycles.
3. Autocorrect undo: "teh" then backspace restores the literal and doesn't re-correct. A one-slip fix ("tomorroe") is fixed on space.
4. Switching apps mid-sentence (`0xdead10cc`). Full Access off with no crash.
5. Whether the clipboard "Allow Paste" prompt freezes the keys.
6. Trackpad in Arabic text follows the finger. Backspace switches to whole words after about 2 s.
7. Bar at 40 pt not clipped. Re-check now that the top row reaches 12 pt into the bar.
