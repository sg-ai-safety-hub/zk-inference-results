#!/usr/bin/env python3
"""Re-derive every `measured` constant from its run artifact.

One section per driver, registered in SECTIONS when the driver's first run
lands.  A section receives the audit and the constants it is responsible for,
opens `runs/<run>/<artifact>`, recomputes each value, and calls `claim`.  A
`measured` constant no section claims is a failure: the audit never accepts a
constant without an artifact it has read.  Run through `check.py`.
"""
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from constants import load  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]


class Audit:
    def __init__(self, fails):
        self.fails = fails
        self.claimed = set()
        self.npass = 0

    def claim(self, key, computed, tol=0.001):
        """`computed`, from the artifact, against the stored value."""
        e = load()["constants"][key]
        published = e["value"]
        agree = abs(computed) <= tol if published == 0 else abs(computed / published - 1) <= tol
        print(f"{'PASS' if agree else 'FAIL'}  {key:52s} stored={published}  artifact={computed:,.6g}  "
              f"[runs/{e['run']}/{e['artifact']}]")
        self.claimed.add(key)
        if agree:
            self.npass += 1
        else:
            self.fails.append(f"audit: {key}: stored {published}, artifact {computed}")

    def exact(self, key, computed):
        e = load()["constants"][key]
        agree = computed == e["value"]
        print(f"{'PASS' if agree else 'FAIL'}  {key:52s} stored={e['value']}  artifact={computed}")
        self.claimed.add(key)
        if agree:
            self.npass += 1
        else:
            self.fails.append(f"audit: {key}: stored {e['value']!r}, artifact {computed!r}")


def artifact(run, name):
    """One committed artifact of one run, as JSON."""
    return json.loads((ROOT / "runs" / run / name).read_text())


def manifest(run):
    return artifact(run, "manifest.json")


# -- headline-c4096 ------------------------------------------------------------
def _sequence_totals(run):
    """One sequence run's slices, added up.

    A plan split over several processes reports one summary per process, and
    the sequence's own cost is their sum: the segments, the fresh cells, and
    the seconds at each timing scope.  `loop` is the one scope the prover does
    not sum for us -- each process reports its own `loop_secs` -- and it is the
    only one that includes reading the witness and building the segment.
    """
    d = ROOT / "runs" / run
    t = {"segments": 0, "fresh": 0.0, "commit": 0.0, "stwo": 0.0, "whole": 0.0,
         "loop": 0.0, "peak_mib": 0, "slices": 0}
    for f in sorted(d.glob("slice_*.json")):
        s = json.loads(f.read_text())["result"]["summary"]
        t["slices"] += 1
        t["segments"] += s["n"]
        t["fresh"] += s["fresh_sum"]
        t["commit"] += s["commit_sum"]
        t["stwo"] += s["stwo_sum"]
        t["whole"] += s["whole_sum"]
        t["loop"] += s["loop_secs"]
    for f in sorted(d.glob("mem_*.json")):
        t["peak_mib"] = max(t["peak_mib"], json.loads(f.read_text())["max_mib"])
    return t


def headline_c4096(a, keys):
    """The sequence at context 4,096: the counts, the cells and the seconds.

    Every rate is `derived` and recomputed by check.py from the entries here,
    so nothing in this section divides anything.
    """
    if not keys:
        return
    run = sorted({e["run"] for e in keys.values()})[0]
    cfg = artifact(run, "config.json")
    t = _sequence_totals(run)
    print(f"  runs/{run}: {t['slices']} slices, {t['segments']} segments, "
          f"{t['fresh']:,.0f} fresh cells")
    a.exact("segments.headline.c4096", t["segments"])
    a.exact("positions.headline.c4096", cfg["positions"])
    a.claim("cells.headline.c4096.fresh", t["fresh"])
    a.claim("secs.headline.c4096.commit", t["commit"])
    a.claim("secs.headline.c4096.stwo_total", t["stwo"])
    a.claim("secs.headline.c4096.whole_wall", t["whole"])
    a.claim("secs.headline.c4096.loop", t["loop"])
    a.exact("mem.headline.c4096.peak_mib", t["peak_mib"])


