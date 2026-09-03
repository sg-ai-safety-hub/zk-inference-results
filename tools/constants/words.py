#!/usr/bin/env python3
"""Fail on a banned word in durable prose and print the replacement.

    python3 tools/constants/words.py README.md REPRODUCE.md docs/

Files are Markdown; directories are walked for `*.md`.  Fenced code blocks and
inline code spans are not prose and are skipped.  One fixed list with fixed
replacements: an author who hits it makes one substitution.  This file never
counts, classifies or reads issues and pull requests.
"""
import pathlib
import re
import sys

# (pattern, say instead).  Whole words, case-insensitive.
BANNED = [
    (r"levers?", "candidate optimisation, named"),
    (r"prizes?", "pre-registered threshold"),
    (r"brackets?", "acceptance range"),
    (r"bites?", "the negative control fails as expected"),
    (r"rungs?", "quantization variant"),
    (r"ladders?", "the sequence of quantization variants"),
    (r"arms?", "backend"),
    (r"(?<!residual )(?<!residual-)streams?", "work item, issue"),
    (r"wall(?![- ]clock)", "wall-clock time, end-to-end wall-clock time"),
    (r"flags?-(?:off|on)", "default build, with the flag enabled"),
    (r"bit-for-bit (?:line|control)", "reference digest, byte-for-byte regression check"),
    (r"declared", "asserted by the prover and checked by nothing"),
    (r"opt-in", "off by default"),
    (r"inert", "unconstrained padding"),
    (r"one-ahead", "pipelined with one-segment lookahead"),
    (r"leave-fraction", "fraction of committed cells removed"),
    (r"paired-equivalent", "normalised per paired evaluation"),
    (r"ties?", "binding, equality constraint"),
    (r"glue", "residual stream"),
    (r"walks?", "Freivalds check"),
    (r"fills?", "witness generation"),
    (r"famil(?:y|ies)", "kernel group"),
    (r"regions?", "AIR component"),
    (r"(?:causal |solo )?corners?", "the diagonal block"),
    (r"rectangles?", "the attention score block"),
    (r"bands?", "key tile"),
    (r"frozen spec", "the fixed quantization configuration"),
    (r"load-bearing", "required, not merely faster"),
    (r"regime [12]", "per-position accounting, per-proof accounting"),
    (r"box(?:es)?", "host"),
]
RULES = [(re.compile(rf"\b{p}\b", re.I), say) for p, say in BANNED]
FENCE = re.compile(r"^(```|~~~)")
INLINE = re.compile(r"`[^`\n]*`")


def prose_lines(text):
    """(line number, text) for every line outside fenced code, code spans removed."""
    fenced = False
    for i, line in enumerate(text.splitlines(), 1):
        if FENCE.match(line.strip()):
            fenced = not fenced
            continue
        if not fenced:
            yield i, INLINE.sub("", line)


def check(path):
    hits = []
    for n, line in prose_lines(path.read_text(encoding="utf-8")):
        for rule, say in RULES:
            for m in rule.finditer(line):
                hits.append(f"{path}:{n}: '{m.group(0)}' -> say: {say}")
    return hits


def files(args):
    for a in args:
        p = pathlib.Path(a)
        if p.is_dir():
            yield from sorted(p.rglob("*.md"))
        elif p.exists():
            yield p
        else:
            sys.exit(f"words.py: {p} does not exist")


def main(argv):
    if not argv:
        sys.exit(__doc__)
    hits = [h for f in files(argv) for h in check(f)]
    for h in hits:
        print(h)
    if hits:
        print(f"{len(hits)} banned word(s); replace each as shown.")
        return 1
    print("words.py: nothing banned.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
