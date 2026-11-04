# Kalam R&D plan (2026-11-04)

Five research passes fed this plan. The full reports, with sources, are in `docs/research/`:
- `01-user-sentiment.md`: Apple, Gboard and SwiftKey on iPhone;
- `02-arabic-bilingual.md`: Arabic and bilingual typing;
- `03-ui-sizing-touch.md`: UI sizing and touch HCI;
- `04-prediction-autocorrect.md`: decoding and autocorrect research;
- `05-code-audit.md`: a code audit of Kalam at `4abd9ab`.

Phases 8 (gestures, done in `eb35259`) and 9 (emoji) in `PROMPTS.md` are not repeated here.

The file:line references come from `4abd9ab`, before the folder reorganization (`9e1a763`). Find the moved file by name, and re-check each bug against the current code before fixing it.

## What the research says, in one screen

1. **People leave keyboards over trust, not features.** The top hates across all keyboards:
   - autocorrect that changes a correct word, or changes it back after you undo it;
   - letters dropped when typing fast (the iOS 26 bug: the key lights up but another letter is typed);
   - third-party keyboards that silently die and fall back to Apple's (a memory kill).
2. **Sizes are already right.** Kalam's 54 pt row pitch, 6 pt gaps, about 34 pt keys and 40 pt bar match Apple's and sit near the research plateau (9 to 9.6 mm pitch). Don't spend time on sizes; spend it on the touch model.
3. **Personal touch model.** Gboard learns each user's touch offset per key, and the research shows gains of 8% or more from about 60 to 200 touches. We record every tap already, so this is the biggest accuracy win we haven't taken.
4. **"It knows me" beats "it's smart".** Ranked: revert memory, then protecting the user's own words, then personal phrases. A neural LM is worth about 1% at Google's scale. CoreML in an extension risks a memory kill, and we have too little Egyptian text to train one. Skip it for now (D5 holds).
5. **Bilingual.** Nobody does Egyptian dialect well, and SwiftKey's "type both at once" is the most loved. Users hate suggestions in the wrong script, and the cursor going the wrong way in mixed RTL/LTR text.

Already done, so don't rebuild:
- clipboard history;
- long-press digits;
- the literal word in quotes;
- "Don't suggest" on long-press;
- hold-delete switching to whole words;
- a one-backspace undo;
- rollover;
- touch-down haptics;
- Western digits by default;
- the supplementary lexicon (Text Replacements as words).

## Phase 10: Lost keystrokes and silent wrong output (do first)

These are bugs the audit found in the touch path. They break G1 and cost the most trust.

