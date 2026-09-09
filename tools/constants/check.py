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
    # What one proved position costs in proof bytes: the sequence's whole proof
    # over the positions it proves.  Both sides are `measured` rows of the same
    # run, so this is not a second measurement.  The serialized total is the one
    # divided at both contexts, because that is what a verifier is given.
    **{f"proof.headline.c{c}.bytes_per_position": (lambda c=c: chk(
        f"c{c} headline proof bytes per proved position",
        v(f"proof.headline.c{c}.total_bytes") / v(f"positions.headline.c{c}"),
        f"proof.headline.c{c}.bytes_per_position", 0.001))
       for c in (4096, 16384)},
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
    # What one proved position costs (docs/decisions): the seconds it took and
    # the dollars those seconds are worth at the card's reference rate.  Both
    # sides of every division are entries of this file, so nothing here is a
    # second measurement; the rate is `external` and names its source.
    **{f"secs_per_position.headline.c{c}.{s}": (lambda c=c, s=s: chk(
        f"c{c} headline seconds per proved position, {s.replace('_', ' ')}",
        v(f"secs.headline.c{c}.{s}") / v(f"positions.headline.c{c}"),
        f"secs_per_position.headline.c{c}.{s}", 0.001))
       for c in (4096, 16384) for s in ("whole_wall", "loop")},
    **{f"usd_per_1k_positions.headline.c{c}.{s}": (lambda c=c, s=s: chk(
        f"c{c} headline USD per 1,000 proved positions, {s.replace('_', ' ')}",
        v(f"secs.headline.c{c}.{s}") / v(f"positions.headline.c{c}")
        * v("cost.h100_reference_usd_per_hour") / 3600 * 1000,
        f"usd_per_1k_positions.headline.c{c}.{s}", 0.001))
       for c in (4096, 16384) for s in ("whole_wall", "loop")},
    # The same seconds over the plan instead of over the positions: what one
    # segment of the sequence cost on average, and what one of the model's 32
    # layers cost over the whole sequence.  A segment's own cost grows with the
    # prefix its token block reads, so neither row is any one segment's time.
    # The layer row divides by the layer count and not by a constant of this
    # file: 32 is the model's, the audit reads it off each run's own config and
    # refuses a run that reports another, and the two output head segments are
    # in the seconds and are not a layer.
    **{f"secs_per_segment.headline.c{c}.{s}": (lambda c=c, s=s: chk(
        f"c{c} headline seconds per segment, {s.replace('_', ' ')}",
        v(f"secs.headline.c{c}.{s}") / v(f"segments.headline.c{c}"),
        f"secs_per_segment.headline.c{c}.{s}", 0.001))
       for c in (4096, 16384) for s in ("whole_wall", "loop")},
    **{f"secs_per_layer.headline.c{c}.loop": (lambda c=c: chk(
        f"c{c} headline seconds per layer, loop",
        v(f"secs.headline.c{c}.loop") / 32,
        f"secs_per_layer.headline.c{c}.loop", 0.001))
       for c in (4096, 16384)},
    # The cost model's commitment-rate input: committed cells over the seconds
    # the commitment path took, both measured on the same proof.
    "rate.microbench.commit": lambda: chk(
        "microbench commitment rate",
        v("cells.microbench.compose_fresh") / v("secs.microbench.compose_commit") / 1e6,
        "rate.microbench.commit", 0.001),
    # Cold: the extraction the proofs read plus the proving scope, which is what
    # the sequence costs on a host that holds no witness dump yet.  At context
    # 16,384 the run extracted twice and the cold row counts the prove sweep
    # alone: the survey sweep's dumps are read by the kernel emitters and by no
    # proof, and emitting kernels is not in the cold figure either.
    **{f"secs.headline.c{ctx}.cold_{s}": (lambda ctx=ctx, s=s, ex=ex: chk(
        f"c{ctx} headline cold {s.replace('_', ' ')} seconds",
        v(ex) + v(f"secs.headline.c{ctx}.{s}"),
        f"secs.headline.c{ctx}.cold_{s}", 0.001))
       for ctx, ex in ((4096, "secs.headline.c4096.extract"),
                       (16384, "secs.headline.c16384.extract_prove"))
       for s in ("whole_wall", "loop")},
    **{f"usd_per_1k_positions.headline.c{ctx}.cold_{s}": (lambda ctx=ctx, s=s: chk(
        f"c{ctx} headline USD per 1,000 proved positions, cold {s.replace('_', ' ')}",
        v(f"secs.headline.c{ctx}.cold_{s}") / v(f"positions.headline.c{ctx}")
        * v("cost.h100_reference_usd_per_hour") / 3600 * 1000,
        f"usd_per_1k_positions.headline.c{ctx}.cold_{s}", 0.001))
       for ctx in (4096, 16384) for s in ("whole_wall", "loop")},
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
