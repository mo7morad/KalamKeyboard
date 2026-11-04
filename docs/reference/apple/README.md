# Apple keyboard reference (SPEC D6, §15)

Captured from Apple's own keyboards in the iOS Simulator on 2026-11-04. Phase 1 builds the layout JSON and the look from these files. Moe's real-device screenshot `moe-iphone17-en-letters-shifted-dark.png` is the ground truth for the EN look. The simulator matches it (see "Compared with Moe's iPhone").

## Device

- **Simulator:** iPhone 17 (UDID 561E7CD7-5D40-4978-8FB5-9C59E3F99ADB), portrait. This is Moe's model.
- **Runtime:** iOS 27.0 (24A5423a). The installed iOS 27.1 runtimes (24A94232, 24A94425) only support "iPhone Duo", so iOS 27.0 is the newest runtime that runs an iPhone 17.
- **Screen:** 402 x 874 pt at @3x, so the PNGs are 1206 x 2622 px. Divide pixel values by 3 to get points.
- **Keyboards:** `AppleKeyboards = (en_US@sw=QWERTY;hw=Automatic, ar@sw=Arabic;hw=Automatic, emoji@sw=Emoji)`, set in the simulator's global defaults, then a reboot. Locale is en_US, and the languages are en-US and ar. With these settings the Arabic 123 page shows Eastern Arabic digits (١٢٣).
- **Host field:** a `UITextView` with default traits (return key = `default`). The `*-nobar` files use `autocorrectionType = .no`, `spellCheckingType = .no` and `inlinePredictionType = .no`, which hide the suggestion bar.
- **Status bar:** overridden to 9:41.

## Files

Every capture has a `-light.png` and a `-dark.png` version.

| File | Shows |
|---|---|
| `en-shifted` | EN letters, auto-shift on (empty field), with the suggestion bar |
| `en-letters` | EN letters, lowercase (shift tapped off) |
| `en-123` | EN 123 page |
| `en-symbols` | EN #+= page |
| `en-letters-nobar` | EN letters with the suggestion bar hidden |
| `ar-letters` | AR letters (the bar shows predictions for an empty field) |
| `ar-123` | AR 123 page |
| `ar-symbols` | AR #+= page |
| `ar-letters-nobar` | AR letters with the bar hidden |
| `popup-e`, `popup-a`, `popup-u`, `popup-n`, `popup-c` | EN long-press alternates |
| `popup-i`, `popup-o`, `popup-s`, `popup-y`, `popup-z`, `popup-l` | More EN alternates (Phase 5, light only, cropped to the keyboard top; `Tools/screenshot-harness/UITests/Accents.swift`) |
| `popup-alef`, `popup-yeh`, `popup-waw`, `popup-heh` | AR long-press alternates for ا ي و ه |
| `popup-kaf` | AR ك held down. It turned out to have an alternate (گ). |
| `popup-tashkeel` | AR tanween key ◌ً held down: the tashkeel strip (device round 1, light only, cropped to the keyboard) |
| `keypress-f` | Key-press preview bubble: finger down on `f`, which has no alternates |
| `keypress-q` | Key-press preview on the left edge key `q`. The bubble is clipped to the screen edge, not shifted. |
| `suggestions-en` | Next-word predictions after "I am going to the " (store, gym, grocery) |
| `suggestions-en-typing` | Bar while typing (light: "I am going to the sto") |
| `suggestions-ar` | Predictions after "انا رايح " (light: من، مصر، في) |
| `moe-iphone17-en-letters-shifted-dark.png` | Moe's real phone (do not modify) |

Notes on the files:

- The long-press popups were taken on a field that already held earlier test input. The text in their suggestion bars ("eaunc", "Eauncqbfqbf", and so on) is leftover junk. Ignore it.
- In `popup-e-dark` the shift key is drawn highlighted, but the letters are lowercase.

`Tools/screenshot-harness/` holds the XcodeGen app, the UI test and the stdlib-Python measuring scripts used here. `Tools/screenshot-harness/dumps/*.txt` are the XCUITest element trees for each page, with exact key hit-frames and accessibility labels. To recapture, set `base` in `Tools/screenshot-harness/UITests/Capture.swift` to a writable folder, run `Tools/screenshot-harness/watcher.sh` from that folder, and run the `Capture` tests once per appearance (`xcrun simctl ui <udid> appearance light|dark`, written into `mode`). On a headless simulator, the app calls the KIF private-API trick (`forceSoftwareKeyboard`). Without it, iOS acts as if a hardware keyboard is attached and hides the on-screen keyboard.

