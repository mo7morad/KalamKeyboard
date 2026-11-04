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
