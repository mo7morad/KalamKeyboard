# 07: An underline on the corrected word via marked text (Phase 21 spike)

**Verdict: no-go.** Marked text can't keep Moe's text exactly right. In every host tested, a tap that moves the cursor while the word is marked doesn't reach the keyboard, and the next letter lands after the corrected word instead of where Moe tapped. The underline also doesn't look like Apple's. Nothing shipped. Step 2 was not built.

Run on 2026-11-05 on an iPhone 17 simulator (iOS 27.0) cloned for this phase ("Phase21 iPhone 17"). Spike code was a throwaway build from a detached worktree. Frames are in `07-frames/`.

## What was tried

When space autocorrects a word, Kalam already inserts the replacement and the auto-space. The spike then turned them into marked text:

1. `deleteBackward()` over the replacement and the space, then `setMarkedText("The ", selectedRange: (4, 0))`. The space has to be inside the marked text: marked text always holds the caret, and `insertText(" ")` after a marked "The" replaces the marked text with the space.
2. Clear the mark after 2 s, before any other key's edit, before a bar tap or paste, and when the host hides.

Two ways to clear it were tried:

- **(a) `proxy.unmarkText()`:** loses text. With an edit right after it (the next letter, punctuation, return or backspace), "The " was gone: "teh␣o" left just "o". The proxy doesn't apply the unmark before the next edit, so the host still sees the marked text and the edit replaces it.
- **(b) `proxy.insertText(markedText)`:** commits the marked text the way an IME does. This order keeps the text right in every case except the cursor move (below). Every key handler has to clear the mark first, before it reads `documentContextBeforeInput`, because that context leaves out marked text: right after the mark it read "" instead of "The ".

The keyboard hiding needs the clear in `NSExtensionHostWillResignActive`. A clear in `viewWillDisappear` comes too late: the host drops the insert and keeps "The " marked. The next word then replaced it. In the harness, "The " from the hide case vanished when the next "teh" was typed.

## Results per host and case (order b, hide handled on resign-active)

Cases: **A** space then wait, **B** next letter at once, **C** backspace undo, **D** punctuation ("."), **E** return, **F** tap to move the cursor while marked and then type, **G** hide (home) and come back.

| Host | A | B | C | D | E | F | G | Underline |
|---|---|---|---|---|---|---|---|---|
| Harness UITextView | ok | ok | ok | ok | ok | **wrong** | ok (only with the resign-active clear) | blue, covers the space |
| Harness UITextField | ok | ok | ok | ok | ok | **wrong** | ok | blue, covers the space |
| Messages (body field) | ok | ok | not run | ok | ok | **wrong** | ok | blue, covers the space |
| Safari, web `<textarea>` | ok | ok | ok | ok | ok | **wrong** | ok | shown on the first line only; none after a return |
| Safari address bar | n/a | | | | | | | Kalam never autocorrects URL fields (SPEC 8.5 rule 1), so nothing is marked |
| Notes, Mail | not available | | | | | | | These apps aren't installed on the iOS 27.0 simulator runtime |

**Case F is the blocker.** "the o " then "teh␣", then a tap at the start of the text, then "k":

- Without marked text (control run in the harness UITextView), you get "Kthe o the ", which is right.
- With marked text, every host gives "the o the k": the k lands after the corrected word, not where Moe tapped.
  - UIKit (UITextView, UITextField, Messages) keeps the caret inside the marked word. The tap only moves it to the word's start (`kalam-tap-caret-stuck-uitextview.png`, `kalam-tap-caret-stuck-messages.png`).
  - Safari draws the caret where Moe tapped, but the marked word stays marked (`kalam-tap-caret-moved-safari.png`). The commit and the letter still go after the corrected word.
  - In neither case does the keyboard get `textDidChange` or `selectionDidChange`. `documentContextBeforeInput` doesn't change, so Kalam can't tell that the tap happened.

Fixing a word right after a correction is exactly when Moe taps back into his text, so this case will happen. A 2 s window only makes it rarer. No call order fixes it, because the keyboard is never told about the tap.

## Compared with Apple

- **Apple** (`apple-underline.png`, `apple-underline-next-word.png`): a thin, light blue-violet underline under the word only, not the space. It stays after the next word is typed, and the caret moves freely.
- **Marked text** (`kalam-marked-uitextview.png`): the host's IME underline. It is thicker and saturated blue, covers the trailing space, goes away when the mark is cleared, and in Safari doesn't always show (`kalam-no-underline-safari.png`).

Even where the text stayed right, it doesn't look like Apple's underline.

## Proposal: the best in-keyboard alternative (not built)

Show the correction in the bar right after it happens. This reuses Apple's own undo offer and Phase 19's bar:

- When space autocorrects a word, the bar shows, until the next letter (or about 3 s), the original literal **unquoted in alt1** as a revert offer, as Apple's undo offer does (`autocorrect-ar-undo`, `autocorrect-en-undo-offer-bar-light` in `docs/reference/apple/`).
- The primary slot shows the replacement on the capsule for a moment, then cross-fades to the predictions. This gives the "something was corrected" signal where the underline would have been.
- A tap on the offer reverts the correction, like today's tap-to-revert (SPEC 5.4): the literal goes back, the rejection is recorded, and the literal is learned. Backspace keeps working as the one-key undo.
- Everything stays inside the keyboard, so no host can lose or misplace text. It costs one bar state and reuses the revert-offer path that already exists (`RecentAutocorrects`, `BarSlot.isRevert`).

## Notes for anyone retrying

- `documentContextBeforeInput` leaves out marked text. Kalam's word state, undo slot and punctuation spacing all read it, so the mark has to be cleared before any of them run.
- `unmarkText()` through the proxy is not a safe commit. `insertText(sameText)` is.
- Clear the mark in `NSExtensionHostWillResignActive`. `viewWillDisappear` is too late.
- Third-party hosts (WhatsApp, Instagram, Telegram) weren't testable here and would add their own text-view quirks.
