import json
from pathlib import Path

import pytest

from normalize import normalize

VECTORS = Path(__file__).resolve().parents[3] / "shared-test-vectors/normalization_vectors.json"
CASES = json.loads(VECTORS.read_text(encoding="utf-8"))["cases"]


@pytest.mark.parametrize("case", CASES, ids=[c["input"] for c in CASES])
def test_shared_vectors(case):
    assert normalize(case["input"], case["lang"]) == case["expected"]
