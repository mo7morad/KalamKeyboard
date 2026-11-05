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

---

## Phase 11: autocorrect you can trust (docs/rd-plan.md)

```
Phase 11. Read CLAUDE.md, SPEC §2, §3, §5.4, §8.2, §8.5, §8.6, §9.2, docs/rd-plan.md (Phase 11) and docs/research/04-prediction-autocorrect.md §3 to §5.
Re-check each item against the current code first; skip and report what's already done.
Scope (logic in Autocorrect / TextContext / Learner / Engine with tests):
- Revert memory: deleting an autocorrected word and retyping the literal at the same spot is a rejection, like the one-backspace undo (the literal stays, the pair is stored, the literal counts as accepted).
- Never correct away a word Moe used 2 or more times (typed or imported), unless it's a recorded typo of another word.
- Guard rules: no correction inside URLs, paths, domains or emails (the whole token at the cursor), for mixed-script words, or for mid-sentence capitals; a stricter margin for words of 1 to 3 letters (EngineConfig, tuned with eval).
- Ambiguous contractions (its, were, ill, well, hell, id, shell, wed, shed, lets): suggest the contraction, never auto-apply it.
- Tap a corrected word (cursor in or after it) to revert it: the bar offers the original, and a tap replaces the whole word around the cursor.
- Learning hygiene: next-word predictions never offer a word that is neither a valid base word nor known to Moe.
Update SPEC §3 D8, §5.4, §8.5, §8.6, §9.2. Done when: engine tests pass, the policy table tests are extended, an eval run is logged in docs/eval-log.md with the guards holding, and docs/device-checklist.md has a Phase 11 section.
```

---

## Phase 12: a touch model that learns Moe's thumbs (docs/rd-plan.md)

```
Phase 12. Read CLAUDE.md, SPEC §2, §3, §5.2, §8.2, §8.3, §9.1, §9.2, §12, docs/rd-plan.md (Phase 12) and docs/research/03-ui-sizing-touch.md, 04-prediction-autocorrect.md §3.
Scope (engine with tests; the extension only passes taps along):
- A fixed tap offset in EngineConfig (key units), set from the device round 2 trace (taps land about 7 pt above the caps' centers), checked with eval under a matching tap bias.
- Per-key learned offsets: words committed and not reverted align their taps to their letters; a running mean per key in the personal store, shrunk toward the all-keys mean while data is thin, capped at 0.3 key widths, used by the spatial model. Hit areas don't move.
- Learned confusion pairs: one-letter substitutions in Moe's corrections make that key pair a cheaper far substitution.
- kalam-cli tapmap prints the per-key offsets (from the store, or from a pulled device trace).
- eval gets a tap-bias noise option.
Update SPEC §8.2, §9.1, §12. Done when: engine tests pass, eval runs with and without the bias are logged in docs/eval-log.md with the guards holding, and docs/device-checklist.md has a Phase 12 section (a trace before and after, the tapmap).
```

---

## Phase 13: Arabic and code-switching (docs/rd-plan.md)

```
Phase 13. Read CLAUDE.md, SPEC §2, §3, §5.4, §6, §8.2, §8.3, §8.6, §9.3, docs/rd-plan.md (Phase 13), docs/research/02-arabic-bilingual.md and docs/issues.md.
Re-check each item against the current code first; skip and report what's already done.
Scope (engine with tests):
- Suggestions only in the script being typed: verify it and lock it with tests.
- Wrong-layout rescue: a word typed on one layout that maps key-for-key (same physical spot) to a known word of the other language is offered in a side slot. Never switch the layout by itself.
- Franco: Latin tokens with digits from the chats become known words, complete by prefix and are never autocorrected (verify, fix gaps).
- Arabic variants: ة/ه, ى/ي and hamza forms cost nothing in the beam already (shared key); the best other spelling of the typed word always gets a side slot.
- Sentence start: base bigrams after <s> get less weight against the unigram and Moe's own (EngineConfig, tuned with eval; docs/issues.md).
Update SPEC §5.4, §8.2, §8.3. Done when: engine tests pass, an eval run is logged with the guards holding, and docs/device-checklist.md has a Phase 13 section (incl. backspace with tashkeel and lam-alef).
```

---

## Phase 14: text polish (docs/rd-plan.md, Apple parity)

```
Phase 14. Read CLAUDE.md, SPEC §2, §3, §5.2, §5.4, §8.6, §8.7, docs/rd-plan.md (Phase 14) and docs/research/05-code-audit.md §2.
Re-check each item against the current code first; skip and report what's already done (the mid-word suggestion tap was done in Phase 11).
Scope (rules in TextContext / KeyBehavior with tests, the extension calls them):
- The space before . , ? ! goes after a plain typed space too; a space right after an auto-space adds nothing.
- Quotes: an opening quote after a space keeps it, a closing one takes its place. Auto-capitals after ." .) ?" and the like.
- Caps lock makes suggestions all caps. Holding shift while typing capitalizes every letter.
- Backspace acceleration (0.5 s delay, 0.1 s then 0.06 s, slower whole words) and trackpad acceleration.
- Bar slots highlight, buzz and click on touch-down, like keys.
Update SPEC §5.2, §5.4, §8.6, §8.7. Done when: engine tests pass and docs/device-checklist.md has a Phase 14 section (side by side with Apple's keyboard).
```

---

