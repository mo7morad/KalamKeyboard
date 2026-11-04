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
