#!/usr/bin/env python3
"""Re-derive every `measured` constant from its run artifact.

One section per driver, registered in SECTIONS when the driver's first run
lands.  A section receives the audit and the constants it is responsible for,
opens `runs/<run>/<artifact>`, recomputes each value, and calls `claim`.  A
`measured` constant no section claims is a failure: the audit never accepts a
constant without an artifact it has read.  A `derived` constant whose two sides
are counts in an artifact rather than entries of the file is re-derived here as
well, and `check.py`'s derived table calls the same reader.  Run through
`check.py`.
"""
import fractions
import hashlib
import json
import pathlib
import re
import statistics
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


def _slice_proof_sizes(a, run):
    """Per segment, the proof before serialization and the JSON the prover wrote.

    A slice output's chunk row carries both: `proof_bytes` is the proof
    structure's own size and `proof_ser_bytes` the length of the document that
    was written and that a verifier is given.  The rows are written as each
    segment is proved and before anything else touches the file, so they are
    true sizes even where the run later shrank the proof on the volume.  Two
    rows for one `ser_tag` would mean one segment counted twice; the plan gives
    each tag once and so must the slices.
    """
    sizes = {}
    for f in sorted((ROOT / "runs" / run).glob("slice_*.json")):
        for c in json.loads(f.read_text())["result"]["chunks"]:
            if c["ser_tag"] in sizes:
                a.fails.append(f"audit: {run}: two slice rows for segment {c['ser_tag']}")
            sizes[c["ser_tag"]] = (c["proof_bytes"], c["proof_ser_bytes"])
    return sizes


def _layers(a, run, cfg):
    """The model's layer count, which the per-layer rows divide by."""
    if cfg.get("layers") != 32:
        a.fails.append(f"audit: {run}: the run reports {cfg.get('layers')} layers and the "
                       f"derived per-layer rows divide by 32")


def _grid_verified(a, run, doc, want):
    """One verifier record per segment of a grid that was given `--verify`."""
    v = doc["verified"]
    if not v.get("all") or v.get("accepted") != want or v.get("run") != want:
        a.fails.append(f"audit: {run}: the grid verified {v.get('accepted')} of {v.get('run')} "
                       f"segment proofs, and the plan has {want}")
    secs = {}
    for c in v["chunks"]:
        if c["tag"] in secs:
            a.fails.append(f"audit: {run}: two verifier records for segment {c['tag']}")
        if not c["accepts"]:
            a.fails.append(f"audit: {run}: segment {c['tag']} was rejected")
        secs[c["tag"]] = c["verify_secs"]
    return secs


def headline_c4096(a, keys):
    """The sequence at context 4,096: the counts, the cells, the seconds, the
    size of the proof and what verifying it cost.

    Every rate is `derived` and recomputed by check.py from the entries here,
    so nothing in this section divides anything.  This run kept every proof
    whole to the end, so `grid.json` holds all 290 true serialized sizes and
    the same one grid pass replayed the verifier over each of them; the slice
    outputs carry the proof before serialization beside the same serialized
    size, and the two are required to agree segment for segment.
    """
    if not keys:
        return
    run = sorted({e["run"] for e in keys.values()})[0]
    cfg = artifact(run, "config.json")
    t = _sequence_totals(run)
    print(f"  runs/{run}: {t['slices']} slices, {t['segments']} segments, "
          f"{t['fresh']:,.0f} fresh cells")
    _layers(a, run, cfg)
    a.exact("segments.headline.c4096", t["segments"])
    a.exact("positions.headline.c4096", cfg["positions"])
    a.claim("cells.headline.c4096.fresh", t["fresh"])
    a.claim("secs.headline.c4096.commit", t["commit"])
    a.claim("secs.headline.c4096.stwo_total", t["stwo"])
    a.claim("secs.headline.c4096.whole_wall", t["whole"])
    a.claim("secs.headline.c4096.loop", t["loop"])
    a.exact("mem.headline.c4096.peak_mib", t["peak_mib"])

    grid = artifact(run, "grid.json")["result"]
    ser = {}
    for c in grid["chunks"]:
        if c["tag"] in ser:
            a.fails.append(f"audit: {run}: two grid rows for segment {c['tag']}")
        ser[c["tag"]] = c["proof_bytes"]
    if len(ser) != t["segments"]:
        a.fails.append(f"audit: {run}: the grid sizes {len(ser)} segments and the slices "
                       f"prove {t['segments']}")
    sizes = _slice_proof_sizes(a, run)
    for tag, (_, s) in sorted(sizes.items()):
        if ser.get(tag) != s:
            a.fails.append(f"audit: {run}: segment {tag} is {s} bytes in its slice output "
                           f"and {ser.get(tag)} in the grid")
    print(f"  runs/{run}: {len(ser)} serialized proofs, {sum(ser.values()):,} bytes, the "
          f"grid and the slice outputs agreeing segment for segment")
    if "proof.headline.c4096.total_bytes" in keys:
        a.exact("proof.headline.c4096.total_bytes", sum(ser.values()))
        a.exact("proof.headline.c4096.bytes_per_segment_median",
                statistics.median(ser.values()))
    if "proof.headline.c4096.bytes_per_segment_mean_last_block" in keys:
        # The like-for-like point against a run that proves one token block at
        # one prefix: the last block's layer segments, whose prefix is the whole
        # context.  The head segment over that block is not a layer segment and
        # is left out, and the count has to be the model's own layers or the row
        # is not that block.
        last = max(c["block"] for c in grid["chunks"])
        block = [c["proof_bytes"] for c in grid["chunks"]
                 if c["block"] == last and not c["head"]]
        if len(block) != cfg["layers"]:
            a.fails.append(f"audit: {run}: block {last} has {len(block)} layer segments "
                           f"and the model has {cfg['layers']}")
        a.claim("proof.headline.c4096.bytes_per_segment_mean_last_block",
                sum(block) / len(block))
    if "proof.headline.c4096.total_in_memory_bytes" in keys:
        mem = [m for m, _ in sizes.values()]
        a.exact("proof.headline.c4096.total_in_memory_bytes", sum(mem))
        a.exact("proof.headline.c4096.in_memory_bytes_per_segment_median",
                statistics.median(mem))
    if "verify.headline.c4096.secs_total" in keys:
        secs = _grid_verified(a, run, grid, t["segments"])
        a.claim("verify.headline.c4096.secs_total", sum(secs.values()))
        a.claim("verify.headline.c4096.secs_per_segment_median",
                statistics.median(secs.values()))


# -- headline-c16384: the size of the proof ------------------------------------
# No artifact of this run holds every proof's true size on its own, because the
# proofs were shrunk to the roots the link check reads as the run went.  Two
# together do.  `proofs-g<blocks>.json` is the shrink step's record: the sha256
# and the size of each of the 1,057 proofs the first pass wrote, taken before
# that proof was rewritten as its commitments alone.  `verify-fixup.json` is the
# grid over the 34 segments the fix-up re-proved, whose proofs were never
# shrunk, so its chunk rows carry their true `proof_bytes`.  33 of those 34
# supersede a first-pass record and the 34th, the head over the last prompt
# block, is a plan line the first pass did not have.
#
# The fix-up's line and the tag the first pass wrote its one head chunk under
# are named here rather than guessed, and the alignment below is what checks
# them: the group records tile the first pass's plan in plan order, and the
# first pass's plan is the committed one without the line the fix-up added.
FIXUP_ADDED = "B31head"          # the head over the last prompt block
FIRST_PASS_HEAD = ("head", "B32head")   # what the first pass called its head chunk


def _plan_tags(run):
    """Every plan line's `--ser-tag`, in plan order."""
    return [m.group(1) for m in
            (re.search(r"--ser-tag (\S+)", line)
             for line in (ROOT / "runs" / run / "plan.txt").read_text().splitlines())
            if m]


def _proof_bytes(a, run):
    """One true serialized size per segment of the plan, out of the two artifacts.

    The seven group records are read in plan order against the committed plan
    with `FIXUP_ADDED` removed, tag for tag, and the only tag allowed to differ
    is the first pass's bare `head` where that plan says `B32head`.  A record
    that does not land where the plan puts it stops the audit, so the rename is
    checked and not assumed.  A segment the fix-up re-proved then takes the
    fix-up's size and its first-pass record is dropped; every other segment
    takes the first pass's.  A segment left with no size, or with two, is a
    failure: the total is the sum over the plan and each line counts once.
    """
    broke = len(a.fails)
    plan = _plan_tags(run)
    fixup = artifact(run, "verify-fixup.json")["result"]
    fix = {c["tag"]: c["proof_bytes"] for c in fixup["chunks"]}
    for name in (FIXUP_ADDED, FIRST_PASS_HEAD[1]):
        if name not in fix:
            a.fails.append(f"audit: {run}: the fix-up did not re-prove {name}")

    rows, lo = [], 0
    for f in sorted((ROOT / "runs" / run).glob("proofs-g*.json"),
                    key=lambda p: json.loads(p.read_text())["plan_lo"]):
        g = json.loads(f.read_text())
        if g["plan_lo"] != lo or g["plan_hi"] - g["plan_lo"] != len(g["proofs"]):
            a.fails.append(f"audit: {run}: {f.name} covers plan lines "
                           f"{g['plan_lo']}-{g['plan_hi']} with {len(g['proofs'])} "
                           f"records, and the group before it ended at {lo}")
        if sum(r["bytes"] for r in g["proofs"]) != g["bytes_before"]:
            a.fails.append(f"audit: {run}: {f.name}'s records do not add up to its "
                           f"own bytes_before")
        rows += g["proofs"]
        lo = g["plan_hi"]

    first = [t for t in plan if t != FIXUP_ADDED]
    if len(rows) != len(first):
        a.fails.append(f"audit: {run}: {len(rows)} first-pass records against "
                       f"{len(first)} plan lines without {FIXUP_ADDED}")
        return None
    for want, row in zip(first, rows):
        got = FIRST_PASS_HEAD[1] if row["tag"] == FIRST_PASS_HEAD[0] else row["tag"]
        if got != want:
            a.fails.append(f"audit: {run}: the first pass wrote {row['tag']} where "
                           f"the plan has {want}")

    sizes = {}
    for t, row in zip(first, rows):
        if t not in fix:
            sizes.setdefault(t, []).append(row["bytes"])
    for c in fixup["chunks"]:
        sizes.setdefault(c["tag"], []).append(c["proof_bytes"])
    for t in plan:
        n = len(sizes.get(t, ()))
        if n != 1:
            a.fails.append(f"audit: {run}: segment {t} takes {n} sizes, not one")
    for t in sorted(set(sizes) - set(plan)):
        a.fails.append(f"audit: {run}: {t} has a size and is not in the plan")
    if len(a.fails) != broke:
        return None
    kept = len(first) - len(fix) + 1        # the fix-up's own added line is not one
    print(f"  runs/{run}: {len(plan)} segments sized once each -- {kept} from the "
          f"first pass and {len(fix)} from the fix-up, which superseded "
          f"{len(fix) - 1} first-pass records")
    return {t: v[0] for t, v in sizes.items()}


def _verify_secs(a, run):
    """One verifier record per segment of the plan, out of the same two passes.

    The proofs were replayed where they were still whole: the first pass's
    group by group as the run went, the fix-up's over the 34 it re-proved.  The
    partition is the one `_proof_bytes` takes, so a segment the fix-up re-proved
    takes the fix-up's seconds and every other takes the first pass's, and a
    segment left with none, or with two, is a failure.  A rejected proof is one
    as well: seconds for a proof the verifier did not accept are not a number
    about this sequence.
    """
    broke = len(a.fails)
    plan = _plan_tags(run)
    fixup = artifact(run, "verify-fixup.json")["result"]
    fix = _grid_verified(a, run, fixup, len(fixup["chunks"]))
    group = {}
    for f in sorted((ROOT / "runs" / run).glob("verify-g*.json")):
        g = json.loads(f.read_text())["result"]
        for tag, secs in _grid_verified(a, run, g, len(g["chunks"])).items():
            tag = FIRST_PASS_HEAD[1] if tag == FIRST_PASS_HEAD[0] else tag
            if tag in group:
                a.fails.append(f"audit: {run}: two group verifier records for {tag}")
            group[tag] = secs
    out = {}
    for t in plan:
        if t in fix:
            out[t] = fix[t]
        elif t in group:
            out[t] = group[t]
        else:
            a.fails.append(f"audit: {run}: segment {t} was never replayed by the verifier")
    for t in sorted((set(fix) | set(group)) - set(plan)):
        a.fails.append(f"audit: {run}: {t} was verified and is not in the plan")
    if len(a.fails) != broke:
        return None
    print(f"  runs/{run}: {len(out)} segment proofs replayed once each -- "
          f"{len(out) - len(fix)} by the first pass and {len(fix)} by the fix-up")
    return out


