"""Builds Tools/data/egyptian-words.tsv (PROMPTS Phase 18): Egyptian clitic forms for the AR base lexicon.

For each frequent Egyptian corpus word that CAMeL Tools' Egyptian morphology (calima-egy-r13) analyzes,
it tries the common clitic forms (و/ف/ب/ح/ه, object and لـ pronouns, the negation م…ش) and keeps the ones
calima-egy analyzes and the corpus never shows, capped per stem. calima-egy is generous (it reads حالله as
the verb حال), so some forms are odd; they cost little as candidates (eval-log Phase 18). Output: surface<TAB>stem per line.
build.py adds them as candidates that never block autocorrect (SPEC 7.1).

    CAMELTOOLS_DATA=$PWD/data .venv/bin/python egyptian_words.py
"""
import argparse
import re
import sys
import unicodedata
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Tools/lexicon-builder"))
from normalize import AR_DROP, normalize  # noqa: E402  (the shared normalization, SPEC 6.1)

CORPORA = ROOT / "Tools/lexicon-builder/corpora/egyptian"
WORD_RE = re.compile(r"[ء-غف-يٱ]+")  # build.py's Arabic-letters filter
STRETCHED_RE = re.compile(r"(.)\1\1")  # ملياااار: comment stretching, never a stem
MIN_STEM_COUNT = 50
MAX_FORMS_PER_STEM = 12

# Common Egyptian clitics (SPEC 8.5 rule 2 lists the same family). Tried in this order, so the cap keeps the commonest.
SUFFIXES = ("ه", "ها", "هم", "ك", "كم", "ني", "نا", "ش", "لي", "له", "لك", "لها", "لهم", "لنا")
PREFIXES = ("و", "ف", "ب", "ح", "ه")


def words(text: str) -> list:
    """Arabic-letter tokens with tashkeel and tatweel dropped, as wordfreq tokenizes them."""
    clean = "".join(c for c in unicodedata.normalize("NFC", text) if ord(c) not in AR_DROP)
    return [w for w in WORD_RE.findall(clean) if len(w) > 1 and not STRETCHED_RE.search(w)]


def clitic_forms(stem: str) -> list:
    """Candidate surfaces: one prefix and/or one suffix, and the negation م…ش."""
    forms = [stem + s for s in SUFFIXES] + [p + stem for p in PREFIXES]
    forms += [p + stem + s for p in PREFIXES for s in SUFFIXES[:7]]
    return forms + ["م" + stem + "ش", "ما" + stem + "ش"]


def generate(corpus: Counter, analyzable) -> dict:
    """surface -> stem for the clitic forms of the frequent analyzable corpus words that calima-egy analyzes and
    the corpus lacks, at most MAX_FORMS_PER_STEM per stem."""
    attested = {normalize(w, "ar") for w in corpus}
    generated = {}
    for stem, count in corpus.most_common():
        if count < MIN_STEM_COUNT:
            break
        if not analyzable(stem):
            continue
        kept = 0
        for form in clitic_forms(stem):
            if kept == MAX_FORMS_PER_STEM:
                break
            if normalize(form, "ar") not in attested and form not in generated and analyzable(form):
                generated[form] = stem
                kept += 1
    return generated


def camel_analyzable():
    """A cached calima-egy-r13 lookup: True when the analyzer has any analysis for the word."""
    from camel_tools.morphology.analyzer import Analyzer
    from camel_tools.morphology.database import MorphologyDB

    analyzer = Analyzer(MorphologyDB.builtin_db("calima-egy-r13"))
    cache = {}

    def analyzable(word: str) -> bool:
        if word not in cache:
            cache[word] = bool(analyzer.analyze(word))
        return cache[word]

    return analyzable


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--corpus", type=Path, action="append", help="default: corpora/egyptian/*.txt")
    parser.add_argument("--out", type=Path, default=ROOT / "Tools/data/egyptian-words.tsv")
    args = parser.parse_args()
    corpus = Counter()
    for path in args.corpus or sorted(CORPORA.glob("*.txt")):
        with path.open(encoding="utf-8") as lines:
            for line in lines:
                corpus.update(words(line))
    generated = generate(corpus, camel_analyzable())
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("".join(f"{form}\t{stem}\n" for form, stem in generated.items()), encoding="utf-8")
    print(f"wrote {args.out}: {len(generated)} forms from {len(set(generated.values()))} stems")


if __name__ == "__main__":
    main()
