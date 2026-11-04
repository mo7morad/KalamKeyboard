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
