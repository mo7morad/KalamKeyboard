# Eval log

Every tuning change gets a logged run (CLAUDE.md rule 10). Guards: false autocorrect on clean known words ≤ 0.5%, and no metric regresses.

```bash
cd Packages/KalamEngine && swift build -c release
K=.build/release/kalam-cli; R=../../KeyboardExtension/Resources; H=../../Tools/data/heldout
$K eval --lang en --klex $R/en.klex --heldout $H/en.txt          # defaults: --limit 500 --seed 1
$K eval --lang ar --klex $R/ar.klex --heldout $H/ar.txt
$K eval-personal --chat <_chat.txt>... --sender "Mohamed Morad" --klex-en $R/en.klex --klex-ar $R/ar.klex
```

- **eval:** 500 seeded-random held-out Leipzig sentences per language (EN 9,645 words, AR 10,082 words at seed 1). Each tap is a Gaussian draw (σ = 0.35 key units) around its key center on the en-letters / ar-letters page; the tap types the char key whose hit rect is nearest.
  - Autocorrect top-1: over valid base words whose noisy literal came out wrong, the share committed (space) as the right word. The "ranked first" share is a diagnostic.
  - False autocorrect: valid base words tapped at key centers that the commit changes.
  - Next-word top-3 and keystroke savings use the simulated typist (taps a top-3 suggestion as soon as it is the target).
  - Latency: wall time per `candidates` and `predict` request, release build, Apple-silicon Mac. The device budget is p95 ≤ 12 ms, and the device is 2 to 3x slower.
  - `--bias-x` / `--bias-y` (Phase 12) shift every noisy tap by a fixed amount before the key under it is chosen; the default is no bias.
  - Up to Phase 3b the noise was substitutions only. Since Phase 3c, each letter also has a 1.5% omission, a 1.5% extra tap after it (half a doubled tap, half a neighbouring key within 1.2 key units), and a 0.5% swap with the next letter. One-letter words get no omission. Results before and after this change don't compare.
- **eval-personal:** Moe's 3 chats, 3,759 of his messages, sorted by time, then text. `--fold k` holds out message i when i % 10 == k. Up to Phase 3b, every 10th message in file order was held out (375 messages: EN 87 words, AR 1,320 words). "AC changes" is the share of held-out words, typed at key centers, that the commit changes. Moe leaves typos, so some changes are right.
  - **Moe AR R / W** (a guard since Phase 3c): the AR changes in the personal setup over all 10 folds (14,005 words), each judged right or wrong by hand. The judgements live outside the repo, because they quote Moe's text.

Columns: AC = autocorrect top-1 on noisy words, FA = false autocorrect on clean words, NW = next-word top-3, KS = keystroke savings, p50/p95/p99 = candidates latency in ms.

## 2026-11-04 · Phase 3b baseline and first tuning pass

git: `1548350` plus the Phase 3b working tree. klex sha256:
- AR `d729d2df97f37aacc4b9b7fc85fb759d8cf222e13761d29c5ffff1f0791e767e`, used for every run.
- EN `bd483c2c867b59d4293a712d28066b900ef81f894ff3517898332d9673ce6f32` before the casing rebuild.
- EN `b98ee2a1ce04961b578d85667eb171352b4c55f9e32c79b4e15efb844205ed42` after it (`CASING_MIN_SHARE = 0.9`); only the final run uses it.

### Baseline (SPEC defaults)

The beam search breaks cost ties by node id here. Before, ties followed Swift's per-process hash seed, and repeated runs differed by about 0.2 pp.

| Lang | AC | ranked 1st | FA | NW | KS | p50 / p95 / p99 | predict p95 |
|---|---|---|---|---|---|---|---|
| EN | 27.3% | 64.6% | 0.05% (5 / 9,492) | 22.5% | 35.0% | 0.27 / 1.72 / 1.92 | 0.11 |
| AR | 26.7% | 58.5% | 0.00% (0 / 9,775) | 19.8% | 25.7% | 0.34 / 2.99 / 3.43 | 0.12 |

Seed 2: EN AC 28.5%, NW 22.6%, KS 34.5%; AR AC 27.4%, NW 20.5%, KS 26.5%. Seed noise is about 1 pp.

eval-personal baseline, as measured by the orchestrator (real lexicons, 375 held-out messages):

| Lang | Setup | NW | KS |
|---|---|---|---|
| EN | base | 18.3% | 36.5% |
| EN | personal | 20.0% | 40.0% |
| AR | base | 2.3% | 9.5% |
| AR | personal | 15.3% | 25.9% |

The same command rerun deterministically on this tree (chats in glob order) gives:

| Lang | Setup | NW | KS | AC changes |
|---|---|---|---|---|
| EN | base | 10.3% | 23.1% | 1.1% |
| EN | personal | 14.9% | 28.1% | 1.1% |
| AR | base | 2.3% | 7.8% | 0.2% |
| AR | personal | 15.2% | 24.3% | 0.8% |

### Runs, in order

Code changes are marked [code]. The other rows are `--set` values on top of the last kept or candidate row.

| Run | EN AC / FA / KS | AR AC / FA / KS | Moe AR personal KS / changes | Verdict |
|---|---|---|---|---|
| [code] invalid base variants: unknown LM as the literal, never a non-literal candidate or prediction (SPEC 8.5 rule 2) | 27.3 / 0.05 / 34.9 | 26.7 / 0.00 / 25.7 | 24.3 / 0.8 | kept (correctness) |
| unknownLogProb −16 | 38.2 / 0.05 / 35.4 | 32.1 / 0.00 / 26.0 | 24.3 / 1.6 | AR changes ↑ |
| unknownLogProb −18 | 49.6 / 0.05 / 35.7 | 41.3 / 0.00 / 26.2 | 24.3 / 2.7 | AR changes ↑ (dialect words wrongly changed) |
| insertionCost 4 | 28.2 / 0.07 / 37.4 | 27.0 / 0.00 / 27.7 | 25.5 / 0.8 | see next |
| insertionCost 5 | 28.4 / 0.07 / 37.8 | 27.0 / 0.00 / 28.0 | 25.9 / 0.6 | kept |
| insertionCost 6 | 28.4 / 0.07 / 37.9 | 27.0 / 0.00 / 28.1 | n/a | no gain over 5 |
| [code] variant fix only for lazy spellings: never when the literal holds a char normalization drops or maps (all 7 EN false fixes were week's → weeks, We're → were) | 28.4 / 0.01 / 37.8 | 27.0 / 0.00 / 28.0 | 25.9 / 0.6 | kept |
| validLiteralBonus 1 / 2 / 3 (new lever) | KS 37.7 / 37.6 / 37.3 | KS 27.9 / 27.8 / 27.7 | 25.8 / 25.6 / 25.4 | rejected: KS ↓; lever removed |
| completionPenalty 0.5 | 28.0 / 0.01 / 38.3 | 26.8 / 0.00 / 28.7 | 26.3 / 0.6 | rejected: AC ↓ |
| bigramShare 0.8 | 26.8 / 0.02 / 37.8 | 26.5 / 0.00 / 28.0 | 25.9 / 0.5 | rejected: AC ↓ |
| unknownLogProb −18, gentle θ 8 | 52.7 / 0.01 / 38.7 | 27.0 / 0.00 / 28.6 | 25.9 / 0.6 | candidate |
| + sigma 0.45 | 43.9 / 0.01 / 39.1 | 23.8 / 0.00 / 29.4 | 27.1 / 0.4 | AC ↓ |
| + sigma 0.5 | 49.1 / 0.01 / 39.0 | 25.9 / 0.00 / 29.1 | 26.6 / 0.5 | AC ↓ |
| sigma 0.45, unknownLogProb −21, gentle θ 11 | 58.0 / 0.01 / 39.4 | 23.8 / 0.00 / 29.7 | 27.2 / 0.4 | AR AC ↓ |
| sigma 0.5, unknownLogProb −20, gentle θ 10 | 58.4 / 0.01 / 39.2 | 25.9 / 0.00 / 29.3 | 26.6 / 0.5 | AR AC ↓ |
| sigma 0.45, unknownLogProb −21, gentle θ 9.5 | = above | 27.7 / n/a / 29.7 | 27.2 / 0.8 | passes, but θ 9.5 also blocks the AR variant fix (انا → أنا) when Moe turns it on |
| [code] per-language unknown prior: unknownLogProbEN −21, unknownLogProbAR −16.5, gentle θ back to 4.0 | 58.0 / 0.01 / 39.4 | 31.2 / n/a / 29.3 | 27.1 / 1.0 | AR changes ↑ |
| unknownLogProbAR −16 / −15 | | 29.1 / 26.3 (AC) | 27.0 / 0.9, 27.0 / 0.8 | |
| unknownLogProbAR −15.5 | | 27.7 / n/a / 29.0 | 27.0 / 0.8 | **kept** |
| [code] EN casing: store a casing only when it holds ≥ 90% of the word's non-initial forms (I-forms still forced); en.klex rebuilt | final row | | | kept (ok, covid, turkey now lowercase) |

