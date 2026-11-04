# Research 1: what users say about Apple, Gboard and SwiftKey on iPhone (2026-11-04)

About 25 searches and 6 fetched pages. MacRumors forum pages returned 403 and Reddit wasn't directly reachable, so the Reddit material comes from press and Apple Community coverage of those threads. Little has been written about Fleksy or Typewise since 2015.

## 1. Top loves per keyboard (most mentioned first)

**Apple keyboard**
1. The space-bar trackpad, which moves freely across lines. Gboard's version stays on one line. 9to5Google calls it "the only good thing about the iPhone's keyboard".
2. It's always there: in password fields, with the dictation mic, and it never switches away.
3. System Text Replacement expands reliably.
4. Small touches, like not adding a space before 's after an autocorrected word.

**Gboard**
1. Better typo correction than Apple's.
2. Haptics (historically).
3. Swipe typing and the sliding space bar.
4. Dictation reviewers rate more accurate than Apple's.

**SwiftKey**
1. Autocorrect noticeably better than Apple's, and fewer accidental keystrokes. Its "Tap Map" shows how it has adapted to where you tap.
2. A persistent number row.
3. Clipboard manager.
4. Themes.

**Typewise:** big hexagon keys, which it claims cut typos sharply.

## 2. Top hates per keyboard (most mentioned first)

