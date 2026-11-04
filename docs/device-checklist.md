# Device checklist

Things only Moe's iPhone 17 can verify. Tick each one, and note anything that feels off in `docs/issues.md`.

## Phase 1: keyboard shell

Setup: install a Debug build, then Settings > General > Keyboard > Keyboards > Add New Keyboard > Kalam, and turn on Allow Full Access. Test in Notes, Messages and WhatsApp.

**Look (compare with `docs/reference/kalam/` and Apple's keyboard)**

- [ ] EN letters, 123 and #+= pages line up with Apple's: key sizes, gaps, corner radius, label sizes, light and dark.
- [ ] Arabic letters match `docs/reference/apple/ar-letters-*.png`: ض at the far left, ج at the far right, the blank before delete in row 3, the tanween key, ١٢٣.
- [ ] The whole keyboard sits about 7 pt higher than Apple's, and its panel is about 7 pt taller (iOS gives third-party keyboards a taller globe strip). Say if it bothers you.
- [ ] The small "A" / "ع" mark on the space bar, and the top-row digit hints, are readable but quiet.
- [ ] Return key: ⏎ icon in Notes; "search" in Safari's address bar; "send" where an app asks for it; dimmed when the field is empty and the app requires text.
- [ ] Dark mode follows the system and apps that force a dark keyboard.

**Feel**

- [ ] Typing fast never drops a letter. Two-thumb rollover: press the next key before releasing the last one; both letters arrive, in order.
- [ ] A letter is typed on release, at the key under the finger. Sliding along a row moves the popup with the finger.
- [ ] Key-press bubble on letters; none on the bottom row. Top-row bubbles are pushed down to stay inside the keyboard (a limit of third-party keyboards).
- [ ] Long-press (0.35 s) opens the strip: e, a, u, n, c, k on EN; ا ي و ه ك on AR. Top-row keys offer their digit, preselected. Slide and release types the pick.
- [ ] Shift: one tap shifts one letter; a quick double tap locks caps (icon changes); a tap unlocks.
- [ ] Auto-shift at the start of a field, after ". " and after a new line. Not in Arabic.
- [ ] Double space after a word types ". ".
- [ ] Backspace: one tap deletes one character; holding repeats after about half a second, then switches to whole words after about 2 s of holding.
- [ ] Space bar trackpad: drag sideways or hold 0.4 s, the labels hide and the cursor follows (also in Arabic text: the cursor moves the way the finger does).
- [ ] 123 page: typing space or ' goes back to letters.
- [ ] EN/AR key switches language; the choice survives closing and reopening the keyboard and switching apps.

**Feedback (by ear and hand, next to Apple's keyboard)**

- [ ] Haptic on every touch-down, light, close to Apple's.
- [ ] Sounds: letters click (1104), delete has its own sound (1155), shift / 123 / EN/AR / space / return use the modifier sound (1156). Each backspace repeat clicks. Silent switch mutes them.
- [ ] Sounds at "Louder" 0 match the first build. Move Kalam > Settings > Louder a little: the next keyboard open is quiet, and it grows evenly toward the right, at the top as loud as device round 1, with no crackle. Note the position that sounds right: ____
- [ ] With Full Access off: the bar shows "Turn on Full Access for learning, haptics and sounds", and nothing crashes.

**Memory (Console.app, subsystem `com.morad.kalam.keyboard`, category "memory": "footprint X MB, headroom Y MB")**

- [ ] Note the footprint and headroom readings on first open: ____ MB, ____ free.
- [ ] 20 show/hide cycles across 3 apps (Notes, Messages, WhatsApp): MB grows by less than 2 MB. Final: ____ MB.
- [ ] The latency field shows "– ms" (Phase 5 fills it).

## Phase 5: suggestions, autocorrect and learning

Setup: install a Debug build with Console.app open on the Mac (subsystem `com.morad.kalam.keyboard`), and test in Notes, Messages and WhatsApp.

**Typos and undo**

- [ ] Type "teh": the bar shows “teh” on the left and **the** in bold in the middle. Space gives "the ".
- [ ] Right after that, one backspace gives "teh" back (the space goes too). Space again keeps "teh", and "teh" is no longer corrected later.
- [ ] Typing a word fast with one neighbour-key slip (e.g. "tomorroe") fixes it on space; ".", "," and return fix it too.
- [ ] A correct word, a name in your contacts, "OMG" or a word with a digit is never changed.
- [ ] "dont" becomes "don't" (contraction fix on). "انا" stays انا (Arabic variant fix off by default), with أنا offered in the bar.
- [ ] No autocorrect in Safari's address bar, an email field or a password field.

**Bar**

- [ ] Tapping a suggestion replaces the word and adds a space; typing "." or "," right after removes that space ("hello, ").
- [ ] With an empty word the bar shows 3 next words. After ". " they are capitalized (shift is on).
- [ ] Arabic: the bar is mirrored (best in the middle, the second choice on the right).
- [ ] Long-press a suggestion: "Don’t suggest ‘x’" appears; tap it and the word stops appearing. The app's Learned Words lists it as Blocked.

**Learning**

- [ ] New word: type a made-up word plus a space (pick one Kalam doesn't correct, because an undo alone makes a word known), dismiss the keyboard, then type it again after reopening it (a second session) and dismiss again. In the next session, typing its first letters suggests it, and it is no longer autocorrected.
- [ ] Next word: type the same phrase 3 times (e.g. "see you at the gym", or an Arabic one), each followed by a space. Then type its first words: the next word appears in the bar.
- [ ] A word imported from WhatsApp, or added or forgotten in the app, shows up (or disappears) the next time the keyboard opens.
- [ ] With Pause Learning on, a new word typed twice in two sessions is still not suggested.

**Latency and memory (Console.app: "footprint ... headroom" on each open, "session: N requests, p95 X ms" on dismiss)**

- [ ] While typing quickly, the latency stays under about 12 ms most of the time, and never above 20 ms. Note the usual value: ____ ms.
- [ ] Note footprint and headroom on first open (EN) ____ / ____, after switching to Arabic ____ / ____. Headroom must stay above 10 MB.
- [ ] 20 show/hide cycles across Notes, Messages and WhatsApp: MB grows by less than 2 MB. Start ____ MB, end ____ MB.
- [ ] Optional: Console.app, subsystem `com.morad.kalam.keyboard`, shows "session: N requests, p95 X ms" after each dismiss.

**Robustness**

- [ ] With Full Access off: the banner shows, typing still works with no autocorrect, and nothing crashes.
- [ ] Type in an app, switch to another app mid-sentence, and come back a minute later: no crash, and the keyboard still suggests (0xdead10cc).
- [ ] Settings changed in the app (autocorrect off, Eastern Arabic digits, digit hints) apply the next time the keyboard opens. With Eastern digits on, the Arabic 123 page and hints show ١٢٣.
- [ ] Long-press i, o, s, y, z and l on the EN page: the accents match Apple's.

## Phase 6: host app

Setup: install a Debug build. Keep one WhatsApp `_chat.txt` in Files (extract the zip there first).

- [ ] Setup shows "Kalam is added" once the keyboard is added. (The simulator can't read this, so it stayed hidden there.)
- [ ] Open Settings lands on Kalam's page, with Keyboards and Allow Full Access.
- [ ] Import a real `_chat.txt`:
  - "Mohamed Morad" is preselected and the message counts look right;
  - the result appears;
  - the "no base word lists" warning is absent.
- [ ] A big chat (10k+ messages) imports without freezing the app, and switching apps during the import doesn't kill it.
- [ ] Learned Words: EN and Arabic lists, search, swipe to forget or block, add a word. Arabic rows read right to left.
- [ ] Export Backup to Files, then Reset Learning, then Restore from that backup: the words come back.
- [ ] Restoring a random file shows "This file isn't a Kalam backup." and keeps your data.
- [ ] Change a setting in the app; the keyboard follows it the next time it appears (needs Phase 5).
- [ ] Leave the app in the background for a minute while you type in another app: no crash (0xdead10cc).

## Clipboard (SPEC 5.5)

Setup: install a Debug build with Full Access on, and Kalam > Settings > Clipboard on (the default).

- [ ] Copy text in Safari, then open Kalam in Notes. Does iOS ask "Allow Paste"? The simulator does, and the keys freeze until it is answered. Set Settings > Apps > Kalam > Paste from Other Apps to Allow: the prompt stops. iOS may still show a small "Kalam pasted from …" banner at the top; say if it bothers you. Note what you saw: ____
- [ ] Right after copying in another app, the bar's middle slot shows "📋" and the clip's first line. A tap pastes it, and the chip goes away. Copy again and type a letter instead: the chip goes too.
- [ ] The clipboard button sits at the bar's left edge in EN and AR. It reads like a toolbar glyph, not a key. It opens the panel at the keys' height (the keyboard doesn't grow), in light and dark; the bar becomes the header (selected button, "Clipboard", "Clear", "ABC"), and "ABC" and the button both go back to the letters.
- [ ] In the panel: a tap pastes the tile and the panel stays open. Long-press a tile: Pin moves it to the top with a pin mark, Unpin returns it, Delete removes it. "Clear" removes all but the pinned.
- [ ] An Arabic clip's tile is right-aligned.
- [ ] Copy something, wait an hour (or more), open the panel: unpinned items are gone, pinned ones are still there, also after restarting the phone.
- [ ] A long clip (a few paragraphs, then something over 10,000 characters): the long one pastes whole and its tile shows 3 lines; the over-long one isn't kept. Scrolling the panel stays smooth.
- [ ] A password copied from Passwords or a password manager doesn't show up.
- [ ] Copy something in another app, come back and type a few words without opening the panel: the chip appears within about a second of the next keystroke or cursor move, and typing stays as fast as before.
- [ ] Pasted words aren't learned: paste a made-up word, type space, and it isn't suggested later.
- [ ] Full Access off: no button, no chip, no prompt, nothing crashes.
- [ ] Clipboard setting off: no button and no chip; turn it on again and the pinned items are still there.
- [ ] Images: copy a photo in Photos (Share > Copy Photo), open Kalam in WhatsApp and open the panel. The photo's tile shows its thumbnail, with no chip in the bar. Copy some text, then tap the photo's tile: "Copied. Hold the text field and tap Paste." shows for about 2 seconds. Hold the message field, tap Paste: the photo arrives. Long-press the tile: Pin and Delete work as for text.
- [ ] Take a screenshot, tap Copy and Delete in its editor (or copy it from Photos): it shows up in the panel, and tapping it then pasting works the same.
- [ ] Copy 20 different photos one after another, opening the panel after each. With all 20 in the panel, scroll it up and down: the logged footprint stays low (note the number: ____ MB) and Kalam isn't killed.

## Device round 1

Setup: install a Debug build with Full Access on. Each run appends to the Debug trace, `<App Group container>/Library/Caches/kalam-trace.log` (the older half at `kalam-trace.1.log` once it passes 1 MB). Before each test, note the time; after it, the orchestrator pulls the file with devicectl.

- [ ] Fast two thumbs in Notes, EN: type "the quick brown fox jumps over the lazy dog" 3 times as fast as you can, with both thumbs. Count dropped letters ____ and swapped letters or spaces ("hit here" for "hi there") ____. Then the same 3 times on Apple's keyboard for a baseline ____.
- [ ] The same in AR with "انا رايح الشغل دلوقتي وراجع بالليل": dropped ____, swapped ____, Apple's baseline ____.
- [ ] Edge keys fast: alternate q and p (EN), then ض and ج (AR), 20 times each, as fast as you can. Every press lands, in order, with no lag next to the middle keys. Note any miss ____.
- [ ] Tashkeel: hold the ◌ً key (AR bottom row). The strip shows ◌ٓ ◌ٰ ـ ◌ْ ◌ِ ◌ُ ◌ّ ◌ً ◌َ ◌ٍ ◌ٌ with ◌ً selected; release without sliding types ً; slide to ◌ّ and release types ّ. The marks sit on dotted circles and the strip fits on the screen. Compare with Apple's.
- [ ] Height: switch between Apple's keyboard and Kalam in the same field. The panel top should match Apple's; Kalam's rows sit about 3.6 pt (1 mm) higher. Say if it still looks off ____.
- [ ] The bar at 40 pt: suggestions, dividers, the clipboard button and chip, the "Don't suggest" overlay and the clipboard panel header are not clipped.
- [ ] Haptics: at the max strength setting, compare a few taps with Apple's keyboard (Settings > Sounds & Haptics > Keyboard Feedback > Haptic on). Kalam should feel as strong and crisp or stronger. Too strong? ____
- [ ] Sounds: at the same ringer volume, Kalam's key, delete and modifier clicks are louder than Apple's but the same character. The silent switch mutes them. Too loud? ____

## Phase 8: Gboard gestures

Setup: install a Debug build. Test in Notes, EN and AR.

- [ ] Backspace swipe: type "one two three four", put the finger on backspace and slide left slowly. About every finger-width (22 pt) one more whole word goes, with a delete click per word. Slide back right: the words come back in order. Back to the start point: the text is exactly as before the touch. Release mid-way: the result stays. Too sensitive or too slow? ____
- [ ] Backspace swipe in the middle of a word ("hello wor", cursor at the end): the first step deletes "wor" whole. Then type a new word: suggestions and autocorrect behave normally.
- [ ] Hold backspace until it repeats, then slide left: the repeat stops and words go instead. Plain tap and hold-repeat still behave as before.
- [ ] Right after an autocorrect (typed "teh " became "the "), a backspace swipe: no crash, words go, and the text looks right.
- [ ] Slide from shift: with shift off, put the finger on shift, slide onto "h", release: "H", and shift is off after. Release on shift itself: shift toggles as a plain tap. With caps lock on: the letter is capital and caps lock is off after (say if you'd rather keep it) ____.
- [ ] Slide from 123: put the finger on 123 (the numbers page shows at once), slide onto "5", release: "5" is typed and the letters page returns. Same from ١٢٣ in AR. A plain tap on 123 still just switches. From the 123 page, slide from #+= onto "%": typed, back to the 123 page.
- [ ] Swipe down to hide: a quick, straight swipe down starting on a top-row or middle-row letter hides the keyboard and types nothing. A slow drag, a diagonal drag, or a swipe starting on z..m does not.
- [ ] Fast two-thumb typing for a minute in EN and AR: the keyboard never hides by itself, no letters missing. Long-press strips (hold "e" and pick an accent) never hide it.
- [ ] Rollover, slide between letters, long-press strips and the space trackpad all feel exactly as before.

## Phase 9: emoji (SPEC 5.6)

- [ ] The face button sits right of the clipboard button in EN and AR, and also shows with Full Access off (then at the left edge, the banner beside it).
- [ ] Tap it: the keys give way to the emoji grid, same height, 5 rows, starting at Smileys & People (or Recents once you have some). Light and dark mode both look right.
- [ ] Scroll sideways: smooth, and the header name and highlighted strip icon follow the category at the left edge. Tap each strip icon: it jumps to that category.
- [ ] Tap a few emoji in WhatsApp: each one is inserted, the panel stays open, each tap clicks and buzzes like a key. Reopen the panel: they lead Recents, newest first.
- [ ] Backspace in the strip deletes one emoji per tap (not half of one); holding it repeats, then goes word by word, like the key.
- [ ] ABC, or the face button again, returns to the letters. The clipboard button while the emoji panel is open switches straight to the clipboard panel.
- [ ] Any emoji that draws as an empty box or a "?" (the phone lacks it) ____.
- [ ] Type "pizza", "love", "coffee", "قهوة", "حب": the bar offers the emoji in the right slot (left slot in Arabic). Tap it: the word becomes the emoji plus a space. Type "teh pizza": the emoji is never put in on space by autocorrect.
- [ ] Long-press the emoji slot: no "Don't suggest" overlay. Note any word whose emoji pick looks wrong next to Apple's ____.
- [ ] Memory: open the panel and fling through all categories twice. The logged footprint ____ MB, and Kalam isn't killed.

## Phase 10: lost keystrokes

Setup: install a Debug build with Full Access on. Test in Notes unless a step says otherwise.

- [ ] Fast two thumbs, EN: type "the quick brown fox jumps over the lazy dog" 3 times as fast as you can. Dropped letters ____, swapped letters or spaces ____. Same in AR with "انا رايح الشغل دلوقتي وراجع بالليل": dropped ____, swapped ____.
- [ ] Slow space: type "hi", then press and hold space for about half a second without moving, and release. A space is typed (the key labels may hide while you hold). Hold and slide sideways: the cursor moves and no space is typed. Slide a little, then back, without the cursor moving: say what happens ____.
- [ ] Low bar taps right after typing: type "hel" and, within a blink, tap the middle suggestion near its bottom edge. Note whether a top-row letter was typed instead ____ (expected mid-typing: the letter).
- [ ] Low bar taps after a pause: type "hel", wait a second, tap the middle suggestion near its bottom edge: the suggestion is picked, no letter. Same for the clip chip (copy some text first, then tap the chip low in an empty field). Top-row taps mid-typing still land as before; any lost ones ____.
- [ ] Slow presses, AR: press and hold ض, ص, ه and ح for about half a second and release without sliding. Each types its letter, never a digit. The strip shows the digit and the letter, with the letter selected; slide onto the digit and release types the digit.
- [ ] Slow presses, EN with digit hints on: holding q types 1 and holding e types 3 (the digit is drawn, so it's selected). With digit hints off (host app setting): holding q types q and holding e types e; the strip still offers the digit.
- [ ] Cancels: while typing a word, pull down a notification banner (or have one arrive) or start the home-bar swipe mid-tap. The letter under the finger is typed (or say if it isn't) ____. A long-press strip that gets cancelled types nothing.
- [ ] Trackpad in mixed text: in "hello مرحبا world" put the cursor inside "hello" on the AR layout and drag right on space: the cursor moves right. Put it inside "مرحبا" on the EN layout and drag right: the cursor moves right on screen too. Note any part where it goes the wrong way ____.
- [ ] Undo after punctuation: type "teh," : it shows "the,". Backspace deletes the ","; the next backspace turns "the" back into "teh". Same with "teh." , "teh?" , "teh!" and "teh" + return. Then type "teh," again: it is not corrected this time.
- [ ] Undo after a space then punctuation: type "teh" + space (shows "the ") then ",": shows "the, ". Backspaces go " ", then ",", then "the" becomes "teh".
- [ ] Holding backspace after "the," deletes characters normally (it doesn't revert "the" mid-repeat).

## Phase 11: autocorrect you can trust

Setup: install a Debug build with Full Access on, autocorrect normal in EN. Test in Notes unless a step says otherwise. Use made-up words that aren't in your store yet (say "teh", "tgem").

- [ ] Retype after deleting a correction: type "I saw teh " (shows "the "), type "cat", then backspace through "cat", the space and "the". Type "teh" + space: it stays "teh", and the bar showed no bold suggestion while you typed it. Type "teh " again later in a new sentence: never corrected again.
- [ ] Same with the backspace swipe: type "I saw tgem " (shows "them "), swipe back over that word, retype "tgem" + space: it stays.
- [ ] Tap to revert in Notes: type "I saw teh cat " ("the cat"). Tap right after "the" (between "e" and the space): the middle slot shows “teh”. Tap it: "the" becomes "teh", no extra space, the cursor stays right after it. Tap inside "the" (between "t" and "h"): same result. Long-press the “teh” slot: no "Don't suggest".
- [ ] Tap to revert in WhatsApp: same steps in a chat. Does the slot appear ____? Is the whole word replaced, with nothing left over or deleted from the next word ____?
- [ ] A word used twice stays: type a made-up word like "kalamo" + space twice in the same chat (not corrected the first time? note it ____). From then on it is never corrected, even in a new session the same day.
- [ ] URLs and domains: in a normal text field, type "www.goo" + space, "a/b " , "e.g " , "x@y " and "😂teh ": none of them changes.
- [ ] Mixed script: type "helloمر" + space (switch layouts mid-word): it stays as typed.
- [ ] Names mid-sentence: type "I met Jphn " with shift pressed for the "J": it stays "Jphn". "Teh " at the start of a sentence (auto-shift) still becomes "The ".
- [ ] Ambiguous contractions stay: type "its ", "were ", "well ", "ill ", "lets ": none changes, and "it's", "we're", "we'll", "I'll", "let's" show in the bar while you type them.
- [ ] Contractions still fix: "im " becomes "I'm ", "dont " becomes "don't ", "cant " becomes "can't ", also mid-sentence with shift ("Im " → "I'm ").
- [ ] Short words: note any 2 or 3 letter typo you expected to be fixed that now stays ____ (the stricter margin).
- [ ] Mid-word suggestion tap: type "hello world", put the cursor between "hel" and "lo", tap a suggestion (say "help"): the whole word becomes "help", with no leftover "lo" and no double space before "world". Try it in Notes, WhatsApp and Messages: any host where the wrong characters go ____ (whether hosts count the cursor move in characters, as the keyboard assumes, is device-only). Try it in Arabic too ____.
- [ ] Predictions never show a one-off typo: type "see yuo " once, then later type "see " and look at the bar: "yuo" never shows (it may after you use it twice in two sessions).

## Phase 12: touch model

Setup: install a Debug build with Full Access on, autocorrect normal. Test in Notes unless a step says otherwise. The tap offset is now -0.13 key units (7 pt up), and each key learns its own offset from words you commit and don't revert.

- [ ] Trace before: first thing after installing, type a few normal EN and AR messages (2 to 3 minutes each), then tell the orchestrator to pull `kalam-trace.log` with devicectl. It runs `kalam-cli tapmap --lang en --trace kalam-trace.log` and the same with `--lang ar`. Mean dy EN ____ key units (____ pt), AR ____ (____ pt).
- [ ] Use Kalam normally for a few days. Then back up the store (host app, Data, Backup) and send the file. The orchestrator runs `kalam-cli tapmap --lang en --personal <backup>` and `--lang ar`. Learned all-keys dy EN ____, AR ____; keys with the most taps ____; any key whose effective offset looks odd (sideways, or at the 0.3 cap) ____.
- [ ] Trace after: the same 2 to 3 minutes of typing as before, pulled and run through tapmap again. Mean dy EN ____, AR ____. Count the corrected letters (backspaces inside a word) in both traces: before ____, after ____.
- [ ] Feel of the top row: type "quiet", "power", "type", "ضحك", "صحيح" fast. Wrong letters from the row below or from the bar ____. Edge keys: "zap", "plop", "quip", and AR ض, ج, ش, ة, ى words: wrong letters ____.
- [ ] Taps that land low: type with your thumb deliberately a bit low on the bottom letter row ("zxcvbnm" words like "bacon", "venom"). Does anything get worse than before ____?
- [ ] A habitual swap gets fixed: pick a one-letter slip you make often (say "tha" for "the", a far-apart pair). Each time, delete the wrong word and type the right one within 10 s, for two different words with the same slip (e.g. "tha" then "the", "sha" then "she"). After that, the same slip in a third word is corrected (or is first in the bar) ____.

## Phase 13: Arabic and code-switching

Setup: install a Debug build with Full Access on, autocorrect normal, your WhatsApp chats imported. Test in Notes unless a step says otherwise.

- [ ] Script of the bar with mixed context: on the AR layout, type "ok " then start an Arabic word ("ان"): every slot is Arabic. Switch to EN and type "hab" right after an Arabic word: every slot is Latin. Empty word after "hello " on the AR layout: the 3 predictions are Arabic. Any slot in the wrong script ____.
- [ ] Wrong layout, AR word on the EN page: on the EN layout, type السلام by where its letters sit on the Arabic page (the keys "gfafgk"). Before space, the right slot shows السلام. Tap it: "gfafgk" becomes "السلام " and the layout stays EN. Then شكرا ("albg") and 2 words of your own, typed by feel: rescued ____, not rescued ____.
- [ ] Wrong layout, EN word on the AR page: on the AR layout, type "hello" by where its letters sit on the EN page (تثككح). The left slot (alt2 in Arabic) shows "hello"; tap it: replaced, layout stays AR. Later, on the EN layout, "hel" offers hello as usual (learned as English).
- [ ] No false rescues: type normal EN and AR for a few minutes. An Arabic word in the EN bar (or the reverse) while you were typing a real word ____ (write the word).
- [ ] Rescue next to an emoji: on the EN layout, type a word that has an emoji and is an Arabic word by position, if you find one ____; the emoji keeps the right slot and the rescue moves to the left.
- [ ] Franco: type "3ashan", "7aga", "ma3lesh" (digit by long-press) + space: none changes. Type "3as": 3ashan shows in the bar (once your import holds it). Type a slip "3ashsn" + space: it stays as typed.
- [ ] ة/ه in the slot: type "مدرسه": مدرسة shows in a slot (the right one if it isn't already in the bar), and space keeps "مدرسه". Same for "انا" (أنا in a slot) and "علي" / "على". Note any where the other spelling never shows ____.
- [ ] Sentence-start bar: at the start of a new note, type "hel": the middle slot shows ____ (help or hello expected, not "he"). On the AR layout at the start, type "انا": the middle slot shows ____ (انا expected, not أما).
- [ ] Backspace on tashkeel: type "مُحَمَّد" with the marks (long-press), then press backspace once: only the last mark (or the last letter if it has none) goes ____. Put the cursor after "مَ" and press backspace: the mark goes and م stays ____.
- [ ] Lam-alef: type "لا" (ل then ا), then press backspace once: "ل" stays ____. Same in WhatsApp and Messages ____.

## Phase 14: text polish (side by side with Apple's keyboard)

Setup: install a Debug build with Full Access on, autocorrect normal, double-space period on, auto-capitals on. Do each step in Notes on Kalam, then the same keystrokes on Apple's keyboard, and note where Apple differs.

- [ ] Space before punctuation: type "hello" + space + "," then "ok" + space + "?". Kalam gives "hello, ok? " ____. Apple gives ____. With the double-space period off, type "hello" + 2 spaces + ",": both spaces stay. Type "hello" + space + ":": the space stays.
- [ ] Space after a suggestion: type "hel", tap "hello" in the bar, then space: still one space ("hello "). Space again: "hello. " ____. Apple, tapping a suggestion then space twice ____.
- [ ] Space after punctuation: type "ok." (Kalam shows "ok. "), then space, then space: "ok.  " with no second period ____. Apple ____.
- [ ] Quotes after a suggestion: tap a suggestion for "said", then type `"`: the space stays (`said "`). Type "hi", tap a suggestion, then `"`: it closes with no space before it (`said "hi"`). Apple ____.
- [ ] Apostrophe after a suggestion: tap "Moe" from the bar, then `'` and "s": "Moe's" ____.
- [ ] Capitals after closing quotes: type `He said "hi."` + space: shift turns on. Same for `(done.)` + space and `really?"` + space ____. Apple ____.
- [ ] Caps-lock bar: double-tap shift, type "hel": every slot is in capitals (HELLO, HELP), and an empty word shows all-caps predictions. Tap one: it goes in all caps. Type "TEH" + space in caps lock: becomes "THE" ____. Apple ____.
- [ ] Shift held: hold shift with one thumb and type "nasa" with the other: "NASA". Lift shift: the next letter is lowercase ____. Hold shift with no letters and lift: one capital follows (a plain tap). Double-tap for caps lock, then hold shift (that turns it off) and type: capitals until you lift. The slide from shift onto a letter still types one capital ____. Apple ____.
- [ ] Backspace speed: hold backspace on a long paragraph. It starts after about half a second, speeds up, then switches to words after about 1.7 s. Lift as soon as you see words going: how many words too many went ____? Apple: how many too many ____? Same with the emoji panel's backspace ____.
- [ ] Trackpad speed: hold space and drag slowly: about one character per 9 pt, as before. A fast flick across the bar moves much further (about 2.5 times). Can you land on a given letter in a long line ____? Apple ____.
- [ ] Bar touch feedback: press a suggestion slot and hold: it highlights and you feel the key haptic and hear the click at once; the word goes in on release. Long-press still opens "Don't suggest". Press the clip chip: same feedback. The highlight clears on release every time (none left stuck) ____. Apple ____.

## Phase 15: comfort settings

Setup: install a Debug build with Full Access on. Change the settings in the Kalam app (Settings, Typing), then switch to the host app and bring the keyboard up again.

- [ ] Each height in Notes and in WhatsApp, number row off (Compact, Default, Tall): no key or bar clipped, the suggestion bar fits, the clipboard and emoji panels open and fill the key area, and iOS's ~75 pt globe strip still sits below the keys. Total keyboard height (top of the bar to the top of the strip) at Compact ____ pt, Default ____ pt, Tall ____ pt (expected 241.4 / 257.4 / 273.4).
- [ ] Typing feel: type a paragraph at Compact and at Tall. Typos compared with Default: Compact ____, Tall ____. Top-row and bottom-row taps still land (q, p, space, return) ____.
- [ ] Number row on, at each height: the keyboard is 30 / 34 / 38 pt taller than with it off ____. Total height at Compact ____ pt, Default ____ pt, Tall ____ pt (expected 271.4 / 291.4 / 311.4). The 123 and #+= pages keep the same height (bigger keys), with no jump when switching pages ____.
- [ ] Number row digits: tap 1 to 0 on EN: each types its digit with a popup, fast rollover across digits and letters works ____. The q row draws no digit hints, and holding q types nothing extra (no strip); holding e still shows the accents ____.
- [ ] Arabic number row: with Eastern Arabic digits off, the AR page's row types 1 to 0; on, ١ to ٠, left to right like Apple's 123 page ____. Holding ض shows no digit strip ____.
- [ ] Words after a digit: type "3ashan" with the number row's 3, and "2day": autocorrect leaves them alone as before ____.
- [ ] Switching settings: with the keyboard open in Notes, go to the Kalam app and change the height or the number row, then come back to Notes: the change shows the next time the keyboard appears (not before) ____. Digit Hints is greyed out in Settings while the number row is on.

## Device round 3: lost keystrokes

Setup: install a Debug build with Full Access on. Test in Notes, then WhatsApp, EN then AR. The Debug trace now also logs bar touches ("bar touch at x,y slot n") and trackpad starts.

- [ ] Sloppy space: type "hello world how are you" 3 times fast with two thumbs, hitting space with a slight sideways flick. Every space arrives ____. The key labels may blink on a flick that slides far; say if that bothers you ____.
- [ ] Two thumbs over a slid space: in "hi there", let the space thumb slide a little while the other thumb starts "there". It gives "hi there", never "hit here" ____.
- [ ] Trackpad still works: hold space and drag, or drag sideways right away: the cursor moves and no space is typed. A short slide that never moves the cursor types a space ____.
- [ ] Top row after a pause: type "ok ", wait a second, then tap q, w, e, t, p aiming high, near the bar's bottom edge. Each types its letter unless it landed right under a suggestion (then the suggestion is picked, as before). A high tap on q or w no longer opens the emoji or clipboard panel ____. The emoji and clipboard buttons still open when tapped in their middle ____.
- [ ] If a keystroke still goes missing: note the time, the key, and whether it clicked and buzzed, then send `kalam-trace.log` ____.