X = 0.9 was picked by inspection, because casing doesn't move any eval metric. Corpus shares: OK 0.68, Turkey 0.58, COVID 0.52. Between 0.6 and 0.9 the corpus is mostly news title case on common nouns (Street, King, University, Queen). Above 0.9 it is mostly proper nouns (March 0.93, Google 0.96, NASA 0.97). Apple (0.89) drops to lowercase.

### Tuned (new EngineConfig defaults)

sigma 0.45 (SPEC 0.55), insertionCost 5 (SPEC 3), unknownLogProbEN −21 and unknownLogProbAR −15.5 (SPEC −14). All other values are as in SPEC.

| Lang | AC | ranked 1st | FA | NW | KS | p50 / p95 / p99 | predict p95 |
|---|---|---|---|---|---|---|---|
| EN | 58.0% | 88.5% | 0.01% (1 / 9,492) | 22.5% | 39.4% | 0.24 / 1.46 / 1.62 | 0.11 |
| AR | 27.7% | 62.8% | 0.00% (0 / 9,775) | 19.8% | 29.0% | 0.30 / 2.59 / 3.04 | 0.11 |

Seed 2: EN AC 58.5%, FA 0.02%, NW 22.6%, KS 39.3%; AR AC 28.4%, FA 0.00%, NW 20.5%, KS 29.7%.

eval-personal, tuned:

| Lang | Setup | NW | KS | AC changes |
|---|---|---|---|---|
| EN | base | 10.3% | 27.5% | 4.6% |
| EN | personal | 14.9% | 32.2% | 3.4% |
| AR | base | 2.3% | 11.1% | 0.3% |
| AR | personal | 15.2% | 27.0% | 0.8% |

The EN changes are 3 or 4 of 87 words: 3 are right (guidence, syndrom, Securtiy), and 1 is wrong in base-only (LLMs → looks). Of the 11 AR personal changes, 4 are right and 7 are wrong (dialect clitic forms and completions). Candidates p95 stays under 4 ms on this Mac, so the completion frontier keeps its linear scan.

## 2026-11-04 · Phase 3c: noisier eval, 10 folds, safer Arabic autocorrect

git: `99da801` plus the Phase 3c working tree. klex sha256: EN `b98ee2a1…05ed42`, AR `d729d2df…e767e` (as in 3b). Eval at seed 1, with the new noise for every row. Moe = eval-personal over the 10 folds, personal setup (EN 834 words, AR 14,005 words).

A wrong change costs Moe more than a missed fix: he has to notice it and undo it, and he already leaves 10 to 20% of his typos. So a rule that trades a few right changes for many fewer wrong ones is kept.

One judgement call: بصديقتي → يصديقتي (11 of the changes in the rows before the clitic rule, which keeps it as ب + صديقتي) is counted as right. The importer already flagged بصديقتي as a likely typo (Moe typed يصديقتي at least 10x as often), and he slips ب for ي elsewhere (يحبيبتب, بعمب).

| Run | EN AC / FA / KS | AR AC / FA / KS | Moe EN KS | Moe AR KS | Moe AR R / W | Verdict |
|---|---|---|---|---|---|---|
| 3b config on the new noise | 51.3 / 0.01 / 38.2 | 24.2 / 0.00 / 28.2 | 38.7 | 27.0 | 55 / 49 | baseline |
| insertionCost 3 | 48.4 / 0.01 / 34.5 | 24.6 / 0.00 / 25.1 | 36.4 | 25.2 | n/a (181 changes) | rejected |
| insertionCost 4 | 51.1 / 0.01 / 37.6 | 24.7 / 0.00 / 27.5 | 38.0 | 26.5 | n/a (118 changes) | rejected: 5 stays |
| omissionCost 2.5 | 51.1 / 0.01 / 38.2 | 24.0 / 0.00 / 28.2 | 38.5 | 27.0 | 55 / 48 | rejected |
| omissionCost 4 | 51.2 / 0.01 / 38.2 | 24.2 / 0.00 / 28.0 | 39.0 | 27.0 | 53 / 48 | rejected |
| transpositionCost 1.5 | 51.1 / 0.01 / 38.0 | 24.1 / 0.00 / 27.9 | 38.6 | 26.8 | 55 / 50 | rejected |
| transpositionCost 3 | 51.7 / 0.01 / 38.4 | 24.3 / 0.00 / 28.5 | 38.8 | 27.1 | 55 / 47 | gain within seed noise; dropped at the end: an imported swap typo (tamma → tamam, WhatsAppParserTests) stops being fixed |
| transpositionCost 4 | 51.4 / 0.01 / 38.5 | 24.2 / 0.00 / 28.5 | 38.8 | 27.1 | 54 / 47 | no better than 3 |
| sigma 0.4 (tr 3) | 46.3 / 0.01 / 38.2 | 21.6 / 0.00 / 28.6 | 39.3 | 27.6 | 47 / 42 | rejected: AC ↓ |
| sigma 0.5 (tr 3) | 55.0 / 0.01 / 38.3 | 26.0 / 0.00 / 28.1 | 37.8 | 26.5 | 55 / 47 | rejected: AR KS ↓; sigma stays 0.45 |
| [code] gentle: c* within 1 edit (edit distance on keys, a swap is 1) (tr 3) | 51.7 / 0.01 / 38.4 | 12.5 / 0.00 / 28.5 | 38.8 | 27.1 | 54 / 33 | replaced: two neighbour-key slips count as two edits, so AR AC halves |
| [code] + completion adds at most 1 letter past the taps (`autocorrectMaxAddedLetters` 1) | 51.7 / 0.01 / 38.4 | 12.5 / 0.00 / 28.5 | 38.8 | 27.1 | 54 / 33 | kept |
| [code] gentle: c*'s edit cost (not spatial) ≤ `gentleMaxEditCost` 3.0, i.e. one omission or swap, no extra tap or far key | 51.7 / 0.01 / 38.4 | 23.7 / 0.00 / 28.5 | 38.8 | 27.1 | 52 / 19 | kept, replaces the edit-distance rule |
| gentleMaxEditCost 2.9 (doubled or hamza omissions only) | 51.7 / 0.01 / 38.4 | 22.6 / 0.00 / 28.5 | 38.8 | 27.1 | 45 / 13 | rejected: blocks real one-letter omissions |
| gentleMaxEditCost 5 | 51.7 / 0.01 / 38.4 | 24.3 / 0.00 / 28.5 | 38.8 | 27.1 | 55 / 41 | rejected |
| [code] AR rule 2: a known word plus one clitic counts as valid (prefixes و ف ب ل ك ه ح ال, suffixes ه ها هم ك كم ني نا ي; stem ≥ 2 letters, a valid base word or known to Moe) | 51.7 / 0.01 / 38.4 | 21.2 / 0.00 / 28.5 | 38.8 | 27.1 | 33 / 5 | kept |
| unknownLogProbAR −14 | 51.7 / 0.01 / 38.4 | 18.1 / 0.00 / 28.2 | 38.8 | 27.0 | 22 / 3 | rejected: −11 right for −2 wrong |
| unknownLogProbAR −17 | 51.7 / 0.01 / 38.4 | 25.6 / 0.00 / 28.8 | 38.8 | 27.1 | 38 / 15 | rejected: +5 right for +10 wrong; −15.5 stays |
| [code] EN rule 3: no autocorrect when a capital follows the first letter (LLMs, iOS, PhD; covers all caps) | in the final row | | | | | kept |
| [code] prefix لل (ل + ال, which drops its alif), orchestrator review | = | 21.0 / 0.00 / 28.2 | 38.7 | 27.0 | 33 / 4 | kept: only للرجالة → الرجالة goes |
| **Final** (transpositionCost 2) | 51.3 / 0.01 / 38.2 | 21.0 / 0.00 / 28.2 | 38.7 | 27.0 | **33 / 4** | |