## iOS 27 look (important differences from older iOS)

- The keyboard is a rounded panel ("glass" style). Its top corners have a radius of about 26 pt, and its bottom corners follow the display's corners. A 1 pt lighter rim runs along the top edge.
- **All keys use the same color.** Shift, delete, 123, emoji, space and return are not a darker "special" gray. This holds in light and dark mode, on every page and in both languages.
- Face ID layout:
  - Bottom key row: `[123] [emoji] [space] [return]` (AR adds a tanween key).
  - Below the keys sits a separate strip with the globe (left) and dictation mic (right). These are system controls, not keys.
  - Our SPEC §5.2 bottom row `[123] [EN/AR] [space] [return]` replaces the emoji key with EN/AR. Apple puts emoji there.
- The space bar has no label. A small grey language hint sits in its bottom-right corner: "A" for EN, "ع" for AR.
- The return key is an icon: ⏎ for EN, and a mirrored arrow for AR. Delete is the ⌫ "x in a tag" icon. Shift is an arrow outline, filled when shift is on.

## Layouts

Rows are listed in **visual left-to-right order**, as seen on screen (including Arabic). Widths are relative, with 1.0 = one letter key *pitch* (key plus its share of the gap). The visual cap is `width x pitch - 6.33 pt`.

### EN letters (en-letters / en-shifted)

Letter pitch 39.33 pt.

```
row 1: q w e r t y u i o p                                 (10 x 1.0)
row 2: a s d f g h j k l                                   (9 x 1.0, indented 0.5 on each side)
row 3: shift(1.30) [gap 0.20] z x c v b n m [gap 0.20] delete(1.31)
row 4: 123(1.25) emoji(1.25) space(5.02) return(2.52)
```

When shifted, the labels are uppercase. With the field empty, the shift glyph is filled (auto-shift).

### EN 123 (en-123)

```
row 1: 1 2 3 4 5 6 7 8 9 0                                 (10 x 1.0)
row 2: - / : ; ( ) $ & @ ”                                 (10 x 1.0)
row 3: #+=(1.30) [gap 0.20] . , ? ! ’ [gap 0.20] delete(1.31)  (the 5 punctuation keys are 1.41 each)
row 4: ABC(1.25) emoji(1.25) space(5.02) return(2.52)
```

### EN #+= (en-symbols)

```
row 1: [ ] { } # % ^ * + =
row 2: _ \ | ~ < > € £ ¥ •
row 3: 123(1.30) [gap] . , ? ! ’ [gap] delete(1.31)     (1.41 each, as on 123)
row 4: ABC(1.25) emoji(1.25) space(5.02) return(2.52)
```

### AR letters (ar-letters)

11 keys per row. Arabic letter pitch is 36.0 pt (0.915 of an EN key). The widths below use 1.0 = one **Arabic** letter key (36 pt).

```
row 1: ض ص ث ق ف غ ع ه خ ح ج                               (11 x 1.0)
row 2: ش س ي ب ل ا ت ن م ك ة                               (11 x 1.0)
row 3: ء ظ ط ذ د ز ر و ى [blank 0.60] delete(1.40)         (9 x 1.0; delete is at the right edge, as in EN)
row 4: ١٢٣(1.37) emoji(1.37) space(4.11) tanween ً (1.37) return(2.75)
```

Notes:

- The row 4 frames are the same as EN apart from the space split. In EN units: 123 1.25, emoji 1.25, space 3.76, ً 1.25, return 2.52.
- The tanween key's label is `ً` (U+064B fathatan), drawn on a dotted circle.
- Ar has **no shift key** and no shifted page.
- ض is at the far left, and ج at the far right.
- ة, ى and ء each have their own key.

### AR 123 (ar-123)

Same geometry as EN 123.

```
row 1: ١ ٢ ٣ ٤ ٥ ٦ ٧ ٨ ٩ ٠
row 2: - / : ؛ ( ) $ & @ ”
row 3: #+=(1.30) [gap] . ، ؟ ! ’ [gap] delete(1.31)
row 4: ابج(1.25) emoji(1.25) space(5.02) return(2.52)
```