# -- headline-c16384 -----------------------------------------------------------
def headline_c16384(a, keys):
    """The sequence at context 16,384: the same arithmetic as the c4096 row.

    The plan is proved in groups of token blocks and each group in processes of
    64 segments, so there are more slice outputs than at the smaller context;
    the grouping sits between the processes and is in none of the four timing
    scopes, so the run's own cost is still the sum over the slices and
    `_sequence_totals` reads this run exactly as it reads that one.  Every rate
    is `derived` and recomputed by check.py from the entries here, and so is the
    proof size per proved position, over the total `_proof_bytes` assembles.
    """
    if not keys:
        return
    run = sorted({e["run"] for e in keys.values()})[0]
    cfg = artifact(run, "config.json")
    t = _sequence_totals(run)
    print(f"  runs/{run}: {t['slices']} slices, {t['segments']} segments, "
          f"{t['fresh']:,.0f} fresh cells")
    _layers(a, run, cfg)
    a.exact("segments.headline.c16384", t["segments"])
    a.exact("positions.headline.c16384", cfg["positions"])
    a.claim("cells.headline.c16384.fresh", t["fresh"])
    a.claim("secs.headline.c16384.commit", t["commit"])
    a.claim("secs.headline.c16384.stwo_total", t["stwo"])
    a.claim("secs.headline.c16384.whole_wall", t["whole"])
    a.claim("secs.headline.c16384.loop", t["loop"])
    a.exact("mem.headline.c16384.peak_mib", t["peak_mib"])
    sizes = _slice_proof_sizes(a, run)
    if "proof.headline.c16384.total_bytes" in keys:
        assembled = _proof_bytes(a, run)
        if assembled is not None:
            # The slice outputs were written as each segment was proved, before
            # any proof was shrunk, so their `proof_ser_bytes` is a second
            # witness of the same 1,058 sizes -- one written by the prover, one
            # by the shrink step and the fix-up's grid.  They are required to
            # agree segment for segment, which is what lets the median be read
            # off the slices.
            for tag, b in sorted(assembled.items()):
                s = sizes.get(tag, (None, None))[1]
                if s != b:
                    a.fails.append(f"audit: {run}: segment {tag} is {s} bytes in its slice "
                                   f"output and {b} in the record the total is assembled from")
            if set(sizes) != set(assembled):
                a.fails.append(f"audit: {run}: the slices size {len(sizes)} segments and the "
                               f"assembled record {len(assembled)}")
            a.exact("proof.headline.c16384.total_bytes", sum(assembled.values()))
    if "proof.headline.c16384.bytes_per_segment_median" in keys:
        a.exact("proof.headline.c16384.bytes_per_segment_median",
                statistics.median(s for _, s in sizes.values()))
    if "proof.headline.c16384.total_in_memory_bytes" in keys:
        mem = [m for m, _ in sizes.values()]
        a.exact("proof.headline.c16384.total_in_memory_bytes", sum(mem))
        a.exact("proof.headline.c16384.in_memory_bytes_per_segment_median",
                statistics.median(mem))
    if "verify.headline.c16384.secs_total" in keys:
        secs = _verify_secs(a, run)
        if secs is not None:
            a.claim("verify.headline.c16384.secs_total", sum(secs.values()))
            a.claim("verify.headline.c16384.secs_per_segment_median",
                    statistics.median(secs.values()))
    if "verify.headline.c16384.link_check_secs" in keys:
        a.exact("verify.headline.c16384.link_check_secs",
                artifact(run, "timing.json")["grid_seconds"])


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
# -- control-flags-off-c4096 ---------------------------------------------------
def control_flags_off_c4096(a, keys):
    """The same sequence with the five reductions off, one segment in flight.

    A plan split over processes reports one summary per process, so this run is
    read exactly as the headline rows are.  The loop key says serial because
    this loop is: the headline row's overlaps one segment's generation with
    another's proving and this one does not, so the two are not a pair at that
    scope while their cells are one.  The fraction the reductions remove is
    `derived` and check.py recomputes it from the two cell counts."""
    if not keys:
        return
    run = sorted({e["run"] for e in keys.values()})[0]
    cfg = artifact(run, "config.json")
    t = _sequence_totals(run)
    assert cfg["pipeline"] == 0, f"{run}: the control is the run with one segment in flight"
    print(f"  runs/{run}: {t['slices']} slices, {t['segments']} segments, "
          f"{t['fresh']:,.0f} fresh cells, one segment in flight")
    a.exact("segments.control.c4096", t["segments"])
    a.claim("cells.control.c4096.fresh", t["fresh"])
    a.claim("secs.control.c4096.serial_loop", t["loop"])
    a.exact("mem.control.c4096.peak_mib", t["peak_mib"])


# -- negative-controls ---------------------------------------------------------
def negative_controls(a, keys):
    """The control suite: what refused, what was skipped by name, what crashed.

    Every number here is a count the run's own gate wrote into `controls.json`,
    except the accepted controls, which are counted again from each target's
    probe record: the gate fails the run on one, so a stored zero has to be
    re-derived from the records and not from the gate that already refused to
    pass a non-zero."""
    if not keys:
        return
    run = sorted({e["run"] for e in keys.values()})[0]
    c = artifact(run, "controls.json")
    accepted = 0
    for name in sorted(c["targets"]):
        doc = artifact(run, f"{name}.json")
        accepted += sum(1 for p in doc["result"]["probes"] if p.get("accepted"))
    print(f"  runs/{run}: {len(c['targets'])} targets, {c['designed_rejections']} designed "
          f"rejections, {c['crashes']} crash(es), {accepted} accepted")
    a.exact("controls.suite.designed_rejections", c["designed_rejections"])
    a.exact("controls.suite.accepted", accepted)
    a.exact("controls.suite.crashes", c["crashes"])
    real = c["targets"]["real"]
    a.exact("controls.real.c4096.designed_rejections", real["designed_rejections"])
    a.exact("controls.real.c4096.skipped_by_name", len(real["skipped"]))


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


# -- model-commitment ----------------------------------------------------------
def model_commitment(a, keys):
    """The published model commitment, and the digest a paper would cite.

    The digest is recomputed here from the table itself rather than read off
    the field beside it: a digest a run states about itself is a claim, not a
    check.  The two derivations agreeing, and every segment's model root and
    shape root being the manifest's, are gate conditions of the run and are
    checked again here so that a run directory edited afterwards cannot pass.
    """
    if not keys:
        return
    run = sorted({e["run"] for e in keys.values()})[0]
    c = artifact(run, "commitment.json")
    g = artifact(run, "grid.json")["result"]
    canon = "\n".join(f"{r['layer']} {r['model_root']} {r['model']}"
                       for r in c["table"]) + "\n"
    digest = hashlib.sha256(canon.encode()).hexdigest()
    bad_model = sum(1 for x in g["model_roots"]["chunks"]
                    if not x["ok"] or not x["model_ok"])
    bad_pre = sum(1 for x in g["pre_roots"]["chunks"]
                  if not x["ok"] or not x["model_ok"])
    print(f"  runs/{run}: {c['layers']} layer coordinates over {c['cells']} cells; "
          f"{len(g['model_roots']['chunks'])} model roots and "
          f"{len(g['pre_roots']['chunks'])} shape roots compared, "
          f"{bad_model + bad_pre} not the commitment's")
    if c["verifier_form_disagreements"]:
        a.fails.append("audit: the two derivations of the commitment disagree: "
                       f"{c['verifier_form_disagreements']}")
    if bad_model or bad_pre:
        a.fails.append(f"audit: {bad_model} model root(s) and {bad_pre} shape root(s) "
                       "are not the published commitment's")
    a.exact("commitment.c4096.layers", c["layers"])
    a.exact("commitment.c4096.cells", c["cells"])
    a.exact("commitment.c4096.sha256", digest)


# -- moe-routing ---------------------------------------------------------------
# What a mixture model's router actually did, against what a counted mixture row
# assumes it does.  One key per (model, context, block size), and the reader
# parses the key rather than holding a table of them: the driver takes the model
# on its command line, so a second model is a second run of the same driver and
# not a second reader here.  Written with the driver and inert until its first
# run lands, because a `measured` constant no section re-derives is a failure and
# the recording is then a merge and nothing else.
MOE_KEY = re.compile(
    r"^moe\.routing\.(?P<model>[a-z0-9_]+)\.c(?P<ctx>\d+)\.s(?P<s>\d+)\.(?P<field>\w+)$")


def _moe_block(run, key):
    """The (result, block, field) a `moe.routing.*` key names, out of the run's
    artifact, or (None, None, None) where that run measured no such block."""
    m = MOE_KEY.match(key)
    if not m:
        return None, None, None
    res = artifact(run, "routing.json")["result"]
    if res.get("key_slug") != m["model"]:
        return None, None, None
    b = res.get("contexts", {}).get(m["ctx"], {}).get("blocks", {}).get(m["s"])
    return res, b, m["field"]


def moe_routing(a, keys):
    """Every figure here is a mean over the mixture layers and the blocks each
    prompt divides into, and the file carries the per-layer means: so the mean is
    re-derived from them rather than read back.  Each layer measured the same
    number of blocks, which is what makes the mean of the per-layer means the
    figure and not an average of averages over unequal sets."""
    for key, e in sorted(keys.items()):
        _res, b, field = _moe_block(e["run"], key)
        if b is None:
            a.fails.append(f"audit: {key}: runs/{e['run']}/routing.json holds no block "
                           f"of this model at this context and block size")
            continue
        rows = b["layers"]
        if field in ("distinct_experts_mean", "tokens_per_expert_max_mean"):
            a.claim(key, sum(r[field] for r in rows) / len(rows))
        else:
            a.fails.append(f"audit: {key}: this section re-derives no field named "
                           f"{field!r}")


def moe_routing_uniform(key):
    """`E (1 - (1 - k/E)^S)`: what the routing assumption gives for the same
    block, out of the experts and the top-k the run recorded.  Those are counts
    in an artifact and not entries of the constants file, which is why the entry
    is `derived` and why `check.py`'s derived table calls this reader."""
    e = load()["constants"][key]
    res, _b, field = _moe_block(e["run"], key)
    if res is None:
        raise SystemExit(f"audit: {key}: runs/{e['run']}/routing.json is not this "
                         f"model's routing")
    if field != "distinct_experts_uniform":
        raise SystemExit(f"audit: {key}: this reader is the routing assumption's own "
                         f"answer and nothing else")
    experts, topk = res["experts"], res["topk"]
    s = int(MOE_KEY.match(key)["s"])
    return experts * (1.0 - (1.0 - topk / experts) ** s)


# -- sections: (driver name, function(audit, keys)) ----------------------------
# Added when a driver's first run lands; each function re-derives the constants
# whose `run` was made by that driver.
# -- microbench ----------------------------------------------------------------
# Every criterion identifier this run froze a time for, and the file the audit
# reads it back from.  A criterion estimate is in nanoseconds; the constants are
# in seconds, which is the only arithmetic here.
_BENCH_TIMES = {
    "hash.merkle_simd_secs": "merkle throughput/simd merkle",
    "hash.merkle_cpu_secs": "merkle throughput/cpu merkle",
    "field.m31_mul_secs": "M31 mul",
    "field.m31_add_secs": "M31 add",
    "field.qm31_mul_secs": "SecureField mul",
    "field.m31_mul_simd_secs": "mul_simd",
    "lookup.simd_generic_logup_secs": "simd generic logup lookup 2_16",
    "lookup.cpu_generic_logup_secs": "cpu generic logup lookup 2_16",
    "fri.fold_line_secs": "fold_line",
}


