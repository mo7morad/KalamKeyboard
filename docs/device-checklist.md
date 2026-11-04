# Device checklist

Things only Moe's iPhone 17 can verify. Tick each one, and note anything that feels off in `docs/issues.md`.

## Phase 1: keyboard shell

Setup: install a Debug build, then Settings > General > Keyboard > Keyboards > Add New Keyboard > Kalam, and turn on Allow Full Access. Test in Notes, Messages and WhatsApp.

**Look (compare with `docs/reference/kalam/` and Apple's keyboard)**

- [ ] EN letters, 123 and #+= pages line up with Apple's: key sizes, gaps, corner radius, label sizes, light and dark.
- [ ] Arabic letters match `docs/reference/ar-letters-*.png`: ض at the far left, ج at the far right, the blank before delete in row 3, the tanween key, ١٢٣.
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
- [ ] With Full Access off: the bar shows "Turn on Full Access for learning, haptics and sounds", and nothing crashes.

**Memory (Debug overlay, red text at the top-left of the bar)**

- [ ] Note the MB and "free" readings on first open: ____ MB, ____ free.
- [ ] 20 show/hide cycles across 3 apps (Notes, Messages, WhatsApp): MB grows by less than 2 MB. Final: ____ MB.
- [ ] The latency field shows "– ms" (Phase 5 fills it).

## Phase 5: suggestions, autocorrect and learning

Setup: install a Debug build, turn on Settings > Debug Overlay in the Kalam app (red text at the top-left of the bar), and test in Notes, Messages and WhatsApp.

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

**Latency and memory (Debug overlay: "MB · free · ms")**

- [ ] While typing quickly, the latency stays under about 12 ms most of the time, and never above 20 ms. Note the usual value: ____ ms.
- [ ] Note MB and "free" on first open (EN) ____ / ____, after switching to Arabic ____ / ____. "free" must stay above 10 MB.
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
