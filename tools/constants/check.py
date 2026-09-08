#!/usr/bin/env python3
"""Consistency check on `constants.json`, then the artifact audit.

    python3 tools/constants/check.py [--strict]

Structure: every entry carries the nine fields; its grade is one of the five;
a `measured` entry names a run directory that exists, with a manifest, and an
artifact in it; an `external` entry's note carries a URL; an `asserted` entry's
note gives the reason; a `derived` entry is recomputed below from the entries
it names.  Then `audit.py` re-derives every `measured` entry from its artifact.
`--strict` also fails on a non-empty `discrepancies` list, which a release tag
requires.  This file reads no prose.
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from constants import load, value as v  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIELDS = ("value", "unit", "card", "context", "timing_scope", "grade", "note")
GRADES = ("measured", "derived", "projected", "external", "asserted")
fails = []


def chk(name, got, key, tol=0.005):
    """A `derived` entry recomputed: relative tolerance, absolute when the stored value is 0."""
    exp = v(key)
    ok = abs(got - exp) <= tol if exp == 0 else abs(got - exp) / abs(exp) <= tol
    print(f"{'OK  ' if ok else 'FAIL'}  {name:44s} stored={exp}  computed={got:,.6g}")
    if not ok:
        fails.append(f"derived: {key}")


# -- every `derived` entry this file knows how to recompute --------------------
# One line per derived constant; a derived entry with no line here fails below.
DERIVED = {
    "verinf.maverick.tok_s": lambda: chk(
        "VerInf Maverick positions/s", v("verinf.maverick.positions") / (v("verinf.maverick.prover_hours") * 3600),
        "verinf.maverick.tok_s", 0.001),
    "verinf.gb10_vs_h200_bandwidth_ratio": lambda: chk(
        "GB10 measured / H200 spec bandwidth",
        v("verinf.gb10_measured_bandwidth_gbps") / v("hardware.h200.hbm_gbps_spec"),
        "verinf.gb10_vs_h200_bandwidth_ratio", 0.001),
    # The sequence at context 4,096.  A rate is cells over the seconds at one
    # timing scope, and a positions-per-second row is the sequence's positions
    # over the same seconds; both sides of every division are `measured` rows
    # of the same run, so nothing here is a second measurement.
    **{f"rate.headline.c4096.{s}": (lambda s=s: chk(
        f"c4096 headline {s.replace('_', ' ')} rate",
        v("cells.headline.c4096.fresh") / v(f"secs.headline.c4096.{s}") / 1e6,
        f"rate.headline.c4096.{s}", 0.001))
       for s in ("commit", "stwo_total", "whole_wall", "loop")},
    # The sequence at context 16,384: the same two divisions over the same
    # kind of rows, one campaign up.
    **{f"rate.headline.c16384.{s}": (lambda s=s: chk(
        f"c16384 headline {s.replace('_', ' ')} rate",
        v("cells.headline.c16384.fresh") / v(f"secs.headline.c16384.{s}") / 1e6,
        f"rate.headline.c16384.{s}", 0.001))
       for s in ("commit", "stwo_total", "whole_wall", "loop")},
    **{f"pos_s.headline.c16384.{s}": (lambda s=s: chk(
        f"c16384 headline positions/s, {s.replace('_', ' ')}",
        v("positions.headline.c16384") / v(f"secs.headline.c16384.{s}"),
        f"pos_s.headline.c16384.{s}", 0.001))
       for s in ("whole_wall", "loop")},
    # The ablation: what one reduction removes, as a fraction of the figure
    # without it.  The key tiles' reduction is measured against no reduction at
    # all; the other four extend it, so each is measured against it.
    **{f"gkr.ablation.{name}.leave_frac_{what}": (lambda name=name, what=what, base=base: chk(
        f"{name} removes, {what}",
        1 - v(f"{'cells' if what == 'cells' else 'secs'}.ablation.c4096.{name}"
              f"{'' if what == 'cells' else '.loop'}")
          / v(f"{'cells' if what == 'cells' else 'secs'}.ablation.c4096.{base}"
              f"{'' if what == 'cells' else '.loop'}"),
        f"gkr.ablation.{name}.leave_frac_{what}", 0.002))
       for what in ("cells", "loop")
       for name, base in (("bands", "none"), ("bands_dequant", "bands"),
                          ("bands_residual_stream", "bands"), ("bands_freivalds", "bands"),
                          ("bands_attnout", "bands"), ("all_five", "none"))},
    **{f"pos_s.headline.c4096.{s}": (lambda s=s: chk(
        f"c4096 headline positions/s, {s.replace('_', ' ')}",
        v("positions.headline.c4096") / v(f"secs.headline.c4096.{s}"),
        f"pos_s.headline.c4096.{s}", 0.001))
       for s in ("whole_wall", "loop")},
    # The cost model's commitment-rate input: committed cells over the seconds
    # the commitment path took, both measured on the same proof.
    "rate.microbench.commit": lambda: chk(
        "microbench commitment rate",
        v("cells.microbench.compose_fresh") / v("secs.microbench.compose_commit") / 1e6,
        "rate.microbench.commit", 0.001),
}

URL = re.compile(r"https?://\S+")


def structure():
    doc = load()
    c = doc["constants"]
    print(f"{len(c)} constants, {len(doc['discrepancies'])} discrepancies\n")
    for k, e in c.items():
        missing = [f for f in FIELDS if f not in e]
        if missing:
            fails.append(f"{k}: missing {missing}")
            continue
        if e["grade"] not in GRADES:
            fails.append(f"{k}: grade {e['grade']!r} is not one of {GRADES}")
        if e["value"] is None and not e["note"]:
            fails.append(f"{k}: null with no note")
        if e["grade"] == "measured":
            run, art = e.get("run"), e.get("artifact")
            if not run or not art:
                fails.append(f"{k}: measured without run and artifact")
            else:
                d = ROOT / "runs" / run
                if not (d / "manifest.json").exists():
                    fails.append(f"{k}: run {run} has no manifest")
                if not (d / art).exists():
                    fails.append(f"{k}: artifact runs/{run}/{art} does not exist")
        elif e["grade"] == "external" and not URL.search(e["note"]):
            fails.append(f"{k}: external without a URL in its note")
        elif e["grade"] == "asserted" and len(e["note"]) < 20:
            fails.append(f"{k}: asserted without a reason")
        elif e["grade"] == "derived" and k not in DERIVED:
            fails.append(f"{k}: derived but check.py does not recompute it")
        elif e["grade"] == "projected" and not e.get("inputs"):
            fails.append(f"{k}: projected without `inputs` naming the model's constants")
        if "source" in e:
            fails.append(f"{k}: free-text `source` field; use run/artifact or the note")


def main(argv):
    structure()
    for k in sorted(DERIVED):
        if k in load()["constants"]:
            DERIVED[k]()
    import audit  # noqa: E402
    audit.run(fails)
    if "--strict" in argv and load()["discrepancies"]:
        fails.append(f"{len(load()['discrepancies'])} open discrepancies; a tag needs none")
    print()
    if fails:
        print("FAILURES:", *fails, sep="\n  ")
        return 1
    print("all consistent.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
