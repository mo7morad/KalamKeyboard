# PROMPTS.md

## How to use

- **Orchestrated mode (current):** the main session hands each phase prompt to its own subagent and reviews the result (see CLAUDE.md). The steps below describe the manual mode.
- One phase = one Claude Code session.
- Run `/clear` before each phase. The repo files are the memory, so you don't need to re-explain anything.
- Paste the phase prompt. Claude Code plans first, you approve, it builds and tests, you run the device checklist, then it commits.
- If a phase grows too big, ask it to split the plan into steps and approve one step at a time.

---

## Phase 0: you, by hand (~20 min)

Done by the orchestrator instead: `project.yml` + `xcodegen generate` covers steps 1 to 8 and 10 (team BD8SA4X398, `com.morad.kalam`, `group.com.morad.kalam`). Step 9 (screenshots) still needs Moe.

1. In Xcode, create a new **iOS App** project: SwiftUI, name `Kalam`, deployment target iOS 18.0.
2. File → New → Target → **Custom Keyboard Extension**, named `KalamKeyboard`. Activate its scheme.
3. Under Signing, set your paid team on both targets. Bundle IDs: `<prefix>.kalam` and `<prefix>.kalam.keyboard`.
4. Add the **App Groups** capability to both targets, with the group `group.<prefix>.kalam`.
5. In KalamKeyboard's Info.plist, under `NSExtension` → `NSExtensionAttributes`, set:
   - `RequestsOpenAccess` = YES
   - `PrimaryLanguage` = `mul`
   - `IsASCIICapable` = YES
6. Confirm the project folders are **synchronized folders** (the default for new projects in Xcode 16+).
7. Create these folders: `Packages/`, `Tools/`, `docs/reference/`, `shared-test-vectors/`.
8. Put `SPEC.md`, `CLAUDE.md` and `PROMPTS.md` in the repo root, and `normalization_vectors.json` in `shared-test-vectors/`.
9. Add the screenshots listed in SPEC §15 to `docs/reference/`.
10. Run `git init` and make the first commit.
11. Run `claude` in the repo root and paste the kickoff prompt.

---

## Kickoff (first session)

```
Read CLAUDE.md, then SPEC.md in full. Do not write code.
1) Check the repo against PROMPTS.md Phase 0 and SPEC §15 (targets, App Group, Info.plist keys, screenshots). List what is missing.
2) List contradictions, risks or gaps you see in SPEC, max 8, one line each, most severe first.
3) Ask me at most 5 questions. Then stop.
```

---

## Phase 1: keyboard shell (Apple feel, no suggestions)

```
Phase 1. Read CLAUDE.md, SPEC §2, §3, §4, §5, §11.
Goal: a keyboard that looks and feels like Apple's for English and Arabic, with no engine.
Scope:
- Create Packages/KalamEngine (library + empty kalam-cli) containing only Layout models and the layout JSON resources (SPEC §5.1), built from docs/reference/ screenshots. Add a unit test that loads every layout, checks key ids are unique, and checks every letter page has the expected alternates.
- Give me exact Xcode steps to add the local package and link KalamEngine to both targets. Wait until I confirm.
- KeyboardView (UIKit, single view, layer-drawn keys): touch model §5.2 (nearest-key hit test, touch-up commit, rollover, popups, long-press alternates, shift/caps lock, backspace repeat → word delete, space trackpad, double-space period, 123/#+= pages, return key types, EN/AR key, globe rules), appearance and height matching the screenshots, light/dark.
- FeedbackPlayer §5.3 (haptic on touch-down, sound IDs 1104/1155/1156).
- Empty suggestion bar placeholder with the Full Access banner.
- Memory hygiene §11: view teardown in deinit, Debug-only footprint + headroom overlay.
Out of scope: engine, suggestions, learning, host app screens.
Done when: package tests pass, both targets build, and you hand me a device checklist (feel, sounds by ear vs Apple, haptics, rollover with two thumbs, trackpad, Arabic layout vs screenshot, 20 show/hide cycles memory).
Start in plan mode and wait for my OK.
```

---

## Phase 2: engine core (fixture data only)

