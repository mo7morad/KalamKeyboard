"""Builds the test fixture lexicons: python3 fixture.py (writes next to fixture-source.json)."""
import json
import math
from pathlib import Path

from klex import PREFERRED, VALID, write_klex
from normalize import normalize

FIXTURES = Path(__file__).resolve().parents[2] / "Packages/KalamEngine/Tests/KalamEngineTests/Fixtures"
MIN_ZIPF = 2.0
AR_MARKED = set("أإآؤئءةى")
PREFERRED_MIN_SHARE = 0.15


def flag_words(lang: str, freqs: dict) -> dict:
    """surface -> (frequency, flags), with the validity and preferred-spelling rules of SPEC 7.1."""
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
            valid = math.log10(freqs[s]) + 9 >= MIN_ZIPF
            words[s] = (freqs[s], (VALID if valid else 0) | (PREFERRED if s == preferred else 0))
    return words


def build_fixtures(source: Path) -> dict:
    """lang -> .klex bytes for every language in the source file."""
    data = json.loads(source.read_text(encoding="utf-8"))
    return {
        lang: write_klex(
            lang,
            flag_words(lang, spec["words"]),
            {tuple(pair.split(" ")): p for pair, p in spec["bigrams"].items()},
            spec["casing"],
        )
        for lang, spec in data.items()
    }


if __name__ == "__main__":
    for lang, blob in build_fixtures(FIXTURES / "fixture-source.json").items():
        (FIXTURES / f"fixture-{lang}.klex").write_bytes(blob)
