import zlib

import pytest

from fixture import FIXTURES, build_fixtures
from klex import HEADER, HEADER_SIZE, SECTION

BUILT = build_fixtures(FIXTURES / "fixture-source.json")


@pytest.mark.parametrize("lang", ["en", "ar"])
def test_fixture_is_checked_in_byte_for_byte(lang):
    assert BUILT[lang] == (FIXTURES / f"fixture-{lang}.klex").read_bytes()


@pytest.mark.parametrize("lang", ["en", "ar"])
def test_header_and_sections(lang):
    blob = BUILT[lang]
    magic, version, header_lang, crc = HEADER.unpack_from(blob)
    assert (magic, version, header_lang) == (b"KLEX", 1, lang.encode())
    assert crc == zlib.crc32(blob[HEADER_SIZE:])
    end = HEADER_SIZE
    for i in range(7):
        offset, length, _ = SECTION.unpack_from(blob, HEADER.size + i * SECTION.size)
        assert offset == end  # sections are contiguous and in order
        end = offset + length
    assert end == len(blob)

