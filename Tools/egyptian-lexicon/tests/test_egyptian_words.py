from collections import Counter

import egyptian_words
from egyptian_words import generate, words


def test_words_drop_marks_latin_one_letter_and_stretched_tokens():
    assert words("مُـش عايز، hello و ملياااار ده") == ["مش", "عايز", "ده"]


def test_forms_come_from_frequent_analyzable_stems_skip_attested_ones_and_are_capped(monkeypatch):
    monkeypatch.setattr(egyptian_words, "MIN_STEM_COUNT", 2)
    monkeypatch.setattr(egyptian_words, "MAX_FORMS_PER_STEM", 2)
    corpus = Counter({"بنجرب": 9, "بنجربه": 1, "زززز": 9, "بيلعب": 1})
    analyzable = {"بنجرب", "بنجربه", "بنجربها", "بنجربهم", "بنجربك", "ززززه", "بيلعب", "بيلعبه"}.__contains__
    assert generate(corpus, analyzable) == {"بنجربها": "بنجرب", "بنجربهم": "بنجرب"}
