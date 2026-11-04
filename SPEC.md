# Kalam: personal iOS keyboard (English + Arabic)

Single user (Moe), installed with a paid Apple Developer account, never published.
App Store rules, privacy, security hardening and legal concerns do not matter here: it only has to work perfectly for Moe. iOS platform limits still do, because iOS enforces them at runtime.

Source of truth for Claude Code. `CLAUDE.md` holds the working rules, `PROMPTS.md` the phase prompts.

---

## 0. TL;DR

- A custom keyboard extension (UIKit) that **feels like Apple's** (layout, key popups, haptics, the 3 system click sounds) and **predicts like Gboard** (learns Moe's words, casing, phrases and typos, and gives personal-first next-word prediction).
- Engine: a pure Swift package (`KalamEngine`) tested with `swift test` on the Mac. Base dictionaries: memory-mapped binary files built offline by a Python script. Personal learning: SQLite in the App Group container.
- Languages: English and Arabic (Moe writes Egyptian dialect casually and switches between AR and EN). No swipe typing. No network.
- Built in phases (`PROMPTS.md`), and each phase is verified before the next one starts.

## 1. Goals and non-goals

Goals, in priority order:

1. **G1 Feel.** Never drop a keystroke and never lag. Typing feel at least as good as Apple's keyboard.
2. **G2 Memory.** Learns Moe's vocabulary, casing, phrases and his own typos. Stops "correcting" words he actually uses.
3. **G3 Prediction.** Strong next-word prediction, with personal data first.
4. **G4 Autocorrect.** Fixes real typos, one backspace undoes it, and it never fights known words.
5. **G5 Two languages.** EN and AR in one keyboard with a one-tap switch.

Non-goals for v1: swipe/glide typing, dictation (no mic access in keyboard extensions), an emoji panel (use the system emoji keyboard via the globe), themes, iPad layouts, sync, and App Store compliance. Section 14 lists features for later.

## 2. Platform facts to design around

| Fact | Consequence |
|---|---|
| iOS enforces a memory ceiling on keyboard extensions, about **60 MB phys_footprint** (dirty + compressed pages) on recent iPhones. Crossing it means a silent jetsam kill: no crash log, and iOS swaps back to the previous keyboard. It is an OS limit, not a policy, so it applies to personal builds too. It can't be raised: Xcode 27.1 won't provision `com.apple.developer.kernel.increased-memory-limit` for an app extension. | No self-imposed memory budget. Use whatever makes the keyboard work best and stay under the real ceiling on Moe's phone, read at runtime as `phys_footprint + os_proc_available_memory()`. |
| **Memory-mapped files are nearly free** (clean pages are not charged); parsed Swift arrays and dictionaries are charged. One shipping keyboard went from 52 MB to 27 MB by moving its word list to an mmapped binary. | Base lexicons are mmapped binaries and are never parsed into Swift collections. |
| `UIInputViewController` is recreated for each host app, and old views can stay alive. | Tear down the view hierarchy in `deinit`, deferred one main-queue turn. Leak-test with show/hide cycles. |
| Each extra thread costs about 0.5 MB of stack. `DispatchQueue.global` spawns threads. | Use one serial engine queue. No global queues and no Swift-concurrency `Task` in the hot path. |
| **Full Access** is required for App Group shared-container writes. Older docs say haptics and sounds need it too. | `RequestsOpenAccess = YES`. Show a banner in the keyboard if `hasFullAccess == false`. |
| `AVAudioPlayer` goes through the media volume bus, so clicks become inaudible at low media volume. `AudioServicesPlaySystemSound` uses the ringer volume, respects the silent switch and needs no audio session. | Use system sound IDs **1104** (key), **1155** (delete), **1156** (modifier). |
| iOS forces the system keyboard in secure fields and phone-pad fields. Some apps block third-party keyboards. Extensions get no microphone. | Accept these limits; don't try to work around them. |
| `documentContextBeforeInput` is partial and can be nil. | Engine context = the last 2 words from it. The keyboard keeps its own word state and resyncs on `textDidChange`. |
| A SQLite lock held in an App Group container while the process suspends gets the process killed (`0xdead10cc`). | Short transactions only. Never hold a transaction open while idle. Flush on `viewWillDisappear`. |
| KeyboardKit's free tier gives a basic English layout only. Localized layouts (Arabic) and autocomplete are paid Pro features, and it abstracts away raw touch points. | Don't use KeyboardKit (D1). |

