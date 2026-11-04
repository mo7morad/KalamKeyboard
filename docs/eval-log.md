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
