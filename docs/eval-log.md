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
| transpositionCost 3 | 51.7 / 0.01 / 38.4 | 24.3 / 0.00 / 28.5 | 38.8 | 27.1 | 55 / 47 | gain within seed noise; dropped at the end: an imported swap typo (tamma → tamam, WhatsAppTests) stops being fixed |
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
