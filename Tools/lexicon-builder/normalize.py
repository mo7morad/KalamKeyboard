"""Lookup-key normalization (SPEC 6.1). Mirrors KalamEngine/Normalization.swift."""
import unicodedata

AR_DROP = (
    {0x0640, 0x0670, 0x200C, 0x200D, 0x200E, 0x200F}
    | set(range(0x064B, 0x0660))
    | set(range(0x06D6, 0x06EE))
)
AR_MAP = {
    "أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا",
    "ى": "ي", "ة": "ه", "ؤ": "و", "ئ": "ي",
    "ک": "ك", "ی": "ي",
}
APOSTROPHES = {"'", "’", "‘", "ʼ"}


def normalize(text: str, lang: str) -> str:
    if lang == "ar":
        nfc = unicodedata.normalize("NFC", text)
        return "".join(AR_MAP.get(c, c) for c in nfc if ord(c) not in AR_DROP)
    nfd = unicodedata.normalize("NFD", text)
    return "".join(c for c in nfd if unicodedata.combining(c) == 0 and c not in APOSTROPHES).lower()
