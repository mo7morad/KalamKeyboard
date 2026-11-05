"""Builds a real base lexicon (SPEC 7.1): python3 build.py en|ar [--corpora DIR] [--out FILE] ...

Unigrams come from wordfreq; bigrams and the EN casing table from the Leipzig sentence files,
minus a deterministic 5% held-out split that is written out for kalam-cli eval. AR also adds the
generated Egyptian forms of Tools/data/egyptian-words.tsv and trains bigrams on corpora/egyptian/masri.txt,
each when present (PROMPTS Phase 18)."""
import argparse
import json
import math
import re
import sys
import time
import urllib.request
import zlib
from collections import Counter
from itertools import chain
from pathlib import Path

import wordfreq

from klex import CANDIDATE, PREFERRED, SENTENCE_START, VALID, write_klex
from normalize import normalize

ROOT = Path(__file__).resolve().parents[2]
TOP_WORDS = {"en": 150_000, "ar": 250_000}
WORD_RE = {
    "en": re.compile(r"[a-z]+(['’][a-z]+)*"),
    "ar": re.compile(r"[ء-غف-يٱ]+"),  # Arabic letters, no tatweel or marks
}
LEIPZIG_PREFIX = {"en": "eng", "ar": "ara"}
MIN_ZIPF = 2.0
MIN_VARIANT_SHARE = 0.03
PREFERRED_MIN_SHARE = 0.15
AR_MARKED = set("أإآؤئءةى")
HELDOUT_EVERY = 20  # 1 in 20 = 5%
MIN_BIGRAM_COUNT = 2
APOSTROPHES = str.maketrans("’‘ʼ", "'''")
CASED_WORD_RE = re.compile(r"[A-Za-z]+(?:'[A-Za-z]+)*")
I_FORMS = ("i", "i'm", "i'll", "i'd", "i've")
CASING_MIN_SHARE = 0.9  # below it, news title case (Street, King) and split forms (OK / ok) stay lowercase
GENERATED_FREQ = 1e-8  # zipf 1: generated Egyptian forms rank below every attested word
EGYPTIAN_SENTENCES = "egyptian/masri.txt"  # the dataflare Masri slice; the YouTube comments only seed stems (eval-log Phase 18)
MISSPELLINGS_URL = (
    "https://en.wikipedia.org/w/api.php?action=parse&format=json&formatversion=2&prop=wikitext"
    "&page=Wikipedia:Lists_of_common_misspellings/For_machines"
)


def unigrams(lang: str, freqs: dict) -> dict:
    """The top words of the language that pass its word filter, ties broken by spelling."""
    kept = [w for w in freqs if WORD_RE[lang].fullmatch(w)]
    kept.sort(key=lambda w: (-freqs[w], w))
    return {w: freqs[w] for w in kept[: TOP_WORDS[lang]]}


def prune_variants(lang: str, freqs: dict) -> dict:
    """Drops variants holding less than MIN_VARIANT_SHARE of their normalized key's total."""
    totals = Counter()
    for word, freq in freqs.items():
        totals[normalize(word, lang)] += freq
    return {w: f for w, f in freqs.items() if f >= MIN_VARIANT_SHARE * totals[normalize(w, lang)]}


def flag_words(lang: str, freqs: dict, misspellings=frozenset(), min_zipf: float = MIN_ZIPF, generated=frozenset()) -> dict:
    """surface -> (frequency, flags), with the validity and preferred-spelling rules of SPEC 7.1.
    Generated forms are candidates, never valid."""
    groups = {}
    for surface, freq in freqs.items():
        groups.setdefault(normalize(surface, lang), []).append(surface)
    words = {}
    for group in groups.values():
        group.sort(key=lambda s: (-freqs[s], s))
        total = sum(freqs[s] for s in group)
        marked = [s for s in group if freqs[s] / total >= PREFERRED_MIN_SHARE and AR_MARKED & set(s)]
        preferred = marked[0] if lang == "ar" and marked else group[0]
        for s in group:
            valid = math.log10(freqs[s]) + 9 >= min_zipf and s not in misspellings
            kind = CANDIDATE if s in generated else VALID if valid else 0
            words[s] = (freqs[s], kind | (PREFERRED if s == preferred else 0))
    return words


def generated_forms(path: Path, freqs: dict) -> set:
    """The surfaces of Tools/data/egyptian-words.tsv (Tools/egyptian-lexicon) that wordfreq lacks."""
    if not path.exists():
        return set()
    return {line.split("\t", 1)[0] for line in path.read_text(encoding="utf-8").splitlines()} - freqs.keys()


def is_heldout(sentence: str) -> bool:
    """Stable across runs and machines (CRC32 of the text, not Python's salted hash)."""
    return zlib.crc32(sentence.encode("utf-8")) % HELDOUT_EVERY == 0


def tokens(sentence: str, lang: str) -> list:
    """wordfreq tokens, with EN curly apostrophes mapped to ' as in the unigram list."""
    found = wordfreq.tokenize(sentence, lang)
    return [t.translate(APOSTROPHES) for t in found] if lang == "en" else found


def count_corpus(lang: str, sentences, vocab: list) -> tuple:
    """Bigram P(w2 | w1) (w1 may be <s>) and the EN casing table from the training sentences."""
    names = vocab + [SENTENCE_START]
    index = {w: i for i, w in enumerate(names)}
    width = len(names)
    followers = [0] * width  # every token after w1, in vocabulary or not
    pairs = Counter()  # w1 * width + w2: ints keep millions of pairs in memory
    forms = Counter()
    for sentence in sentences:
        prev = width - 1  # <s>
        for token in tokens(sentence, lang):
            cur = index.get(token, -1)
            if prev >= 0:
                followers[prev] += 1
                if cur >= 0:
                    pairs[prev * width + cur] += 1
            prev = cur
        if lang == "en":
            forms.update(CASED_WORD_RE.findall(sentence.translate(APOSTROPHES))[1:])  # skip the sentence-initial word
    bigrams = {}
    for pair, count in pairs.items():
        w1, w2 = divmod(pair, width)
        if count >= MIN_BIGRAM_COUNT:
            bigrams[names[w1], names[w2]] = count / followers[w1]
    return bigrams, (casing_table(forms, set(vocab)) if lang == "en" else {})