```
Phase 2. Read CLAUDE.md, SPEC §2, §3, §6, §7.2, §8.1 to §8.3, §12.
Goal: a working, tested engine on a tiny fixture lexicon. No UI changes.
Scope:
- Normalization (§6.1) in Swift, tested against shared-test-vectors/normalization_vectors.json. Python reference in Tools/lexicon-builder with pytest on the same file.
- Tokenizer (§6.2) with the listed tests.
- .klex format: design it, document it in docs/klex-format.md, write it in Python, read it in Swift (mmapped, failable validated init). Round-trip test on a ~50-word EN+AR fixture with a few bigrams and variants (e.g. انا/أنا, على/علي, dont/don't).
- Beam search (§8.2) with the spatial model over the fixture trie, completions via max-subtree score, variants, literal candidate.
- Scoring (§8.3) with base data only (personal terms = 0). EngineConfig holds every constant.
- kalam-cli suggest with a score breakdown.
Tests must include: spatial typo "rhe"→"the", transposition "teh"→"the", omission "helo"→"hello", doubled-letter "leter"→"letter", AR "انا" shows أنا as a variant, completion "hel"→hello/help, invalid .klex file → engine returns no base suggestions without crashing.
Start in plan mode and wait for my OK.
```

---

## Phase 3: real lexicons + evaluation baseline

```
Phase 3. Read CLAUDE.md, SPEC §3, §7, §12.
Before starting, tell me exactly which Leipzig tarballs to download and where to put them, then wait.
Scope:
- Full builder pipeline (§7.1): wordfreq==3.1.1 unigrams with filters and sizes, Leipzig bigrams via wordfreq.tokenize with <s>, deterministic 5% held-out split, EN casing table, validity flags (zipf threshold, optional Wikipedia misspellings list), variant pruning, AR preferred spelling.
- Output KeyboardExtension/Resources/en.klex and ar.klex. Report file sizes and build time.
- kalam-cli eval with Gaussian tap noise on the real layout geometry (§12). Metrics: autocorrect top-1, false-autocorrect on clean words (guard ≤ 0.5%), next-word top-3, keystroke savings. Write the baseline to docs/eval-log.md.
- Print a 20 EN + 20 AR sanity table (typed → top 3) for me to review.
Done when: pytest and swift test pass, the eval baseline is logged, and the sanity table is reviewed by me.
Start in plan mode and wait for my OK.
```

---

## Phase 4: personal learning

```
Phase 4. Read CLAUDE.md, SPEC §3, §8.3 to §8.5, §9, §12.
Goal: the "remembers me" layer, fully tested on macOS. No UI.
Scope:
- PersonalStore: SQLite schema §9.1, WAL, busy_timeout, migrations, short transactions only.
- Decay §8.4, interpolated LM with personal terms §8.3, personal in-memory trie (cap 30k, LRU by decayed count).
- Learner: commit-buffer state machine §9.2, pending→known rules, rejections from autocorrect undo, manual-correction learning, special tokens, no-learn fields.
- Autocorrect policy §8.5 as a pure function with a table-driven test suite (include: known personal word is never corrected, rejected pair never repeats, gentle vs normal thresholds, EN contraction fix dont→don't, AR variant fix off by default, digits/handles never corrected).
- WhatsApp parser §9.3 with synthetic iOS and Android fixtures.
- kalam-cli eval-personal (90/10 split of a chat file I'll give you) reporting personalization lift.
Start in plan mode and wait for my OK.
```

---

## Phase 5: integration into the keyboard

```
Phase 5. Read CLAUDE.md, SPEC §2, §4, §5.4, §8, §9.2, §11.
Goal: live suggestions, predictions, autocorrect and learning inside the keyboard.
Scope:
- EngineClient: one serial queue, generation numbers, stale-result drop, cooperative cancellation, the ≤20 ms commit-path wait.
- InputController: current word + taps, resync from documentContextBeforeInput on textDidChange/selection change, context words, <s> handling.
- Suggestion bar §5.4 (slot order, RTL mirroring, bold pending autocorrect, quoted literal, tap to accept, long-press to forget).
- Autocorrect on commit with one-backspace undo, punctuation spacing §8.7, auto-shift and casing §8.6.
- Learner hooks, flush on viewWillDisappear, UILexicon import.
- Settings read from App Group UserDefaults (keys defined in KalamEngine so the host app shares them).
- os_signpost latency + footprint logging (Debug overlay shows both).
Done when: everything builds and tests pass, and you give me a device checklist covering: typo fixes, undo, learning a new word after 2 uses, next-word after 3 repeats of a phrase, Arabic variants, latency/memory numbers from the overlay, no crash when Full Access is off.
Start in plan mode and wait for my OK.
```