Final latency (candidates p50 / p95 / p99): EN 0.25 / 1.51 / 1.66 ms, AR 0.32 / 2.69 / 3.14 ms. Predict p95 is 0.11 to 0.12 ms.

Final eval-personal over the 10 folds:

| Lang | Setup | NW | KS | AC changes |
|---|---|---|---|---|
| EN | personal | 20.2% | 38.7% | 1.44% |
| AR | personal | 15.0% | 27.0% | 0.26% (33 right, 4 wrong) |

Synthetic AR AC fell from 24.2% to 21.0%, a cost accepted because that set is MSA news. The 4 remaining wrong AR changes are dialect spellings: يخوي → يخويا (twice), بتلظبط → بالظبط and مؤاخدة → مؤاخذة.

## 2026-11-04 · Device round 2: bolder normal autocorrect

git: `7ab5acd` plus the working tree. klex as in 3c. Moe sets both languages to normal and reports that autocorrect "doesn't auto work" (1 change in ~84 commits on device). New CLI flags: `--autocorrect off|gentle|normal` on `eval`, `eval-personal` and `suggest` (both languages), and `--chat` / `--sender` on `suggest`, which imports the chats into a temp store first (as the host app does) and prints what a space commits.

Moe columns are eval-personal over the 10 folds, personal setup, AR 14,005 words, judged by hand again (the 3c judgements are not in the repo). Re-judged, the 3c gentle config is 32 / 5 rather than 33 / 4. Synthetic AR is given in both modes, because Moe uses normal and the default is gentle.

What the shipped normal did: 41 right and 38 wrong on Moe's chats. So it wasn't too timid, it was wrong half the time. The wrong ones were mostly dialect words outside the base and unknown to Moe's store: clitic forms the rule-2 list lacked (قولتلي, مخلصش, يماما, معملش) and fixes that need an extra tap, a far key or a swap (يسطا → يسط, خوفت → شوفت, عمالين → عاملين).

| Run | EN AC / FA / KS | AR gentle AC / FA / KS | AR normal AC | Moe AR gentle R / W | Moe AR normal R / W | Verdict |
|---|---|---|---|---|---|---|
| 3c final (θ normal 2.5) | 51.3 / 0.01 / 38.2 | 21.0 / 0.00 / 28.2 | 26.3 | 32 / 5 | 41 / 38 | baseline |
| [code] rule 2 clitics: prefix ي (fused يا), suffixes ش لي له لك لها لهم لنا وا, negation م…ش | = | 20.8 / 0.00 / 28.2 | 26.1 | 28 / 3 | 37 / 19 | kept with the next row |
| [code] م…ش only for words of 5+ letters (مقيش and محاش are typos) | = | 20.8 / 0.00 / 28.2 | 26.1 | 30 / 3 | 39 / 19 | kept |
| [code] normal adds c*'s edit cost to θ (both langs), θ 2.5 | 49.4 / 0.01 / 38.2 | = | 24.9 | 30 / 3 | 36 / 7 | candidate |
| same, θ 1.0 | 53.6 / 0.02 / 38.2 | = | 30.7 | 30 / 3 | 39 / 12 | AR kept; EN loses guidence and iterational (a far key, two omissions) |
| [code] edit cost only in AR; θ normal 1.0 for both | **55.5 / 0.02 / 38.2** | **20.8 / 0.00 / 28.2** | **30.7** | **30 / 3** | **39 / 12** | **kept** |
| + knownMinImports 3 | = | | | | 37 / 8 (KS 26.3) | rejected: fewer right changes, KS ↓ |
| + typoNeighbourRatio 5 | = | | | | 39 / 12 | no change |

Offline sweep on the dumped candidate facts (126 AR changes that some policy could make, all judged by hand), at most one wrong change per three right ones. Rule 5 alone at θ 4 / 3 / 2.5 gives 33 / 8, 37 / 14 and 39 / 19, so no threshold alone reaches 3:1 with clearly more right changes than gentle (30 / 3). With the edit cost counted twice, θ 2 / 1.5 / 1 / 0.5 / 0 gives 38 / 8, 38 / 9, 39 / 12, 39 / 15 and 40 / 16. θ 1 is the boldest point that keeps 3:1. Lowering unknownLogProbAR by 2 adds only 3 more changes under this rule, so it stays at -15.5.

Rule 2 known words (cause 2): over the 10 folds, a known literal that isn't a valid base word has a non-literal top candidate only 7 times, and none of them is a typo (اشطا ↔ اشط). Imported typos already go through `markLikelyTypos`. A stricter known rule has nothing to fix here, so none was added.

eval-personal, final:

| Lang | Setup | Mode | KS | AC changes |
|---|---|---|---|---|
| EN | personal | normal | 38.7% | 1.69% (14; was 12: + mediocres → mediocre, + Yaaay → that) |
| AR | personal | normal | 27.0% | 0.36% (39 right, 12 wrong; was 0.57%, 41 / 38) |
| AR | personal | gentle | 27.0% | 0.24% (30 right, 3 wrong; was 32 / 5) |

