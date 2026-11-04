# Issues

Phase 7 works through this file. Add one entry per problem you notice while typing, using the template below. Mark the frequency honestly; "once" is still useful.

```
## <short title>
- Lang / app:
- Context (text before cursor):
- I typed:
- I expected:
- Keyboard did:
- Frequency: once / sometimes / always
```

## Sentence-start bar favours news words over the typed word (found in the Phase 5 review)
- Lang / app: EN and AR, any app
- Context (text before cursor): start of a message or sentence (`<s>`)
- I typed: "hel" (EN) and "انا" (AR)
- I expected: help / hello in the middle slot; انا in the middle slot
- Keyboard did: "he" in the middle for "hel"; أما in the middle for "انا". The base bigrams after `<s>` come from news, where "He …" and "أما …" open many sentences (`kalam-cli suggest`: he −9.19 vs help −9.69; أما −8.11 vs انا −8.34). Space keeps the typed word, so only the bar is off. Mid-sentence ("can you hel") ranks help first. Moe's imported chats should fix the Arabic case; check after the import.
- Frequency: always, at sentence start
- Status (Phase 13): **not fixed by this knob.** `EngineConfig.sentenceStartBigramShare` (the base bigram's share after `<s>`, Moe's own `<s>` bigrams keep theirs) was swept on the EN proxy: 0.7 / 0.5 / 0.3 / 0.1 gave NW 23.2 / 23.1 / 23.1 / 22.9, KS 37.2 / 37.1 / 37.1 / 37.1, AC 47.1 at every value (no bias); with the tap bias AC 48.3 / 48.4 / 48.4 / 48.4 and NW the same as without. Seed 2 at 0.3: NW 23.2 against 23.4. So it stays 0.7 (eval-log Phase 13). The example doesn't reproduce on the proxy at any value: "hel" at `<s>` gives help first (−9.8), and "he" needs an extra-tap edit (5.0) to come up at all, so it can't take the middle slot with today's costs. Moe: rerun `kalam-cli suggest --klex en.klex --typed hel` and `--lang ar --klex ar.klex --typed انا` on the real lexicons; if he or أما still takes the middle, rerun the sweep there (`--set sentenceStartBigramShare=0.3`). The Arabic case is expected to be fixed by his imported `<s>` bigrams, which this knob doesn't touch.
