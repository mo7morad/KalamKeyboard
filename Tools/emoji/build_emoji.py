"""Builds KalamEngine's emoji.json (SPEC 5.6) from Unicode's emoji-test.txt and CLDR annotations.

Stdlib only. Run from anywhere: python3 Tools/emoji/build_emoji.py
Output: the panel's categories in Apple's order (fully-qualified, no skin-tone variants) and a
keyword index per language (normalized keyword -> emoji, best first) for the suggestion bar.
"""
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Tools" / "lexicon-builder"))
from normalize import normalize  # noqa: E402

EMOJI_VERSION = "17.0"
EMOJI_TEST_URLS = [
    f"https://www.unicode.org/Public/emoji/{EMOJI_VERSION}/emoji-test.txt",
    f"https://raw.githubusercontent.com/unicode-org/unicodetools/main/unicodetools/data/emoji/{EMOJI_VERSION}/emoji-test.txt",
]
CLDR = "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json"
ANNOTATION_URLS = [
    CLDR + "/cldr-annotations-full/annotations/{lang}/annotations.json",
    CLDR + "/cldr-annotations-derived-full/annotationsDerived/{lang}/annotations.json",
]
OUT = ROOT / "Packages" / "KalamEngine" / "Sources" / "KalamEngine" / "Resources" / "emoji.json"

# Unicode group -> Apple's category. Component (skin tones, hair) has no category.
CATEGORIES = {
    "Smileys & Emotion": "Smileys & People",
    "People & Body": "Smileys & People",
    "Animals & Nature": "Animals & Nature",
    "Food & Drink": "Food & Drink",
    "Activities": "Activity",
    "Travel & Places": "Travel & Places",
    "Objects": "Objects",
    "Symbols": "Symbols",
    "Flags": "Flags",
}
SKIN_TONES = set(range(0x1F3FB, 0x1F400))
# Function words that would put an emoji in the bar for nearly every sentence.
STOP = {
    "en": set("a an and are as at be by do for from i in is it me my no not of off on or our out so the to up us we with you".split()),
    "ar": {"و", "في", "من", "علي", "الي", "عن", "مع", "او", "ان", "انا", "انت", "هو", "هي", "ما", "لا", "يا"},
}
MAX_PER_KEYWORD = 5
# Apple's first pick where the ranking below picks a rarer emoji (keys are normalized).
PREFERRED = {
    "en": {"love": "❤️", "cool": "😎", "smile": "😊", "happy": "😊", "sad": "😢", "laugh": "😂", "lol": "😂",
           "ok": "👌", "car": "🚗", "money": "💰", "party": "🎉", "kiss": "😘", "cat": "🐱", "dog": "🐶"},
    "ar": {"حب": "❤️", "قلب": "❤️"},
}


def fetch(urls: list[str]) -> str:
    for url in urls:
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                return response.read().decode("utf-8")
        except OSError as error:
            print(f"skip {url}: {error}", file=sys.stderr)
    raise SystemExit("no source reachable")


def parse_emoji_test(text: str) -> tuple[list[tuple[str, list[str]]], dict[str, float]]:
    """Apple's categories in order, each with its fully-qualified base emoji in Unicode order, and
    the emoji version each one came with."""
    order = list(dict.fromkeys(CATEGORIES.values()))
    found: dict[str, list[str]] = {name: [] for name in order}
    versions: dict[str, float] = {}
    category = None
    for line in text.splitlines():
        if line.startswith("# group:"):
            category = CATEGORIES.get(line.split(":", 1)[1].strip())
            continue
        if category is None or not line or line.startswith("#"):
            continue
        data, comment = line.split("#", 1)
        codes, status = (part.strip() for part in data.split(";"))
        scalars = [int(code, 16) for code in codes.split()]
        if status == "fully-qualified" and not SKIN_TONES.intersection(scalars):
            item = "".join(map(chr, scalars))
            found[category].append(item)
            versions[item] = float(re.search(r"E(\d+\.\d+)", comment).group(1))
    return [(name, found[name]) for name in order], versions


def annotations(lang: str) -> dict[str, dict]:
    merged: dict[str, dict] = {}
    for url in ANNOTATION_URLS:
        root = json.loads(fetch([url.format(lang=lang)]))
        merged.update(next(iter(root.values()))["annotations"])  # "annotations" or "annotationsDerived"
    return merged


def words(phrase: str, lang: str) -> list[str]:
    return re.findall(r"[^\W\d_]+", normalize(phrase, lang))


def keyword_index(emoji: list[str], versions: dict[str, float], notes: dict[str, dict], lang: str) -> dict[str, list[str]]:
    """keyword -> emoji, best first. Tiers: the emoji's whole name ("pizza"), the name's head noun
    ("heart" in red heart), a single-word keyword or another word of the name, then a word inside a
    longer keyword. Ties go to older emoji (the 2010 set is the everyday one), then to fewer
    keywords (more specific), then to panel order.
    ponytail: no usage frequencies (Unicode publishes none as data), so a few picks differ from Apple's."""
    ranked: dict[str, dict[str, tuple]] = {}
    for position, item in enumerate(emoji):
        note = notes.get(item.replace("\ufe0f", ""))
        if not note:
            continue
        names = note.get("tts", [])
        keywords = note.get("default", [])
        tiers: dict[str, int] = {}
        for phrase in names + keywords:
            parts = words(phrase, lang)
            head = parts[-1 if lang == "en" else 0] if parts else None  # Arabic puts the noun first
            for word in parts:
                if phrase in names:
                    tier = 0 if len(parts) == 1 else 1 if word == head else 2
                else:
                    tier = 2 if len(parts) == 1 else 3
                tiers[word] = min(tier, tiers.get(word, 3))
        for word, tier in tiers.items():
            if word not in STOP[lang] and len(word) > 1:
                ranked.setdefault(word, {})[item] = (tier, versions[item], len(keywords), position)
    for word, item in PREFERRED[lang].items():
        ranked[word][item] = (-1,)
    return {word: sorted(found, key=found.get)[:MAX_PER_KEYWORD] for word, found in sorted(ranked.items())}


def main() -> None:
    categories, versions = parse_emoji_test(fetch(EMOJI_TEST_URLS))
    emoji = [item for _, items in categories for item in items]
    data = {
        "version": EMOJI_VERSION,
        "categories": [{"name": name, "emoji": items} for name, items in categories],
        "keywords": {lang: keyword_index(emoji, versions, annotations(lang), lang) for lang in ("en", "ar")},
    }
    OUT.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(emoji)} emoji, "
          + ", ".join(f"{lang} {len(index)} keywords" for lang, index in data["keywords"].items())
          + f", {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