| # | Bug | Evidence | Fix |
|---|---|---|---|
| 1 | A slow press on an Arabic top-row key types a hidden digit. Arabic shows no hint, but the strip preselects the digit. | `Views/KeyboardView.swift:190,285` | When no hint is drawn, preselect the letter (or don't offer the digit first). |
| 2 | A slow tap on space (held 0.4 s, no drag) types nothing. | `KeyboardView.swift` trackpad start + `release` | Enter the trackpad on drag only, or type a space if the trackpad never moved the cursor. |
| 3 | The top row reaches 12 pt into the bar, so a low bar tap types a letter instead of picking the suggestion. | `KeyboardView.swift:31,60` | While the bar shows suggestions, give the band back to the bar. Re-check on device. |
| 4 | A system-cancelled touch (edge gesture, banner) drops its letter. | `touchesCancelled` → `finish` | Commit a letter press on cancel if it was down for more than about 30 ms. |
| 5 | The trackpad direction follows the layout language, not the text. English text on the AR layout (or the reverse) moves the wrong way. | `KeyboardView.swift:331` | Pick the direction from the script of the characters around the cursor. |
| 6 | An autocorrect from return or punctuation can't be undone. | `Input/InputController.swift:63,92` | Keep the undo slot for punctuation commits too. Backspace removes the punctuation first, then the next one reverts. |

Done when: each fix has an engine test where the logic lives in `KeyBehavior`/`TextContext`, plus a device checklist (fast typing, slow space, low bar taps, Arabic slow presses).

## Phase 11: Autocorrect you can trust

| # | Change | Why |
|---|---|---|
| 1 | **Revert memory, persistent and broad.** A one-backspace undo, or retyping the literal, stores the rejection. After 1 rejection never make that correction again; after 2 the literal becomes a known word. | The most hated behavior on every keyboard. Today only the exact pair is stored. |
| 2 | **Never correct away a word Moe used 2 or more times** (in chats or live), whatever the base LM thinks. | Covers Egyptian and Franco spellings. |
| 3 | **Guard rules:** no correction for words with digits, `@`, `/`, `.` inside, URLs, emoji, mixed script, ALL CAPS or mid-sentence capitals. A stricter margin for words of 1 to 3 letters. | Standard practice in LatinIME and Gboard; cheap. |
| 4 | **Ambiguous contractions** (its/it's, were/we're, ill/I'll, well/we'll, hell/he'll, id/I'd): suggest the contraction, never auto-apply it. | A top complaint about iOS. Check D8's contraction list against this. |
| 5 | **Tap a corrected word to revert it** (after a few more words). Reads the word before the cursor and offers the original in the bar. | Apple's underline-revert, which people miss. |
| 6 | **Learning hygiene:** a new word needs 2 uses, or 1 explicit bar pick, before it can be suggested. | People hate learned typos. |

Done when: an `eval` and `eval-personal` run is in `eval-log.md`, the false-autocorrect guard (≤ 0.5%) holds, the wrong AR changes over 10 folds don't grow, and the policy table tests are extended.

## Phase 12: A touch model that learns Moe's thumbs

1. **A fixed vertical offset** as an `EngineConfig` tunable (start at about 3 pt up, as research suggests). Fit it from the device trace taps, not by guessing.
2. **Per-key learned offsets:**
   - When a word is committed and not reverted, align its taps to its letters and update a running mean offset per key in the personal store.
   - Cluster neighbouring keys while data is thin.
   - Use the means in the spatial model's Gaussians.
   - Cap the shift at about 0.3 key widths, so a key's centre always maps to that key ("anchored targets").
3. **The spatial model scores; boundaries don't move.** No visible or invisible hit-area resizing beyond the anchored cap. The decoder does the work.
4. **Learned confusion pairs:** key pairs Moe swaps often (from corrections) get a cheaper edit cost.

Done when:
- eval reruns with a tap-offset noise model;
- a device trace before and after shows fewer corrected letters;
- the CLI can print the per-key offset map (a Tap-Map, like SwiftKey's).

## Phase 13: Arabic and code-switching

1. **Suggestions only in the script being typed.** An Arabic-layout word never gets English candidates, and the reverse. Verify it, then lock it with a test.
2. **Wrong-layout rescue:** if a word typed on the EN layout isn't English but maps key-for-key to a known Arabic word ("hgsghl" → "السلام"), offer it in a side slot, and the reverse. Never switch the layout by itself.
3. **Franco vocabulary:** learn Latin-script tokens with digits ("3ashan", "7aga") from the chats as their own words, protected from English autocorrect.
4. **Cheap Arabic edits:** ة/ه, ى/ي and the hamza forms as near-free substitutions in the beam (check what's already there); the variant always gets a side slot.
5. **Arabic sentence start:** fix the open issue (news words at `<s>`) by down-weighting base `<s>` bigrams against personal ones.
6. **Device check:** backspace with tashkeel removes only the mark, and lam-alef splits back to lam.

Done when: the AR eval numbers improve with no guard regressions. The current weak spots are AR keystroke savings 27% vs EN 38.7%, and AR next-word top-3 at 15% vs EN 20%.

## Phase 14: Text polish (small Apple-parity items from the audit)

- Remove the space before `. , ? !` after a plain typed space too (compare with Apple first).
- Space after an auto-space, or after an auto ". ", doesn't add a second space.
- An opening quote after a space keeps the space; a closing quote removes it.
- Auto-capitalize after `."`, `.)`, `?"`.
- In caps lock, suggestions are all caps.
- Holding shift while typing several letters capitalizes all of them (today only the first).
- Suggestion replacement uses `documentContextAfterInput`, so a mid-word cursor replaces the whole word.
- Backspace acceleration: 0.5 s delay, 0.1 s then 0.06 s char repeat, word mode after about 15 chars. A little slower in word mode to avoid overshoot.
- Trackpad acceleration: a fast drag moves more characters per point.
- A press highlight and haptic on bar taps (on touch-down, like keys).

## Phase 15: Comfort settings

- **Keyboard height:** compact 50, default 54, tall 58 pt row pitch. The best-supported comfort option, and it partly offsets iOS's fixed 75 pt strip.
- **Optional number row** (off by default). When it's on, the pitch shrinks 2 to 4 pt so the total height barely grows.

## Not doing (and when to revisit)

- **Neural LM:** revisit once Moe has typed about 3 months with Kalam (personal text plus chats). Train a 1 to 3M-parameter CIFG offline and keep it only if top-3 gains 3 points or more. Then add it as a reranker with mmapped int8 weights and Accelerate, no CoreML.
- **Swipe typing:** Moe's choice.
- **Auto language switching:** users hate it; the wrong-layout rescue covers the need.
- **One-handed mode:** research shows no speed gain on a 6.3" phone.
- **Arabizi-to-Arabic transliteration:** add it if Moe asks.

## Order

1. Phase 10 (bugs).
2. Phase 11 (autocorrect trust).
3. Phase 9 (emoji, already queued in `PROMPTS.md`).
4. Phase 12 (touch model).
5. Phase 13 (Arabic).
6. Phase 14 (polish).
7. Phase 15 (comfort).

Phase 10 and 11 fix what users hate most and are cheap; 12 and 13 are where Kalam can beat Gboard for Moe specifically.