Normal versus 3c: 4 right changes are lost (محاش and يحبيتي now read as clitic forms; اشطات and يكعلمي need an extra tap) and 2 are gained (مايون → مليون, الحنسية → الجنسية). 27 wrong changes are gone. The 12 that remain: عمالين → عاملين (twice), بتلظبط → بالظبط, اسطا → اشطا, وعنلت → وعملتي, مؤاخدة → مؤاخذة, تظبط → اظبط, جيبت → حسيت, بيسهلك → ييسرلك, اتوضى → اتوضيت, احصا → تحيا, العرص → العصر. Gentle loses محاش → محدش and يحبيتي → يحبيبتي (right) and يخوي → يخويا twice (wrong). This eval taps key centers, so a neighbour slip costs 2.47. A real slip lands near the key edge and costs less, so on device the slip fixes clear θ 1 by a wider margin (device-only, unverified). Latency was measured with 3 evals in parallel (EN 0.26 / 1.62 / 1.98, AR 0.34 / 2.86 / 3.57 ms), so it is not comparable with 3c. The rules add no search work.

Moe's device examples (`suggest --chat` with the 3 chats, normal, key-center taps):
- دلوثا → دلوقت (one far slip, margin 3.4) and نشتغ → نشتغل (completion of one letter, margin 4.6) are fixed.
- عانلة stays as typed, which is right: on device, عائلة ranks first by 0.99 with a 0.38 share, and fixing it would give the wrong word. With no context, the CLI fixes it to عاملة.
- دولوثت (an extra tap plus a slip, margin 0.8) and عليهاه (an extra tap, margin 1.9, and it also reads as عليها + ه) stay as typed. In Moe's chats, extra-tap fixes at such margins are mostly real words (بعتتلي, اتطمنت, عاوزينا).
- تينيتنن has no candidate within the edit limits. الاخيار is the valid word الأخيار (rule 2).

## 2026-11-04 · Phase 11: autocorrect you can trust (proxy lexicons)

Proxy lexicons, not comparable with earlier rows: the real klex can't be built in this session, so `/proxy/en.klex` and `/proxy/ar.klex` hold the same wordfreq 3.1.1 unigrams, EN bigrams and held-out sentences from the Brown corpus, and AR pseudo-sentences sampled from wordfreq's Arabic unigrams (AR NW and KS mean nothing here; AR AC and FA do). git: `0ac0d27` plus the Phase 11 working tree. klex sha256: EN `4dc43a49ae710a53d47366ba361222c67ca27a834242dd8ffecb4d04d44bad86`, AR `5e3e099b9be89b65d80ef65127487a53afc064061826d5c5bfe065fa46f768d7`. Seed 1, 500 sentences.

```bash
K=.build/release/kalam-cli
$K eval --lang en --klex /proxy/en.klex --heldout /proxy/heldout/en.txt [--set autocorrectShortWordMargin=M]
$K eval --lang ar --klex /proxy/ar.klex --heldout /proxy/heldout/ar.txt --autocorrect normal|gentle [--set autocorrectShortWordMargin=M]
```

| Run | EN AC / FA / NW / KS | AR normal AC / FA | AR gentle AC / FA | Verdict |
|---|---|---|---|---|
| baseline `0ac0d27` | 52.4 / 0.00 / 23.2 / 37.4 | 22.9 / 0.00 | 7.4 / 0.00 | |
| Phase 11 rules, short-word margin 0 | 48.1 / 0.00 / 23.2 / 37.4 | 22.9 / 0.00 | 7.4 / 0.00 | EN cost is the mid-sentence capitals rule alone (see below) |
| margin 0.5 | 48.1 / 0.00 | 22.9 / 0.00 | 7.0 / 0.00 | |
| **margin 1.0** | **48.1 / 0.00 / 23.2 / 37.4** | **22.8 / 0.00** | **6.7 / 0.00** | **kept** (no EN cost) |
| margin 2.0 | 48.1 / 0.00 | 22.7 / 0.00 | 5.6 / 0.00 | |

- The short-word margin costs no EN AC at any value tried, so it stays at 1.0 as planned. Its cost is AR gentle 0.7 pp (7.4 to 6.7) and AR normal 0.1 pp. The proxy's FA is 0 throughout, so it can't show what the margin buys; on device it should stop 1 to 3 letter slips into other short words (Moe's Franco and dialect fragments).
- The mid-sentence capitals rule (a capital literal outside a sentence start is never corrected, the variant fix aside) costs 4.3 pp of EN AC on the proxy: with it disabled the run gives 52.4 again. Brown is news text, and 7.4% of its words are capitalized mid-sentence (State, Senate, County, Department, John), which the noisy typist mistypes with shift held. Moe's chats capitalize mid-sentence mostly for names, which is what the rule protects, so the rule is kept as specified. A narrower variant that still corrects when c* itself displays with a capital (a known name, Jphn to John) gives 50.5 on the proxy; it wasn't taken, because it would also turn a friend's name into another name.
- The other rules don't move the proxy: no personal store (rule 2 protection, retype and tap reverts), the eval passes `inToken: false`, Brown has no mixed-script words, and its apostrophes are exact taps, so the ambiguous contractions never come up.
- Predictions: NW and KS are unchanged; the eval has no personal n-grams, which is where pending words were coming from.
- Latency (3 evals in parallel): EN candidates 0.44 / 2.86 / 3.20 ms, AR 0.52 / 4.70 / 5.99 ms, as at baseline. The rule 2 store read happens only for a correction about to happen.

To rerun on the Mac with the real lexicons and Moe's chats (from `Packages/KalamEngine`, defaults are Phase 11's):

```bash
swift build -c release
K=.build/release/kalam-cli; R=../../KeyboardExtension/Resources; H=../../Tools/data/heldout
$K eval --lang en --klex $R/en.klex --heldout $H/en.txt
$K eval --lang ar --klex $R/ar.klex --heldout $H/ar.txt --autocorrect normal
$K eval --lang ar --klex $R/ar.klex --heldout $H/ar.txt --autocorrect gentle
for k in 0 1 2 3 4 5 6 7 8 9; do
  $K eval-personal --chat <_chat.txt>... --sender "Mohamed Morad" --klex-en $R/en.klex --klex-ar $R/ar.klex --fold $k --autocorrect normal
  $K eval-personal --chat <_chat.txt>... --sender "Mohamed Morad" --klex-en $R/en.klex --klex-ar $R/ar.klex --fold $k --autocorrect gentle
done
```

What to expect, and to judge (Moe AR R / W over the 10 folds):
- EN synthetic AC drops (the capitals rule, as above; Leipzig news capitalizes like Brown). FA stays ≤ 0.5%.
- AR synthetic AC drops a little (the short-word margin), FA stays 0.
- eval-personal AR changes should fall a little, mostly through the short-word margin (short dialect words) and mixed-script words. Rule 2's new protection adds little here: a word imported twice was already known, and imports that `markLikelyTypos` or `keepLazySpellingsPending` zero out don't count. It matters for live typing (a word typed twice in one session). Judge every AR change right or wrong as in Device round 2 (normal 39 / 12, gentle 30 / 3); the guard is that the wrong count doesn't grow.
- EN eval-personal changes should fall (capitals, ambiguous contractions, words used twice); next-word top-3 may move slightly, since pending one-off words no longer get predicted.

## 2026-11-04 · Phase 12: touch model (proxy lexicons)

