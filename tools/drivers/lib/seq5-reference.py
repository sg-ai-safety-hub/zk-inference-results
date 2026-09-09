#!/usr/bin/env python3
"""Derive the harness's measured 8B reference chunks from segments already proved.

    seq5-reference.py --runs runs/ --layer 16 \
        --from <run-id>:<segment tag>:<context> [--from ...] \
        [--out DIR] [--record FILE]

`harness.eval.predict.predict` reads its measured 8B reference from
`<--artifacts>/seq5/seq_c<C>_L<k>.json`, one file per context, and takes
`result.point` out of it; a file that is not there is a hard exit.  No run
writes that file.  A whole-sequence run writes one `slice_*.json` per proving
process, each holding under `result.chunks` the segments that process proved,
and every field the reference needs is in the segment.  This reads the named
segment out of the named run's slices and writes it as the one-segment document
the harness expects, into a directory the caller owns.

Without `--out` nothing is written and the sources are only checked, which is
what a driver calls before it books a card.  `--record` writes what was read --
run id, slice, segment tag, block, and the three numbers a reader would look up
first -- for the run's manifest.

A segment is named by its `ser_tag`, `B<block>L<layer>`, and never by the
`layer` field beside it: that field is the segment's index in the composed
sequence, not the model's layer, and a head segment earlier in the same slice
shifts the two apart.  In both headline runs the slice that holds the last token
block starts with the previous block's head segment, so `layer == 16` there is
the model's layer 15.

What the written file holds.  `result.point`, with the sub-objects the harness's
readers take fields from copied whole and nothing else:

    cells         `cells.fresh` is the reference itself, which is what `REF8B()`
                  returns; `base`, `interaction` and `preprocessed` are read by
                  the attention fits.
    params        `nh` and `hd` are the shape the registration asserts is the
                  8B's; `s`, `c`, `log_table`, `kmax` and `ao_rem_bits` say what
                  was proved.
    family_cells  `key_tiles` and `interaction_by_family.key_tiles.cells` are
                  what the registration's self-check reproduces to the cell.
    phases        the wall and prove seconds the attention fits read.

plus `accepts`, `off_table`, `ref_mismatch` and `peak_rss_bytes`.  The segment's
`proof_sha256` is deliberately not among them: the run that writes this file
proved nothing, and a document carrying a digest claims a proof it made.  The
digest of the proof the segment came from is in the record instead.

Refusals, each of them a reason the reference would not be the measurement it
claims to be: a source run directory, manifest, slice, segment or field that is
not there; a segment that did not accept, that fell off a table, that disagreed
with its reference, that left an edge unbound, or that was proved under an
unsound skip; a segment whose block length, context or attention shape is not
the one asked for; a tag whose layer is not the layer asked for.
"""
import argparse
import json
import os
import sys

# The 8B attention shape the registration asserts its reference has
# (`cm.LLAMA8B`), and the block length the frozen spec chunks at.
NH, HD, S = 32, 128, 512

FIELDS = ("cells", "params", "family_cells", "phases")
SCALARS = ("accepts", "off_table", "ref_mismatch", "peak_rss_bytes")


def bad(msg):
    sys.exit(f"seq5-reference.py: {msg}")


def load(path, what):
    if not os.path.exists(path):
        bad(f"{what} is not there: {path}")
    with open(path) as f:
        return json.load(f)


def segment_of(rundir, run, tag):
    """The one segment tagged `tag` in `run`'s slices, and the slice it is in."""
    slices = sorted(f for f in os.listdir(rundir)
                    if f.startswith("slice_") and f.endswith(".json"))
    if not slices:
        bad(f"{run} holds no slice_*.json; it is not a whole-sequence run")
    found = []
    for name in slices:
        doc = load(os.path.join(rundir, name), f"{run}/{name}")
        for seg in doc.get("result", {}).get("chunks", []):
            if seg.get("ser_tag") == tag:
                found.append((name, doc, seg))
    if not found:
        bad(f"no segment tagged {tag} in {run}; the reference cannot be derived from a "
            "run that did not prove it")
    if len(found) > 1:
        bad(f"{len(found)} segments tagged {tag} in {run}, in "
            f"{', '.join(n for n, _, _ in found)}; a tag names one segment")
    return found[0]