def microbench(a, keys):
    """The cost model's inputs: one composed segment, and the primitives under it.

    The composed segment is the only thing in this run that proves anything, so
    it is the run's binding table as well as its commitment rate, and the audit
    checks that it accepted and bound every edge before it takes a number off
    it.  The rest are the vendored library's own benchmarks, whose estimate
    files carry the mean in nanoseconds.
    """
    if not keys:
        return
    run = sorted({e["run"] for e in keys.values()})[0]
    if {"cells.microbench.compose_fresh", "secs.microbench.compose_commit"} & set(keys):
        doc = artifact(run, "compose-simd.json")
        p, prov = doc["result"]["point"], doc["provenance"]
        if not p["accepts"]:
            a.fails.append("audit: microbench's composed segment did not accept")
        if prov["unsound_skips"]:
            a.fails.append(f"audit: microbench's segment ran with skips {prov['unsound_skips']}")
        if not prov["binding"]["all_bound"]:
            a.fails.append(f"audit: microbench's segment left edges {prov['binding']['unbound']} unbound")
        print(f"  runs/{run}: one composed segment, {p['cells']['fresh']:,} fresh cells, "
              f"{len(_BENCH_TIMES)} benchmark times")
        if "cells.microbench.compose_fresh" in keys:
            a.exact("cells.microbench.compose_fresh", p["cells"]["fresh"])
        if "secs.microbench.compose_commit" in keys:
            a.claim("secs.microbench.compose_commit", p["phases"]["commit_secs"])
    for key, ident in _BENCH_TIMES.items():
        if key in keys:
            d = artifact(run, f"criterion/{ident}/new/estimates.json")
            a.claim(key, d["mean"]["point_estimate"] / 1e9)


# -- sections: (driver name, function(audit, keys)) ----------------------------
# Added when a driver's first run lands; each function re-derives the constants
# whose `run` was made by that driver.

# -- the quality campaigns -----------------------------------------------------
def _quality(group):
    """One perplexity campaign's rows, re-derived from the harness's own output.

    A harness run proves nothing, so the first thing the audit checks is that it
    says so: `kind` is `harness`, there is no proof digest and there is no
    binding table.  A run that claimed to be a harness run and carried either
    would have been refused by `lib/manifest.py` before it got here, and this is
    the same check from the other side.

    The perplexities come from the rows the harness wrote.  The differences
    against the float reference and their standard errors are the harness's too,
    computed there from the per-token losses that are in the run's own `nll/`
    directory; the audit reads them back rather than recomputing them, because
    a paired standard error over twenty thousand positions is not arithmetic
    this file can do without numpy, which the checks run without.
    """
    def section(a, keys):
        if not keys:
            return
        run = sorted({e["run"] for e in keys.values()})[0]
        doc = artifact(run, "ppl.json")
        p, rows = doc["provenance"], doc["result"]
        pairs = doc.get("paired", {})
        cfg = artifact(run, "config.json")
        if p.get("kind") != "harness":
            a.fails.append(f"audit: {run} is not marked a harness run")
        if p.get("binding") is not None or p.get("proof_sha256") is not None:
            a.fails.append(f"audit: {run} says it is a harness run and carries a proof")
        print(f"  runs/{run}: {p['model']} at {str(p['model_revision'])[:12]}, "
              f"{len(rows)} variants on the {p['device']}, "
              f"corpus {p['corpus']['sha256'][:16]}")
        cpath = ROOT / "runs" / run / "cosine.json"
        crows = {}
        if cpath.exists():
            cdoc = artifact(run, "cosine.json")
            crows = cdoc["result"] if "provenance" in cdoc else cdoc
        for spec in cfg["specs"].split():
            k = spec.replace("-", "_")
            if rows.get(spec) and rows[spec]["chunks"] != cfg["chunks"]:
                a.fails.append(f"audit: {spec} was measured on {rows[spec]['chunks']} chunks, "
                               f"not the {cfg['chunks']} the run configured")
            for key, value in ((f"{group}.ppl_{k}", rows.get(spec, {}).get("ppl")),
                               (f"{group}.ppl_{k}_delta_pct", pairs.get(spec, {}).get("delta_pct")),
                               (f"{group}.ppl_{k}_se_nats", pairs.get(spec, {}).get("se_nats")),
                               (f"{group}.cosine_{k}", crows.get(spec, {}).get("cosine_mean"))):
                if key in keys:
                    if value is None:
                        a.fails.append(f"audit: {key} has no number in the run's outputs")
                    else:
                        a.claim(key, value)
    return section


# -- sections: (driver name, function(audit, keys)) ----------------------------
# Added when a driver's first run lands; each function re-derives the constants
# whose `run` was made by that driver.

# -- quality-suite -------------------------------------------------------------
_TASK_SCORE = {"gpqa_d": ("gpqa", "acc"), "mmlu_pro": ("mmlu_pro", "acc"),
               "ifeval_prompt_strict": ("ifeval", "prompt_strict")}
# the perplexity rows this page names differently from their variants
_DOC_SPELLING = {"static": "ppl_static_w8a8"}


def quality_suite(a, keys):
    """The 8B model's quality rows: perplexity, three task suites, and the size
    of the suite itself.

    A harness run proves nothing, so the audit first checks that it says so.
    Then every number is read back from the file the harness wrote it into: the
    perplexities and their paired differences from the rows, the task scores and
    their item-by-item differences from the scored suites, and the suite's own
    position counts from the per-item rows those scores were computed over.
    """
    if not keys:
        return
    run = sorted({e["run"] for e in keys.values()})[0]
    ppl = artifact(run, "ppl.json")
    p, rows, pairs = ppl["provenance"], ppl["result"], ppl.get("paired", {})
    cfg = artifact(run, "config.json")
    if p.get("kind") != "harness":
        a.fails.append(f"audit: {run} is not marked a harness run")
    if p.get("binding") is not None or p.get("proof_sha256") is not None:
        a.fails.append(f"audit: {run} says it is a harness run and carries a proof")
    tdoc = artifact(run, "tasks.json")
    tasks = tdoc["result"] if "provenance" in tdoc else tdoc
    print(f"  runs/{run}: {p['model']} at {str(p['model_revision'])[:12]}, "
          f"{len(rows)} variants and {len(tasks)} scored configurations")
    for spec in cfg["ppl_specs"].split():
        n = _DOC_SPELLING.get(spec, "ppl_" + spec.replace("-", "_"))
        for key, value in ((f"quality.8b.{n}", rows.get(spec, {}).get("ppl")),
                           (f"quality.8b.{n}_delta_pct", pairs.get(spec, {}).get("delta_pct")),
                           (f"quality.8b.{n}_se_nats", pairs.get(spec, {}).get("se_nats"))):
            if key in keys:
                if value is None:
                    a.fails.append(f"audit: {key} has no number in the run's outputs")
                else:
                    a.claim(key, value)
    for label, (task, field) in _TASK_SCORE.items():
        for spec in cfg["task_specs"].split():
            t = tasks.get(spec, {}).get(task)
            key = f"quality.8b.{label}_{spec.replace('-', '_')}"
            if key in keys:
                if not t:
                    a.fails.append(f"audit: {key}: {task} under {spec} did not score")
                    continue
                if not t["complete"]:
                    a.fails.append(f"audit: {task} under {spec} scored only part of the suite")
                a.claim(key, t[field])
        q = (tasks.get("y-delay-vw12", {}).get(task) or {}).get("paired_vs_fp32")
        for key, value in ((f"quality.8b.{label}_paired_delta_y_delay_vw12",
                            (q or {}).get("delta")),
                           (f"quality.8b.{label}_paired_se_vs_fp32_y_delay_vw12",
                            (q or {}).get("se"))):
            if key in keys:
                if value is None:
                    a.fails.append(f"audit: {key} has no number in the run's outputs")
                else:
                    a.claim(key, value)
    # the suite's own size, counted from the per-item rows the scores came from
    if {"suite.decode_positions", "suite.e11_positions"} & set(keys):
        import glob
        items = prompt = gen = 0
        for task in ("gpqa", "mmlu_pro", "ifeval"):
            for f in glob.glob(str(ROOT / "runs" / run / "tasks" /
                                   f"{task}.y-delay-vw12.*.jsonl")):
                for line in open(f):
                    if line.strip():
                        d = json.loads(line)
                        items += 1
                        prompt += d.get("n_prompt", 0)
                        gen += d.get("n_gen", 0)
        if "suite.decode_positions" in keys:
            a.exact("suite.decode_positions", items + gen)
        if "suite.e11_positions" in keys:
            a.exact("suite.e11_positions", prompt + gen)


# -- sections: (driver name, function(audit, keys)) ----------------------------
# Added when a driver's first run lands; each function re-derives the constants
# whose `run` was made by that driver.

# -- prefill-sweep -------------------------------------------------------------
def prefill_sweep(a, keys):
    """The key tiles' cost against the block length, at the context equal to it.

    Each point's cells come from that point's own proof, which the audit opens
    and checks accepted with no skip and every edge bound.  The two coefficients
    are refitted here from those points rather than read out of the run's
    summary: two unknowns and no intercept, which is four lines of arithmetic
    and worth doing rather than trusting.
    """
    if not keys:
        return
    run = sorted({e["run"] for e in keys.values()})[0]
    cfg = artifact(run, "config.json")
    pts = []
    for s in [int(x) for x in cfg["points"].split()]:
        doc = artifact(run, f"dd_s{s}.json")
        p, prov = doc["result"]["point"], doc["provenance"]
        if not p["accepts"] or p.get("off_table"):
            a.fails.append(f"audit: S={s} did not accept, or has {p.get('off_table')} off the table")
        if prov["unsound_skips"]:
            a.fails.append(f"audit: S={s} ran with skips {prov['unsound_skips']}")
        if not prov["binding"]["all_bound"]:
            a.fails.append(f"audit: S={s} left edges {prov['binding']['unbound']} unbound")
        pts.append((s, p["family_cells"]["key_tiles"], p["cells"]["fresh"]))
        for key, value in ((f"cells.b9_prefill.c{s}.key_tiles", p["family_cells"]["key_tiles"]),
                           (f"cells.b9_prefill.c{s}.fresh", p["cells"]["fresh"])):
            if key in keys:
                a.exact(key, value)
    print(f"  runs/{run}: {len(pts)} points, {cfg['sweep_variant']}, "
          f"key tiles {pts[0][1]:,} to {pts[-1][1]:,}")
    if {"design.prefill_key_tile_s_squared", "design.prefill_key_tile_s"} & set(keys):
        # least squares for y = g S^2 + d S, no intercept
        a11 = sum(s ** 4 for s, _, _ in pts); a12 = sum(s ** 3 for s, _, _ in pts)
        a22 = sum(s ** 2 for s, _, _ in pts)
        b1 = sum(s ** 2 * y for s, y, _ in pts); b2 = sum(s * y for s, y, _ in pts)
        det = a11 * a22 - a12 * a12
        g = (b1 * a22 - b2 * a12) / det
        d = (a11 * b2 - a12 * b1) / det
        resid = max(abs(y - (g * s * s + d * s)) for s, y, _ in pts)
        if resid > 1.0:
            a.fails.append(f"audit: the two-coefficient form does not reproduce the points; "
                           f"largest residual {resid:,.0f} cells")
        if "design.prefill_key_tile_s_squared" in keys:
            a.claim("design.prefill_key_tile_s_squared", g)
        if "design.prefill_key_tile_s" in keys:
            a.claim("design.prefill_key_tile_s", d)


