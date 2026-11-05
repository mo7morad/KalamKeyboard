"""Turns the two downloaded Hugging Face parquet files into one text per line (run once, PROMPTS Phase 18):

    cd Tools/lexicon-builder/corpora
    curl -L -o dataflare-arabic-dialect/train.parquet --create-dirs \
      https://huggingface.co/datasets/dataflare/arabic-dialect-corpus/resolve/main/data/train-00000-of-00001.parquet
    curl -L -o fr3on-arabic-dialect/train.parquet --create-dirs \
      https://huggingface.co/datasets/fr3on/arabic-dialect-corpus/resolve/main/data/train-00000-of-00001.parquet
    uv run --no-project --python 3.11 --with pyarrow python ../../egyptian-lexicon/corpus_text.py

pyarrow is only needed to read parquet, here, once; it is in no requirements file.
Writes egyptian/masri.txt (dataflare, dialect Masri) and egyptian/comments.txt (fr3on, label EG)."""
from pathlib import Path

import pyarrow.parquet as pq

SLICES = [
    ("dataflare-arabic-dialect/train.parquet", "dialect", "Masri", "egyptian/masri.txt"),
    ("fr3on-arabic-dialect/train.parquet", "label", "EG", "egyptian/comments.txt"),
]

for source, column, value, out in SLICES:
    table = pq.read_table(source, columns=["text", column]).to_pydict()
    Path(out).parent.mkdir(exist_ok=True)
    with open(out, "w", encoding="utf-8") as lines:
        for text, tag in zip(table["text"], table[column]):
            if tag == value and text:
                lines.write(" ".join(text.split()) + "\n")