**Apple, iOS 26**
1. Dropped or wrong letters when typing fast. The key highlights U but J or H gets typed (NekoMichi's slow-motion video). Partly fixed in 26.4; some users still report it.
2. Autocorrect swaps correct words for unrelated ones ("the" becomes "Theresa", "for" becomes "of"), sometimes right before send. Some people turn autocorrect off entirely.
3. It changes a word back after you rejected the correction.
4. Typos get learned into the dictionary, and the usual fix is resetting the whole keyboard dictionary.
5. its/it's, were/we're, ill/I'll: it guesses wrong about half the time.
6. No "never suggest this word again" option.
7. No number row, no clipboard, no customization.

**Gboard (iOS)**
1. Crashes or resets, then falls back to Apple's keyboard. Tied to Full Access.
2. Feels worse than Gboard on Android.
3. Text Replacement sometimes expands, sometimes only shows up as a suggestion.
4. Single-line cursor.
5. Predictions don't learn your style.

**SwiftKey (iOS)**
1. Switches back to Apple's keyboard after 4 to 7 seconds of use, or every time it opens (iOS 18.3 and 26.2).
2. The Liquid Glass redesign (4.3.5) brought crashes, missing keys and spacing bugs.
3. Lag that crept in over recent versions.
4. Corrects words that were already right.

**Fleksy / Typewise:** slow to appear (Fleksy up to 10 s), weak prediction, steep learning curve for the hexagon layout, missing features.

Across 1 to 3 star reviews of five third-party keyboards (Unstar, method unclear): autocorrect fighting correct words 26%, lag and dropped keys 21%, privacy 18%, ads 16%, updates removing features 12%.

## 3. Why third-party keyboards feel worse, and what an extension can fix

| Problem | Fixable in the extension? |
|---|---|
| Switching back to Apple's keyboard. Mostly a silent kill at about 60 MB with no crash log; also crashes. | Yes: stay under memory, never crash |
| Slow or blank first appearance | Mostly: build views lazily, mmap data, no heavy work in `viewDidLoad` |
| Missed taps and lag | Yes: touch-down handling, no main-thread waits |
| Missing haptics | Yes (Kalam has them) |
| Single-line cursor | Yes |
| Inconsistent Text Replacement | Yes: `requestSupplementaryLexicon` gives the user's shortcuts |
| Password fields use Apple's keyboard | No: iOS rule |
| No dictation mic | No |
| Globe-key switching friction | No |
| Height or feel differs from Apple's | Yes (Kalam matches it) |

## 4. Autocorrect and prediction behavior

**Praised:**
- learning the user's own words, including the "ducking" fix in iOS 17;
- SwiftKey adapting to where you tap;
- undoing a correction right after it happens;
- smart spacing around apostrophes.

**Cursed:**
- changing real dictionary words;
- re-correcting after you rejected it;
- learning typos permanently;
- contraction guessing (its, were, ill, well, hell);
- random capitalization;
- bad words that keep coming back with no way to remove them;
- suggestions behaving differently on two devices.

## 5. Top 15 takeaways for Kalam

NEW means the agent couldn't see it in its brief. The orchestrator checked: Kalam already has "Don't suggest" on long-press (6), the literal in quotes (13) and hold-delete word mode (14).

1. Never get jetsam-killed. A silent kill that swaps in Apple's keyboard is the top reason people leave third-party keyboards.
2. The key that lights up must be the letter that's typed: same touch, same timestamp. This is iOS 26's biggest failure, so test it hard on device.
3. NEW: Sticky rejection. Once Moe undoes a correction or retypes the word, never correct that word in that spot again, and lower its penalty from then on.
4. NEW: Never autocorrect a valid word (in the English or Arabic lexicon, or learned) to another valid word unless confidence is very high.
5. NEW: Don't learn typos permanently. Require 2 or more uses or an accepted suggestion, and let learned words decay.
6. Long-press a suggestion to forget it (Kalam has it).
7. NEW: Merge Moe's iOS Text Replacements via `requestSupplementaryLexicon` and always expand them. Kalam reads them as words; check whether it expands the shortcuts.
8. NEW: Don't guess on its/were/ill/well/hell/id. Leave them alone, or suggest the contraction without applying it.
9. NEW: Smart apostrophe spacing. After an autocorrected word, typing 's attaches without a space.
10. Fast cold start: first frame within about 100 ms, with the engine loading after the keys are drawn. Measure on device.
11. Space-bar trackpad across lines, not stuck on one line like Gboard's. Check the multi-line part.
12. NEW: Mixed English and Arabic. Pick the language per word, or suggest Arabic words while on the English layout (and the reverse), so switching costs nothing.
13. The literal typed word in the left slot (Kalam has it while an autocorrect is pending).
14. Hold delete to accelerate to whole words (Kalam has it).
15. NEW: Degrade, never stall. If the engine or SQLite fails, typing keeps working with no suggestions. Never let Full Access state cause resets (Gboard's failure).

Things Kalam can't fix: password-field fallback, the dictation mic and the globe-key switching friction.

## Sources
- https://www.techradar.com/phones/ios/youre-not-bad-at-typing-ios-26s-autocorrect-is-broken-and-theres-still-no-fix-in-ios-26-2
- https://www.techradar.com/phones/drives-me-crazy-ios-26-4-has-fixed-an-infuriating-keyboard-bug-but-one-problem-has-still-gone-unsolved
- https://www.macrumors.com/2026/03/18/ios-26-4-iphone-keyboard-bug-fix/
- https://www.macworld.com/article/2952872/heres-proof-that-those-iphone-typos-you-keep-making-arent-your-fault.html
- https://www.slashgear.com/2012833/ios-26-keyboard-bug-typo-wrong-letters
- https://mjtsai.com/blog/2025/11/03/ios-18-and-ios-26-autocorrect
- https://piunikaweb.com/2026/05/25/ios-keyboard-skipping-letters-reset/
- https://discussions.apple.com/thread/255241829
- https://discussions.apple.com/thread/256019667
- https://windowsreport.com/?p=1506762
- https://www.slashgear.com/2041467/iphone-keyboard-flaws-microsoft-swiftkey-alternative
- https://9to5google.com/2026/02/16/gboard-might-finally-add-a-cursor-the-only-good-thing-about-the-iphones-keyboard/
- https://www.yahoo.com/tech/gboard-why-did-google-make-such-a-good-154806972.html
- https://antyweb.pl/google-nie-potrafi-naprawic-gboarda-dla-ios-od-miesiecy-tylko-tak-da-sie-z-niego-korzystac
- https://unstar.app/blog/gboard-swiftkey-grammarly-fleksy-typewise-keyboard-apps-ranked-2026
- https://developer.apple.com/forums/thread/743534
- https://dev.to/tbds_2dadf2b626f315902eae/the-three-hard-constraints-of-an-ios-keyboard-extension-46af
- https://spy.macrumors.com/threads/state-of-3rd-party-keyboards-on-ios.1958640
- https://www.yahoo.com/tech/skip-the-apostrophe-when-youre-typing-on-your-112713774399.html
- https://bgr.com/tech/iphone-keyboard-autocorrect-problems-swear-words/
- https://www.macrumors.com/2026/04/01/ios-27-upgraded-keyboard-rumor/
- https://www.igeeksblog.com/typewise-custom-keyboard-ios-app-review/