# -- gkr-ablation-c4096 --------------------------------------------------------
def gkr_ablation_c4096(a, keys):
    """Each GKR reduction priced on one sample of segments.  A configuration is
    one process over the sample, so its loop time is that process's own and
    needs no summing.  Every fraction is `derived` and check.py recomputes it
    from the rows here."""
    if not keys:
        return
    run = sorted({e["run"] for e in keys.values()})[0]
    d = ROOT / "runs" / run
    cfg = artifact(run, "config.json")
    a.exact("segments.ablation.c4096", cfg["sample_segments"])
    print(f"  runs/{run}: {len(cfg['configurations'])} configurations over "
          f"{cfg['sample_segments']} segments of token block {cfg['sample_block']}")
    for name in cfg["configurations"]:
        s = json.loads((d / f"{name}.json").read_text())["result"]["summary"]
        assert s["n"] == cfg["sample_segments"], f"{name}: {s['n']} segments, not the sample's"
        a.claim(f"cells.ablation.c4096.{name}", s["fresh_sum"])
        a.claim(f"secs.ablation.c4096.{name}.loop", s["loop_secs"])
# -- memory-probe-c16384 -------------------------------------------------------
def memory_probe_c16384(a, keys):
    """The segment loops at context 16,384: what each cost and what each peaked at.

    The probe proves the same four segments once with the pipeline off and once
    with it on, so those two rows differ in one variable and the cells are the
    same cells; `layer0` is a third row, one segment on its own, and is not
    comparable with either.  A loop's peak is the largest sample the card returned while
    that loop ran; the prover's own `mem_after_prove_max` is in the loop's
    output beside it, and the audit checks that the two agree rather than
    choosing between them.  A loop the card could not hold writes its sampler
    file and no output, and has no constants here to re-derive.
    """
    if not keys:
        return
    run = sorted({e["run"] for e in keys.values()})[0]
    cfg = artifact(run, "config.json")
    print(f"  runs/{run}: block {cfg['probe_block']} of {cfg['blocks']}, "
          f"{cfg['probe_segments']} segments per loop")
    if "segments.probe.c16384" in keys:
        a.exact("segments.probe.c16384", cfg["probe_segments"])
    for tag in ("serial", "pipelined", "layer0", "pipelined_l0"):
        if f"mem.probe.c16384.{tag}_peak_mib" not in keys:
            continue
        m = artifact(run, f"mem_{tag}.json")
        d = artifact(run, f"{tag}.json")["result"]["summary"]
        sampled, reported = m["max_mib"], round(d["mem_after_prove_max"] / 2 ** 20)
        if sampled != reported:
            a.fails.append(f"audit: {tag}: the card sampler says {sampled} MiB and the "
                           f"prover says {reported} MiB for the same loop")
        if bool(d["pipe"]) != bool(m["pipeline"]):
            a.fails.append(f"audit: {tag}: the loop reports pipe={d['pipe']} where the "
                           f"probe asked for {m['pipeline']}")
        want = {"layer0": 1, "pipelined_l0": 2}.get(tag, cfg["probe_segments"])
        if d["n"] != want:
            a.fails.append(f"audit: {tag}: {d['n']} segments proved, {want} asked for")
        a.exact(f"mem.probe.c16384.{tag}_peak_mib", sampled)
        if f"secs.probe.c16384.{tag}_loop" in keys:
            a.claim(f"secs.probe.c16384.{tag}_loop", d["loop_secs"])
    if "cells.probe.c16384.fresh" in keys:
        a.claim("cells.probe.c16384.fresh",
                artifact(run, "serial.json")["result"]["summary"]["fresh_sum"])


# -- sections: (driver name, function(audit, keys)) ----------------------------
# Added when a driver's first run lands; each function re-derives the constants
# whose `run` was made by that driver.
SECTIONS = [
    ("headline-c4096", headline_c4096),
    ("gkr-ablation-c4096", gkr_ablation_c4096),
    ("memory-probe-c16384", memory_probe_c16384),
]


def run(fails):
    a = Audit(fails)
    c = load()["constants"]
    measured = {k: e for k, e in c.items() if e["grade"] == "measured"}
    print("\n" + "=" * 100)
    print(f"ARTIFACT AUDIT: {len(measured)} measured constants, {len(SECTIONS)} sections")
    print("=" * 100)
    for driver, fn in SECTIONS:
        mine = {k: e for k, e in measured.items()
                if (ROOT / "runs" / e["run"] / "manifest.json").exists()
                and manifest(e["run"]).get("driver", "").endswith(f"/{driver}.sh")}
        fn(a, mine)
    for k in sorted(set(measured) - a.claimed):
        fails.append(f"audit: {k} is measured but no section re-derives it")
    print(f"{a.npass} re-derived and agreeing; {len(set(measured) - a.claimed)} unclaimed")
    return a


if __name__ == "__main__":
    f = []
    run(f)
    sys.exit(1 if f else 0)