Sources: dev.to "The three hard constraints of an iOS keyboard extension" (TBDS); KeyboardKit and KeyboardKit Pro READMEs; Stack Overflow on sound IDs 1104/1155/1156.

## 3. Decisions (locked unless Moe changes them)

- **D1 UI in UIKit.** One custom `KeyboardView` with layer-drawn keys and raw touch handling, so that we get raw touch coordinates for the spatial model, rollover and exact haptic timing at the lowest memory cost. The host app is SwiftUI.
- **D2 Engine as a local Swift package** `Packages/KalamEngine`: a `KalamEngine` library (no UIKit import) plus a `kalam-cli` executable for debugging and evaluation. It must build and test on macOS.
- **D3 Base lexicon** is a custom binary `.klex` file per language, mmapped, and built by `Tools/lexicon-builder` (Python).
  - Unigrams come from `wordfreq==3.1.1` "large" lists (verified: EN 321k entries, AR 620k).
  - Bigrams are counted from Leipzig Corpora Collection sentence files.
- **D4 Personal store** is SQLite (system `SQLite3` with a thin wrapper, no GRDB) in the App Group container, in WAL mode.
- **D5 Decoder** is a trie beam search with a touch-point (spatial) error model plus an interpolated n-gram language model (personal + base). No neural models in v1, because of the memory limit.
- **D6 Layouts are JSON data** built from Moe's screenshots of Apple's keyboards (`docs/reference/`). Do not guess the Apple Arabic layout.
- **D7 One extension serves both languages** (`PrimaryLanguage = mul`). A dedicated EN/AR key switches between them internally.
- **D8 Variant auto-fix defaults.**
  - The Arabic spelling-variant auto-fix (انا→أنا) is **off** by default, but variants still appear as suggestions. In wordfreq, انا (7.9e-4) is as common as أنا (7.8e-4), and dialect الي collides with إلى.
  - The English contraction fix (dont→don't, im→I'm) is **on** by default.
- **D9 Personal seed:** Moe imports his own WhatsApp messages (exported `.txt`) through the host app. This is the main way to cover Egyptian dialect, because the base Arabic data is mostly MSA.
- **D10 No third-party dependencies** without asking. Python may use `wordfreq` and `pytest` only.
- **D11 Concurrency.** The engine is confined to one serial `DispatchQueue`, and the package uses Swift 5 language mode in v1 to avoid strict-concurrency churn.
- **Names:** product "Kalam"; bundle IDs `<prefix>.kalam` and `<prefix>.kalam.keyboard`; App Group `group.<prefix>.kalam`. Rename freely in Phase 0.

## 4. Architecture

```
Kalam/
  Kalam.xcodeproj
  App/                      SwiftUI host app (target: Kalam)
  KeyboardExtension/        UIKit keyboard (target: KalamKeyboard)
    Resources/en.klex, ar.klex
  Packages/KalamEngine/
    Sources/KalamEngine/    engine (no UIKit)
      Resources/Layouts/*.json
    Sources/kalam-cli/      debug + eval CLI
    Tests/KalamEngineTests/ (+ Fixtures/)
  Tools/lexicon-builder/    Python builder + pytest
    corpora/                (gitignored raw downloads)
  shared-test-vectors/normalization_vectors.json
  docs/reference/           Moe's screenshots
  docs/klex-format.md, docs/eval-log.md, docs/issues.md
  SPEC.md  CLAUDE.md  PROMPTS.md
```

```
touch ─▶ KeyboardView (main) ──insertText──▶ textDocumentProxy   (never waits on engine)
              │ Tap(char, point)
              ▼
       InputController (main): current word, taps, shift, lang, autocorrect-undo slot
              │ request(generation)                    ▲ SuggestionResult(generation)
              ▼                                        │
       EngineQueue (1 serial queue) ── KalamEngine ────┘
                    ├─ BaseLexicon   (mmapped .klex per language)
                    ├─ PersonalStore (SQLite, App Group, WAL)
                    └─ Learner       (commit buffer → batched writes)
```

- Results carry a generation number, and stale results are dropped. A request that is already stale when the engine queue reaches it is skipped. There is no in-loop cancellation, since candidates take 2.6 ms at p95 on a Mac (Phase 3b). Add it if the device p99 calls for it.
- Layout JSON lives in the engine package resources, so the keyboard UI, the spatial model and the CLI's typing simulator share one geometry.
- `.klex` files are bundled only in the extension target. The CLI and tests take file paths; tests use a small fixture.

## 5. Keyboard UI and feel

### 5.1 Layouts (JSON)