# -- sections: (driver name, function(audit, keys)) ----------------------------
# Added when a driver's first run lands; each function re-derives the constants
# whose `run` was made by that driver.

# -- prefill-sweep-8b ----------------------------------------------------------
def _key_tile_solve(pts, field):
    """The key tile family's three coefficients over the sweep's points.

    The sound defaults tile the prefix in blocks of S -- C/S sub-key-tiles over
    the same heads, the per-token component on the first of them -- and add one
    square diagonal block.  So the family is C/S + 1 copies of one S by S tile
    plus that per-token component, and with T(S) = a S^2 + b S,

        cells(S, C) = (C/S + 1) T(S) + r S = a (S*C + S^2) + b C + g S,  g = b + r

    The prefix key tile's own (S*C, C, S) triple, which is what the cost model
    reads, is (a, b, g - b).  At C = S the second and third columns are both S,
    so a point with C != S is what separates b from g.  Exact rationals: the
    normal equations carry entries near 2^80 and a float solve loses the low
    digits of what is supposed to be an integer count of cells.
    """
    F = fractions.Fraction
    xs = [(F(s * c + s * s), F(c), F(s)) for s, c, _ in pts]
    ys = [F(v[field]) for _, _, v in pts]
    n = 3
    m = [[sum(x[i] * x[j] for x in xs) for j in range(n)]
         + [sum(x[i] * y for x, y in zip(xs, ys))] for i in range(n)]
    for i in range(n):
        pr = next((r for r in range(i, n) if m[r][i]), None)
        if pr is None:
            return None
        m[i], m[pr] = m[pr], m[i]
        pv = m[i][i]
        m[i] = [v / pv for v in m[i]]
        for r in range(n):
            if r != i and m[r][i]:
                f = m[r][i]
                m[r] = [v - f * w for v, w in zip(m[r], m[i])]
    a, b, g = (m[i][n] for i in range(n))
    resid = max(abs(y - (a * x[0] + b * x[1] + g * x[2])) for x, y in zip(xs, ys))
    return a, b, g, resid


def prefill_sweep_8b(a, keys):
    """The key tiles' cost in the block length and the prefix, at the 8B width.

    Each point's cells come from that point's own proof, which the audit opens
    and checks accepted with no skip and every edge bound.  The three
    coefficients are re-solved here from those points rather than read out of
    the run's summary.  With three points and three coefficients the solve is
    exact, so the residual it reports is zero by construction and is not a check
    of the form; the audit still fails a non-zero one, because a non-zero
    residual on an exact solve would mean the arithmetic here is wrong.

    Only the committed side is claimed.  The interaction side does not take this
    form under the five GKR reductions the paper reports, and the run's
    per-key-tile split is the evidence: at a 256-token block over a 4,096-key
    prefix the 48 prefix sub-key-tiles do not all cost the same and none of them
    costs what the diagonal block does.
    """
    if not keys:
        return
    run = sorted({e["run"] for e in keys.values()})[0]
    cfg = artifact(run, "config.json")
    grid = [(int(x.split(":")[0]), int(x.split(":")[0])) for x in cfg["points"].split()]
    grid += [(int(x.split(":")[0]), int(x.split(":")[1]))
             for x in cfg["extra_points"].split()]
    pts = []
    for s, c in grid:
        doc = artifact(run, f"dd_s{s}_c{c}.json")
        p, prov = doc["result"]["point"], doc["provenance"]
        if not p["accepts"] or p.get("off_table"):
            a.fails.append(f"audit: S={s} C={c} did not accept, or has "
                           f"{p.get('off_table')} off the table")
        if prov["unsound_skips"]:
            a.fails.append(f"audit: S={s} C={c} ran with skips {prov['unsound_skips']}")
        if not prov["binding"]["all_bound"]:
            a.fails.append(f"audit: S={s} C={c} left edges {prov['binding']['unbound']} unbound")
        pr = p["params"]
        width = pr["hd"] * pr["nh"]
        if (pr["hd"], pr["nh"]) != (128, 32) or any(m["n_in"] != width or m["n_out"] != width
                                                    for m in pr["mats"]):
            a.fails.append(f"audit: S={s} C={c} is not the 8B width -- 32 heads of 128 "
                           "with every matmul equal to their product")
        if not pr["diagonal_block"] or (s, c) != (pr["s"], pr["c"]):
            a.fails.append(f"audit: S={s} C={c} is not the point its file is named for, "
                           "or was proved without the diagonal block")
        fam = p["family_cells"]
        base = fam["key_tiles"]
        inter = fam["interaction_by_family"].get("key_tiles", {}).get("cells", 0)
        v = {"key_tiles": base, "key_tiles_interaction": inter,
             "key_tiles_fresh": base + inter, "fresh": p["cells"]["fresh"]}
        pts.append((s, c, v))
        for suffix in ("key_tiles", "key_tiles_fresh", "fresh"):
            key = f"cells.b9_prefill_8b.s{s}c{c}.{suffix}"
            if key in keys:
                a.exact(key, v[suffix])
    print(f"  runs/{run}: {len(pts)} points, {cfg['variant']}, "
          f"key tiles {pts[0][2]['key_tiles']:,} to {pts[-1][2]['key_tiles']:,}")
    off_diagonal = [1 for s, c, _ in pts if s != c]
    if not off_diagonal:
        a.fails.append("audit: the sweep has no point with C != S, so the C and S "
                       "coefficients are one variable")
        return
    # The committed side only.  With the five GKR reductions on, the key tiles'
    # interaction is not of this form -- the prefix's sub-key-tiles and the
    # diagonal block do not cost the same there, and solving it returns a
    # negative per-token component -- so `attention_grid.fresh_cell_coeffs` is
    # not claimed from this run and the run's own per-key-tile split says why.
    key = "attention_grid.base_cell_coeffs"
    if key in keys:
        got = _key_tile_solve(pts, "key_tiles")
        if got is None:
            a.fails.append(f"audit: {key}: the three coefficients are not separable "
                           "over this run's points")
            return
        coeff_a, coeff_b, coeff_g, resid = got
        if resid:
            a.fails.append(f"audit: {key}: the three-coefficient form leaves a residual "
                           f"of {float(resid):,.0f} cells")
        a.exact(key, [float(coeff_a), float(coeff_b), float(coeff_g - coeff_b)])


# -- predict-14b ---------------------------------------------------------------
def predict_14b(a, keys):
    """The 14B model's layer proofs: what the shape cost, added up over its layers.

    The run's own summary is written from the per-layer outputs by the job, and
    this section re-derives that summary from those outputs rather than trusting
    it: every layer's proof is opened, checked to have accepted with no skip and
    every edge bound, and the sums are taken here.

    The comparison against the registered prediction is not recomputed here:
    `harness/eval/predict/compare.py` makes it, from these same outputs, and the
    run carries both of its documents. What this file re-derives of it is the
    one row that is a constant, `e4.qwen2p5_14b.c4096.rho`, which `check.py`
    computes from the measured entry below and the registered figure that
    `registered_14b` reads out of the registration run.
    """
    if not keys:
        return
    run = sorted({e["run"] for e in keys.values()})[0]
    cfg = artifact(run, "config.json")
    n = cfg["layers"]
    fresh = tiles = 0.0
    rss = 0
    for k in range(n):
        doc = artifact(run, f"L{k}.json")
        p, prov = doc["result"]["point"], doc["provenance"]
        if not p["accepts"]:
            a.fails.append(f"audit: layer {k} did not accept")
        if p.get("off_table") or p.get("ref_mismatch"):
            a.fails.append(f"audit: layer {k}: off_table {p.get('off_table')}, "
                           f"ref_mismatch {p.get('ref_mismatch')}")
        if prov["unsound_skips"]:
            a.fails.append(f"audit: layer {k} ran with skips {prov['unsound_skips']}")
        if not prov["binding"]["all_bound"]:
            a.fails.append(f"audit: layer {k} left edges {prov['binding']['unbound']} unbound")
        fresh += p["cells"]["fresh"]
        tiles += p["family_cells"]["key_tiles"]
        rss = max(rss, p["peak_rss_bytes"])
    print(f"  runs/{run}: {n} layers, {fresh:,.0f} fresh cells, "
          f"largest process {rss / 2 ** 30:.1f} GiB")
    for key, value in (
            ("e4.qwen2p5_14b.c4096.layers", n),
            ("e4.qwen2p5_14b.c4096.cells_fresh", fresh),
            ("e4.qwen2p5_14b.c4096.cells_per_token_layers", fresh / cfg["s"]),
            ("e4.qwen2p5_14b.c4096.key_tiles_cells", tiles),
            ("e4.qwen2p5_14b.c4096.peak_rss_bytes", rss)):
        if key in keys:
            if isinstance(value, int):
                a.exact(key, value)
            else:
                a.claim(key, value)


# -- the registered prediction the 14B measurement is compared against ---------
# Not a section: a registration measures nothing, so no `measured` constant
# names its run.  It is the reader for the one derived row that is read out of
# it, and `check.py`'s derived table calls it.
_PREDICTED_14B = "e4.qwen2p5_14b.c4096.predicted_cells_per_token_layers"


def registered_14b(ctx=4096):
    """The registered prediction's own layers-only figure for the 14B at `ctx`.

    Read out of the registration the entry names, and checked to be the document
    whose digest that entry's note carries: a registration is the thing that
    must not move after it is made, so a file that is not the one registered is
    a failure here and not a number.
    """
    e = load()["constants"][_PREDICTED_14B]
    doc = artifact(e["run"], e["artifact"])["result"]
    if doc["schema"] != "e4-registration/1":
        raise SystemExit(f"audit: runs/{e['run']}/{e['artifact']} is not a registration")
    if doc["prediction_sha256"] not in e["note"]:
        raise SystemExit(f"audit: {_PREDICTED_14B}: the registration in runs/{e['run']} is "
                         f"{doc['prediction_sha256']}, which its note does not name")
    return doc["shapes"]["Qwen2.5-14B-Instruct"]["contexts"][str(ctx)]["cells_per_token_layers"]


