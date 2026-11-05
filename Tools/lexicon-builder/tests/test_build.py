import io
from collections import Counter

import pytest

import build
from build import (
    casing_table,
    count_corpus,
    flag_words,
    generated_forms,
    is_heldout,
    parse_misspellings,
    prune_variants,
    training_sentences,
    unigrams,
)
from klex import CANDIDATE, PREFERRED, VALID


def test_unigram_filters_keep_only_words_of_the_language(monkeypatch):
    monkeypatch.setitem(build.TOP_WORDS, "en", 3)
    freqs = {"the": 5e-2, "don't": 1e-3, "co-op": 1e-3, "3ashan": 1e-3, "café": 1e-3, "of": 3e-2, "zebra": 1e-6}
    assert unigrams("en", freqs) == {"the": 5e-2, "of": 3e-2, "don't": 1e-3}
    ar = {"كده": 1e-4, "أنا": 1e-3, "مـحمد": 1e-4, "hello": 1e-3, "٣": 1e-3}
    assert set(unigrams("ar", ar)) == {"كده", "أنا"}


def test_top_cut_breaks_frequency_ties_by_spelling(monkeypatch):
    monkeypatch.setitem(build.TOP_WORDS, "en", 2)
    assert list(unigrams("en", {"bb": 1e-3, "aa": 1e-3, "cc": 1e-3})) == ["aa", "bb"]


def test_heldout_split_is_a_fixed_function_of_the_text():
    assert is_heldout("a29") and not is_heldout("I love you.")  # pinned CRC32 values, same on every machine
    share = sum(is_heldout(f"sentence {i}") for i in range(20_000)) / 20_000
    assert 0.045 < share < 0.055


def test_heldout_sentences_are_written_out_and_never_yielded(tmp_path):
    corpus = tmp_path / "eng_x" / "eng_x-sentences.txt"
    corpus.parent.mkdir()
    corpus.write_text("1\ta29\n2\tI love you.\n", encoding="utf-8")
    heldout = io.StringIO()
    assert list(training_sentences([corpus], heldout)) == ["I love you."]
    assert heldout.getvalue() == "a29\n"


def test_bigrams_map_curly_apostrophes_and_start_at_s():
    bigrams, _ = count_corpus("en", ["I don’t know", "I don't know"], ["don't", "i", "know"])
    assert bigrams == {("<s>", "i"): 1.0, ("i", "don't"): 1.0, ("don't", "know"): 1.0}


def test_bigram_probability_counts_unknown_followers_and_drops_singletons():
    sentences = ["go home", "go home", "go zorp", "go away"]
    bigrams, _ = count_corpus("en", sentences, ["away", "go", "home"])
    assert bigrams == {("<s>", "go"): 1.0, ("go", "home"): 0.5}


def test_casing_takes_the_most_common_non_initial_form():
    sentences = ["Apple said so", "we like Apple", "they like Apple", "we use Apple", "Bob said hi"]
    _, casing = count_corpus("en", sentences, ["apple", "bob", "said", "i"])
    assert casing == {"apple": "Apple", "i": "I"}  # "Bob" only appears sentence-initially


def test_casing_needs_90_percent_of_the_forms_and_forces_the_i_forms():
    forms = Counter({"May": 2, "may": 2, "NASA": 9, "nasa": 1, "OK": 68, "ok": 32, "i'm": 9})
    assert casing_table(forms, {"may", "nasa", "ok", "i'm", "i'll"}) == {
        "nasa": "NASA", "i'm": "I'm", "i'll": "I'll",
    }


def test_validity_needs_min_zipf_and_no_misspelling():
    words = flag_words("en", {"their": 1e-3, "thier": 1e-6, "rare": 1e-8}, misspellings={"thier"})
    assert {w: bool(flags & VALID) for w, (_, flags) in words.items()} == {"their": True, "thier": False, "rare": False}
    assert flag_words("en", {"rare": 1e-8}, min_zipf=1.0)["rare"][1] & VALID


def test_misspelling_list_keeps_the_left_side_of_arrow_lines_only():
    wikitext = "==Intro==\nSome text.\n<pre>\nabandonned->abandoned\nAccomodate->accommodate\nwich->which, witch\n</pre>"
    assert parse_misspellings(wikitext) == {"abandonned", "accomodate", "wich"}


def test_pruning_drops_variants_under_three_percent_of_their_key():
    freqs = {"إلى": 0.97, "الي": 0.02, "الى": 0.01, "on": 1.0}
    assert prune_variants("ar", freqs) == {"إلى": 0.97, "on": 1.0}
    assert set(prune_variants("en", {"don't": 0.96, "dont": 0.04})) == {"don't", "dont"}


@pytest.mark.parametrize(
    "freqs, preferred",
    [
        ({"انا": 0.51, "أنا": 0.49}, "أنا"),  # a marked spelling with >= 15% share wins
        ({"انا": 0.9, "أنا": 0.1}, "انا"),  # under 15%: the most frequent wins
    ],
)
def test_arabic_preferred_spelling(freqs, preferred):
    words = flag_words("ar", freqs)
    assert [w for w, (_, flags) in words.items() if flags & PREFERRED] == [preferred]


def test_generated_forms_are_the_tsv_surfaces_wordfreq_lacks(tmp_path):
    tsv = tmp_path / "egyptian-words.tsv"
    tsv.write_text("مبنجربش\tبنجرب\nفيه\tفي\n", encoding="utf-8")
    assert generated_forms(tsv, {"فيه": 1e-3}) == {"مبنجربش"}
    assert generated_forms(tmp_path / "missing.tsv", {}) == set()


def test_generated_forms_are_candidates_never_valid():
    words = flag_words("ar", {"مبنجربش": 1e-2, "مش": 1e-2}, generated={"مبنجربش"})
    assert words["مبنجربش"][1] & (VALID | CANDIDATE) == CANDIDATE
    assert words["مش"][1] & (VALID | CANDIDATE) == VALID