- One file per language and page (`en-letters`, `en-numbers`, `en-symbols`, `ar-letters`, ...).
- Rows hold keys: `{id, label, output, width, kind, alternates[], popup}`.
  - `width` is in relative units, where 1.0 = a standard letter key.
  - `kind` ∈ char | shift | backspace | space | return | globe | lang | page.
- The keyboard computes frames at runtime. The engine gets key centers in **key units** (1.0 = one standard key width or height), never points.
- Built from the screenshots in `docs/reference/`, then compared side by side with them.
- Arabic alternates must include at least: ا → أ إ آ ء, ي → ى ئ, و → ؤ, ه → ة. Arabic punctuation: ، ؛ ؟. English alternates follow Apple's accents.
- Gboard-style long-press digits on the top row (q→1 … p→0; Arabic top row → digits, Western or Eastern per setting), with small hint labels (setting, default on). This also helps typing Franco words like "3ashan".

### 5.2 Touch model

- **Hit-testing:** every touch point maps to a key (nearest key, no dead zones).
- **Haptic and sound fire on touch-down.** A letter is output on touch-up, at the key under the finger. The finger may slide, and the popup follows it.
- **Rollover:** a new touch-down immediately commits any pending letter touch.
- **Tap recording:** record the commit point of every letter tap (in key units) as a `Tap`.
- **Popups:** a key popup appears on press (except on bottom-row keys).
  - A long-press of 0.35 s opens the alternates strip. Slide to select, and release to insert.
- **Shift:** a tap shifts one letter; a double-tap within 0.3 s locks caps. Auto-shift follows 8.6.
- **Backspace:**
  - Touch-down deletes 1 character.
  - Holding for 0.45 s starts repeat deletion every 0.09 s.
  - After 15 repeats, it switches to whole-word deletion.
  - Sound 1155 plays on each deletion.
- **Space:**
  - A tap inserts a space, which is also the autocorrect commit.
  - A horizontal drag of more than 12 pt, or a long-press of 0.4 s, enters trackpad mode: key labels hide, and the cursor moves via `adjustTextPosition` at about 1 character per 9 pt. Releasing exits.
- **Double-space** → ". " when the previous character is a letter or digit (setting).
- **Pages:** 123 and #+= pages work like Apple's. Typing space or ' on the 123 page returns to letters.
- **Return:** the label comes from `returnKeyType`. It looks dimmed when `enablesReturnKeyAutomatically` is set and the field is empty.
- **Bottom row:**
  - When `needsInputModeSwitchKey == false` (Face ID iPhones): `[123] [EN/AR] [space] [return]`.
  - When it's true: `[123] [globe] [EN/AR] [space] [return]`. The globe uses `handleInputModeList(from:with:)`: a tap goes to the next system keyboard, and a long-press opens the list.
  - The EN/AR key toggles the layout and the engine language. The last-used language is remembered.
- **Appearance:** light and dark follow `textDocumentProxy.keyboardAppearance` and the trait collection. Match the screenshots for key color, corner radius, shadow, font, keyboard height per device, and suggestion bar height.
  - iOS 27 puts a taller globe/dictation strip under third-party keyboards than under Apple's, so Kalam sits about 7 pt higher than Apple's keyboard. The extension can't change that (Phase 1).

### 5.3 Feedback

There is a single `FeedbackPlayer`, called on touch-down for every key.

- **Haptic:**
  - One `UIImpactFeedbackGenerator(style: .light)`.
  - Call `prepare()` on keyboard appear and after each fire.
  - `impactOccurred(intensity:)` with the intensity setting (0.3 to 1.0, default 0.7).
- **Sound:** `AudioServicesPlaySystemSound`.
  - Letters, digits and punctuation → 1104; backspace → 1155; shift, 123, EN/AR, globe, return and space → 1156.
  - Verify this mapping by ear against Apple's keyboard on the device and adjust the table if needed.
- Never use `AVAudioPlayer` or `AVAudioSession` in the extension.
- Phase 7 experiment: a Core Haptics transient (intensity 0.6, sharpness 0.8). Keep it only if it starts reliably inside the extension and feels closer to Apple's.

### 5.4 Suggestion bar

- **Layout:** 3 slots in Apple style. EN order is `[alt1] [primary] [alt2]`; AR mirrors it (RTL).
- **While typing a word:**
  - The primary slot shows the best candidate.
  - If an autocorrect is pending, the primary is **bold** and alt1 shows the literal in quotes (“teh”).
  - Otherwise, alt1 shows the 2nd candidate and alt2 the 3rd.