def predict_13b(a, keys):
    """The 13B model's layer proofs: what the shape cost, added up over its layers.

    The run's own summary is written from the per-layer outputs by the job, and
    this section re-derives that summary from those outputs rather than trusting
    it: every layer's proof is opened, checked to have accepted with no skip and
    every edge bound, the sums are taken here, and the summary is then checked
    against them.

    The run proves 39 of the model's 40 layers. Layer 0 is in no dump: the
    harness refuses to write it, because the attention output's quotient term at
    that layer is 7 + 26 = 33 bits against the field's 31 in the widest form
    there is, and the divisor range is the layer's own, which a driver may only
    widen. So the layer set is read off the run rather than counted from the
    model, and a gap anywhere but layer 0 is a failure here.

    Each layer output reports its proof twice, `proof_bytes` for the structure
    the prover held and `proof_ser_bytes` for the document a verifier is given,
    and the size rows here are the serialized one summed and its median over the
    39.
    """
    if not keys:
        return
    run = sorted({e["run"] for e in keys.values()})[0]
    cfg = artifact(run, "config.json")
    layers = sorted(int(f.stem[1:]) for f in (ROOT / "runs" / run).glob("L*.json"))
    absent = [k for k in range(cfg["layers"]) if k not in layers]
    if absent != [0]:
        a.fails.append(f"audit: runs/{run} proves layers {layers}, and the layer this "
                       f"driver expects to be absent is layer 0 alone, not {absent}")
    fresh = tiles = 0.0
    by_layer, rss, ser, mem = {}, 0, [], 0
    for k in layers:
        doc = artifact(run, f"L{k}.json")
        p, prov = doc["result"]["point"], doc["provenance"]
        if not p["accepts"]:
            a.fails.append(f"audit: layer {k} did not accept")
        if p.get("off_table") or p.get("ref_mismatch"):
            a.fails.append(f"audit: layer {k}: off_table {p.get('off_table')}, "
                           f"ref_mismatch {p.get('ref_mismatch')}")
        if prov["unsound_skips"]:
            a.fails.append(f"audit: layer {k} ran with skips {prov['unsound_skips']}")
        if not prov["binding"]["all_bound"]:
            a.fails.append(f"audit: layer {k} left edges {prov['binding']['unbound']} unbound")
        by_layer[str(k)] = p["cells"]["fresh"]
        fresh += p["cells"]["fresh"]
        tiles += p["family_cells"]["key_tiles"]
        rss = max(rss, p["peak_rss_bytes"])
        ser.append(p["proof_ser_bytes"])
        mem += p["proof_bytes"]
    # the job's own summary, against the same sums taken here
    summary = artifact(run, "measured.json")["summary"]
    for field, got in (("layers", len(layers)), ("fresh_sum", fresh),
                       ("key_tiles_sum", tiles), ("peak_rss_bytes_max", rss)):
        if summary[field] != got:
            a.fails.append(f"audit: runs/{run} measured.json says {field} {summary[field]} "
                           f"and its layer outputs say {got}")
    print(f"  runs/{run}: {len(layers)} of {cfg['layers']} layers (layer 0 is in no dump), "
          f"{fresh:,.0f} fresh cells, largest process {rss / 2 ** 30:.1f} GiB")
    print(f"  runs/{run}: {sum(ser):,} serialized proof bytes over {len(ser)} segments, "
          f"{mem / sum(ser):.3f} of that in memory")
    for key, value in (
            ("e4.codellama_13b.c4096.layers", len(layers)),
            ("e4.codellama_13b.c4096.cells_fresh_by_layer", by_layer),
            ("e4.codellama_13b.c4096.cells_fresh", fresh),
            ("e4.codellama_13b.c4096.cells_per_token_layers", fresh / cfg["s"]),
            ("e4.codellama_13b.c4096.key_tiles_cells", tiles),
            ("e4.codellama_13b.c4096.peak_rss_bytes", rss),
            ("positions.predict13b.c4096", cfg["s"]),
            ("proof.predict13b.c4096.total_bytes", sum(ser)),
            ("proof.predict13b.c4096.bytes_per_segment_median", statistics.median(ser))):
        if key in keys:
            if isinstance(value, (int, dict)):
                a.exact(key, value)
            else:
                a.claim(key, value)


# -- unproved-baseline ---------------------------------------------------------
# The three rates one point of the baseline records, and the positions each is
# over: the prompt for `prefill`, the generated positions less the one the
# prefill call already emitted for `decode`, and every position for `end_to_end`.
_BASELINE_PARTS = ("prefill", "decode", "end_to_end")
_BASELINE_SECONDS = {"prefill": "prefill_s", "decode": "decode_s",
                     "end_to_end": "wall_s"}


def _baseline_points(run, cfg):
    """Every point this run wrote, as (backend, context, batch, document).

    The file names are the harness's own -- model tag, backend, context, batch
    and the number of generated tokens -- and the driver's own `config.json`
    says which of them were asked for, so a point that was asked for and is
    absent is visible here as a missing file rather than as a silence.
    """
    tag = cfg["model"].split("/")[-1].lower().replace(".", "")
    n = cfg["new_tokens"]
    for be in cfg["backends"].split():
        for c in (int(x) for x in cfg["contexts"].split()):
            for b in (int(x) for x in cfg["batches"].split()):
                f = ROOT / "runs" / run / f"{tag}_{be}_c{c}_b{b}_n{n}.json"
                if f.exists():
                    yield be, c, b, json.loads(f.read_text())


def unproved_baseline(a, keys):
    """The baseline's three rates per point, recomputed from the repetitions.

    Nothing here is proved, so there is no binding table and no digest to gate
    on.  What is gated instead is that every record says so -- it declares
    itself a harness record and carries no proof digest -- and that its seconds
    came off a card rather than out of the mock backend, which a record marked
    synthetic is refused for.

    Each stored value is the median over the repetitions of that repetition's
    own rate, so this takes the median again from `per_rep` rather than reading
    the summary back, and it recomputes each repetition's rate from the
    positions and the seconds first.  That is the arithmetic the constant rests
    on: the prompt over the prefill's wall-clock time, the generated positions
    less one over the decode's, and every position over the whole pass's.
    """
    if not keys:
        return
    run = sorted({e["run"] for e in keys.values()})[0]
    cfg = artifact(run, "config.json")
    npoints = 0
    for be, c, b, doc in _baseline_points(run, cfg):
        where = f"baseline {be} C={c} batch={b}"
        prov = doc["provenance"]
        if prov.get("kind") != "harness":
            a.fails.append(f"audit: {where} does not say it is a harness record")
        if prov.get("proof_sha256") or prov.get("proof_sha256s"):
            a.fails.append(f"audit: {where} says it is unproved and carries a proof")
        if prov.get("unsound_skips"):
            a.fails.append(f"audit: {where} ran with skips {prov['unsound_skips']}")
        m = doc.get("measured")
        if not m:
            continue
        if doc["run"].get("synthetic") or doc["backend"].get("synthetic"):
            a.fails.append(f"audit: {where} reports synthetic seconds")
            continue
        npoints += 1
        pos = m["positions"]
        for part in _BASELINE_PARTS:
            secs = _BASELINE_SECONDS[part]
            for i, r in enumerate(m["per_rep"]):
                want = pos[part] / r[secs]
                if abs(r[f"pos_s_{part}"] / want - 1) > 1e-6:
                    a.fails.append(
                        f"audit: {where} repetition {i}: the {part} rate "
                        f"{r[f'pos_s_{part}']} is not {pos[part]} positions over "
                        f"{r[secs]} s")
            key = f"pos_s.unproved.{be}.c{c}.b{b}.{part}"
            if key in keys:
                a.claim(key, statistics.median(r[f"pos_s_{part}"] for r in m["per_rep"]))
    print(f"  runs/{run}: {npoints} measured points over "
          f"{len(cfg['backends'].split())} backend(s), three rates each")


# -- microbench-cells ----------------------------------------------------------
def _cell_points(a, run, name, key="points"):
    """One cell-cost subcommand's points, with what every one of them must say.

    None of these subcommands makes a proof of the composed segment, so there is
    no binding table to gate on; what is gated instead is per point, and it is
    the same three things everywhere: the proof of that point accepted, nothing
    landed off a table, and the gadget agreed with the subcommand's own model of
    the arithmetic wherever it checked one.
    """
    doc = artifact(run, name)
    if doc["provenance"]["unsound_skips"]:
        a.fails.append(f"audit: {name} ran with skips {doc['provenance']['unsound_skips']}")
    pts = doc["result"][key]
    for i, pt in enumerate(pts):
        where = f"{name} point {i}"
        if not pt.get("accepts", True):
            a.fails.append(f"audit: {where} was rejected")
        if pt.get("off_table"):
            a.fails.append(f"audit: {where} has {pt['off_table']} values off a table")
        if pt.get("reference_mismatch"):
            a.fails.append(f"audit: {where} disagrees with its own reference on "
                           f"{pt['reference_mismatch']} values")
    return doc["result"], pts


def microbench_cells(a, keys):
    """What one operation of each kind costs in committed cells.

    The driver has been run more than once and a later run answers subcommands an
    earlier one could not, so each entry is re-derived from its own run's outputs
    and never from another run that the same driver made.
    """
    for run in sorted({e["run"] for e in keys.values()}):
        _microbench_cells_run(a, run, {k: e for k, e in keys.items() if e["run"] == run})