def casing_table(forms: Counter, vocab: set) -> dict:
    """lowercase word -> its most common casing, stored only when that differs and holds CASING_MIN_SHARE of
    the word's non-initial forms; i and i-contractions forced when in vocab."""
    by_lower = {}
    for form, count in forms.items():
        lower = form.lower()
        if lower in vocab:
            by_lower.setdefault(lower, []).append((-count, form != lower, form))
    table = {}
    for lower, seen in by_lower.items():
        neg_count, _, form = min(seen)
        total = -sum(neg for neg, _, _ in seen)
        if -neg_count >= CASING_MIN_SHARE * total:
            table[lower] = form
    table.update({w: "I" + w[1:] for w in I_FORMS if w in vocab})
    return {lower: form for lower, form in table.items() if form != lower}


def training_sentences(paths: list, heldout_out):
    """Yields the non-held-out sentences of the Leipzig files and writes the held-out ones to heldout_out."""
    for path in paths:
        with path.open(encoding="utf-8") as lines:
            for line in lines:
                sentence = line.rstrip("\n").partition("\t")[2]
                if is_heldout(sentence):
                    heldout_out.write(sentence + "\n")
                else:
                    yield sentence


def parse_misspellings(wikitext: str) -> set:
    """The misspelled sides of the "misspelling->correction" lines."""
    return {line.split("->", 1)[0].strip().lower() for line in wikitext.splitlines() if "->" in line}


def load_misspellings(path: Path) -> set:
    """Reads the cached list, fetching it once from Wikipedia. An unreachable list means no list."""
    if not path.exists():
        try:
            request = urllib.request.Request(MISSPELLINGS_URL, headers={"User-Agent": "lexicon-builder/1.0"})
            with urllib.request.urlopen(request, timeout=30) as response:
                wikitext = json.load(response)["parse"]["wikitext"]
        except (OSError, ValueError, KeyError) as error:
            print(f"warning: misspellings list unavailable ({error}); building without it", file=sys.stderr)
            return set()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(wikitext, encoding="utf-8")
    return parse_misspellings(path.read_text(encoding="utf-8"))


def build(lang: str, corpora: Path, heldout: Path, egyptian: Path) -> tuple:
    """(words, bigrams, casing, generated) for write_klex, with words still unflagged."""
    words = unigrams(lang, wordfreq.get_frequency_dict(lang, wordlist="large"))
    generated = generated_forms(egyptian, words) if lang == "ar" else set()
    words = prune_variants(lang, words | dict.fromkeys(generated, GENERATED_FREQ))
    generated &= words.keys()
    masri = corpora / EGYPTIAN_SENTENCES
    extra = [masri] if lang == "ar" and masri.exists() else []
    vocab = sorted(words)
    paths = sorted(corpora.glob(f"{LEIPZIG_PREFIX[lang]}*/*-sentences.txt"))
    if not paths:
        sys.exit(f"no {LEIPZIG_PREFIX[lang]}*/*-sentences.txt under {corpora}")
    heldout.parent.mkdir(parents=True, exist_ok=True)
    with heldout.open("w", encoding="utf-8") as heldout_out:
        bigrams, casing = count_corpus(lang, chain(training_sentences(paths, heldout_out), lines(extra)), vocab)
    sources = [p.name for p in paths + extra]
    print(f"{lang}: {len(words)} words ({len(generated)} generated), {len(bigrams)} bigrams, {len(casing)} casings from {sources}")
    return words, bigrams, casing, generated


def lines(paths: list):
    """Every line of the Egyptian corpus: one text each, all for training (none enters the held-out file)."""
    for path in paths:
        with path.open(encoding="utf-8") as texts:
            yield from (line.rstrip("\n") for line in texts)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("lang", choices=sorted(TOP_WORDS))
    parser.add_argument("--corpora", type=Path, default=ROOT / "Tools/lexicon-builder/corpora")
    parser.add_argument("--out", type=Path, help="default: KeyboardExtension/Resources/<lang>.klex")
    parser.add_argument("--heldout", type=Path, help="default: Tools/data/heldout/<lang>.txt")
    parser.add_argument("--misspellings", type=Path, default=ROOT / "Tools/data/misspellings.wikitext")
    parser.add_argument("--min-zipf", type=float, default=MIN_ZIPF)
    parser.add_argument("--egyptian", type=Path, default=ROOT / "Tools/data/egyptian-words.tsv",
                        help="AR only, its forms are added when the file exists (Tools/egyptian-lexicon)")
    args = parser.parse_args()
    started = time.monotonic()
    misspellings = load_misspellings(args.misspellings) if args.lang == "en" else set()
    out = args.out or ROOT / f"KeyboardExtension/Resources/{args.lang}.klex"
    heldout = args.heldout or ROOT / f"Tools/data/heldout/{args.lang}.txt"
    words, bigrams, casing, generated = build(args.lang, args.corpora, heldout, args.egyptian)
    blob = write_klex(args.lang, flag_words(args.lang, words, misspellings, args.min_zipf, generated), bigrams, casing)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(blob)
    print(f"wrote {out} ({len(blob):,} bytes) in {time.monotonic() - started:.1f} s")


if __name__ == "__main__":
    main()