The letters key is labeled "ابج". The parentheses carry a U+200E LRM prefix in their AX labels.

### AR #+= (ar-symbols)

```
row 1: [ ] { } # ٪ ^ * + =        (the percent key is U+066A ٪)
row 2: _ \ | ~ < > € £ ¥ •
row 3: ١٢٣(1.30) [gap] . ، ؟ ! ’ [gap] delete(1.31)
row 4: ابج(1.25) emoji(1.25) space(5.02) return(2.52)
```

## Long-press alternates (visual left-to-right, [x] = the base letter, highlighted on open)

On iOS 27 the alternates open as a single rounded strip above the key, with the base letter already selected. If you release without sliding, the base letter is typed.

| Key | Alternates, left to right |
|---|---|
| e | ë é [e] è ê ě ẽ ē ė ę |
| a | Two rows. Top: æ ã å ā ă ą. Bottom: [a] à á â ä ǎ |
| u | ų ů ű ũ ü ú ù [u] û ǔ ū |
| n | ň ṇ ń ñ [n] |
| c | [c] ç ć č ċ |
| k | ķ [k] (seen in an exploration run) |
| ا | آ إ أ [ا] (in RTL reading order: ا أ إ آ) |
| ◌ً | ◌ٓ ◌ٰ ـ ◌ْ ◌ِ ◌ُ ◌ّ [◌ً] ◌َ ◌ٍ ◌ٌ: maddah U+0653, superscript alef U+0670, tatweel U+0640, sukun, kasra, damma, shadda, fathatan, fatha, kasratan, dammatan (U+0652 U+0650 U+064F U+0651 U+064B U+064E U+064D U+064C). Read from the image; the second mark is a short vertical stroke, so superscript alef, not hamza above. |
| ي | [ي] ئ |
| و | ؤ [و] |
| ه | هـ [ه] (the alternate looks like ه with a tatweel, the initial form. The exact code points weren't readable from the image.) |
| ك | گ [ك] |
| q, b, f | none (these show the key-press preview instead) |

Notes:

- The alternates were read from the images. Where two glyphs look alike (ṇ, ẽ, ǎ, ǔ), check against a device if it matters.
- Compared with SPEC §5.1, Apple does **not** offer ء under ا, ى under ي, or ة under ه. Each of those has its own key on Apple's layout. Our extra alternates are a Kalam choice, not Apple behavior.

## Metrics (points, iPhone 17, portrait)

Measured from the PNGs with `Tools/screenshot-harness/scan.py`, `corner.py`, `glyph.py` and `colors.py`, and checked against the XCUITest frames.

**Heights**

- Keyboard with the suggestion bar: **328 pt** (panel top y=546 to the screen bottom at 874).
- Keyboard without the bar: **301 pt** (panel top y=573). The keys don't move. Only the panel's top edge drops by 27 pt.
- Inside the 328 pt (y from the panel top):
  - 0 to 44: suggestion bar, three 134 pt slots.
  - 44 to 270: key area, 226 pt (the `Keyboard` element, y 590 to 816).
  - 270 to 328: bottom strip with globe and mic, 58 pt. The globe hit-frame is 68 x 69 pt, centered at about (42, 840) on screen.

**Keys**

- Row pitch (hit rows): **54 pt**. Rows start at y=597 (7 pt below the top of the key area).
- Key cap height: **42.3 pt**. The cap is inset about 1.3 pt from the top of its 54 pt hit row.
- Vertical gap between caps: **11.7 pt**.
- EN key width pitch: **39.33 pt** (alternating 39.3 and 39.7 hit widths). The cap is **33.0 pt** wide.
- AR letter pitch: **36.0 pt**, with a cap of about **29.5 pt**.
- Horizontal gap between caps: **6.3 pt**.
- Side margin: the first cap starts at x=7.0 and the last ends at 395.3, so about 7 pt on the left and 6.7 pt on the right.
- In EN row 3 the gap between shift and z (and between m and delete) is 14.3 pt.
- Cap x-positions (EN letters):
  - Row 1 starts at 7.0, then steps by 39.33.
  - Row 2 starts at 26.7.
  - Shift cap is 7.0 to 51.7, and delete is 350.3 to 395.3.
  - Bottom row caps: 123 7.0 to 49.7, emoji 56.3 to 99.0, space 105.7 to 296.3, return 303.0 to 395.3.
- Key corner radius: **about 8 pt**. The edge profile looks like a continuous ("squircle") curve, so use `cornerCurve = .continuous`.
- No key shadow is visible in either mode.

**Fonts** (estimated from ink height, SF Pro)

- Uppercase letter labels: **about 22 pt**. The cap height of H is 15.3 pt, ÷ 0.705.
- Lowercase labels look larger: x-height 13 pt ÷ 0.53 gives **about 24 to 25 pt**. Apple probably uses a bigger size for lowercase. Match it visually.
- Arabic alef: ink is 15.3 pt tall.
- Suggestion bar text: **about 17 pt** ("The" has a cap height of 12.3 pt).
- 123, ABC and similar labels are smaller, about 16 to 17 pt.

**Colors**

| | Light | Dark |
|---|---|---|
| Keyboard background (panel, bar and bottom strip) | `#E2E3E8` (the top of the bar fades to `#E5E6EB`) | `#202020` |
| Letter key | `#FFFFFF` | `#444444` |
| Special keys (shift, delete, 123, emoji, space, return, ً) | `#FFFFFF` (same as letters) | `#444444` (same as letters) |
| Key label / icons | `#000000` | `#FFFFFF` |
| Suggestion text | `#4A4A4C` | `#A2A2A2` |
| Suggestion divider (1 pt) | `#D3D4D9` | `#313133` |
| Key while pressed | `#DCDCDC` | `#676767` |
| Alternates strip / key-press bubble | `#FFFFFF` | `#353535` strip, `#565656` bubble |
| Panel top rim | about `#EAEBF1` | about `#303030` to `#3E3E3E` |

**Popups**

- The alternates strip is about 68 pt tall, with its bottom just above the key's row.
- The key-press bubble for `f` is about 58 pt wide (68 pt including its soft edge). It covers the row above, and its glyph is about 1.35x the key's glyph.

## Compared with Moe's iPhone (moe-iphone17-en-letters-shifted-dark.png)

The file was rescaled at 2.9453 px/pt and compared with `en-shifted-dark`.

**Same as the simulator, within the error of the downscale:**

- Key positions (all rows within 0.3 pt).
- Row pitch (54), cap height (42), gaps (6 and 12), bottom-row widths and keyboard height.
- Corner radius (7.7 vs 7.9 pt measured).
- Colors: keys `#454545` vs `#444444`, background `#212121` vs `#202020`, labels `#FFFFFF`. All keys share one color, as in the simulator.
- Fonts: H ink 15.3 pt in both, Q 17.3 pt in both.
- Globe and mic strip, emoji key, and the "A" hint in the space bar.

**Differences:**

1. **Suggestion bar leading icon slot.** On the device, the bar starts with a round icon slot (about 0 to 59 pt, icon centered near x=30; it looks like Apple's writing-tools or "Intelligence" glyph). The three word slots follow at about 59 to 174, 174 to 288 and 288 to 402 pt (about 114 pt each). The simulator has no icon, so its slots are 134 pt each. Kalam has no such feature, so the decision is to use 3 equal slots. If Moe wants it to look identical, reserve about 59 pt on the leading side.
2. Moe's host app (Claude) draws its own dark UI above the keyboard. That doesn't affect the keyboard.
3. The bar text is slightly lighter on the device (`#AFAFAF` vs `#A2A2A2`). This is probably resampling, and possibly the device's bar text weight.

## Not captured, and why

- **Device-only:** the key-press/alternates timing, haptics and sounds can't be seen in screenshots.
- **Caps-lock state, the emoji keyboard, and the globe long-press list:** not requested, so skipped.
- **Return-key variants** (Go, Search, Send): not captured. The default field only shows the ⏎ icon.
- **Exact Unicode of the هـ alternate and of the look-alike accent glyphs:** read visually. An AX dump during the hold wasn't possible, because the test thread is blocked while it holds the key.
- **Western-digit AR 123:** Apple's setting for Arabic digits wasn't explored. The default with the `ar` keyboard is Eastern Arabic digits.
- **The iPhone 18 Pro was dropped:** the orchestrator redirected the capture to Moe's iPhone 17. A temporary 18 Pro simulator I created was deleted.
- The iPhone 17 simulator was left with the EN+AR keyboards installed (useful for later comparisons). Its status bar override was cleared, and its appearance was set back to light.