---

## Phase 6: host app

```
Phase 6. Read CLAUDE.md, SPEC §9.3, §10.
Scope: Setup screen (steps + open Settings), Try-it field, Settings, Learned words (search, state, count, forget/block, add), Import (WhatsApp _chat.txt via fileImporter with sender picker, paste text), Data (stats, export backup via VACUUM INTO + share sheet, restore, reset).
All store access goes through KalamEngine's PersonalStore. Keep transactions short (the keyboard may be writing at the same time).
Done when: builds, store-level tests for import/backup/restore pass, and you give me a device checklist.
Start in plan mode and wait for my OK.
```

---

## Phase 7: tuning and hardening (after ~1 week of daily use)

```
Phase 7. Read CLAUDE.md, SPEC §8, §11, §12, and docs/issues.md.
For each issue: reproduce it with kalam-cli (add a regression test), fix via EngineConfig or code, rerun eval, and log it in docs/eval-log.md. Guards must not regress.
Also: review device latency/memory logs I paste, run the Core Haptics experiment (§5.3) behind a setting, and run a leak check (20 show/hide cycles across 3 apps).
Start by listing the issues grouped by root cause, then wait for my OK.
```

### `docs/issues.md` entry template

```
## <short title>
- Lang / app: 
- Context (text before cursor): 
- I typed: 
- I expected: 
- Keyboard did: 
- Frequency: once / sometimes / always
```

---

## Phase 8: Gboard gestures (device round 2, Moe's pick)

```
Phase 8. Read CLAUDE.md, SPEC §2, §3, §5.1, §5.2.
Scope:
- Backspace swipe left deletes whole words, live: each step left deletes one more word, dragging back right restores them, release keeps the result.
- Slide from shift onto a letter types one capital and shift returns off. Slide from 123 (or ١٢٣) onto a key of the numbers page types it and returns to letters, like Apple.
- A clear downward swipe on the keys hides the keyboard (dismissKeyboard), with thresholds strict enough that fast typing never triggers it.
Update SPEC §5.2. Done when: builds, engine tests pass, the geometry/gesture math has tests, and you give a device checklist.
```

---

## Phase 9: emoji panel and emoji suggestions (device round 2, Moe's pick)

```
Phase 9. Read CLAUDE.md, SPEC §2, §3, §5.4, §5.5.
Scope:
- Data: a Tools script builds emoji.json (Apple-style categories from Unicode emoji-test.txt, EN and AR keywords from CLDR annotations), committed as a KalamEngine resource.
- Panel: an emoji button in the bar next to the clipboard button opens an Apple-style emoji panel in place of the keys (category tabs, recents, ABC, backspace). Apple's emoji glyphs via the system font.
- Suggestions: when the current word matches an emoji keyword (EN or AR), the bar offers the emoji; a tap replaces the word with it.
Update SPEC §5.4 and a new §5.6. Done when: builds, tests pass, and you give a device checklist.
```

---

## Phase 10: lost keystrokes and silent wrong output (docs/rd-plan.md)

```
Phase 10. Read CLAUDE.md, SPEC §2, §3, §5.2, §8.5, §8.7, docs/rd-plan.md (Phase 10) and docs/research/05-code-audit.md.
Re-check each bug against the current code first; skip and report any that is already fixed.
Scope (logic in KeyBehavior / TextContext with tests, the extension only calls it):
- A slow press on a top-row key preselects the digit only when its hint is drawn (EN with hints on). Otherwise the letter is in the strip and preselected.
- A space held into the trackpad that never moved the cursor types a space on release.
- The top row's 12 pt reach into the bar holds only during a typing burst; after a pause, while the bar shows suggestions, the band is the bar's.
- A system-cancelled letter press held 30 ms or more commits its letter.
- The trackpad direction follows the script of the text at the cursor, not the layout.
- An autocorrect committed by punctuation or return can be undone: backspace removes the punctuation, the next one reverts.
Update SPEC §5.2 and §8.5. Done when: engine tests pass, and docs/device-checklist.md has a Phase 10 section (fast typing, slow space, low bar taps, Arabic slow presses, cancels, mixed-script trackpad, undo after punctuation).
```