def _microbench_cells_run(a, run, keys):
    """One microbench-cells run, and the entries that name it.

    Eleven subcommands, and each of them reports a marginal figure: the cells the
    gadget adds, with the shared tables left out because a table is a fixed cost
    of the segment and is not multiplied by a count, and with the cells the
    producer already commits left out because the cost model charges those
    elsewhere.  Nothing here is a time, so nothing here takes a median over
    repetitions: a cell count is the same in every repetition and each point
    carries the one count its own proof committed.

    `kmax` backs no constant and is a gate instead: it is the same gadget at six
    table sizes, and the figure the cost model reads must not move across them.
    The four sections below section (7) read outputs an earlier run of this
    driver does not have, so each of them is entered only for a run whose own
    entries name it.
    """
    # (1) the dequantization variants, one point each, read off each point's own
    #     `spec` rather than off the order the points come in.
    dq, pts = _cell_points(a, run, "b6-dequant.json")
    by_variant = {}
    for pt in pts:
        v = pt["spec"]["variant"]
        assert v not in by_variant, f"two {v} points in one sweep"
        by_variant[v] = pt
    print(f"  runs/{run}: {len(by_variant)} dequantization variants over "
          f"{dq['n']:,} accumulators, {dq['per_row']} per row")
    for key, variant in (("model_constants.dequant_chain_cells_per_acc", "chain"),
                         ("model_constants.dequant_pow2_cells_per_acc", "pow2"),
                         ("model_constants.attnout_int8_cells_per_acc", "int8")):
        if key in keys:
            a.claim(key, by_variant[variant]["cells_per_acc_marginal"])

    # (2) the width sweep: the same variant at six accumulators-per-row, whose
    #     closed form is `intercept + row / width`.  Two unknowns and six points,
    #     so the two are solved from the widest pair and the other four have to
    #     reproduce exactly -- these are cell counts, and a closed form that is
    #     off by a cell is not the closed form.
    wd, pts = _cell_points(a, run, "b3-width.json")
    w = sorted((pt["spec"]["per_row"], fractions.Fraction(pt["cells_per_acc_marginal"]))
               for pt in pts)
    (p0, m0), (p1, m1) = w[-2], w[-1]
    row = (m0 - m1) / (fractions.Fraction(1, p0) - fractions.Fraction(1, p1))
    intercept = m1 - row / p1
    resid = max(abs(m - (intercept + row / p)) for p, m in w)
    print(f"  runs/{run}: {len(w)} accumulator widths, {w[0][0]} to {w[-1][0]} per row, "
          f"{float(intercept)} + {float(row)}/width, largest residual {float(resid)} cells")
    if resid != 0:
        a.fails.append(f"audit: the width sweep is not {intercept} + {row}/width; "
                       f"largest residual {float(resid)} cells")
    for key, computed in (("model_constants.dequant_pow2_cells_per_acc_intercept", intercept),
                          ("model_constants.dequant_pow2_cells_per_row", row)):
        if key in keys:
            a.claim(key, float(computed))

    # (3) `kmax`, the gate: the table grows and the marginal figure does not.
    km, pts = _cell_points(a, run, "b4-kmax.json")
    marg = {pt["cells_per_acc_marginal"] for pt in pts}
    tab = sorted(pt["cells_per_acc_with_tables"] for pt in pts)
    print(f"  runs/{run}: {len(pts)} table sizes, marginal {sorted(marg)}, "
          f"with tables {tab[0]} to {tab[-1]}")
    if len(marg) != 1:
        a.fails.append(f"audit: the marginal figure moves with the table size: {sorted(marg)}")
    elif marg != {by_variant["pow2"]["cells_per_acc_marginal"]}:
        a.fails.append(f"audit: the table-size sweep reports {marg} where the "
                       f"variant sweep reports {by_variant['pow2']['cells_per_acc_marginal']}")

    # (4) the requantize, with and without the scale argument.  The cost model
    #     reads the largest of the points that carry the argument.
    rq, pts = _cell_points(a, run, "b65-requant.json")
    with_max = [pt for pt in pts if pt["with_max"]]
    print(f"  runs/{run}: {len(pts)} requantize points, {len(with_max)} with the scale argument")
    if not with_max:
        a.fails.append("audit: no requantize point carries the scale argument")
    elif "model_constants.requant_cells_per_value" in keys:
        a.claim("model_constants.requant_cells_per_value",
                max(pt["cells_per_value_marginal"] for pt in with_max))

    # (5) the residual stream's two measured primitives.  The subcommand's own
    #     `primitives` block is what the cost model reads, and `add` and `mul`
    #     are the two entries in it that come off a point; `unary` and `value`
    #     are constants of the subcommand and are claimed by nothing here.
    rs, pts = _cell_points(a, run, "b65-residual-stream.json")
    prim = rs["primitives"]
    for pt in pts:
        if not pt.get("binding_ok", True):
            a.fails.append(f"audit: the residual-stream {pt['gadget']} point is not bound")
    by_gadget = {pt["gadget"]: pt["cells_per_op_marginal"] for pt in pts}
    print(f"  runs/{run}: {len(pts)} residual-stream points, add {prim['add']}, mul {prim['mul']}")
    for key, name in (("model_constants.residual_stream_add_cells_per_op", "add"),
                      ("model_constants.residual_stream_mul_cells_per_op", "mul")):
        if prim[name] != by_gadget.get(name):
            a.fails.append(f"audit: primitives.{name} is {prim[name]}, and the {name} "
                           f"point reports {by_gadget.get(name)}")
        if key in keys:
            a.claim(key, prim[name])

    # (6) the argmax, on the strict statement.  The lax one is the same layout
    #     without the binding and is not what the cost model prices.
    am, pts = _cell_points(a, run, "b10-argmax.json")
    strict = [pt for pt in pts if not pt.get("lax")]
    if len(strict) != 1:
        a.fails.append(f"audit: {len(strict)} strict argmax points, expected one")
    else:
        pt = strict[0]
        cmps = am["tokens"] * am["vocab"]
        print(f"  runs/{run}: argmax over {am['vocab']:,} entries and {am['tokens']} tokens, "
              f"{cmps:,} comparisons")
        if pt["cells"]["fresh"] != pt["cells"]["base"] + pt["cells"]["interaction"]:
            a.fails.append("audit: the argmax point's fresh cells are not its base plus "
                           "its interaction cells")
        if "model_constants.argmax_cells_per_comparison" in keys:
            a.claim("model_constants.argmax_cells_per_comparison",
                    pt["cells"]["fresh"] / cmps)

    # (7) the packed attention, whose grid figure has to be the same at every
    #     instance count -- that is what makes it the grid's own price rather
    #     than one packing's.
    pk, pts = _cell_points(a, run, "b6-pack.json")
    grid = {pt["alpha_grid"] for pt in pts}
    print(f"  runs/{run}: {len(pts)} packings, {[pt['insts'] for pt in pts]} instances, "
          f"grid {sorted(grid)}")
    if len(grid) != 1:
        a.fails.append(f"audit: the grid figure moves with the instance count: {sorted(grid)}")
    if "model_constants.attention_cells_per_head_key_token" in keys:
        a.claim("model_constants.attention_cells_per_head_key_token", pts[0]["alpha_grid"])

    # (8) the weight Freivalds check.  What it measures is a law and not a point:
    #     the three QM31 accumulator columns cost 12 cells a trace row and a row
    #     carries `p` weights, so the fresh side is `12/p` and the preprocessed
    #     side `1 + 4/p`.  The design point backs the two entries; the sweep
    #     beside it is the gate, and these are cell counts, so both closed forms
    #     have to hold exactly at every width and not to a tolerance.  The law is
    #     the one-matmul group's: a group of `n` costs `(4 + 8n)/(n p)`.
    freivalds = ("model_constants.weight_freivalds_cells_per_weight",
                 "model_constants.weight_freivalds_preprocessed_cells_per_weight")
    if any(k in keys for k in freivalds):
        fv, design = _cell_points(a, run, "b3-freivalds.json")
        _, widths = _cell_points(a, run, "b3-freivalds-widths.json")
        if len(design) != 1:
            a.fails.append(f"audit: {len(design)} Freivalds design points, expected one")
        for pt in design + widths:
            p, cells = pt["weights_per_row"], pt["cells"]
            if pt["matmuls"] != 1:
                a.fails.append(f"audit: the Freivalds point at {p} weights a row covers "
                               f"{pt['matmuls']} matmuls, and 12/p is the one-matmul group")
            if (cells["cells_per_weight"], cells["preprocessed_per_weight"]) != (12 / p, 1 + 4 / p):
                a.fails.append(f"audit: the Freivalds point at {p} weights a row reports "
                               f"{cells['cells_per_weight']} fresh and "
                               f"{cells['preprocessed_per_weight']} preprocessed cells a weight, "
                               f"and the law is {12 / p} and {1 + 4 / p}")
        print(f"  runs/{run}: Freivalds at "
              f"{', '.join(str(pt['weights_per_row']) for pt in design + widths)} weights a row, "
              f"12/p fresh and 1 + 4/p preprocessed at every one")
        for key, name in zip(freivalds, ("cells_per_weight", "preprocessed_per_weight")):
            if key in keys:
                a.claim(key, design[0]["cells"][name])

    # (9) one LogUp lookup on its own, which every other subcommand here reports
    #     only from inside a gadget that has its own lookups.  One figure per
    #     lookup batch size, and the two arities have to agree at each: an
    #     interaction column is one QM31 whatever the relation's arity, so the
    #     arity moves what the gadget commits and not the column count.
    if "model_constants.logup_marginal_cells_per_lookup" in keys:
        lg, pts = _cell_points(a, run, "logup.json")
        by_batch = {}
        for pt in pts:
            b, marg = str(pt["logup_batch_size"]), pt["cells"]["marginal_cells_per_lookup"]
            if by_batch.setdefault(b, marg) != marg:
                a.fails.append(f"audit: the LogUp marginal at batch {b} is {by_batch[b]} on the "
                               f"{pt['kind']} lookup's arity and {marg} on the other")
        closed = lg["closed_form"]["marginal_cells_per_lookup"]
        if [by_batch.get(str(b + 1)) for b in range(len(closed))] != closed:
            a.fails.append(f"audit: the LogUp points report {by_batch} and the subcommand's own "
                           f"closed form {closed}")
        print(f"  runs/{run}: {len(pts)} LogUp points over {len(by_batch)} batch sizes, "
              f"marginal {by_batch}")
        a.exact("model_constants.logup_marginal_cells_per_lookup", by_batch)

    # (10) the dequantization at the rounding the cost model charges, in its own
    #      output so that the two roundings never claim one number.  The base
    #      figures are the committed columns alone over the accumulators a row
    #      carries, which is what a proof with `--gkr-dequant` builds.  The gate
    #      is the distance to the sweep in (1): one cell an accumulator at every
    #      variant the rounding can move, on the marginal figure and on the base.
    away_keys = {"model_constants.dequant_chain_away_cells_per_acc": ("chain", "marginal"),
                 "model_constants.dequant_pow2_away_cells_per_acc": ("pow2", "marginal"),
                 "model_constants.dequant_chain_away_base_cells_per_acc": ("chain", "base"),
                 "model_constants.dequant_pow2_away_base_cells_per_acc": ("pow2", "base")}
    if any(k in keys for k in away_keys):
        aw, pts = _cell_points(a, run, "b6-dequant-away.json")
        away = {}
        for pt in pts:
            if pt["spec"]["round"] != "away":
                a.fails.append(f"audit: the away sweep carries a {pt['spec']['round']} point")
            away[pt["spec"]["variant"]] = pt
        print(f"  runs/{run}: {len(away)} dequantization variants at the rounding away from zero "
              f"over {aw['n']:,} accumulators, {aw['per_row']} per row")
        for variant, pt in sorted(away.items()):
            even = by_variant[variant]
            dm = even["cells_per_acc_marginal"] - pt["cells_per_acc_marginal"]
            db = even["columns"]["base"] - pt["columns"]["base"]
            if (dm, db) != (1, aw["per_row"]):
                a.fails.append(f"audit: the {variant} variant is {dm} cells an accumulator and "
                               f"{db} columns cheaper at the rounding away from zero, and the "
                               f"round half to even is one cell and {aw['per_row']} columns above it")
        for key, (variant, side) in sorted(away_keys.items()):
            if key in keys:
                a.claim(key, away[variant]["cells_per_acc_marginal"] if side == "marginal"
                        else away[variant]["columns"]["base"] / aw["per_row"])

    # (11) the argmax marginal, as a slope.  One vocabulary cannot separate what
    #      a comparison costs from what the gadget costs whatever the vocabulary
    #      is; three at the same token count and the same comparisons a row can,
    #      and cell counts have to be collinear exactly and not to a tolerance.
    if "model_constants.argmax_marginal_cells_per_comparison" in keys:
        sweep = []
        for name in ("b10-argmax.json", "b10-argmax-v16k.json", "b10-argmax-v32k.json"):
            res, pts = _cell_points(a, run, name)
            strict = [pt for pt in pts if not pt.get("lax")]
            if len(strict) != 1:
                a.fails.append(f"audit: {len(strict)} strict argmax points in {name}, expected one")
                return
            sweep.append((res["vocab"] * res["tokens"], strict[0]["cells"]["fresh"],
                          res["tokens"], strict[0]["layout"]["per_row"]))
        sweep.sort()
        shape = {(tok, per_row) for _, _, tok, per_row in sweep}
        if len(shape) != 1 or len({x for x, _, _, _ in sweep}) != len(sweep):
            a.fails.append(f"audit: the three argmax vocabularies are at {sorted(shape)} tokens "
                           f"and comparisons a row over "
                           f"{sorted(x for x, _, _, _ in sweep)} comparisons; the slope needs one "
                           f"token count, one row width and three comparison counts")
            return
        slopes = {fractions.Fraction(y1 - y0, x1 - x0)
                  for (x0, y0, _, _), (x1, y1, _, _) in zip(sweep, sweep[1:])}
        slope = sorted(slopes)[0]
        fixed = sweep[0][1] - slope * sweep[0][0]
        print(f"  runs/{run}: argmax over {', '.join(f'{x:,}' for x, _, _, _ in sweep)} "
              f"comparisons, {float(slope)} cells each and a fixed side of {float(fixed):,.0f} "
              f"cells")
        if len(slopes) != 1:
            a.fails.append(f"audit: the three argmax vocabularies are not collinear: "
                           f"{sorted(float(s) for s in slopes)} cells a comparison")
        a.claim("model_constants.argmax_marginal_cells_per_comparison", float(slope))


# -- the witness extraction, at both contexts ----------------------------------
# The extraction is not a proving scope: it happens before the prover is called
# and is in none of the four scopes the slice outputs report.  Each driver times
# every extraction pass it makes and writes one row per pass, so the audit adds
# the rows up itself rather than reading a total the job printed.
def _extraction(key_of):
    def section(a, keys):
        mine = {k: e for k, e in keys.items() if k in key_of.values()}
        if not mine:
            return
        run = sorted({e["run"] for e in mine.values()})[0]
        rows = artifact(run, "extract.json")["passes"]
        by_sweep, by_group = {}, {}
        for r in rows:
            sweep = r.get("sweep", "extract")
            by_sweep[sweep] = by_sweep.get(sweep, 0) + r["seconds"]
            by_group.setdefault((sweep, r.get("blocks", "all")), 0)
            by_group[(sweep, r.get("blocks", "all"))] += r["seconds"]
        print(f"  runs/{run}: {len(rows)} extraction passes, "
              + ", ".join(f"{s} {n:,} s over "
                          f"{len([1 for k in by_group if k[0] == s])} group(s)"
                          for s, n in sorted(by_sweep.items())))
        # the driver's own phase file, where it has one, must say the same
        if (ROOT / "runs" / run / "timing.json").exists():
            t = artifact(run, "timing.json")["extract_seconds"]
            if t != by_sweep:
                a.fails.append(f"audit: {run}: timing.json reports {t} and the passes "
                               f"add up to {by_sweep}")
            # a group extracted twice has one row, its last; groups.jsonl keeps
            # every attempt, so each group's total must be one of its rows
            seen = {}
            for line in (ROOT / "runs" / run / "groups.jsonl").read_text().splitlines():
                g = json.loads(line)
                seen.setdefault(g["blocks"], []).append(g["extract_seconds"])
            for (sweep, blocks), secs in sorted(by_group.items()):
                if sweep == "prove" and secs not in seen.get(blocks, []):
                    a.fails.append(f"audit: {run}: the prove sweep extracted blocks "
                                   f"{blocks} in {secs} s and groups.jsonl has "
                                   f"{seen.get(blocks)}")
        for sweep, key in key_of.items():
            if key in mine:
                a.exact(key, by_sweep[sweep])
    return section