## Phase 15: comfort settings (docs/rd-plan.md)

```
Phase 15. Read CLAUDE.md, SPEC §2, §3, §5.1, §5.2, §10, docs/rd-plan.md (Phase 15) and docs/research/03-ui-sizing-touch.md.
Scope (geometry and settings in the engine with tests; the keyboard and the host app read them):
- Keyboard height: compact 50, default 54, tall 58 pt row pitch, a host-app setting.
- Optional number row (off by default) on the letters pages, with a smaller pitch so the keyboard grows less; the top row then drops its digit hints and long-press digits.
- Tap points stay in the letters page's key units, whatever the height or number row, so the spatial model and learned offsets keep working.
Update SPEC §5.1, §5.2, §10. Done when: engine tests pass (geometry for each height, key units with and without the number row) and docs/device-checklist.md has a Phase 15 section.
```

---

## Phase 16: a benchmark that looks like Moe's typing (autocorrect, both languages)

Why: Moe says autocorrect is weak in both languages. Today's evals can't show it. `eval` only scores words that are valid base words (so Egyptian words such as بنجربه or مفيش are never scored), and `eval-personal` taps key centres, so it only measures wrong changes, never fixes. The fox trace shows the misses: brow (valid word, context says brown), fo, حاخالص (extra tap), وفمقيش (swap plus extra tap), كويسك ه (stray space).

```
Phase 16. Read CLAUDE.md, SPEC §2, §3, §8.2, §8.3, §8.5, §12 and docs/eval-log.md (last two entries).
Scope (kalam-cli only; no engine behaviour change):
- eval-personal --noise: types each held-out word of Moe's chats with NoisyTypist (sigma, bias and the
  omission / extra-tap / swap rates as in eval, Moe-like bias-y -0.13), with the personal model trained on the
  other 90%. A word counts when it's a valid base word or known in the trained personal model.
  Report per language: fix rate (noisy taps -> intended word), wrong-change rate (clean taps -> anything else),
  top-1 rate, and a breakdown of misses by error kind (substitution, omission, extra tap, swap, real-word).
- --samples N prints misses and wrong changes with their taps' error kind.
- A real-word case: a noisy result that is itself another valid word (brow for brown) is counted separately.
Log a baseline on the real klex + Moe's 3 chats, 10 folds, normal mode, in docs/eval-log.md.
Done when: swift test passes and the baseline is logged. This baseline is the bar Phase 17 must beat.
```

## Phase 17: better autocorrect, measured (EN + AR)

```
Phase 17. Read CLAUDE.md, SPEC §2, §3, §7, §8.2, §8.3, §8.5, docs/research/06-autocorrect-leaders.md, docs/eval-log.md (Phase 16 baseline).
Work from the Phase 16 miss breakdown, biggest bucket first. Each change is its own eval run (10 folds,
both languages) logged in docs/eval-log.md. Keep it only if the fix rate rises and the wrong-change rate
doesn't (wrong changes stay at or under the baseline; FA <= 0.5% on the synthetic eval).
Candidates, in expected order of value (docs/research/06-autocorrect-leaders.md):
1. Re-tune the edit costs and AR's double-counted edit cost on the new benchmark (insertion 5.0 makes
   حاخالص -> خالص impossible; the AR rule adds c*'s edits to theta).
2. Post-correction (Gboard, iOS): when the next word commits, re-score the previous word with context on
   both sides and replace it when the margin is large and it's one cheap edit away (brow -> brown before fox).
   Same one-backspace undo and revert memory as an autocorrect. Tunables (margin, max edit cost) in EngineConfig.
3. Egyptian dialect data in the AR base: a Masri corpus into the AR unigrams and bigrams in
   Tools/lexicon-builder (data only, the .klex stays mmapped). Measure footprint and the benchmark.
4. AR clitic candidates: a known stem plus one clitic (بنجرب+ه) as a candidate, not only as a protected literal
   (CAMeL Tools only if Moe allows the dependency).
5. Space errors (Gboard, SwiftKey Smart Space): a stray space inside a word (كويسك ه), a missed space
   (thequick), only if the benchmark shows them.
All tunables in EngineConfig. Update SPEC §8.2, §8.5. Done when: swift test passes, every kept change has its
eval line, and docs/device-checklist.md has a Phase 17 section (the fox sentence and 3 Arabic sentences).
```

## Phase 18: autocorrect that looks like Apple's (visuals only)

A keyboard extension can't draw in the host app's text, so Apple's underline on a corrected word and its popover are out of reach. Everything Apple shows in the bar is in reach.

```
Phase 18. Read CLAUDE.md, SPEC §2, §3, §5.3, §5.4, §8.5 and Moe's screen recording of Apple's keyboard in
docs/reference/apple/ (autocorrect-*.png frames).
Scope (KeyboardExtension/Views/SuggestionBar.swift, behaviour unchanged):
- Match Apple's pending-autocorrect look frame by frame: the primary slot's highlight (shape, colour,
  light and dark), the quoted literal, text weight, and how the slots animate in and out as Moe types.
- After a commit, the bar's revert state and the backspace undo look like Apple's.
- No main-thread work beyond today's (one layer animation per change, no repaint per keystroke).
Update SPEC §5.4. Done when: the extension builds, simulator screenshots sit next to Apple's frames in
docs/reference/kalam/, and docs/device-checklist.md has a Phase 18 section.
```