Proxy lexicons, not comparable with earlier rows (the same `/proxy` klex and held-out files as Phase 11, sha256 EN `4dc43a49ae710a53d47366ba361222c67ca27a834242dd8ffecb4d04d44bad86`, AR `5e3e099b9be89b65d80ef65127487a53afc064061826d5c5bfe065fa46f768d7`). git: `b28b295` plus the Phase 12 working tree. Seed 1, 500 sentences. Bias = the eval typist's systematic tap shift (`--bias-y`), offset = the decoder's `tapOffsetY`, both in key units (-0.13 = 7 pt up). No personal store, so the learned per-key offsets and confusion pairs don't take part (unit tests cover them).

```bash
K=.build/release/kalam-cli
$K eval --lang en --klex /proxy/en.klex --heldout /proxy/heldout/en.txt --bias-y B --set tapOffsetY=O
$K eval --lang ar --klex /proxy/ar.klex --heldout /proxy/heldout/ar.txt --autocorrect normal|gentle --bias-y B --set tapOffsetY=O
```

| Run | bias / offset | EN AC / FA / NW / KS | AR normal AC / FA / KS | AR gentle AC / FA |
|---|---|---|---|---|
| baseline `1b74a57` | 0 / none | 48.1 / 0.00 / 23.2 / 37.4 | 22.8 / 0.00 / 21.0 | 6.7 / 0.00 |
| (a) | 0 / 0 | 48.1 / 0.00 / 23.2 / 37.4 | 22.8 / 0.00 / 21.0 | |
| (b) Moe's bias, today's decoder | -0.13 / 0 | 47.0 / 0.00 / 23.2 / 37.2 | 23.2 / 0.00 / 21.0 | 7.0 / 0.00 |
| **(c) Moe's bias, offset** | **-0.13 / -0.13** | **48.3 / 0.00 / 23.2 / 37.4** | **25.2 / 0.00 / 21.1** | **8.0 / 0.00** |
| (d) no bias, offset | 0 / -0.13 | 47.1 / 0.00 / 23.2 / 37.2 | 21.6 / 0.00 / 20.5 | 6.0 / 0.00 |

- (a) reproduces the baseline exactly: the new code paths cost nothing with the offset at 0.
- **Kept tapOffsetY = -0.13** (the default now). Under the measured bias, (c) beats (b) by 1.3 pp EN and 2.0 pp AR normal (1.0 gentle), and gets AC back to the unbiased level or above. If Moe's taps had no bias, the offset would cost about 1 pp of AC (d against a: EN 1.0, AR 1.2, gentle 0.7) and 0.2 to 0.5 pp KS, about seed noise. FA stays 0 everywhere (clean taps at the key centers pay 0.04 per letter for the offset, never enough to flip a commit).
- The limit of this comparison: the eval typist's hit rects tile each row at the key centers, while on the device each row's hit band starts 5 pt (0.09 key units) higher (SPEC 5.2). With bias -0.13 the typist types the row above more often than the device would (EN 6,222 mistyped words against 6,127 unbiased; on the device the raised bands catch most of those taps). So (b) is a little worse than the device is today and the gap from (b) to (c) a little larger than the device will see. What (c) against (b) does show is that the decoder, measuring taps against the shifted centers, ranks the intended word better for the same taps.
- Latency (4 evals in parallel): EN candidates 0.43 / 2.80 / 3.16 ms, AR 0.52 / 4.67 / 5.94 ms, as at baseline. The offsets are applied to the key centers once, when the spatial model is built.

To rerun on the Mac with the real lexicons and Moe's chats (from `Packages/KalamEngine`, defaults are Phase 12's):

```bash
swift build -c release
K=.build/release/kalam-cli; R=../../KeyboardExtension/Resources; H=../../Tools/data/heldout
for b in 0 -0.13; do for o in 0 -0.13; do
  $K eval --lang en --klex $R/en.klex --heldout $H/en.txt --bias-y $b --set tapOffsetY=$o
  $K eval --lang ar --klex $R/ar.klex --heldout $H/ar.txt --autocorrect normal --bias-y $b --set tapOffsetY=$o
done; done
$K eval --lang ar --klex $R/ar.klex --heldout $H/ar.txt --autocorrect gentle --bias-y -0.13
for k in 0 1 2 3 4 5 6 7 8 9; do
  $K eval-personal --chat <_chat.txt>... --sender "Mohamed Morad" --klex-en $R/en.klex --klex-ar $R/ar.klex --fold $k --autocorrect normal
  $K eval-personal --chat <_chat.txt>... --sender "Mohamed Morad" --klex-en $R/en.klex --klex-ar $R/ar.klex --fold $k --autocorrect gentle
done
```

What to expect, and to judge (Moe AR R / W over the 10 folds):
- Synthetic: the same pattern as the proxy, (c) above (b), FA ≤ 0.5%.
- eval-personal types at key centers with no bias, so it sees the (d) cost: AR changes may move slightly. Import typos with a one-letter far substitution seen twice now cost 2.5 instead of 5.0, so a few more of those slips get corrected. Judge every AR change right or wrong as before; the guard is that the wrong count doesn't grow. If it does, rerun with `--set learnedConfusionCost=5` to see which of the two changes it comes from.
- Then `kalam-cli tapmap --lang en --trace <kalam-trace.log>` on a fresh device trace: if its mean dy is far from -0.13 (say beyond -0.08 or -0.18), rerun the synthetic eval with that bias and offset before changing the default.

## 2026-11-04 · Phase 13: Arabic and code-switching (proxy lexicons)

Proxy lexicons, not comparable with earlier rows (the same `/proxy` klex and held-out files as Phase 11 and 12, sha256 EN `4dc43a49ae710a53d47366ba361222c67ca27a834242dd8ffecb4d04d44bad86`, AR `5e3e099b9be89b65d80ef65127487a53afc064061826d5c5bfe065fa46f768d7`). git: `416f71f` plus the Phase 13 working tree. Seed 1, 500 sentences, AR autocorrect normal. Bias = the eval typist's `--bias-y` (-0.13 = Moe-like taps, Phase 12). The one tunable is `sentenceStartBigramShare` (SPEC 8.3): the base bigram's share of λ2 after `<s>`; at 0.7 the LM is exactly today's.

```bash
K=.build/release/kalam-cli
$K eval --lang en --klex /proxy/en.klex --heldout /proxy/heldout/en.txt --bias-y B [--set sentenceStartBigramShare=S]
$K eval --lang ar --klex /proxy/ar.klex --heldout /proxy/heldout/ar.txt --autocorrect normal --bias-y B [--set sentenceStartBigramShare=S]
$K suggest --klex /proxy/en.klex --typed hel [--set sentenceStartBigramShare=S]
```