# -- what a proved position commits, per component -----------------------------
# One reader for both contexts.  A segment's proof commits six trees: the shape
# and model trees, which are preprocessed, the base and interaction trees, and
# the boundary trees, which carry the residual stream and the keys and values a
# segment hands on.  The chunk output names four of the six and not the boundary
# trees, so `boundary` is read as the cells `fresh` has above base and
# interaction.  The interaction tree comes with its own split by component; the
# base tree has no split and is added up here component by component out of the
# counters beside the chunk's `cells` object.  The relations
# below are the whole point of the reader: it refuses unless the two
# preprocessed trees add up to the preprocessed cells beside them, the eleven
# components add up to the interaction tree, the base components add up to the
# base tree with the unattributed cells beside them, the chunks add up to the
# run's `fresh` row, and the recorded rows themselves close the same three
# sums.  A count that does not close is not recorded.
_TREES = ("base", "interaction", "boundary", "model", "shape")

# The base tree's components, in the three shapes the counters are written in:
# a bare integer for five of them, a dict for `embed`, which a layer-0 segment
# states and no other, and rows carrying a `cells.base` for `quant` and
# `requant`.  `table` is the ninth and the only one no counter gives as cells:
# every LogUp table commits one multiplicity column in the base tree, the
# chunk's `tables` list gives each table its rows and its key columns and no
# cell count, and `requant_tables` reports the seams' own tables separately, so
# the reader charges one column of its rows for each table and the closure
# below is what fixes the column at one.  Never added on top of these: `mats`,
# which is `dequant` split per matmul, `residual_stream_components`, which is
# `residual_stream` split the same way, `freivalds_weights`, whose cells are
# preprocessed, and `interaction_split`, which is the interaction tree.
_BASE_COMPONENTS = ("attnout", "dequant", "embed", "freivalds", "key_tiles",
                    "quant", "requant", "residual_stream", "table")


def _base_components(a, run, tag, fc):
    """One segment's base tree, per component.  None if a counter is missing."""
    try:
        p = {k: fc[k] for k in ("attnout", "dequant", "freivalds", "key_tiles",
                                "residual_stream")}
        p["embed"] = fc["embed"]["cells"]["base"] if fc["embed"] else 0
        p["quant"] = sum(r["cells"]["base"] for r in fc["quant"])
        p["requant"] = (sum(r["cells"]["base"] for r in fc["requant"])
                        + fc["requant_tables"]["multiplicity"])
        p["table"] = sum(2 ** t["log_rows"] for t in fc["tables"])
    except (KeyError, TypeError) as e:
        a.fails.append(f"audit: {run}: segment {tag} has no base counter for {e}")
        return None
    # the two breakdowns, so that a reader that later adds one of them on top is
    # caught here rather than doubling a component
    for name, whole in (("mats", "dequant"),
                        ("residual_stream_components", "residual_stream")):
        got = sum(r["cells"] for r in fc[name])
        if got != fc[whole]:
            a.fails.append(f"audit: {run}: segment {tag}: {name} adds up to {got} and "
                           f"{whole} is {fc[whole]}; one of the two is a component and "
                           f"the other is its breakdown")
    return p


def _cells_per_position(ctx):
    def section(a, keys):
        pre = f"cells_per_position.headline.c{ctx}."
        mine = {k: e for k, e in keys.items() if k.startswith(pre)}
        if not mine:
            return
        run = sorted({e["run"] for e in mine.values()})[0]
        cells = {k: 0 for k in _TREES}
        cells["fresh"] = cells["preprocessed"] = 0
        comp, base, unattributed, n = {}, {k: 0 for k in _BASE_COMPONENTS}, 0, 0
        for f in sorted((ROOT / "runs" / run).glob("slice_*.json")):
            for ch in json.loads(f.read_text())["result"]["chunks"]:
                n += 1
                c, tag, fc = ch["cells"], ch["ser_tag"], ch["family_cells"]
                for k in ("base", "interaction", "model", "shape", "fresh",
                          "preprocessed"):
                    cells[k] += c[k]
                cells["boundary"] += c["fresh"] - c["base"] - c["interaction"]
                if c["fresh"] < c["base"] + c["interaction"]:
                    a.fails.append(f"audit: c{ctx}: segment {tag}: base and interaction add "
                                   f"up to {c['base'] + c['interaction']} and the segment's "
                                   f"fresh cells are {c['fresh']}")
                for k, v in fc["interaction_by_family"].items():
                    comp[k] = comp.get(k, 0) + v["cells"]
                # the base tree, component by component, and what is left of it
                p = _base_components(a, run, tag, fc)
                if p is None:
                    continue
                for k, v in p.items():
                    base[k] += v
                left = c["base"] - sum(p.values())
                unattributed += left
                if left < 0:
                    a.fails.append(f"audit: c{ctx}: segment {tag}: the base components add "
                                   f"up to {sum(p.values())} and the segment's base tree is "
                                   f"{c['base']}; a component is counted twice")
                elif left and not any(r["component"] == "argmax"
                                      for r in fc["interaction_split"]):
                    a.fails.append(f"audit: c{ctx}: segment {tag}: {left} base cells belong "
                                   f"to no component and the segment states no argmax "
                                   f"gadget, which is the only one the counters leave out")
        if cells["shape"] + cells["model"] != cells["preprocessed"]:
            a.fails.append(f"audit: c{ctx}: shape and model add up to "
                           f"{cells['shape'] + cells['model']} and the chunks report "
                           f"preprocessed {cells['preprocessed']}")
        if sum(comp.values()) != cells["interaction"]:
            a.fails.append(f"audit: c{ctx}: the components add up to {sum(comp.values())} "
                           f"and the interaction tree is {cells['interaction']}")
        stored = load()["constants"].get(f"cells.headline.c{ctx}.fresh")
        if stored and cells["fresh"] != stored["value"]:
            a.fails.append(f"audit: c{ctx}: the chunks report {cells['fresh']} fresh cells "
                           f"and cells.headline.c{ctx}.fresh is {stored['value']}")
        pos = artifact(run, "config.json")["positions"]
        print(f"  runs/{run}: {n} segments over {pos:,} positions; "
              f"{cells['fresh']:,} fresh cells in three trees, "
              f"{cells['interaction']:,} interaction cells in {len(comp)} components, and "
              f"{cells['base']:,} base cells in {len(_BASE_COMPONENTS)} components with "
              f"{unattributed:,} unattributed")
        for k in _TREES:
            if pre + k in mine:
                a.claim(pre + k, cells[k] / pos)
        for k in sorted(comp):
            if pre + "interaction_" + k in mine:
                a.claim(pre + "interaction_" + k, comp[k] / pos)
        for k in _BASE_COMPONENTS:
            if pre + "base_" + k in mine:
                a.claim(pre + "base_" + k, base[k] / pos)
        if pre + "unattributed" in mine:
            a.claim(pre + "unattributed", unattributed / pos)
        # the same two sums over the recorded values, so that a row edited by
        # hand cannot stand while the artifact still closes.  `boundary` is the
        # cells `fresh` has above base and interaction, so this is the one place
        # the three are made to add up to the run's own `fresh` row.
        rec = load()["constants"]
        fresh3 = [pre + k for k in ("base", "interaction", "boundary")]
        if stored and all(k in mine for k in fresh3):
            got, want = sum(rec[k]["value"] for k in fresh3), stored["value"] / pos
            if abs(got / want - 1) > 1e-6:
                a.fails.append(f"audit: c{ctx}: the recorded base, interaction and boundary "
                               f"add up to {got} cells per position and "
                               f"cells.headline.c{ctx}.fresh is {want} per position")
        inter = [pre + "interaction_" + k for k in comp]
        if pre + "interaction" in mine and all(k in mine for k in inter):
            got, want = sum(rec[k]["value"] for k in inter), rec[pre + "interaction"]["value"]
            if abs(got / want - 1) > 1e-6:
                a.fails.append(f"audit: c{ctx}: the recorded components add up to {got} "
                               f"cells per position and the recorded interaction tree is "
                               f"{want}")
        # and the base tree's own split: the nine components with the
        # unattributed cells beside them close to the recorded base tree, and
        # the three trees then close to the run's `fresh` row, so the split is
        # checked against what a proved position costs and not only against the
        # tree it came out of.
        rows = [pre + "base_" + k for k in _BASE_COMPONENTS] + [pre + "unattributed"]
        if pre + "base" in mine and all(k in mine for k in rows):
            got, want = sum(rec[k]["value"] for k in rows), rec[pre + "base"]["value"]
            if abs(got / want - 1) > 1e-6:
                a.fails.append(f"audit: c{ctx}: the recorded base components and the "
                               f"unattributed cells add up to {got} cells per position and "
                               f"the recorded base tree is {want}")
            if stored and all(pre + k in mine for k in ("interaction", "boundary")):
                got += sum(rec[pre + k]["value"] for k in ("interaction", "boundary"))
                want = stored["value"] / pos
                if abs(got / want - 1) > 1e-6:
                    a.fails.append(f"audit: c{ctx}: the recorded base components, the "
                                   f"unattributed cells, the interaction tree and the "
                                   f"boundary trees add up to {got} cells per position and "
                                   f"cells.headline.c{ctx}.fresh is {want} per position")
    return section


# -- what the composed prover builds each gadget at ----------------------------
# The prices the cost model charges were measured on standalone gadget chains,
# one gadget per proof.  The two headline runs prove the same gadgets inside one
# AIR, where a value one gadget commits is the next one's input and the batched
# reductions prove the LogUp running sums, and the same gadget does not cost the
# same there.  The eight `*_composed_*` rows below are what it costs there: cells
# over a count the same segment reports, on the 31 non-embedding layer segments
# of one token block at each context, where every one of the sixteen integers is
# the same on all 62 segments.  Beside them, what those segments cost per decoded
# token, which is what the cost model's registration is compared against.
#
# The ten rows are `derived`, and what they divide are counts in the artifact and
# not entries of this file, so the arithmetic lives here with the other artifact
# readers and `check.py`'s derived table calls `composed_figures()`.
_COMPOSED_KEY = {
    "dequant": "model_constants.dequant_chain_composed_cells_per_acc",
    "requant": "model_constants.requant_composed_cells_per_value",
    "quant": "model_constants.quant_composed_cells_per_value",
    "freivalds": "model_constants.weight_freivalds_composed_cells_per_weight",
    "attnout": "model_constants.attnout_composed_cells_per_acc",
    "residual_stream_mul": "model_constants.residual_stream_composed_mul_cells_per_op",
    "residual_stream_add": "model_constants.residual_stream_composed_add_cells_per_op",
    "residual_stream_unary_plus_mul":
        "model_constants.residual_stream_composed_swiglu_cells_per_op",
}
_PER_TOKEN_KEY = "cells_per_position.headline.c{}.fresh_layers_block"
_LAYER_SEGMENT = re.compile(r"(B\d+)L(\d+)")
_COMPOSED = None


