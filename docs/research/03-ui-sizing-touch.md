# Research 3: UI sizing and touch behavior (2026-11-04)

21 searches. **Apple publishes no keyboard key dimensions**, so the Apple values below are community and screenshot estimates. Measure a screenshot of the iOS 27 system keyboard on the iPhone 17 (402 pt wide, @3x) before tuning further. At 460 ppi and @3x, 1 pt is about 0.166 mm.

## 1. Recommended dimensions

| Item | Recommendation | Apple (approx.) | Basis |
|---|---|---|---|
| Row pitch | 54 pt (9.0 mm) | about 54 pt | Errors stop improving at 9.6 mm for serial thumb taps ([Parhi, MobileHCI'06](https://www.telerik.com/docs/default-source/blogs-docs/parhi-mobilehci06-pdf)) |
| Key visual height | 42 to 44 pt | about 42 to 43 pt | Leaves a vertical gap of about 11 to 12 pt |
| Key visual width | (402 − 2×3 − 9×6)/10 ≈ 34 pt | same idea | 5.6 mm is well under 9.6 mm, so the decoder has to make up for it |
| Horizontal gap | 6 pt | 6 pt | Visual only; hit areas tile the gaps |
| Corner radius | about 8 to 9 pt | about 5 pt before iOS 26, rounder in iOS 26 Liquid Glass | iOS 26 keyboard redesign ([Tom's Guide](https://www.tomsguide.com/phones/iphones/ios-26-is-still-proving-divisive-with-users-months-after-it-launched-and-i-think-i-know-why)) |
| Letter label | SF Pro 22 to 23 pt, Regular (Light looks thin on glass) | about 22.5 pt | Arabic needs a larger optical size, about 24 to 26 pt |
| Popup | key width + 12 pt wide, about 2.1 × key height tall, label 34 to 36 pt, joined to the key; clamped inside the edges on keys 1 and 10 | similar | |
| Suggestion bar | 40 to 44 pt tall, 16 to 17 pt label, middle slot Semibold | about 40 to 45 pt | |
| Space bar | about 5 letter widths | about 5 letter widths | An iPadOS 26 complaint said the space bar was smaller than the key next to it ([Apple](https://origin-discussions2-us-dr-prz.apple.com/thread/256208127)) |
| Total height | 40 (bar) + 4 × 54 + top inset ≈ 263 pt, plus the system strip | | |

**What changed in iOS 26:**
- a glass background, rounder keys and less contrast;
- a fast-typing bug: a key highlighted but its letter was never inserted ([MacRumors](https://www.macrumors.com/2026/03/18/ios-26-4-iphone-keyboard-bug-fix/), [PhoneArena](https://www.phonearena.com/news/Apple-is-finally-fixing-one-of-the-most-annoying-iPhone-bugs-with-iOS-26.4_id179022)). Apple's 26.4 notes say "improved keyboard accuracy when typing quickly";
- SwiftKey users complained about spacing after its Liquid Glass update ([Windows Report](https://windowsreport.com/?p=1506762)).

## 2. Touch model

- **Offset correction:** touches land systematically off target. A fixed shift cut errors by 7.79% ([Henze et al., "100,000,000 Taps", MobileHCI'11](https://eprints.lancs.ac.uk/id/eprint/57576)). Shifting each touch up by about 2 to 4 pt is a cheap win. Learning the offset per key and per user goes further: Gboard learns each user's Gaussian means per key ([Sivek & Riley, "Spatial model personalization in Gboard"](https://arxiv.org/pdf/2209.11311), [Google blog](https://research.google/blog/the-machine-intelligence-behind-gboard/)).
- **Adaptive hit targets:** Apple's patent US 8,232,973 enlarges the likely next letter's hit area invisibly ([AppleInsider](https://appleinsider.com/articles/12/07/31/apple_granted_patent_for_predictive_text_input_ui)).
  - The pitfall is over-resizing: a key shrunk to nothing can't be typed.
  - The fix is "anchored" targets, where the centre of each key always maps to that key ([Gunawardana, Paek, Meek, "Usability Guided Key-Target Resizing for Soft Keyboards", IUI'10](https://www.microsoft.com/en-us/research/publication/usability-guided-key-target-resizing-for-soft-keyboards)).
  - Keep the LM boost mild, a boundary shift of 15 to 25% at most. Better still, score probabilistically in the decoder instead of moving boundaries.
- **Between keys and edges:** nearest key with no dead zones (Kalam has this). Extend edge keys to the screen edge, and give the bottom row the band below it.
- **Rollover:** a new touch commits a key still held, and letters are emitted in touch-down order ([rollover FIFO patent](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/10387032)). Dropped letters in fast typing were exactly the iOS 26 bug.
- **Timing (conventions, not specs):**
  - long-press alternates at 0.35 to 0.45 s;
  - delete repeat starting at about 0.5 s, then every 0.1 s;
  - word deletion after about 1.5 to 2 s or 10 to 20 characters. One user reported 4 s ([Defold](https://forum.defold.com/t/ios-keyboard-repeats-only-once-or-twice/70936)).

## 3. Premium vs cheap feel

- **Latency:** pointing performance degrades above about 25 ms (Jota et al., CHI'13). Dragging latency is visible down to a few ms ([Ng/Annett/Dietz](https://webdocs.cs.ualberta.ca/~wfb/publications/C-2014-SIGCHI-Latency.pdf), [Deber et al., "How Much Faster Is Fast Enough?", CHI'15](https://dcmpx.remotevs.com/com/tactuallabs/www/SL/papers/howMuchFasterIsFastEnoughCHI15.pdf)). Keep app-side touch-to-pixel work under 1 frame.
- **Popup:** instant, no fade-in. Hide it 50 to 80 ms after touch-up, or at once on the next press.
- **Press state:** a quick tint change, not a scale animation.
- **Haptics:** a light, short haptic on touch-down. Hoggan et al. found 30 ms pulses gave significant speed and accuracy gains ([MacKenzie summary](https://www.yorku.ca/mack/mhci2013d.html)). Some later studies found no effect, and about half of users prefer none, so keep it a toggle.
- **Shadow and dark mode:** a 1 pt bottom shadow on keys. In dark mode, enough key-to-background contrast that key edges stay visible on glass.

## 4. Comfort options people value

- **Keyboard height:** Gboard offers extra short to extra tall ([HowToGeek](https://www.howtogeek.com/889328/gboard-keyboard-features-you-should-be-using-on-android/)). SwiftKey on iOS can't resize ([Microsoft](https://support.microsoft.com/en-us/topic/how-to-resize-microsoft-swiftkey-keyboard-8652b54d-893d-478f-a7a3-3564ff947485)).
- **Number row:** SwiftKey has one, off by default ([Microsoft](https://support.microsoft.com/en-us/topic/how-do-i-turn-the-number-row-on-off-in-microsoft-swiftkey-keyboard-b9fc7e22-69f2-4560-8adc-36435a73cd91)).
- **Key borders:** Gboard offers them as a theme toggle.
- **One-handed mode:** reduces thumb reach, but reach-cutting layouts can be slower ([PLoS ONE 2013](https://doaj.org/article/d9b579e4c2a64d9489db00ded86e1dd6), [AVI'22](https://graphics.cs.uh.edu/wp-content/uploads/papers/2022/2022-AVI-keyboardComparisonStudy.pdf)).
- **Fitts' law:** finger touch has an absolute precision floor that plain Fitts' law misses, which favours bigger keys over clever layouts ([Bi, Li, Zhai, "FFitts Law", CHI'13](https://research.google/pubs/ffitts-law-modeling-finger-touch-with-fitts-law/)).

## 5. Ranked recommendations for Kalam

1. **Rollover commit:** a new touch-down commits any key still held (Kalam has this). Add a fast-typing test with overlapping touches.
2. **Learned per-key touch offset.** Start with a fixed upward shift of about 3 pt as an `EngineConfig` tunable, then learn per-key means from accepted words.
3. **Anchored probabilistic targets.** Score against the LM in the decoder. Never visibly resize boundaries, guarantee the key centre always wins, and cap the boost.
4. **Keep the 54 pt pitch.** Don't shrink it to make room for the 75 pt iOS 27 strip, which can't be changed anyway.
5. **Height setting:** compact 50, default 54, tall 58 pt pitch.
6. **Bottom row owns the gap above the system strip** (the 4.5 pt band), and edge keys stretch to the screen edge.
7. **Long-press 0.35 s is fine.** The popup shows immediately on touch-down. Cancel alternates selection if the finger slides off before the timer fires.
8. **Delete repeat:** start at 0.5 s, every 0.08 to 0.1 s, then word deletion after about 15 characters.
9. **Haptic on touch-down** from a prepared generator, with a toggle.
10. **Bar at 40 pt is fine,** with a Semibold middle slot at 16 to 17 pt.
11. **Key radius about 8 pt,** a 1 pt shadow, and stronger key-to-background contrast in dark mode for glass hosts.
12. **Optional number row (off by default).** When it's on, shorten the pitch 2 to 4 pt.

**Platform note:** Kalam gets the height left after the 75 pt strip. One developer reported that reserved-region APIs fail in keyboard extensions and that `needsInputModeSwitchKey` always returns false on iOS 27.1 ([Apple forum](https://developer.apple.com/forums/thread/847963)). Check device behavior rather than trusting the APIs.

**Unverified (needs Moe's phone):** the iOS 27 key metrics, haptic feel, real tap latency.