| Run | EN AC / FA / NW / KS, bias 0 | EN AC / FA / NW / KS, bias -0.13 | AR AC / FA / KS, bias 0 | AR AC / FA / KS, bias -0.13 |
|---|---|---|---|---|
| baseline `416f71f` | 47.1 / 0.00 / 23.2 / 37.2 | 48.3 / 0.00 / 23.2 / 37.4 | 21.6 / 0.00 / 20.5 | 25.2 / 0.00 / 21.1 |
| **share 0.7 (kept)** | **47.1 / 0.00 / 23.2 / 37.2** | **48.3 / 0.00 / 23.2 / 37.4** | **21.6 / 0.00 / 20.5** | **25.2 / 0.00 / 21.1** |
| share 0.5 | 47.1 / 0.00 / 23.1 / 37.1 | 48.4 / 0.00 / 23.1 / 37.4 | 21.8 / 0.00 / 20.5 | 25.4 / 0.00 / 21.1 |
| share 0.3 | 47.1 / 0.00 / 23.1 / 37.1 | 48.4 / 0.00 / 23.1 / 37.4 | 21.9 / 0.00 / 20.5 | 25.6 / 0.00 / 21.2 |
| share 0.1 | 47.1 / 0.00 / 22.9 / 37.1 | 48.4 / 0.00 / 22.9 / 37.3 | 22.0 / 0.00 / 20.5 | 25.7 / 0.00 / 21.2 |
| seed 2, share 0.7 / 0.3 | 47.0 / 23.4 / 36.9 against 47.0 / 23.2 / 36.8 (AC / NW / KS) | 48.4 / 23.4 / 37.3 against 48.4 / 23.2 / 37.2 | | |

- **Kept 0.7:** on the EN proxy (Brown has real sentence starts) no lower share beats it. NW and KS fall 0.1 to 0.3 pp as the share drops (within the 0.5 pp limit, but a loss), and AC moves 0.1 pp with the bias only, which is noise. Seed 2 agrees (0.3 loses 0.2 pp NW). Brown is news like the bigram source, so it favours the news openers this knob would down-weight; Moe's chats may not. The knob stays in `EngineConfig` for the real-lexicon rerun below.
- **AR:** the AR proxy's sentences are random unigram draws, so it can't judge a sentence-start knob. Its AC rises 0.2 to 0.5 pp at lower shares, because the unigram (which the pseudo-sentences are drawn from) gets more weight; that says nothing about real Arabic. The AR effect is unmeasured here.
- **The docs/issues.md example** doesn't reproduce on the proxy: "hel" at `<s>` gives help first at every share (score −9.81 at 0.7, −8.71 at 0.1; hello 7th), and "he" can't come up for "hel" without an extra-tap edit (5.0). The issue is closed as "not fixed by this knob".
- **The rest of Phase 13 doesn't move the eval:** the eval has no personal store and never asks for a wrong-layout rescue or the bar slots, and the learner fix (script, not page) doesn't touch it. The final working tree reproduces the baseline row exactly.
- **Latency** (4 evals in parallel): EN candidates 0.44 / 2.91 / 3.30 ms, AR 0.52 / 4.63 / 5.76 ms, as at baseline. A rescue costs one more search on the other language's engine, only for a 3+ letter non-word with no autocorrect that isn't the start of a word: about one more candidates request (EN 2.9 or AR 4.7 ms p95 here). Not measured by the eval.

To rerun on the Mac with the real lexicons and Moe's chats (from `Packages/KalamEngine`, defaults are Phase 13's):

```bash
swift build -c release
K=.build/release/kalam-cli; R=../../KeyboardExtension/Resources; H=../../Tools/data/heldout
for s in 0.7 0.5 0.3 0.1; do for b in 0 -0.13; do
  $K eval --lang en --klex $R/en.klex --heldout $H/en.txt --bias-y $b --set sentenceStartBigramShare=$s
  $K eval --lang ar --klex $R/ar.klex --heldout $H/ar.txt --autocorrect normal --bias-y $b --set sentenceStartBigramShare=$s
done; done
$K suggest --klex $R/en.klex --typed hel
$K suggest --lang ar --klex $R/ar.klex --typed انا
$K suggest --lang ar --klex $R/ar.klex --typed انا --chat <_chat.txt>... --sender "Mohamed Morad"
for s in 0.7 0.3; do for k in 0 1 2 3 4 5 6 7 8 9; do
  $K eval-personal --chat <_chat.txt>... --sender "Mohamed Morad" --klex-en $R/en.klex --klex-ar $R/ar.klex --fold $k --autocorrect normal --set sentenceStartBigramShare=$s
  $K eval-personal --chat <_chat.txt>... --sender "Mohamed Morad" --klex-en $R/en.klex --klex-ar $R/ar.klex --fold $k --autocorrect gentle --set sentenceStartBigramShare=$s
done; done
```

What to expect, and to judge (Moe AR R / W over the 10 folds):
- At 0.7 every number equals Phase 12's: nothing else in Phase 13 reaches the eval. Judge the AR changes right or wrong as before; the guard is that the wrong count doesn't grow.
- The rd-plan's weak spots are AR keystroke savings (27% against EN 38.7%) and AR next-word top-3 (15% against EN 20%). The sentence-start share is the only Phase 13 change that can move them; look at eval-personal AR NW and KS at 0.3 against 0.7. Take 0.3 only if AR NW or KS gains with EN NW down at most 0.5 pp; otherwise keep 0.7.
- If `suggest --typed hel` still shows "he" in the middle on the real klex, note its score breakdown in docs/issues.md: with today's costs it should need an extra-tap edit.

## 2026-11-04 · Phases 10 to 15 on the real data (Mac)

Real lexicons (`KeyboardExtension/Resources/*.klex`), real held-out files and Moe's 3 chats (10 folds). Baseline `eea2216` (before Phase 10) vs `0124eaf` (after Phase 15), both built `-c release`, seed defaults. Synthetic runs have no tap bias unless noted.

| Run | Baseline | Phases 10 to 15 |
|---|---|---|
| EN synthetic AC / FA / NW / KS | 55.5 / 0.02 / 22.5 / 38.2 | 48.8 / 0.01 / 22.5 / 38.1 |
| AR normal AC / FA / KS | 30.7 / 0.00 / 28.2 | 29.6 / 0.00 / 27.9 |
| AR gentle AC / FA | 20.8 / 0.00 | 20.2 / 0.00 |
| EN, Moe-like taps (bias-y -0.13), offset 0 vs -0.13: AC / KS | | 49.6 / 38.0 vs 50.6 / 38.2 |
| AR normal, Moe-like taps, offset 0 vs -0.13: AC / KS | | 31.1 / 28.0 vs 32.6 / 28.3 |
| Moe EN, 10 folds: NW / KS / changes (normal, gentle) | 20.2 / 38.7 / 14, 6 | 20.2 / 38.7 / 14, 6 |
| Moe AR, 10 folds: NW / KS / changes (normal, gentle) | 15.0 / 27.0 / 50, 33 | 14.8 / 26.7 / 48, 28 |

Moe AR changes, judged by diffing `--samples 100` between the two builds (every change the new build makes, the baseline made too):
- **Normal:** 3 changes dropped and 0 added. All 3 dropped changes were wrong: عمالين→عاملين (fold 4), بيسهلك→ييسرلك, العرص→العصر. So wrong ≤ 12 − 3 = 9, and right stays 39.
- **Gentle:** 4 dropped and 0 added. All 4 were right: ثبل→قبل, يمعام→يمعلم, الجاجات→الحاجات, عذزا→عذرا. So right is 26 and wrong stays 3.

Guards hold: FA ≤ 0.5% everywhere, and the wrong AR changes didn't grow (they fell in normal). Costs:
- EN synthetic AC −6.7 pp. Most of it is the mid-sentence-capitals guard (Leipzig news capitalizes names), plus the 7 pt offset, since these taps have no bias.
- Gentle AR loses 4 right fixes. eval-personal taps key centres, so the 7 pt offset works against it there.

