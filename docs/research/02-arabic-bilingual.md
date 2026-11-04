# Research 2: Arabic and bilingual typing (2026-11-04)

20 web searches. There is very little direct user evidence about Arabic keyboards on iPhone: no Reddit threads about Egyptian keyboards and no review of Gboard Arabic or SwiftKey Arabic on iPhone. These points come from Apple Community threads, Arabic news sites, NLP papers and Unicode/bidi bug trackers. Reasoning without a source is marked as such.

## 1. What users hate

- **Eastern digits by default.** The most repeated complaint in Apple Community. The Arabic keyboard types ٠١٢, Western digits need a long press, and the only setting appears when the whole iPhone is set to Arabic ([1](https://discussions.apple.com/thread/255823224), [2](https://discussions.apple.com/thread/254837124), [3](https://discussions.apple.com/thread/255769866)).
- **Autocorrect breaks Arabic.** Egyptian news sites suggest turning autocorrect off, and iOS 26 brought new complaints about dropped letters and bad suggestions ([akhbarelyom](https://m.akhbarelyom.com/news/newdetails/4155831/1/), [eremnews](https://www.eremnews.com/sciences-technology/ssmab25), [entrepreneur](https://www.entrepreneur.com/business-news/apple-just-fixed-an-iphone-problem-thats-been-driving-typers-crazy)). A Samsung user said prediction stopped learning their colloquial phrasing ([samsung](https://r2.community.samsung.com/t5/%D8%A7%D8%AE%D8%B1%D9%89/%D9%86%D8%B5-%D8%AA%D9%86%D8%A8%D8%A4%D9%8A/m-p/4255029)). No vendor has dialect-aware autocorrect.
- **Hamza and ة/ه.** The Ghalatawi autocorrect library lists hamza forms and ة written as ه as the most common Arabic errors ([pypi](https://pypi.org/project/ghalatawi/)). People also struggle to find the hamza long-press ([apple](https://discussions.apple.com/thread/253943897)).
- **Mixed-direction text.** The cursor sticks to the left margin or text runs left to right ([apple](https://discussions.apple.com/thread/255358998), [apple-jp](https://discussions-jp-prz.apple.com/thread/255351148)). The cursor jumps at Arabic/English run boundaries in every app ([mozilla](https://bugzilla.mozilla.org/show_bug.cgi?id=1521589), [obsidian](https://forum.obsidian.md/t/cursor-movement-arrow-keys-is-broken-inconsistent-in-mixed-rtl-ltr-text/118833)).
- **Punctuation.** The Arabic comma ، displays with the wrong shape in Notes and Messages ([apple](https://discussions.apple.com/thread/253342884), [apple](https://discussions.apple.com/thread/255442710)). A Latin "?" was placed on an Arabic layout by mistake ([mozilla](https://bugzilla.mozilla.org/show_bug.cgi?id=1141006)).
- **Suggestions in the wrong language.** iOS shows predictions in the wrong language when a third-party keyboard's bundle ID implies another one ([apple dev](https://developer.apple.com/forums/thread/757380), [apple](https://discussions.apple.com/thread/252940888)). Apple's Arabic layout has no English letters, so every English word means a layout switch ([apple](https://discussions.apple.com/thread/256186619)).

## 2. What they love, and the best bilingual keyboard

- **SwiftKey** types two languages at once with no switching ([applevis](https://applevis.com/apps/ios/utilities/microsoft-swiftkey-keyboard)). Asharq Al-Awsat praises how it learns personal style ([aawsat](https://aawsat.com/node/731531)). Digital Trends found its autocorrect gentler than Apple's ([digitaltrends](https://uat4.www.digitaltrends.com/mobile/iphone-default-ios-keyboard-boring-replace-microsoft-swiftkey-why)).
- **Gboard** autocorrects and suggests from any enabled language ([apkmirror](https://www.apkmirror.com/?p=1359016), [gizmodo](https://gizmodo.com/download/gboard)).
- **Arabizi converters** (Yamli, Microsoft Maren from Microsoft's Cairo center, Ta3reeb) turn Latin typing into Arabic script, and people like them ([TNW](https://thenextweb.com/news/yamli-type-arabic-arabic-keyboard), [MS](https://learn.microsoft.com/en-us/archive/blogs/mutaz/typing-arabic-has-never-been-this-easy)).
- **Verdict:** SwiftKey's simultaneous mode is the reference for mixed Arabic and English. A Franco mode in Gboard could not be confirmed.

## 3. Code-switching

- On-device language detection works well. Samsung's typing-time detector (character n-grams plus a small selector) reaches 94.5 to 98% ([arXiv 2101.03963](https://arxiv.org/pdf/2101.03963)). Arabizi vs English detection reaches 98.5% ([ACL W14-3629](https://aclanthology.org/W14-3629.pdf)), and the same paper says users type Arabizi because they are more fluent on an English keyboard.
- MSA vs Egyptian is harder (F1 0.83), and so is mixing inside a single word ([arXiv 1909.13016](https://arxiv.org/pdf/1909.13016), [Sabty](https://busca.umc.cl/Record/oai:doaj.org-article:a5ec6db515d345e290c61a851789e27e)).
- **Practice:**
  - Keep the manual layout key. Never let the LM fight the script being typed: suggest only in that script.
  - When a word is typed on the wrong layout, offer a one-tap fix. "hgsghl" is "السلام" typed on the English keyboard; detection should propose the switch, not perform it ([arXiv 1306.6755](https://arxiv.org/pdf/1306.6755.pdf)).
  - Don't switch the layout automatically mid-thought.

## 4. RTL specifics

- **Cursor and trackpad:** logical "forward" in Arabic text moves the cursor left. That is correct, but the drag direction must follow the finger on screen ([mozilla](https://bugzilla.mozilla.org/show_bug.cgi?id=998917)).
- **Backspace:** the consensus is to remove a diacritic on its own first, then the letter ([KDE D7660](https://phabricator.kde.org/D7660)). On lam-alef, users did not want one backspace to delete both letters ([gnome](https://lists.gnome.org/archives/gtk-i18n-list/2001-May/msg00030.html), [fedora](https://www.redhat.com/archives/fedora-trans-ar/2005-April/000802.html)), though the opposite complaint also exists ([bash](https://mail.gnu.org/archive/html/bug-bash/2024-02/msg00155.html)).
- **Suggestion bar:** mirrored in Arabic, primary in the middle, order reversed (SPEC §5.4 already does this).
- **Punctuation:** ، ؛ ؟ in Arabic. Brackets mirror at render time, so the keyboard inserts the logical characters ([unicode](https://unicode.org/mail-arch/unicode-ml/Archives-Old/UML007/0182.html)).

## 5. Research

- Arabic touch layouts have been redesigned by Pareto optimisation ([Strathclyde](https://stax.strath.ac.uk/downloads/j67314071)). In-the-wild studies show error rates correlate only weakly with finger slippage ([Komninos 2018](https://strathprints.strath.ac.uk/66313/)).
- **Neighbouring-key confusions on Apple's Arabic layout:** no study found. From the geometry alone (reasoning, unsourced), expect د/ذ/ز/ر on the bottom row, ى/و/ي, ض/ص, ع/غ/ه, ة/ك and ا/ل. A typo log from Moe's own messages would show the real pairs.
- **Dialect lexicons:**
  - WERd, dialect spelling variants from half a billion tweets ([arXiv 1709.07484](https://arxiv.org/pdf/1709.07484));
  - Egyptian Dialect Corpus, 218k words from Facebook ([github](https://github.com/TaghreedT/EDC));
  - CODA* conventions and the MADAR spelling-correction work ([VarDial 2024](https://aclanthology.org/2024.vardial-1.4.pdf));
  - Arabizi-to-Arabic transliteration data ([LDC](https://www.ldc.upenn.edu/sites/www.ldc.upenn.edu/files/emnlp2014-transliteration-aribizi-into-arabic-orthography.pdf)).

## 6. Takeaways for Kalam (ranked)

LACK means the agent found no sign of it in the SPEC or the code.

1. **RTL trackpad direction (LACK, likely bug).** The finger's x offset goes straight to `adjustTextPosition` with no flip based on the text's script. The audit (research 5) confirms the direction follows the layout language, not the text.
2. **Moe's own spellings win over MSA.** WhatsApp learning gives this; make sure a word typed twice is never autocorrected away. The gentle Arabic default fits.
3. **Suggestions stay in the script being typed (verify).** Never English on the Arabic layout or the reverse.
4. **Wrong-layout fix (LACK).** An English-layout word that isn't English but maps key-for-key to a known Arabic word ("hgsghl" → "السلام") is offered as a suggestion. Cheap with the existing trie.
5. **Keep hamza auto-fix off, but always suggest the variant.** أ/ا/إ and ة/ه alternatives in a side slot.
6. **ى/ي and ة/ه as low-cost edits in the beam (verify).** Same as the hamza alternates.
7. **Western digits by default.** Already the default (Eastern off).
8. **Backspace with tashkeel (LACK, unverified).** Check on the phone that `deleteBackward` removes only the diacritic, and that lam-alef splits back to lam. iOS may delete the whole cluster.
9. **Franco support (partial).** The digit long-press makes "3ashan" possible. Next, learn Arabizi tokens from the chats as their own Latin-script vocabulary so English autocorrect leaves them alone. A full Arabizi-to-Arabic converter is skipped until Moe asks.
10. **Punctuation follows the layout.** Check that double-space gives "." on both layouts, and that auto-capitalization never fires on Arabic.
11. **Seed the Arabic lexicon from dialect data (verify licences).** EDC and WERd could fill Egyptian gaps beyond the 3 chats.
12. **Never auto-switch the layout.** At most, a "switch?" hint after 2 or more wrong-script words in a row (optional).

Device checks: items 1, 8 and 10.
