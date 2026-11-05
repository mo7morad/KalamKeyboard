"""Builds the test fixture lexicons: python3 fixture.py (writes next to fixture-source.json)."""
import json
from pathlib import Path

from build import flag_words
from klex import write_klex

FIXTURES = Path(__file__).resolve().parents[2] / "Packages/KalamEngine/Tests/KalamEngineTests/Fixtures"


def build_fixtures(source: Path) -> dict:
    """lang -> .klex bytes for every language in the source file."""
    data = json.loads(source.read_text(encoding="utf-8"))
    return {
        lang: write_klex(
            lang,
            flag_words(lang, spec["words"], generated=set(spec.get("generated", []))),
            {tuple(pair.split(" ")): p for pair, p in spec["bigrams"].items()},
            spec["casing"],
        )
        for lang, spec in data.items()
    }


if __name__ == "__main__":
    for lang, blob in build_fixtures(FIXTURES / "fixture-source.json").items():
        (FIXTURES / f"fixture-{lang}.klex").write_bytes(blob)
