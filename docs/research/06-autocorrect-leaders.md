# Research 6: what makes Gboard and SwiftKey autocorrect feel good (2026-11-05)

Builds on `04-prediction-autocorrect.md`, which covers the decoder basics (spatial model + lexicon + n-gram, personal offsets, revert memory, guard rules). Most of that is in Kalam already. This pass looks for what's still missing.

## 1. What the leaders do that Kalam doesn't

| Feature | Who | What it does | Kalam today |
|---|---|---|---|
| **Post-correction** | Gboard, iOS | After the next word arrives, re-scores the previous word with context on both sides and replaces it when confident ("quick brow fox" -> "brown"). Fixes real-word errors that commit-time autocorrect can't see ([PhraseFlow](https://drustz.com/assets/pdfs/phraseflow.pdf), [Proofread](https://arxiv.org/pdf/2406.04523)). | None. Rule 2 never touches a valid word. |
| **Space-aware decoding** | Gboard, SwiftKey "Smart Space" | Hypothesizes word breaks inside the taps: a missed space ("thequick"), a space hit instead of a nearby key (b/n/v above space), a stray space inside a word ([Neural Search Space in Gboard Decoder](https://arxiv.org/pdf/2410.15575); SwiftKey 2012 [Android Central](https://www.androidcentral.com/swiftkey-launches-full-version-android-market)). | None. Each space is a hard word end. |
| **Big background LM** | SwiftKey (Fluency), Gboard | Billions of sentences of background text; SwiftKey runs n-gram and neural side by side ([Engadget](https://www.engadget.com/2016/09/15/swiftkey-android-neural-network-update/)). | wordfreq + Leipzig news bigrams: good EN, MSA-only AR. |
| **Personal LM from history** | both | Learns from what the user sends. | Done (WhatsApp import + learner). |
| **Tunable confidence** | LatinIME / HeliBoard | Autocorrect confidence is a slider. | Gentle / normal per language. |

The 2024 Gboard paper also lists the common error types: omission ("hllo"), insertion, substitution, transposition and space errors. Kalam's beam covers the first four; space errors are the gap.

## 2. Egyptian Arabic: the data gap

Kalam's AR base is MSA (wordfreq + Leipzig news). Moe writes Egyptian. Options for Egyptian text, all usable offline in `Tools/lexicon-builder` (data only, no runtime cost; the `.klex` stays mmapped):
- [dataflare/arabic-dialect-corpus](https://huggingface.co/datasets/dataflare/arabic-dialect-corpus): 5.8M tokens over 5 dialects, Masri (Egyptian) is one slice.
- [fr3on/arabic-dialect-corpus](https://huggingface.co/datasets/fr3on/arabic-dialect-corpus): 150k+ informal YouTube comments, Egyptian and Saudi.
- [Lancaster Arabic dialects dataset](https://www.lancaster.ac.uk/staff/elhaj/corpora.html): dialect tokens with frequencies, Egyptian included.
- [Arabic-Egyptian comparable Wikipedia](https://www.kaggle.com/datasets/mksaad/arb-egy-cmp-corpus): Egyptian Wikipedia, formal, a weak fit.

Morphology: [CAMeL Tools](https://camel-tools.readthedocs.io/en/stable/api/morphology.html) has an Egyptian analyzer and generator (`calima-egy-r13`). Offline it could expand Moe's known stems into their clitic forms (بنجرب -> بنجربه, مبنجربش), so they become real candidates. It is a new Python dependency (hard rule 7: needs Moe's OK).

## 3. Neural models

Still no (see 04 §2): about 1% gain at Google scale, CoreML memory risk in the extension, too little Egyptian text to train. Revisit only if the n-gram work plateaus.

## 4. What this adds to the plan (Phases 17 and 18)

In expected order of value for Moe, each gated on the Phase 16 benchmark:
1. Edit-cost and AR-threshold re-tune (already planned).
2. **Post-correction of the previous word** (new): on the next word's commit, re-score the previous word with both neighbours; replace it only when the margin is large and it's one cheap edit away. Same undo and revert memory as an autocorrect. Covers brow -> brown.
3. **Space errors** (new): stray space inside a word (كويسك ه) and a missed space, if the benchmark shows them.

Phase 18 (its own phase): Egyptian corpus + CAMeL Tools word forms into the AR base, approved by Moe on 2026-11-05.