- **With an empty current word:** the bar shows 3 next-word predictions.
- **Tapping a suggestion** replaces the current word (or inserts the prediction) and adds an auto-space. Tapping the literal is an explicit accept, so the word is learned.
- **Blocking a word:** long-press a suggestion to open a small in-keyboard overlay, "Don't suggest ‘x’". This blocks the word (the host app lists it as Blocked; there, "Forget" deletes a word's learned data instead). Use no alerts, since extensions can't show them.
- **Without Full Access:** the bar shows "Turn on Full Access for learning, haptics and sounds", and autocorrect is off, since it couldn't be seen pending.

## 6. Text processing (engine)

### 6.1 Normalization (lookup keys only, never displayed)

- **AR:**
  - Apply NFC.
  - Drop U+0640 (tatweel), U+064B to U+065F, U+0670, Quranic marks U+06D6 to U+06ED (see the vectors), and ZWNJ, ZWJ, LRM and RLM.
  - Map أ إ آ ٱ → ا, ى → ي, ة → ه, ؤ → و, ئ → ي, ک → ك, ی → ي.
  - **Keep ء.**
- **EN:**
  - Apply NFD.
  - Drop scalars whose canonical combining class ≠ 0.
  - Drop apostrophes (' ’ ‘ ʼ) and lowercase.
  - Keep hyphens and digits.
- **Implementation:** iterate **Unicode scalars**, not Swift `Character`s (an Arabic letter plus its tashkeel is a single Character).
- **Tests:** `shared-test-vectors/normalization_vectors.json` (generated from a reference Python implementation) is the contract. The Python builder and the Swift engine must both pass every case. Any change means updating the file and both implementations.

### 6.2 Tokenization (runtime and import)

- **EN word:** a maximal run of `[A-Za-z0-9]` with inner apostrophes, containing at least one letter. So "3ashan" is a word and "2026" is not.
- **AR word:** a maximal run of Arabic letters (U+0621 to U+064A, U+0671) plus tashkeel. The tashkeel is stripped from the stored surface.
- **Special token:** an email, URL, @handle or #tag is kept whole, with lang `tok`.
- Everything else separates words. `. ! ? ؟` and newline end a sentence, which gives `<s>`.

Required tests:

| Input | Tokens |
|---|---|
| "I'm going, don't wait!" | `I'm` `going` `don't` `wait` |
| "أنا مُحَمَّد، وعايز" | `أنا` `محمد` `وعايز` |
| "ok 3ashan kda" | `ok` `3ashan` `kda` |
| "mail me@x.com now" | `mail` `me@x.com`(tok) `now` |

### 6.3 Word identity and casing

- **`ident`** (used in n-grams):
  - EN: the lowercased surface.
  - AR: the surface without tashkeel. Variants stay distinct idents (انا ≠ أنا).
  - tok: the exact surface.
- **Display casing (EN):** Moe's personal casing (his most frequent form) wins over the corpus casing table, which wins over the shift state.

## 7. Base lexicon (`.klex`)

### 7.1 Data pipeline (`Tools/lexicon-builder`, Python 3.11+ venv)

**Unigrams**

- `wordfreq.get_frequency_dict(lang, wordlist='large')`.
- Filter EN with `^[a-z]+(['’][a-z]+)*$` and AR with an Arabic-letters-only regex.
- Keep the EN top 150k and the AR top 250k. Measured:
  - EN 150k gives 146k keys and 318k trie nodes.
  - AR 250k gives 220k keys and 328k trie nodes, and about 25k keys have more than one variant.
- wordfreq keeps hamza forms distinct and includes common Egyptian words (ده, عايز).

**Bigrams and casing**

- Use Leipzig Corpora Collection 1M-sentence corpora for `eng` and `ara`: the newest news/web/wiki ones available.
- Moe downloads the tarballs from https://wortschatz.uni-leipzig.de/en/download/ into `corpora/` himself.
- Use the `*sentences.txt` file (format: `Sentence_ID<TAB>Sentence`). Tokenize with `wordfreq.tokenize(text, lang)` so tokens match the unigram list, and insert `<s>` at each sentence start.
- Hold out 5% of the sentences (deterministic hash split) for evaluation. These must never enter the lexicon.
- **Casing table (EN):** for each lowercase word, use its most common non-sentence-initial casing in the raw sentences, but only if that casing holds at least 90% of those forms. Below that, news title case (Street, King) and split forms (OK / ok) stay lowercase. Force `i` → `I`, and capitalize the I in the i-contractions (i'm, i'll, i'd, i've).

**Validity, pruning and preferred spellings**

- **Validity flag:** a variant is `valid` (counts as a real word and blocks autocorrect) iff zipf ≥ 2.0 (tunable) and it isn't in the EN misspellings list. The list is an optional download: Wikipedia, "Lists of common misspellings/For machines".
- **Variant pruning:** drop variants with less than 3% of their key's total frequency.
- **Preferred spelling (AR):** among variants with a share of at least 15%, pick the most frequent one containing any of أ إ آ ؤ ئ ء ة ى; otherwise, the most frequent variant.

### 7.2 Format requirements

Claude Code designs the exact layout and documents it in `docs/klex-format.md`.

- **Header:** little-endian, with magic `KLEX`, version, lang, section offsets and lengths, counts, and a CRC32 of the body.
- **Sections:**
  - **Trie** over normalized keys (UTF-16 units, children sorted). Each node stores: first child, child count, char, terminal → key id, and max-subtree score (for best-first completion).
  - **Keys** → variant ranges.
  - **Variants:** word id, surface (in a UTF-8 string pool), quantized log-prob, and flags (valid, preferred).
  - **Bigrams:** for each w1 word id (including `<s>`), the top 32 w2 by probability, with quantized log-probs.
  - **Casing table.**
- **Reading:** use `Data(contentsOf:options: .alwaysMapped)` and access it with `withUnsafeBytes` + `loadUnaligned`. No per-query copies.
- **Validation:** validate the header and offsets once, in a failable init. An invalid file means the engine runs personal-only; it must never crash.
- **Budget:** no size cap on disk (mmapped clean pages aren't charged against the ceiling). Map + validate in < 30 ms whatever the file size, so the init checks the header and section bounds only; the body CRC32 is checked by the builder, the tests and `kalam-cli`. Every index read is bounds-checked, so a corrupt file degrades and never crashes. < 3 MB of dirty memory from the lexicon.
- **Round-trip tests:** the Python writer and the Swift reader share a tiny fixture lexicon (about 50 words, both languages) checked into the tests.

## 8. Suggestion engine

### 8.1 Input

```
InputState {
  lang, contextIdents (≤ 2, or <s>),
  taps: [Tap { char, point: (x, y)? in key units }],
  literal, fieldTraits (keyboardType, autocorrectionType, autocapitalizationType, textContentType),
  shiftState
}
```

- Taps without points (resync from context, alternates, programmatic input) are exact characters with no spatial slack.
- Taps whose character normalizes to nothing (an apostrophe in EN) are skipped at zero cost.
- An explicitly typed non-normalized character (for example أ from a long-press) gives +0.5 to variants that contain it.

### 8.2 Candidate generation (beam search)

Search runs over the base trie and a small in-memory personal trie. A search state is `(node, i taps consumed, edits, cost)`. Transitions for tap i:

| Transition | Rule | Cost |
|---|---|---|
| **Match** | Child letter x whose key center is within R = 1.5 key units of the tap point | `(dx² + dy²) / (2σ²)`, with σx = σy = 0.45. Point-less taps allow the exact char only, at cost 0. |
| **Insertion** (extra tap) | i + 1, same node | 5.0 |
| **Omission** (missed letter) | Child x, same i | 3.0; 1.5 if x repeats the previous letter (doubled letters); 1.2 for ء |
| **Transposition** | Taps i and i+1 match x and y in swapped order | 2.0 |
| **Far substitution** | Key outside R | 5.0 |

- **Limits:** at most 2 edits, or 1 if the literal is ≤ 4 characters. No far substitutions if the literal is ≤ 3 characters.
- **Beam:** 64 states per i; dedupe on `(node, i)`, keeping the lowest cost.
- **End states** (i = n):
  - A terminal node gives a full-word candidate.
  - Plus up to 8 best-first completions (via max-subtree score), each with a 1.0 completion penalty.
- Each matched key expands to its variants (surface + base word id).
- **Personal trie:** built at launch from PersonalStore and updated each time the learner writes its batch (at most every 5 s, and on dismiss). Capped at 30k known words, with LRU eviction by decayed count.
- The **literal is always a candidate**, with cost 0. Its LM score is its own if it's known; otherwise `unknownLogProb`: −21 for EN, −15.5 for AR (Arabic unknowns are often real dialect words).
- An **invalid base variant** scores as unknown and is never offered as a candidate or prediction, except as the literal or when Moe knows it.
- Constants in this section were tuned in Phase 3b (`docs/eval-log.md`).

### 8.3 Scoring

```
score(c) = log P_LM(c | ctx) − α·spatial − editCost − completionPenalty + boosts      (α = 1.0)

P(w | a,b) = λ3·Pu(w|a,b) + λ2·[ μb·Pu(w|b) + (1−μb)·PB(w|b) ] + λ1·[ ν·Pu(w) + (1−ν)·PB(w) ]
  Pu = personal (decayed counts), PB = base
  μb = Cu(b,·) / (Cu(b,·) + 3)        personal context evidence
  ν  = Nu / (Nu + 2000)               personal corpus size
  λ3 = 0.5 if Cu(a,b,·) > 0 else 0; the remaining mass is split λ2:λ1 = 0.7:0.3
  P = 0 → unknownLogProb
```

- **Boosts:** a known manual-correction pair (literal → c in the `corrections` table) gives +3.0.
- Blocked words are removed entirely.
- All constants live in `EngineConfig` (one file) and can be overridden by CLI flags for tuning.

### 8.4 Decay

- Every personal count c is stored with a timestamp `t_last`.
- The effective count is `c · 2^(−(now − t_last) / H)`, with H = 60 days.
- On increment: `c ← c(now) + 1` and `t_last ← now`.
- Context totals and Nu decay the same way.

### 8.5 Autocorrect (on commit: space, punctuation or return)

Replace the literal ℓ with the top candidate c* only if all of the following hold:

1. Autocorrect is on for this language, `autocorrectionType != .no`, `keyboardType` is not `.URL` or `.emailAddress`, and `textContentType` is not `.password` or `.oneTimeCode`.
2. ℓ is not known: it's neither a `valid` base variant nor a `known` personal word.
   - In AR, a known word plus one clitic counts as known too (Egyptian forms the MSA base lacks). Prefixes: و ف ب ل ك ه ح ال لل. Suffixes: ه ها هم ك كم ني نا ي. The stem has at least 2 letters.
3. ℓ is not a special token and contains no digits. In EN, it has no capital after its first letter (OMG, LLMs, iOS).
4. There is no recorded rejection of (ℓ → c*).
5. `score(c*) − score(ℓ) ≥ θ`, where θ is 2.5 for "normal" and 4.0 for "gentle". Also, c*'s softmax share among the candidates must be ≥ 0.5.
   - Defaults: EN normal, AR gentle (dialect words are often missing from the base data).
6. c* fixes a slip, not a different word:
   - as a completion, it adds at most 1 letter past the taps (goin → going, never tomo → tomorrow);
   - in gentle mode, its edit cost (the spatial part aside) is at most 3.0: one omission or swap, no extra tap and no far key.

**Variant fix** (an exception to rule 2) applies when all of these hold:

- ℓ and c* share a normalized key.
- ℓ is a lazy spelling: it holds no character that normalization drops or maps (an apostrophe, a hamza). Moe typed those on purpose.
- The setting allows it (EN contractions on; AR variants off by default).
- `P_LM(c*|ctx) ≥ 5 · P_LM(ℓ|ctx)`.
- Moe hasn't kept ℓ 2 or more times.

**Undo**

- If the very next key is backspace (cursor unchanged), restore ℓ and drop the auto-space, all in **one** backspace.
- Record the rejection (ℓ → c*) and mark ℓ as explicitly accepted (known).

**Timing**

- On commit, if the latest result isn't for the current generation, the main thread may wait up to 20 ms for it.
- If it still isn't ready, skip the autocorrect. This is the only place where the main thread waits on the engine.

### 8.6 Predictions and casing

- **Empty current word:** show the top 3 next words, drawn from personal trigrams and bigrams, base bigrams and unigram backoff. Exclude a repeat of the previous word and `<s>`.
- After `. ! ? ؟`, a newline or an empty field, the context is `<s>`. First-word-of-message predictions are personal and valuable.
- **Auto-shift (EN):** at the start of the field, after a sentence end + space, and after a newline, when `autocapitalizationType` allows it.
- **Display casing** follows 6.3. When shift is active, capitalize the first letter of every suggestion.

### 8.7 Punctuation spacing

- An auto-space (inserted after a suggestion tap or an autocorrect) is marked as auto.
- If the next character is one of `. , ! ? ; ، ؛ ؟`, delete the auto-space, insert the punctuation, then insert a space.
- For `: ' " )`, delete the auto-space and insert only the character.

## 9. Personal learning

### 9.1 Store (SQLite, App Group, WAL, `busy_timeout` 200 ms, versioned migrations)

```
words(lang, ident, norm, display, display_votes, count, t_last, state[pending|known|blocked],
      sessions_seen, last_session, uses, imports, source[typed|import|lexicon|manual], accepted_explicitly)
ngrams(lang, w1, w2, w3, count, t_last)        -- w1 = '' for bigrams; '<s>' allowed
corrections(lang, typed, chosen, rejected, count, t_last)
meta(key, value)                                -- stats; the schema version is PRAGMA user_version
```

Add indexes that match the query patterns. Writes from both the keyboard and the host app go through the same `PersonalStore` code.

- `uses` and `imports` are raw (undecayed) counts for the pending → known rules, because a decayed count of 2 is already below 2.
- `display_votes` runs a weighted majority vote over display forms. Sentence-initial capitals don't vote.
- There is no `ctx_totals` table. Context totals are the sums of the loaded continuations, which decay the same way.

### 9.2 Learning rules

- **Commit events:** typed + space/punctuation, suggestion tap, autocorrect, revert, manual correction.
- **Commit buffer:**
  - An event becomes final when another word is committed after it, or at sentence end, or when the keyboard is dismissed.
  - Backspacing into a pending word drops its event.
  - Final events are written in one short transaction, at least every 5 s and on dismiss.
- **pending → known** when any of these holds:
  - count ≥ 2 across ≥ 2 different keyboard sessions;
  - an explicit accept (tapping the literal, or reverting an autocorrect);
  - an import count ≥ 2;
  - a manual add.
- **Manual-correction learning:** if Moe deletes a committed word D and commits W at the same position within 10 s, with edit distance(D, W) ≤ 2 and D ≠ W, then `corrections(D → W) += 1`.
- **Where not to learn:** `.URL` fields, password and oneTimeCode content types, or when "Pause learning" is on.
- **Special tokens** (emails, handles) are learned as lang `tok`. They're suggested by prefix and never autocorrected.
- **UILexicon:** on the first keyboard launch and then weekly, call `requestSupplementaryLexicon` and add its entries (contact names, text replacements) as known words with source `lexicon`.

### 9.3 WhatsApp import

The parser lives in KalamEngine, so the CLI can test it.

- **Input:** `_chat.txt`. Moe extracts the zip in the Files app first, so no zip dependency is needed.
- **Formats:**
  - iOS: `[dd/mm/yy, hh:mm:ss] Name: text`
  - Android: `dd/mm/yyyy, hh:mm - Name: text`
  - Both have multiline continuations.
- **Cleanup:** strip U+200E and U+200F. Skip system lines, `<Media omitted>`, `image omitted`, "This message was deleted" and `<This message was edited>`.
- **Senders:** the UI lists the detected senders, and Moe picks the ones that are him. Only his messages are learned.
- **Learning:**
  - Each message is tokenized and split by script into languages, then fed to the n-gram updates.
  - `t_last` is the message date when it parses; otherwise use now − 30 days.
  - Words with an import count ≥ 2 become known, with two exceptions that stay pending (only the keyboard's typed-use rule can make them known):
    - **Likely typos** (Moe leaves 10 to 20% of typos unfixed): a word that isn't a valid base word, with a neighbour within the search's edit limits that he uses at least 10x as often. Its count goes to `corrections(typo → neighbour)` instead.
    - **Lazy spellings:** a same-key variant of a different valid base word (dont / don't), or an invalid base variant. Otherwise imports would switch off the EN contraction fix (D8) for him.
- A "Paste text to learn" box exists too.
- Fixture tests cover both formats with synthetic chats.

## 10. Host app (SwiftUI)

Screens:

- **Setup:** steps plus a button that opens Settings.
- **Try it:** a text field for testing.
- **Settings.**
- **Learned words:** per language, with search, state and count; swipe to forget or block; add a word manually.
- **Import:** WhatsApp or pasted text.
- **Data:** stats, export a backup (via `VACUUM INTO` + share sheet), restore, and reset learning.

Settings are stored in App Group `UserDefaults`:

| Setting | Default |
|---|---|
| Haptics | on |
| Haptic strength | 0.7 |
| Sounds | on |
| Autocorrect EN (off / gentle / normal) | normal |
| Autocorrect AR (off / gentle / normal) | gentle |
| Auto-capitalize | on |
| Double-space period | on |
| EN contraction fix | on |
| AR variant fix | off |
| Eastern Arabic digits | off |
| Top-row digit hints | on |
| Pause learning | off |
| Debug overlay (Debug builds only) | off |

## 11. Performance and memory budgets

- **Keystroke:** `insertText` runs synchronously, with no engine work, in < 2 ms on the main thread.
- **Suggestions:** on the serial queue, p95 ≤ 12 ms and p99 ≤ 20 ms on the device. Measure with `os_signpost` and log p95 per session.
- **Memory:** no fixed MB budget, only the iOS ceiling (§2). Log phys_footprint and the `os_proc_available_memory()` headroom; headroom under 10 MB at peak is a bug to fix, because the kill is silent. Less than 2 MB growth over 20 show/hide cycles across 3 apps (a leak check).
- **Startup:** the keyboard draws immediately and the lexicon is mapped on the engine queue. First suggestions appear ≤ 150 ms after the keyboard appears.
- **Instrumentation:**
  - A footprint probe (`task_info` / `TASK_VM_INFO` → `phys_footprint`, plus `os_proc_available_memory()` headroom) logged via `Logger`.
  - A Debug-only overlay showing MB, headroom and the last suggestion latency, compiled out of Release.
- **Budget guard tests:** the personal trie cap, and an optional allocation count per query.

## 12. Testing and evaluation

- **`swift test`** covers:
  - normalization vectors and the tokenizer;
  - `.klex` round-trip;
  - beam-search cases and scoring;
  - decay math;
  - the commit-buffer state machine;
  - the autocorrect policy as a table of cases;
  - WhatsApp parser fixtures;
  - store migrations.
- **`pytest`** covers the builder: the vectors, the filters and the format writer.
- **`kalam-cli`:**
  - `suggest --lang en --context "see you" --typed "tomorow"` prints ranked candidates with a score breakdown (LM / spatial / edits / boosts).
  - `eval --lang en|ar --heldout <file> [--personal <db>]` simulates typing with Gaussian tap noise (σ = 0.35 key units) on the real layout geometry, plus per-letter omissions (1.5%), extra taps (1.5%) and swaps (0.5%). It reports:
    - autocorrect top-1 accuracy on noisy words;
    - **false-autocorrect rate on clean known words (guard ≤ 0.5%)**;
    - next-word top-3 accuracy;
    - keystroke savings (the simulated user taps the right suggestion as soon as it appears).
  - `eval-personal` trains a personal store on 90% of Moe's own WhatsApp messages and evaluates on the other 10%. It reports the **personalization lift** in top-3 accuracy and keystroke savings versus base-only.
    - Messages are sorted by time; `--fold k` holds out message i when i % 10 == k.
    - **Guard:** the wrong autocorrect changes on Moe's Arabic over all 10 folds, each judged by hand, must not grow.
- **Tuning log:** every tuning change reruns the eval and is logged in `docs/eval-log.md` (date, params, metrics). Guards must never regress.
- **Device checklists:** Claude Code writes a device checklist for every phase that touches the device; Moe runs it.

## 13. Phases

| # | Phase | Output |
|---|---|---|
| 0 | Moe: Xcode setup | targets, App Group, plist keys, screenshots |
| 1 | Keyboard shell | Apple-feel keyboard, EN + AR, no suggestions |
| 2 | Engine core | normalization, tokenizer, `.klex` (fixture), beam search, scoring, CLI |
| 3 | Real lexicons + eval | `en.klex`, `ar.klex`, eval harness, baseline |
| 4 | Personal learning | store, decay, commit buffer, corrections, WhatsApp parser |
| 5 | Integration | live suggestions, autocorrect + undo, predictions, learning |
| 6 | Host app | settings, learned words, import, backup |
| 7 | Tuning + hardening | issue-driven fixes, device memory/latency, haptics experiment |

**Gate for every phase:** tests are green, the acceptance list is met, Moe confirms the device checklist, and the work is committed.

## 14. Later (not v1)

- A clipboard chip in the bar (the last copied text; needs Full Access).
- Emoji suggestions.
- An Arabic tashkeel key.
- A number-row option.
- iPad layout.
- Swipe typing (excluded by Moe's choice).

## 15. Inputs Moe provides

- **`docs/reference/` screenshots** (same iPhone, portrait, light and dark):
  - Apple EN letters, shifted, 123 and #+=.
  - AR letters, 123 and #+=.
  - Long-press popups for ا ي و ه and 2 or 3 English accents.
  - The suggestion bar.
- **Leipzig tarballs** (Phase 3).
- **WhatsApp `_chat.txt` exports** (Phase 4 for tests and eval, and Phase 6 for real import).