def _composed_counts(ch):
    """The eight (cells, count) pairs one composed layer segment builds.

    Each `cells` is the committed columns plus what the reduction leaves in the
    interaction trace, except the three residual-stream rows, which are the
    components' own committed columns: those are the only bf16 operations whose
    op count a segment reports by itself, and the interaction beside them is the
    whole component's and not the operation's.
    """
    f = ch["family_cells"]
    inter = f["interaction_by_family"]
    rs = {c["tag"]: c for c in f["residual_stream_components"]}
    p = ch["params"]
    return {
        "dequant": (f["dequant"] + inter["dequant"]["cells"],
                    sum(m["n"] for m in f["mats"])),
        "requant": (sum(r["cells"]["base"] for r in f["requant"])
                    + f["requant_tables"]["multiplicity"] + inter["requant"]["cells"],
                    sum(r["checked"] for r in f["requant"])),
        "quant": (sum(q["cells"]["base"] for q in f["quant"]) + inter["quant"]["cells"],
                  sum(q["checked"] for q in f["quant"])),
        "freivalds": (f["freivalds"] + inter["freivalds"]["cells"],
                      sum(w["weights"] for w in f["freivalds_weights"])),
        "attnout": (f["attnout"] + inter["attnout"]["cells"],
                    p["nh"] * p["hd"] * p["s"]),
        "residual_stream_mul": (rs["rpqm"]["cells"] + rs["rpkm"]["cells"],
                                rs["rpqm"]["ops"] + rs["rpkm"]["ops"]),
        "residual_stream_add": (rs["rpqa"]["cells"] + rs["rpka"]["cells"],
                                rs["rpqa"]["ops"] + rs["rpka"]["ops"]),
        "residual_stream_unary_plus_mul": (rs["gsw"]["cells"], rs["gsw"]["ops"]),
    }


def composed_figures():
    """`({key: value}, [what does not close])`, read once and kept.

    The slice output each per-token row names holds one token block's segments;
    the block's 32 layer segments give the per-token row and its 31 non-embedding
    ones the eight prices, which have to be the same integers at both contexts.
    """
    global _COMPOSED
    if _COMPOSED is not None:
        return _COMPOSED
    c = load()["constants"]
    vals, bad, counts = {}, [], {}
    for ctx in (4096, 16384):
        key = _PER_TOKEN_KEY.format(ctx)
        if key not in c:
            continue
        e = c[key]
        if not (ROOT / "runs" / e["run"] / e["artifact"]).exists():
            bad.append(f"{key}: runs/{e['run']}/{e['artifact']} does not exist")
            continue
        blocks = {}
        for ch in artifact(e["run"], e["artifact"])["result"]["chunks"]:
            m = _LAYER_SEGMENT.fullmatch(ch["ser_tag"] or "")
            if m:
                blocks.setdefault(m.group(1), {})[int(m.group(2))] = ch
        if len(blocks) != 1:
            bad.append(f"{key}: {e['artifact']} holds layer segments of "
                       f"{len(blocks)} token blocks and the row is one block's")
            continue
        block, segs = blocks.popitem()
        if sorted(segs) != list(range(32)):
            bad.append(f"{key}: block {block} has layer segments {sorted(segs)} "
                       f"and the row is over the model's 32")
            continue
        shape = {(s["params"]["c"], s["params"]["s"], s["params"]["round"])
                 for s in segs.values()}
        if shape != {(ctx, 512, "even")}:
            bad.append(f"{key}: block {block} was proved at (c, s, round) {shape} "
                       f"and the row is one block of 512 at context {ctx}")
            continue
        vals[key] = sum(s["cells"]["fresh"] for s in segs.values()) / 512
        for k in range(1, 32):
            for name, pair in _composed_counts(segs[k]).items():
                counts.setdefault(name, {}).setdefault(pair, []).append(f"{block}L{k}")
    for name, seen in sorted(counts.items()):
        if len(seen) > 1:
            bad.append(f"the composed segments disagree on {name}: "
                       + "; ".join(f"{p} on {len(w)} segment(s)" for p, w in seen.items()))
        cells, count = max(seen, key=lambda pair: len(seen[pair]))
        vals[_COMPOSED_KEY[name]] = cells / count
    _COMPOSED = (vals, bad)
    return _COMPOSED


def composed_statement(a, keys):
    """The eight composed prices and the two per-token rows, against the segments."""
    vals, bad = composed_figures()
    c = load()["constants"]
    for b in bad:
        a.fails.append(f"audit: composed: {b}")
    for ctx in (4096, 16384):
        key = _PER_TOKEN_KEY.format(ctx)
        if key in vals:
            e = c[key]
            print(f"  runs/{e['run']}: one token block's 32 layer segments at context "
                  f"{ctx:,}, {vals[key] * 512:,.0f} fresh cells over 512 positions")
    for key in sorted(vals):
        if key in c:
            a.claim(key, vals[key])


# -- the cost model's witness assumption block ---------------------------------
# The eleven fields of a `params` block that a model shape and a context do not
# give: the exponent table's height, the attention output's measured ranges and
# the fold's remainder width.  A caller who has a model and a context but no
# witness cannot read them, so the counted cost model assumes them, and every
# projected row names them in its `inputs` as `assumption.cost_model.<field>`.
# Each is the MODE over the 64 layer and first segments of the two headline
# runs -- the same two artifacts the composed prices are read off -- and that is
# what this re-derives.  It is the whole of the assumption: a mode that has moved
# is a different projection, and this section fails rather than letting the rows
# stand on a number the runs no longer say.
_ASSUMPTION_KEY = "assumption.cost_model."
_WITNESS_FIELDS = ("log_table", "kmax", "ao_acc_hi_bits", "ao_acc_lo_bits",
                   "ao_rem_bits", "ao_q_bits", "ao_jo_min", "ao_jo_max",
                   "ao_jv_min", "ao_jv_max", "fold_rem_bits")
# A layer segment or the first segment of a stack, by its `ser_tag`; the output
# head's tag carries no `L` and its plan agrees on a narrower remainder, so it is
# not one of the 64.
_LAYER_OR_FIRST = re.compile(r"B\d+L\d+")


def witness_assumptions(a, keys):
    """The eleven witness-calibrated fields, as the mode over the two runs."""
    mine = {k for k in keys if k.startswith(_ASSUMPTION_KEY)}
    if not mine:
        return
    c = load()["constants"]
    pts = []
    for ctx in (4096, 16384):
        e = c[_PER_TOKEN_KEY.format(ctx)]
        for ch in artifact(e["run"], e["artifact"])["result"]["chunks"]:
            if _LAYER_OR_FIRST.fullmatch(ch["ser_tag"] or ""):
                pts.append((e["run"], ch["ser_tag"], ch["params"]))
    if len(pts) != 64:
        a.fails.append(f"audit: the assumption block is the mode over the two headline "
                       f"runs' 64 layer and first segments and their artifacts hold "
                       f"{len(pts)}")
        return
    print(f"  the witness assumption block, over {len(pts)} layer and first segments of "
          f"the two headline runs")
    for f in _WITNESS_FIELDS:
        key = _ASSUMPTION_KEY + f
        if key not in mine:
            continue
        counts = {}
        for run, tag, p in pts:
            if f not in p:
                a.fails.append(f"audit: {run} segment {tag} carries no {f}")
                return
            counts[p[f]] = counts.get(p[f], 0) + 1
        # `modal_witness` in the cost model breaks a draw the same way: the most
        # common value, and the smallest of them where two are as common.
        a.exact(key, max(sorted(counts), key=lambda v: counts[v]))
    left = sorted(mine - {_ASSUMPTION_KEY + f for f in _WITNESS_FIELDS})
    if left:
        a.fails.append(f"audit: {left} is measured and no run reads it; the fields the "
                       f"runs do not carry are asserted")


# -- reference-digest-plain ----------------------------------------------------
def reference_digest_plain(a, keys):
    """One segment proved on both backends: what generating its trace cost, and
    what generating its LogUp interaction columns cost, on each.

    The same witness, the same flags and the same proof on both sides -- the
    driver proves the segment twice and records that the two agree -- so what
    separates the two backends' seconds is the port and nothing else.
    `full-simd.json` is the host backend and `full-cuda.json` the device one,
    and each carries the segment's own `trace_secs` and `interaction_secs`.
    The ratio of the two is `derived` and `check.py` recomputes it; this
    section reads the four seconds and refuses if the two proofs did not agree,
    because a ratio between two different proofs is not a port.
    """
    if not keys:
        return
    run = sorted({e["run"] for e in keys.values()})[0]
    cfg = artifact(run, "config.json")["reference"]
    if not artifact(run, "full-digest.json").get("both_backends_agree"):
        a.fails.append(f"audit: {run}: the two backends do not prove the same segment, so "
                       f"their seconds are not a ratio of the port")
        return
    print(f"  runs/{run}: one segment at context {cfg['context']:,}, S={cfg['s']}, the five "
          f"reductions on, proved on both backends to the same digest")
    for backend in ("simd", "cuda"):
        point = artifact(run, f"full-{backend}.json")["result"]["point"]
        for phase in ("trace", "interaction"):
            key = f"secs.reference.c{cfg['context']}.{backend}_{phase}"
            if key in keys:
                a.claim(key, point[f"{phase}_secs"])


# -- the card's own memory -----------------------------------------------------
# Every manifest records the GPU as the machine reported it, its memory
# included, and that string is where the card's capacity comes from: not the
# vendor's 80 GB, which would be 81,920 MiB, but what the driver leaves a
# process to allocate.  The row is re-derived off the manifests and required to
# agree across every run on the same card, because a capacity that moves run to
# run is a different card and the memory projections rest on it.
_GPU_MIB = re.compile(r"(\d+)\s*MiB")


def card_memory(a, keys):
    """The H100's memory, as the manifests report it."""
    key = "hardware.h100.memory_total_mib"
    if key not in keys:
        return
    seen = {}
    for m in sorted((ROOT / "runs").glob("*/manifest.json")):
        gpu = json.loads(m.read_text()).get("gpu") or ""
        if "H100" not in gpu:
            continue
        found = _GPU_MIB.search(gpu)
        if not found:
            a.fails.append(f"audit: runs/{m.parent.name}: the manifest reports {gpu!r} and "
                           f"no memory, and the card's capacity is read off that string")
            continue
        seen.setdefault(int(found.group(1)), []).append(m.parent.name)
    if len(seen) != 1:
        a.fails.append(f"audit: the H100 runs report {sorted(seen)} MiB between them; the "
                       f"card's capacity is one number or it is not a constant")
        return
    print(f"  the H100's memory, agreeing over {sum(len(r) for r in seen.values())} manifests")
    a.exact(key, next(iter(seen)))


# -- sections: (driver name, function(audit, keys)) ----------------------------
# Added when a driver's first run lands; each function re-derives the constants
# whose `run` was made by that driver.

SECTIONS = [
    ("headline-c4096", headline_c4096),
    ("headline-c16384", headline_c16384),
    ("gkr-ablation-c4096", gkr_ablation_c4096),
    ("control-flags-off-c4096", control_flags_off_c4096),
    ("negative-controls", negative_controls),
    ("memory-probe-c16384", memory_probe_c16384),
    ("microbench", microbench),
    ("quality-0p5b", _quality("quality.0p5b")),
    ("quality-gemma270m", _quality("quality.gemma270m")),
    ("quality-suite", quality_suite),
    ("prefill-sweep", prefill_sweep),
    ("prefill-sweep-8b", prefill_sweep_8b),
    ("predict-14b", predict_14b),
    ("predict-13b", predict_13b),
    ("unproved-baseline", unproved_baseline),
    ("model-commitment", model_commitment),
    ("moe-routing", moe_routing),
    ("microbench-cells", microbench_cells),
    # the extraction and the per-component cell counts of the two headline
    # runs: separate readers over separate artifacts of the same runs
    ("headline-c4096", _extraction({"extract": "secs.headline.c4096.extract"})),
    ("headline-c16384", _extraction({"prove": "secs.headline.c16384.extract_prove",
                                     "survey": "secs.headline.c16384.extract_survey"})),
    ("headline-c4096", _cells_per_position(4096)),
    ("headline-c16384", _cells_per_position(16384)),
    # the composed statement's own prices, read off one token block of each of
    # the two runs; one section, because a price is only a price if the two
    # agree
    ("headline-c4096", composed_statement),
    # the cost model's witness assumption block, the mode over the same two
    # artifacts' layer and first segments
    ("headline-c4096", witness_assumptions),
    # one segment on both backends, which is where the ported phases' factors
    # come from
    ("reference-digest-plain", reference_digest_plain),
    # the card's memory, off the manifests; registered under one driver because
    # the reader crosses them all
    ("headline-c4096", card_memory),
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