With Moe-like taps, the offset gains about 1 to 1.5 pp AC. Kept as is; check `kalam-cli tapmap` on a fresh device trace.

## 2026-11-05 · Phase 16: the noisy personal benchmark (baseline)

`eval-personal --noise <sigma>` types each held-out word of Moe's chats with NoisyTypist (the eval's omission 1.5%, extra tap 1.5%, swap 0.5%; tap bias default 0,−0.13, Moe-like), with the personal model trained on the other 90%. A word counts when `Engine.isWord` holds: a valid base word, a known personal word or an AR clitic form (the words rule 2 never corrects). `--fold all` sums the 10 folds; each fold seeds its noise with `seed + fold`.

- **Fix rate:** mistyped words that commit as the intended word. **Top-1:** the intended word ranks first. **Wrong change:** the key-centre taps of a counted word commit something else.
- **Real-word:** the noisy literal is itself a word (`Engine.isWord`), so rule 2 never corrects it. It is its own miss bucket and a subset of the fix-rate denominator. Other misses are bucketed by the error kinds the typist made (a substitution is a tap that typed another key).
- `--samples N` prints the first N misses and wrong changes (fold 0 first) with their kinds.

Baseline: working tree on `854da78`, real klex, Moe's 3 chats (1469 messages), 10 folds, `--autocorrect normal`, sigma 0.35, bias-y −0.13, seed 1.

```bash
$K eval-personal --chat <_chat.txt>... --sender "Mohamed Morad" --klex-en $R/en.klex --klex-ar $R/ar.klex \
  --fold all --autocorrect normal --noise 0.35 --samples 20
```

| Lang | Words | Mistyped | Fix rate | Top-1 | Wrong change | Real-word (fixed) |
|---|---|---|---|---|---|---|
| EN | 454 | 285 | **49.1%** (140) | 77.5% | 0.0% (0) | 75 (0) |
| AR | 5788 | 4105 | **24.2%** (993) | 50.9% | 0.0% (0) | 1586 (0) |

Misses by bucket:
- **EN (145):** real-word 75, substitution 45, substitution+extra tap 9, substitution+omission 8, substitution+extra tap+swap 2, extra tap 1, omission 1, omission+extra tap 1, substitution+omission+extra tap 1, substitution+omission+swap 1, swap 1.
- **AR (3112):** real-word 1586, substitution 1117, substitution+extra tap 180, substitution+omission 106, extra tap 54, substitution+swap 33, omission 14, substitution+omission+extra tap 7, substitution+extra tap+swap 6, swap 6, extra tap+swap 2, substitution+omission+swap 1.

What it says, for Phase 17:
- **Real-word is the biggest bucket in both languages** (EN 52%, AR 51% of misses), and its fix rate is 0 by construction. Many of these "words" are wordfreq junk that blocks a fix: ao, rhe, tge, pne, mors, od (EN); افله, معزنا, فلكلية, فدت (AR). The top candidate is often the intended word anyway (rhe→the, tge→the, افله→الله, كب→كل).
- **Ranked first but not applied:** top-1 minus fix rate is 28 pp in EN and 27 pp in AR. Part of it is real-word literals; the rest is the threshold, not the search: in AR normal the edit cost counts twice in θ (انل with top انا, احانل with top أحاول).
- **Plain substitution** is next (EN 45, AR 1117). Omission, extra tap and swap alone are small at these rates.
- **Wrong change is 0 by construction today:** every counted word is one rule 2 protects. It becomes the guard once a real-word rule lets valid literals change. Changes on words that aren't words to the engine (Moe's own typos, unknown dialect) stay in the normal `eval-personal` "autocorrect changes" column, judged by hand.
- **The noise is heavy:** at sigma 0.35 with the −0.13 bias, 63% of EN and 71% of AR counted words come out mistyped, against Moe's 10 to 20%. For reference, sigma 0.2: EN 101 mistyped, fix 60.4%, top-1 81.2%, real-word 26 of 40 misses; AR 1401 mistyped, fix 22.0%, top-1 48.3%, real-word 572 of 1093 misses (extra tap 167 is a bigger share there). Phase 17 can check its kept changes at both sigmas.
- **EN is small:** 454 counted words (the rest of Moe's Latin-script words aren't words to the engine), so a 1-word change is 0.35 pp of the fix rate.
- The refactor (NoisyTypist moved to its own file, error kinds added) doesn't move the synthetic eval: EN 48.8 / 0.01 / 22.5 / 38.1, as in the previous entry.

Sample misses (`--samples 20`, fold 0):

```
miss   [real-word: substitution] so: typed ao -> ao (top so)
miss   [real-word: substitution+omission] for: typed ot -> ot (top of)
miss   [real-word: substitution] the: typed rhe -> rhe (top the)
miss   [real-word: substitution] warm: typed warn -> warn (top warning)
miss   [substitution] better: typed hrrrer -> hrrrer (top herrera)
miss   [real-word: omission] to: typed o -> o (top of)
miss   [real-word: substitution] to: typed ti -> ti (top to)
miss   [real-word: substitution] be: typed he -> he (top be)
miss   [real-word: substitution] of: typed od -> od (top of)
miss   [substitution] yours: typed yphre -> you're (top you're)
miss   [real-word: omission] you: typed ou -> ou (top you)
miss   [real-word: substitution] the: typed tge -> tge (top the)
miss   [substitution+extra tap] everything: typed evreyfjibtx -> evreyfjibtx (top evreyfjibtx)
miss   [substitution] gave: typed gqve -> have (top have)
miss   [real-word: omission] all: typed ll -> ll (top know)
miss   [substitution+extra tap] good: typed golps -> gold (top gold)
miss   [substitution] wished: typed wusjed -> wish (top wish)
miss   [real-word: substitution] more: typed mors -> mors (top more)
miss   [real-word: substitution] one: typed pne -> pne (top one)
miss   [substitution+extra tap] anytime: typed qnnyrime -> qnnyrime (top qnnyrime)
miss   [real-word: substitution] الله: typed افله -> افله (top الله)
miss   [substitution] ويسعدك: typed وطسعدك -> وطسعدك (top وطسعدك)
miss   [substitution] اجي: typed اجث -> اجث (top لينا)
miss   [substitution] ليه: typed لثه -> لثه (top ليهم)
miss   [substitution+omission] وابسط: typed وتسظ -> وتسظ (top وتسظ)
miss   [real-word: substitution+omission] ليه: typed لق -> لق (top قد)
miss   [substitution+extra tap] ناس: typed نترس -> نترس (top مارس)
miss   [real-word: substitution] معانا: typed معزنا -> معزنا (top معانا)
miss   [substitution+extra tap] بتشتغل: typed بتشاتغل -> بتشاتغل (top بتشاتغل)
miss   [real-word: omission] بارت: typed ارت -> ارت (top ارتفاع)
miss   [substitution] احاول: typed احانل -> احانل (top أحاول)
miss   [real-word: substitution] وافر: typed رافت -> رافت (top رأفت)
miss   [real-word: substitution] وقت: typed نبت -> نبت (top وبتاع)
miss   [real-word: substitution] الكلية: typed فلكلية -> فلكلية (top الكلية)
miss   [substitution] انا: typed انل -> انل (top انا)
miss   [real-word: substitution] الترم: typed التتم -> التتم (top الأمر)
miss   [substitution] الي: typed اغس -> اغس (top السيشن)
miss   [real-word: substitution] فات: typed فدت -> فدت (top فات)
miss   [substitution] خلصت: typed ملصع -> ملصع (top كان)
miss   [real-word: substitution] كل: typed كب -> كب (top كل)
```

