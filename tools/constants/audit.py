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


# -- headline-c16384 -----------------------------------------------------------
def headline_c16384(a, keys):
    """The sequence at context 16,384: the same arithmetic as the c4096 row.

    The plan is proved in groups of token blocks and each group in processes of
    64 segments, so there are more slice outputs than at the smaller context;
    the grouping sits between the processes and is in none of the four timing
    scopes, so the run's own cost is still the sum over the slices and
    `_sequence_totals` reads this run exactly as it reads that one.  Every rate
    is `derived` and recomputed by check.py from the entries here.
    """
    if not keys:
        return
    run = sorted({e["run"] for e in keys.values()})[0]
    cfg = artifact(run, "config.json")
    t = _sequence_totals(run)
    print(f"  runs/{run}: {t['slices']} slices, {t['segments']} segments, "
          f"{t['fresh']:,.0f} fresh cells")
    a.exact("segments.headline.c16384", t["segments"])
    a.exact("positions.headline.c16384", cfg["positions"])
    a.claim("cells.headline.c16384.fresh", t["fresh"])
    a.claim("secs.headline.c16384.commit", t["commit"])
    a.claim("secs.headline.c16384.stwo_total", t["stwo"])
    a.claim("secs.headline.c16384.whole_wall", t["whole"])
    a.claim("secs.headline.c16384.loop", t["loop"])
    a.exact("mem.headline.c16384.peak_mib", t["peak_mib"])


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

# -- predict-14b ---------------------------------------------------------------
def predict_14b(a, keys):
    """The 14B model's layer proofs: what the shape cost, added up over its layers.

    The run's own summary is written from the per-layer outputs by the job, and
    this section re-derives that summary from those outputs rather than trusting
    it: every layer's proof is opened, checked to have accepted with no skip and
    every edge bound, and the sums are taken here.

    What is not here is the comparison against the registered prediction. The
    registration cannot be produced at this harness commit (zk-prover #67), and
    a prediction written after the measurement is not a prediction, so the
    measured side is frozen and the comparison waits.
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


# -- sections: (driver name, function(audit, keys)) ----------------------------
# Added when a driver's first run lands; each function re-derives the constants
# whose `run` was made by that driver.

SECTIONS = [
    ("headline-c4096", headline_c4096),
    ("headline-c16384", headline_c16384),
    ("gkr-ablation-c4096", gkr_ablation_c4096),
    ("memory-probe-c16384", memory_probe_c16384),
    ("microbench", microbench),
    ("quality-0p5b", _quality("quality.0p5b")),
    ("quality-gemma270m", _quality("quality.gemma270m")),
    ("quality-suite", quality_suite),
    ("prefill-sweep", prefill_sweep),
    ("predict-14b", predict_14b),
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
