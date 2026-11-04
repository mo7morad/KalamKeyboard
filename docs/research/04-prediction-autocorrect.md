# Research 4: on-device decoding and autocorrect (2026-11-04)

## 1. How the leaders decode

- **Gboard:**
  - Beam search over a C∘L∘G composition: C maps keys to keys, L maps keys to words (the lexicon), and G is the LM. In 2024, G held an n-gram over 64k words plus 170k unigrams.
  - Only states near the touches are expanded, and pruning uses LM plus spatial score. One decoder handles literal input, completions, autocorrect, next-word prediction and post-correction, in a budget of about 20 ms ([Ouyang et al. 2017](https://arxiv.org/pdf/1704.03987); [Zhang et al., EMNLP 2024, "Neural Search Space"](https://aclanthology.org/2024.emnlp-industry.93.pdf)).
  - The spatial model is still a fixed Gaussian around key centres, plus non-Gaussian costs for edits and completions ([Sivek & Riley 2022](https://arxiv.org/pdf/2209.11311)). An LSTM-CTC spatial model was described in 2017 ([Google blog](https://www.research.google/blog/the-machine-intelligence-behind-gboard/)).
  - Raw per-letter error with no decoding is about 8 to 9% (Azenkot & Zhai, cited in the 2024 paper).
- **AOSP LatinIME / HeliBoard:**
  - A proximity grid that searches up to 1.2 key widths and 16 neighbour keys.
  - A squared-distance cost from each key's "sweet spot", converted into edit cost.
  - A normalized-score autocorrect threshold: "modest" is 0.185 (the default), "aggressive" 0.067 ([LatinIME commit](https://gitlab.futo.org/keyboard/latinime/-/commit/116e58c437526ea2503564317e2731b8126acaa4); [ProximityInfo](https://git.aicp-rom.com/packages_input_LatinIME.git/plain/java/src/com/android/inputmethod/keyboard/ProximityInfo.java)).

**Accuracy features, ranked by evidence:**
1. Spatial model plus lexicon constraint.
2. LM context. On a Google email study, spatial plus LM cut word error rate from 38.4% to 5.7% ([Google](https://research.google.com/pubs/archive/43272.pdf)).
3. Personalization: a personal LM takes 5.7% to 4.6%, and personal touch offsets add more.
4. Edit costs (transpositions, insertions, omissions).
5. A longer-context neural LM: only 0.26 to 1.19% Words Modified Ratio at Gboard scale.

## 2. Is a small neural LM feasible in the extension?

- **Shipping examples:**
  - **Gboard:** a one-layer CIFG-LSTM with 670 hidden units, 96-dimension embeddings and a 10k vocabulary, about 1.4 MB quantized ([Hard et al. 2018](https://ar5iv.arxiv.org/html/1811.03604)). Gboard's 2024 neural decoder LM uses a 30k vocabulary and cost 17 to 28% more latency after optimization.
  - **Apple iOS 17:** a GPT-2-style model, about 34M parameters, 6 blocks, hidden size 512 and a 15k vocabulary heavy on emoji. This is Jack Cook's reverse-engineered estimate, not confirmed by Apple. It runs in Apple's own process, not under extension limits ([Cook](https://jackcook.com/2023/09/08/predictive-text.html); [summary](https://mjtsai.com/blog/2023/09/18/apples-new-transformer-powered-predictive-text-model/)).
  - **FUTO Keyboard:** transformers via llama.cpp, with community GGUF models of 36 to 65M parameters on Android ([FUTO](https://docs.keyboard.futo.org/print)).
  - **SwiftKey:** a neural engine on-device since 2015 ([Tom's Hardware](https://www.tomshardware.com/news/swiftkey-local-neural-network-apps,32709.html)).
  - **Older papers:** a 7.4 MB word predictor at 6.5 ms ([Yu et al. 2017](https://paperswithcode.com/paper/an-embedded-deep-learning-based-word)).
- **CoreML inside an extension is the risk.** One developer blew a keyboard extension's memory budget with an 18 MB model through CoreML/TFLite overhead ([r/iosdev](https://red.127.pp.ua/r/iosdev/comments/1egz5b2/running_ml_models_efficiently_on_ios)). Failed Neural Engine compiles caused silent kills on iOS 17+ ([DEV](https://dev.to/tbds_2dadf2b626f315902eae/the-three-hard-constraints-of-an-ios-keyboard-extension-46af)).
- **Compute is not the problem.** A Gboard-sized CIFG needs about 2M multiply-accumulates per step plus about 1M for the softmax: under 1 ms on the CPU with Accelerate.

**Recommendation: not now.** Kalam's Egyptian data is 3 WhatsApp chats, too little to train on, and at Gboard scale the gain was about 1% WMR. Personalization (below) is worth more. Staged path if wanted later:
- **(a)** Train a 1 to 3M-parameter CIFG offline in Python and compare it with the n-gram via `kalam-cli eval` on held-out WhatsApp text. Proceed only if next-word top-3 gains 3 points or more.
- **(b)** Ship it as a reranker of the decoder's top 20, with mmapped int8 weights and hand-written BNNS/vDSP. No CoreML, no Neural Engine.
- **(c)** Only then consider putting it inside the beam, like Gboard's Neural Search Space.

## 3. What gives the most "it knows me" value

- **Never re-correct a reverted word.** Patents treat a backspace right after an autocorrect as an explicit rejection that reduces future corrections ([US 9703394](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/9703394); [US 2014/0310213](https://uspto.report/patent/app/20140310213)). Firefox OS kept correcting "mt." to "My", a well-known example of the hate when this fails ([Mozilla 944857](https://bugzilla.mozilla.org/show_bug.cgi?id=944857)).
- **Per-user touch offsets.** Per-key centre offsets (covariance optional) give significant gains, and clustering keys avoids overfitting ([Sivek & Riley](https://arxiv.org/pdf/2209.11311)). Usable models come from about 60 touches with an accuracy gain over 8% ([Buschek et al. 2013](https://www.dcs.gla.ac.uk/~rod/publications/BusRogMur13.pdf)), or from about 200 touches ([Weir et al. 2012](https://www.dcs.gla.ac.uk/~rod/publications/WeiRogMur12.pdf)).
- **Personal n-grams and phrases, plus contacts.** Gboard's n-gram baseline layers user-history and contacts models on the base LM ([Hard et al.](https://ar5iv.arxiv.org/html/1811.03604)), and it builds a personal dictionary of out-of-vocabulary words and frequent phrases ([Gboard i18n](https://arxiv.org/pdf/1912.01218)).
- **Recency:** Presage's recency predictor gives recently typed words an exponentially decaying boost ([Presage](https://presage.sourceforge.io/features)).
- **Capitalization:** remember the casing the user most often writes for each word.

## 4. Autocorrect policy to avoid "autocorrect rage"

Autocorrect failures drive frustration and perceived workload ([Alharbi & Stuerzlinger](https://vvise.iat.sfu.ca/user/data/papers/autocorrectfrustration.pdf)). At least 8.4% of autocorrections get changed back ([Putze et al.](https://media.suub.uni-bremen.de/bitstream/elib/7008/1/Putze_Platform%20for%20studying%20Self-repairing%20auto-correction_2020_accepted-version_PDF-A.pdf)). iOS 26 shows that perceived "bad autocorrect" is often the touch layer misfiring ([MacRumors](https://www.macrumors.com/2026/03/18/ios-26-4-iphone-keyboard-bug-fix/)).

- Correct only when the best candidate beats the literal by a margin, with a stricter margin when the literal is in the lexicon or the personal store.
- Never correct:
  - a pair the user has reverted before;
  - words with digits, `@`, `/`, `.` inside, URLs or emoji;
  - mixed-script tokens;
  - mid-sentence capitalized words;
  - ALL CAPS.
- Use a stricter rule for words of 1 to 3 characters.
- When the user code-switches, choose the language per token from its script and the previous token's language, never globally.
- After a revert, commit the literal and stop correcting it for the session.

## 5. Ranked improvements for Kalam

| # | Change | Impact | Cost |
|---|---|---|---|
| 1 | Persistent revert memory: a one-backspace undo stores (typed, corrected) in SQLite and blocks it forever; two commits of a literal make it a valid word | High | Low |
| 2 | Protect personal vocabulary: any word used 2 or more times (WhatsApp or live) is never autocorrected away | High | Low |
| 3 | Guard rules from §4 | High | Low |
| 4 | Margin-based threshold (best vs literal), tuned with `kalam-cli eval` against a WMR-style false-correction metric on WhatsApp replay | High | Low to medium |
| 5 | Per-user key offsets: align committed words to their touches and keep a running mean per key (or key cluster) in the Gaussian | Medium to high | Medium |
| 6 | Per-token script/language routing for EN/AR code-switching, including Franco tokens | Medium to high | Medium |
| 7 | Recency cache LM interpolated into the n-gram (session and conversation) | Medium | Low |
| 8 | Capitalization learning (most frequent casing per word) | Medium | Low |
| 9 | Per-user confusion costs from corrections and reverts (key pairs he swaps) | Medium | Medium |
| 10 | Personal trigrams and multi-word phrase suggestions from WhatsApp | Medium | Medium |
| 11 | Post-correction: re-score the previous word once the next word arrives (Gboard does this) | Medium | Medium to high |
| 12 | Tiny CIFG reranker, staged as in §2 and gated on eval | Low to medium | High |

Items 1 to 4 cost little and target the regret users notice most. Items 5 and 6 are where Kalam can beat iOS for Moe.

**Caveats:** none of this was measured on Kalam, and the impact column is a judgment from the sources. Apple's model size is a reverse-engineered estimate, the FUTO community models are unverified, and the CoreML memory reports are anecdotal.