## 2026-11-05 · Phase 17: better autocorrect (real-word fix, post-correction, double taps)

Working tree on `b177f18`, real klex (unchanged, EN `b98ee2a1…`, AR `d729d2df…`), all 3 chats, built `-c release`. Benchmark as in Phase 16, both sigmas, bias-y −0.13, seed 1, `--autocorrect normal`, `--fold all`.

**Re-baseline.** The Phase 16 table ran on one chat only (1469 messages, israa-elayashy). With all 3 chats (3759 messages) the baseline is:

| Sigma | EN words / mistyped | EN fix / top-1 | AR words / mistyped | AR fix / top-1 |
|---|---|---|---|---|
| 0.2 | 797 / 188 | 47.3% (89) / 72.3% | 13373 / 3218 | 20.7% (667) / 52.1% |
| 0.35 | 797 / 527 | 49.5% (261) / 74.4% | 13373 / 9498 | 25.3% (2401) / 51.4% |

Wrong change 0 in both (by construction). Real-word misses at 0.2: EN 52 of 99, AR 1441 of 2551. By the literal's wordfreq zipf (EN / AR): 2 to 3: 20 / 360, 3 to 4: 16 / 280, 4+: 16 / 322, under 2 (AR clitic forms): 479. In about 60% of them the intended word already ranks first.

**Guards** for any rule that lets autocorrect touch valid words: normal `eval-personal` "autocorrect changes" over the 10 folds (key-centre taps of Moe's text; post-correction simulated too), diffed against the baseline (EN 14, AR 48 in normal; AR 29 in gentle) and judged by hand; synthetic FA ≤ 0.5% (baseline EN 48.8 / 0.01, AR normal 29.6 / 0.00, AR gentle 20.2 / 0.00).

Kept, cumulative (fix rate EN / AR):

| Change | σ 0.2 | σ 0.35 | Synthetic AC / FA (EN; AR normal; AR gentle) |
|---|---|---|---|
| Baseline | 47.3 / 20.7 | 49.5 / 25.3 | 48.8 / 0.01; 29.6 / 0.00; 20.2 / 0.00 |
| A. Real-word fix: a valid literal changes when c* (a full word) wins by θ + `realWordMarginEN` 4 / `realWordMarginAR` 10; never to the same AR stem with another suffix | 56.9 / 25.7 | 65.7 / 30.3 | 64.4 / 0.04; 31.8 / 0.00; 20.4 / 0.00 |
| B. + Post-correction with the next word, `postCorrectionMaxCost` 3 | 59.6 / 28.2 | 66.2 / 33.6 | 65.7 / 0.04; 35.1 / 0.00; 24.5 / 0.00 |
| C. + `doubledInsertionCost` 3 (an extra tap repeating the previous key) | **61.2 / 29.6** | **66.0 / 33.8** | 66.6 / 0.04; 35.7 / 0.00; 25.2 / 0.00 |

- Final top-1 at 0.2: EN 72.9%, AR 53.4%. Real-word fixed at 0.2: EN 21 of 52, AR 223 of 1441. KS and NW unchanged (EN 38.2 / 22.5, AR 27.9 / 19.8); candidates p95 EN 1.49, AR 2.58 ms.
- C costs one EN word at 0.35 (349 → 348 of 527); the synthetic eval (6,414 EN words at σ 0.35) gains 0.9 pp, so it's kept.
- `--noise` wrong change, final: EN 0, AR 4 of 13373 (0.03%). All 4 are Moe's own typos that count as words (بمعلم, علبنا, نن, حير), so they are right fixes.
- **Moe's changes, normal:** EN 14 → 14 (the same set). AR 48 → 54: none dropped, 6 added, all right: حدفت→حذفت, بمعلم→يمعلم, علبنا→علينا, نن→من, اللهبة→اللعبة, حير→خير. **Gentle:** AR 29 → 35, 6 added, all right: حدفت→حذفت, بمعلم→يمعلم, اموورك→امورك, مايون→مليون, الجاجات→الحاجات, عذزا→عذرا. So wrong changes didn't grow.
- The benchmark gives post-correction the next word as typed right (its best case); on the device the next word is whatever committed.

Dropped:
- AR normal edit counted once (weight 0 instead of 1): AR 24.9 / 26.8, but +24 Moe changes, nearly all wrong (جوعت→جيبت, عمالين→عاملين, بيعملوه→بيعملوا). Weight 0.5: AR 22.8 / 26.0, +8 changes, all wrong. The double count stays.
- insertionCost 4: EN 47.9 / 48.4, AR 22.2 / 25.1 (σ 0.35 worse). 4.5: 47.9 / 49.0, 21.6 / 25.2 (worse at 0.35). omissionCost 2.5: 48.4 / 49.3, 20.8 / 25.4 (noise level). transpositionCost 1.5: 46.8 / 49.1, 20.7 / 25.2. farSubstitutionCost 4: 46.8 / 48.2, 20.4 / 25.1. All rejected.
- min-zipf 3 rebuild (both klex, with A to C): rates 63.3 / 70.8 EN, 31.0 / 37.9 AR, but only because 28 EN and 817 AR of Moe's words leave the counted set (EN fixes 112 → 105). Moe's changes 68 → 116, many wrong (yapping→tapping, gpt→got, pdfs→odds, حابب→جايب). Rejected; the klex is unchanged. A rebuild at the default zipf reproduces EN `b98ee2a1…` and its held-out file byte for byte.
- Real-word margins: AR 9 adds مزه→مره (Moe's slang); AR 10 and 11 without the suffix rule add خيرك→خيره and يهديها→يهدينا; EN 3 makes 3 wrong changes in `--noise`. Allowing a completion for a valid literal: AR يعين→يعينك, ناقص→ناقصه and similar.
- Post-correction with the real-word margins replaced by a lower one (2, 4, 6 for both languages): AR wrong change 126 / 65 / 27. postCorrectionMaxCost 3.5 or 4: adds يحبيبي→يحبيبتي (Moe writes يحبيبي to Mohamed). Allowing a 1-letter completion: adds انت→انتي, يجازيك→يجازيكي, يهنيك→يهنيكي, and brow fox still isn't fixed (no "brown fox" base bigram).
- doubledInsertionCost 2: AR 30.9 / 34.0, but adds بعتتلي→بعتلي (2x), بتتعمل→بتعمل, تتعمل→تعمل, وببص→وبس. 3.5 and 4 fix fewer.
- Space errors (item 3): not tried. NoisyTypist makes no space errors, so the benchmark can't show them.

```bash
$K eval-personal --chat <3 chats> --sender "Mohamed Morad" --klex-en $R/en.klex --klex-ar $R/ar.klex \
  --fold all --autocorrect normal --noise 0.2      # and 0.35; --set realWordMarginAR=… etc. for the sweeps
$K eval-personal ... --fold k --autocorrect normal --samples 100000   # k = 0..9, the changes diffed by hand
$K suggest --klex $R/en.klex --context "the quick" --typed brow --next fox   # new: what the next word's commit does
```