def check(run, tag, seg, doc, ctx, layer, blocks):
    """Refuse anything that would make the derived reference not a measurement."""
    for f in FIELDS:
        if not isinstance(seg.get(f), dict):
            bad(f"{run} {tag} carries no `{f}`; the reference reads it")
    p, fc = seg["params"], seg["family_cells"]
    if not seg.get("accepts"):
        bad(f"{run} {tag} was not accepted")
    for f in ("off_table", "ref_mismatch"):
        if seg.get(f):
            bad(f"{run} {tag}: {f} is {seg[f]}")
    if not seg.get("binding", {}).get("all_bound"):
        bad(f"{run} {tag} left the edges {seg.get('binding', {}).get('unbound')} unbound")
    skips = doc.get("provenance", {}).get("unsound_skips")
    if skips is None:
        bad(f"{run} {tag}: the slice carries no `provenance.unsound_skips`")
    if skips:
        bad(f"{run} {tag} was proved with the unsound skips {skips} in effect")
    if (p.get("nh"), p.get("hd")) != (NH, HD):
        bad(f"{run} {tag} has {p.get('nh')} heads of {p.get('hd')}, not the 8B's {NH} of {HD}")
    if p.get("s") != S:
        bad(f"{run} {tag} proved a block of {p.get('s')} tokens, not {S}")
    if p.get("c") != ctx:
        bad(f"{run} {tag} proved a prefix of {p.get('c')} tokens, not the {ctx} asked for")
    if "fresh" not in seg["cells"]:
        bad(f"{run} {tag} carries no `cells.fresh`, which is the reference itself")
    kt = fc.get("interaction_by_family", {}).get("key_tiles", {}).get("cells")
    if "key_tiles" not in fc or kt is None:
        bad(f"{run} {tag} carries no key tile family; the registration's self-check "
            "reproduces it to the cell")
    # The block is the one whose prefix is the run's whole context, which in a
    # decode run that grows the prefix one block at a time is the last block and
    # only that one.
    if blocks * S != ctx:
        bad(f"{run} {tag} is block {blocks} of a run whose context is {ctx}: at {S} tokens "
            f"a block, the prefix of {ctx} is block {ctx // S}")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--runs", required=True, help="the runs/ directory")
    ap.add_argument("--layer", type=int, required=True, help="the model layer the reference is")
    ap.add_argument("--from", dest="sources", metavar="RUN:TAG:CONTEXT", action="append",
                    required=True, help="a merged run, the segment's `ser_tag` in it, and the "
                                        "context that segment proved; repeat per context")
    ap.add_argument("--out", metavar="DIR", help="write DIR/seq5/seq_c<C>_L<k>.json; "
                                                 "without it the sources are only checked")
    ap.add_argument("--record", metavar="FILE", help="write what was read, as JSON, for the "
                                                     "run's manifest")
    a = ap.parse_args()

    contexts, seen = {}, set()
    for src in a.sources:
        try:
            run, tag, ctx = src.split(":")
            ctx = int(ctx)
        except ValueError:
            bad(f"--from {src} is not RUN:TAG:CONTEXT")
        if ctx in seen:
            bad(f"two sources for context {ctx}")
        seen.add(ctx)
        rundir = os.path.join(a.runs, run)
        if not os.path.isdir(rundir):
            bad(f"no run directory {rundir}")
        manifest = load(os.path.join(rundir, "manifest.json"), f"{run}'s manifest")
        try:
            block, tag_layer = (int(x) for x in tag.removeprefix("B").split("L"))
        except ValueError:
            bad(f"the segment tag {tag} is not B<block>L<layer>")
        if tag_layer != a.layer:
            bad(f"{tag} is layer {tag_layer}, not the layer {a.layer} asked for")
        name, doc, seg = segment_of(rundir, run, tag)
        check(run, tag, seg, doc, ctx, a.layer, block)

        point = {f: seg[f] for f in FIELDS}
        point.update({f: seg[f] for f in SCALARS if f in seg})
        config = load(os.path.join(rundir, "config.json"), f"{run}'s config")
        out_name = f"seq_c{ctx}_L{a.layer}.json"
        contexts[str(ctx)] = {
            "file": os.path.join("seq5", out_name),
            "run": manifest.get("run_id", run),
            "slice": name,
            "segment": tag,
            "plan_index": seg.get("plan_index"),
            "block": block,
            "blocks": config.get("blocks"),
            "tokens": [block * S, block * S + S - 1],
            "context": ctx,
            "s": S,
            "model": config.get("model"),
            "spec": config.get("spec"),
            "prover_commit": manifest.get("prover_commit"),
            "proof_sha256": seg.get("proof_sha256"),
            "fresh": seg["cells"]["fresh"],
            "key_tiles": seg["family_cells"]["key_tiles"],
            "key_tiles_interaction":
                seg["family_cells"]["interaction_by_family"]["key_tiles"]["cells"],
        }
        if a.out:
            d = os.path.join(a.out, "seq5")
            os.makedirs(d, exist_ok=True)
            doc_out = {"derived_from": contexts[str(ctx)], "result": {"point": point}}
            with open(os.path.join(d, out_name), "w") as f:
                json.dump(doc_out, f, indent=1, sort_keys=True)
                f.write("\n")

    record = {
        "what": f"the measured 8B layer {a.layer} reference chunk at each context, which "
                "`harness.eval.predict.predict` reads from "
                f"`<--artifacts>/seq5/seq_c<C>_L{a.layer}.json` and takes "
                "`result.point.cells.fresh` out of",
        "how": "derived from the segment each named run proved, by `ser_tag`; nothing was "
               "proved for it and no field was transcribed",
        "why_this_block": "the last token block of each run, the only one whose prefix is the "
                          "run's whole context: a decode run grows the prefix one block of "
                          f"{S} tokens at a time, so every earlier block is a different C",
        "contexts": contexts,
    }
    if a.record:
        with open(a.record, "w") as f:
            json.dump(record, f, indent=1, sort_keys=True)
            f.write("\n")
    for ctx, c in sorted(contexts.items(), key=lambda kv: int(kv[0])):
        print(f"seq5-reference.py: C={ctx:<6} {c['run']} {c['slice']} {c['segment']} "
              f"(block {c['block']} of {c['blocks']}, tokens {c['tokens'][0]}-{c['tokens'][1]})"
              f"  fresh {c['fresh']:,}"
              + (f"  -> {c['file']}" if a.out else "  checked, not written"))


if __name__ == "__main__":
    main()
