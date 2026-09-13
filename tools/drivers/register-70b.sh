#!/bin/sh
# register-70b: the prediction `predict-70b` is measured against, registered.
#
#   tools/drivers/register-70b.sh
#
# **The registration is recorded BEFORE `predict-70b.sh` measures.** That is the
# one rule the experiment has: a prediction written after the measurement is not
# a prediction. `predict-70b.sh` refuses to start until this run is in `runs/`,
# writes this prediction's digest into its own config and refuses a block length
# this registration was not counted at, so the order is register, measure,
# compare and the record says so from both ends.
#
# It takes no host and no card. A registration is a computation over this
# repository's `constants.json`, two layer chunks two recorded runs already
# proved, and the block of fields below: it runs where the repository is, and
# this and `register-13b.sh` and `register-14b.sh` are the drivers here that
# open no ssh connection.
#
# COUNTED, and counted at a STATED block of fields. The owner's ruling of
# 2026-09-11 is that a shape whose segment can be stated is counted from the
# trace layout and not priced from the 8B's per-unit constants
# (`docs/decisions/2026-09-11-cells-are-counted-from-the-layout-wherever-a-shape-can-be-stated.md`),
# and the counted path needs one thing a model and a context do not give it: the
# fields a run calibrates off its own witness -- the master exponent table, the
# normalisation window, the attention output's accumulator and divisor widths.
# `register-13b.sh` reads them off that model's dumps. There is no dump here and
# there will not be one: what `predict-70b.sh` proves is a SYNTHETIC layer
# segment at the Llama-3.1-70B width, built by the prover's own fixed-seed
# generator, so the fields are STATED here instead, each one with where it comes
# from, and the statement travels into the registration and is what the
# measurement tests. Three kinds, and they are not equally strong:
#
#   * `log_table` and `kmax` the prover takes verbatim from the flags
#     `predict-70b.sh` passes (`main.rs`, `params_of`: `arg_scalar(args,
#     "--table-bits", ...)` and `arg_scalar(args, "--kmax", ...)`). Stated, not
#     assumed;
#   * `ao_q_bits` and the fold's two pins are the generator's own: a synthetic
#     layer sets the attention output's width to 8, so the first is 7, and
#     `--layout b10` puts all seven matmuls on the chain and delays none, so the
#     other two are 0. Stated, not assumed;
#   * the attention output's measured windows -- the divisor's range, the
#     accumulator's two limbs and the `jo` and `jv` extremes -- no flag pins,
#     and they exist only once the generator has drawn the layer. Those are the
#     ASSUMPTION, and they are stated at the values the same generator produced
#     at the 8B attention width, in the one recorded run of it at this context:
#     `2026-09-09-prefill-sweep-8b-h200`, output `dd_s256_c4096.json`. They are
#     properties of the attention's own arithmetic -- the head dimension, the
#     prefix, the block and `--numbits` -- and the 70B width shares every one of
#     those with that point; what it does not share is the head count, which
#     these four do not depend on.
#
# C = 4,096 ALONE, and the document says so in its own `contexts_not_registered`.
# The attention output's divisor range and the master exponent table both grow
# with the prefix, so a segment at one context is not counted at another's
# fields, and `harness/eval/predict/predict.py` refuses to. There is a recorded
# synthetic segment at C = 4,096 to state the assumed four from and none at
# C = 16,384, so the second context is measured by `predict-70b.sh` and is
# registered against nothing. Pinning `--ao-rem-bits` and the accumulator limbs
# in that driver is what would make every field of a synthetic segment a flag
# and let both contexts be registered in advance; it is the owner's call and is
# not taken here.
#
# THE BLOCK IS 128 AND NOT 512, and that is the memory answer. One 70B layer
# segment at a 512-token block does not fit an 80 GB card at either context: the
# 8B's own measured pairs put the card at 47.9 MiB per million cells of the
# largest segment at C = 4,096 and 33.2 at C = 16,384, and this segment counts
# 2.85 G cells at C = 4,096 and 4.53 G at C = 16,384 at that block. At 128 it
# counts 1.08 G and 2.04 G, which the same two ratios put at 63.5% and 82.9% of
# the 81,559 MiB the card reports. A block that is not 512 is a different
# quantity: it is in this registration's own statement, it is an argument of
# `predict-70b.sh`, and that driver refuses a call that names another one.
#
# What it does. It archives zk-prover at the commit pinned below into a
# directory of its own, derives the two measured 8B reference chunks the
# prediction is anchored on out of the runs this repository holds, writes the
# fields file from the block below through the module that owns that schema, and
# runs `harness.eval.predict.predict` against `constants.json` and that file
# with no micro-benchmark inputs directory anywhere on the command line or in
# the environment. What comes back is checked before anything is written, and
# the run is refused when:
#
#   * any cell cost the prediction charged came from a micro-benchmark
#     directory rather than from a constants key. The cost model reads
#     constants first and falls back to `--inputs DIR`, a directory that is in
#     no repository and that nothing here can reproduce; the prediction's own
#     `frozen_inputs.cell_costs` says which source each of its inputs came from,
#     and this reads that record rather than trusting the command line;
#   * an input the model charges names a constants key this file does not hold.
#     Those are the ones a run in this repository is supposed to back, and the
#     model would silently charge zero for them;
#   * the constants file the prediction froze by digest is not this
#     repository's, or that file has uncommitted changes. A registration
#     against bytes that are in no commit cannot be reproduced;
#   * the statement the registration prices is not the statement
#     `predict-70b.sh` proves, or the block it counted is not the block that
#     driver is told to prove. A registration that prices another statement, or
#     counts another segment, is another registration;
#   * the document registers anything other than the one shape asked for here, or
#     was priced rather than counted, or counted a segment it read off a dump: a
#     synthetic segment has no dump, and a document that names one is not this
#     one;
#   * the count is short of a segment the stack has. Nothing is absent here --
#     no extractor refused anything, because nothing was extracted -- so a stack
#     of 80 is counted as 80 or the run is refused.
#
# What it does not refuse, and records instead: an input the model prices by
# analogy or by standing in a neighbouring one, the composed-prover figures the
# harness carries as a repository fixture of its own, and every input the model
# cannot price at all. None of those is a number from outside the two
# repositories; all of them are in the registration by name, and the run's
# `config.json` counts them by source so a reader of the record sees the split
# without opening the registration.
#
# What it writes. `runs/<run-id>/registration.json`, `config.json` and
# `manifest.json`, the same three the other two registration drivers write and
# in the same shape: a `provenance` block saying which tree computed it, under
# which commit, and a `result` holding the registration document exactly as the
# harness emitted it, its own provenance block and both of its digests included.
# The registration's identity is `prediction_sha256`, a digest of the content and
# not of the file.
#
# The two reference chunks are derived and not measured, the same derivation
# `predict-13b.sh` makes for the same two chunks; they are not written into this
# run, because the registration names the run, the slice output, the segment and
# the proof digest each came from, and the manifest's `derived` block says it
# again. `lib/seq5-reference.py` holds what they are and what makes the
# derivation refuse.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
ZK_PROVER=${ZK_PROVER_DIR:-$ROOT/../zk-prover}     # a local clone to archive the commit from
NAME=register-70b

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=registration         # a prediction, not a measurement: this run proves nothing
# The shape registered, as `harness/eval/predict/predict.py` names it, and the
# file that harness writes it to: the same name with every run of characters
# that is not a letter or a digit turned into one dash, lower case, which is the
# rule that module applies to a selection that is not the three E4 registered.
SHAPE="Llama-3.1-70B"
REGFILE=registration-llama-3-1-70b.json
NLAY=80                    # the stack's own layer count, from the model's config
# The pinned commit. It carries three things this registration needs and
# zk-prover main does not: the counted-registration record for this shape, the
# `--block` the document is counted at, and `witness_fields --synthetic`, which
# writes a fields file for a segment that has no dump. This is the head of
# zk-prover's `shape-70b-synthetic` branch and it is NOT MERGED. RE-PIN THIS
# when it is -- the merged commit is the one a reader can fetch, and an
# unmerged branch head is not.
COMMIT=51ee439a7a55b5f050483e7b6ac3338d38ec7e34
# The statement the registration prices, which is what `predict-70b.sh` proves:
# its GKR flags and its diagonal block, and the two drivers have to name the
# same set.
STATEMENT="--diagonal-block --gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
# The block and the context this registration is counted at, and the head
# grouping the count needs. `predict-70b.sh` takes the block as an argument and
# refuses one this registration was not counted at; the head grouping is that
# driver's own `HEAD_GROUPS`.
BLOCK=128
CTX=4096
HEAD_GROUPS=16,16,16,16
# The measured 8B reference chunks the prediction is anchored on, one per
# context. The anchor is the 8B layer block whatever shape is registered: it is
# what says how far the same predictor is from a measurement at the one width
# anything was ever measured at. The same two segments `predict-13b.sh` and
# `register-13b.sh` derive, named the same way.
LAYER=16
SEQ5="--from 2026-09-09-headline-c4096-h100:B8L16:4096
      --from 2026-09-08-headline-c16384-h100:B32L16:16384"

# ---- the refusals that cost nothing, before anything is built ----------------
# 1. the measurement must not have happened yet, and the registration must not
#    have been made already. A prediction written after the measurement is not a
#    prediction, and a second registration beside the first is two documents
#    where the record needs one: replacing a registration means removing the run
#    that holds it, deliberately.
set -- "$ROOT"/runs/*-predict-70b-* "$ROOT"/runs/*-register-70b-*
for d in "$@"; do
    [ -d "$d" ] || continue
    echo "$NAME: runs/$(basename "$d") is already recorded." >&2
    echo "        A registration comes before the measurement and is made once: if this" >&2
    echo "        one has to be replaced, remove that run directory first, and if the" >&2
    echo "        measurement has already happened it is the measurement that is re-run." >&2
    exit 2
done
# 2. a micro-benchmark inputs directory in the environment would be read at
#    import by the cost model and would put numbers from outside both
#    repositories into the prediction. It is refused here rather than caught
#    afterwards, so the message says what to do about it.
if [ -n "${ZK_COSTMODEL_INPUTS:-}" ]; then
    echo "$NAME: ZK_COSTMODEL_INPUTS is set.  The registration is made from" >&2
    echo "        constants.json and the stated fields alone; unset it and run this again." >&2
    exit 2
fi
# 3. the constants file has to be the one in the repository's history: the
#    registration freezes it by digest, and a digest of uncommitted bytes names
#    nothing anyone can read back.
if [ -n "$(git -C "$ROOT" status --porcelain -- constants.json)" ]; then
    echo "$NAME: constants.json has uncommitted changes.  The registration freezes it" >&2
    echo "        by digest; commit it first, so the digest names bytes this" >&2
    echo "        repository holds." >&2
    exit 2
fi
git -C "$ZK_PROVER" rev-parse --git-dir > /dev/null 2>&1 ||
  { echo "no zk-prover clone at $ZK_PROVER (set ZK_PROVER_DIR)" >&2; exit 2; }
git -C "$ZK_PROVER" cat-file -e "$COMMIT^{commit}" ||
  { echo "the pinned commit $COMMIT is not in $ZK_PROVER; fetch it" >&2; exit 2; }
ZK_RESULTS_COMMIT=$(git -C "$ROOT" rev-parse HEAD)

# ---- the pinned sources ------------------------------------------------------
# An archive and not a clone: the same tree `tools/remote/push.sh` puts on a
# host, with the same `.source-commit` beside it, which is where the harness's
# own provenance block reads the commit it records from.
SRC=$(mktemp -d "${TMPDIR:-/tmp}/$NAME.XXXXXX")
# The reference chunks go to a path with no random part in it, under the
# repository, so that the arguments the prediction records as its own name a
# directory this repository can make again.  They are derived, read and removed
# inside this one run.
ART=$ROOT/runs/.$NAME-ref
OUT=$(mktemp -d "$ROOT/runs/.$NAME-out.XXXXXX")
rm -rf "$ART"
mkdir "$ART"
DERIVED=$(mktemp)
GATE=$(mktemp)
STATED=$(mktemp)
# The fields file goes to a path with no random part in it, under the
# repository, for the same reason the reference chunks do: what the prediction
# records as its own arguments has to name a directory this repository can make
# again.  It is written, read and removed inside this one run; what outlives it
# is the block itself, which is in this file and in the registration.
FIELDS=$ROOT/runs/.$NAME-fields.json
trap 'rm -rf "$SRC" "$ART" "$OUT"; rm -f "$DERIVED" "$GATE" "$STATED" "$FIELDS"' EXIT INT TERM
git -C "$ZK_PROVER" archive --format=tar "$COMMIT" | tar -C "$SRC" -xf -
echo "$COMMIT" > "$SRC/.source-commit"
echo "$NAME: zk-prover@$COMMIT -> $SRC"

# ---- the reference chunks, derived from runs this repository holds -----------
# shellcheck disable=SC2086
python3 "$HERE/lib/seq5-reference.py" --runs "$ROOT/runs" --layer "$LAYER" $SEQ5 \
    --out "$ART" --record "$DERIVED"

# ---- the stated block: the whole assumption this registration makes ----------
# One segment's fields, and every row of the fields file is this block, because
# every segment of a synthetic stack at one width IS the same segment. The
# shape is Llama-3.1-70B's own published configuration; the knobs are
# `predict-70b.sh`'s flags; `stated_from` says of each field which of the three
# kinds above it is, and travels into the registration with it.
cat > "$STATED" <<'STATEDEOF'
{
 "model": "Llama-3.1-70B (the width; synthetic, and no weight of it is read)",
 "spec": "b10-final",
 "c": 4096,
 "s": 128,
 "d": 8192, "dff": 28672, "nh": 64, "nkv": 8, "hd": 128, "vocab": 128256,

 "log_table": 24,
 "kmax": 20,
 "ao_q_bits": 7,
 "fold_rem_bits": 0,
 "fold_alpha": 0,
 "k_bits": 11,
 "q_bits": 12,
 "nmax": 511,
 "z_min": 511,
 "deq_variants": {"q": "chain", "k": "chain", "v": "chain", "o": "chain",
                  "gate": "chain", "up": "chain", "down": "chain"},

 "ao_rem_bits": 21,
 "ao_acc_lo_bits": 16,
 "ao_acc_hi_bits": 6,
 "ao_acc_mag": false,
 "ao_denp2": false,
 "ao_jo_min": -13,
 "ao_jo_max": -12,
 "ao_jv_min": -12,
 "ao_jv_max": -6,

 "stated_from": {
  "log_table": "a flag: predict-70b.sh passes --table-bits 24 as the first of the two table widths it tries, and params_of takes it verbatim. The same generator sized its own table at exactly 24 at the 8B attention width at every recorded point -- a 64-token block at C=64, a 128-token block at C=128 and a 256-token block at C=4,096. A run that has to widen the table to 25 is a run at another table and is reported as one: five cells a row makes that 83.9 M more cells a segment",
  "kmax": "a flag: predict-70b.sh passes --kmax 20 and params_of takes it verbatim. It is also the prover's own blind bound for this shape, so the flag and the derivation agree: the widest matmul is `down` at 28,672 inputs, 127 * 127 * 28,672 is 462,450,688, which is 29 bits, and the window is the bits above the 9 the mantissa carries. The sound cap is 21",
  "ao_q_bits": "the generator's: a synthetic layer sets the attention output's width to 8 and ao_q_bits is that minus one",
  "fold_rem_bits": "the generator's: --layout b10 puts all seven matmuls on the chain dequantize gadget and delays none, so the layer has no fold matmul and no fold pin",
  "fold_alpha": "the generator's, for the same reason as fold_rem_bits",
  "deq_variants": "the generator's: --layout b10 is the chain on all seven (`MAT_VARIANTS_CHAIN`, prover/src/layer.rs)",
  "k_bits": "a flag: the quantize widths predict-70b.sh proves at, which are the recorded statement's",
  "q_bits": "a flag: the quantize widths predict-70b.sh proves at, which are the recorded statement's",
  "nmax": "a flag: --numbits 9, so 2^9 - 1",
  "z_min": "a flag: --numbits 9, so 2^9 - 1",
  "ao_rem_bits": "ASSUMED, from the recorded synthetic segment 2026-09-09-prefill-sweep-8b-h200 dd_s256_c4096.json: the same generator with --synth-residual-stream and --diagonal-block, the same head dimension of 128, the same --numbits 9 and --round even, at the same context. No flag pins it here and the witness that settles it does not exist yet",
  "ao_acc_lo_bits": "ASSUMED, from the same recorded segment. The limbs are params_of's split of the accumulator this layer draws",
  "ao_acc_hi_bits": "ASSUMED, from the same recorded segment",
  "ao_acc_mag": "derived from the four stated above, by params_of's own rule: the offset form is taken wherever it fits, and 1 + 16 + 6 + (ao_jv_max - ao_jo_min) = 30 is inside the field's 31",
  "ao_denp2": "derived from the two stated above, by params_of's own rule: ao_q_bits + ao_rem_bits = 28 is inside 30, so the plain form stands",
  "ao_jo_min": "ASSUMED, from the same recorded segment",
  "ao_jo_max": "ASSUMED, from the same recorded segment",
  "ao_jv_min": "ASSUMED, from the same recorded segment",
  "ao_jv_max": "ASSUMED, from the same recorded segment"
 }
}
STATEDEOF

# ---- the fields file, written by the module that owns the schema -------------
( cd "$SRC/harness" && uv sync --frozen )
uv run --project "$SRC/harness" --frozen python -m harness.eval.predict.witness_fields \
    --synthetic "$STATED" --layers "$NLAY" --head-groups "$HEAD_GROUPS" --out "$FIELDS"

# ---- the prediction ----------------------------------------------------------
# The harness's own environment, its default (host) torch group: nothing here
# reads a weight or a card. The command runs from the repository root so that
# what it records as its arguments is a path this repository has, and `--inputs`
# is named nowhere.
ARTREL=runs/$(basename "$ART")
FIELDSREL=runs/$(basename "$FIELDS")
ARGS="--constants constants.json --artifacts $ARTREL --shape $SHAPE --cells exact --witness-fields $FIELDSREL --block $BLOCK --json"
# shellcheck disable=SC2086
if ! ( cd "$ROOT" && uv run --project "$SRC/harness" --frozen \
        python -m harness.eval.predict.predict $ARGS ); then
    echo >&2
    echo "$NAME: the harness did not produce a registration for this shape." >&2
    echo "        A shape it holds no row for is refused rather than registered, and" >&2
    echo "        so is one with no counted-registration record: both are rows in" >&2
    echo "        harness/eval/predict/predict.py, the seven-tuple from the model's" >&2
    echo "        published config and the date and standing the registration is made" >&2
    echo "        under. Add them at the pinned commit and register again." >&2
    exit 3
fi

# ---- the gate, and the run's two outputs -------------------------------------
cat > "$GATE" <<'PY'
"""Refuse a registration that was not computed from this repository, and write
the run's outputs.  Nothing here recomputes a prediction: what is read is the
registration's own record of what it read."""
import hashlib
import importlib.util
import json
import pathlib
import sys

from harness import provenance

(root, out, args, statement, zk_results_commit, label, shape, nlay, block, ctx,
 fields_path) = sys.argv[1:12]
root, out = pathlib.Path(root), pathlib.Path(out)
nlay, block, ctx = int(nlay), int(block), int(ctx)
# The file `--json` wrote, found through the module rather than guessed: it is
# written beside `predict.py`, and where that is depends on how the harness's
# environment installed the project.  A shape registered on its own is written
# under its own name and never over the document E4's three are registered in.
spec = importlib.util.find_spec("harness.eval.predict.predict")
import re
slug = re.sub(r"[^a-z0-9]+", "-", shape.lower()).strip("-")
reg = json.loads((pathlib.Path(spec.origin).parent / "out"
                  / f"registration-{slug}.json").read_text())
argv = args.split()
bad = []

if reg.get("schema") != "e4-registration/1":
    bad.append(f"the document's schema is {reg.get('schema')!r} and not e4-registration/1")

frozen = reg["frozen_inputs"]
sha = hashlib.sha256((root / "constants.json").read_bytes()).hexdigest()
if frozen.get("constants_file_sha256") != sha:
    bad.append(f"the prediction froze the constants file {frozen.get('constants_file_sha256')} "
               f"and this repository's is {sha}")

costs = frozen["cell_costs"]
by_source = {}
for name, e in sorted(costs.items()):
    by_source.setdefault(e["source"], []).append(name)
if by_source.get("inputs"):
    bad.append("these inputs came from a micro-benchmark directory and not from the "
               "constants file: " + ", ".join(by_source["inputs"]))
missing = [n for n, e in sorted(costs.items())
           if e["source"] == "absent" and e["charged"] and e["key"]]
if missing:
    bad.append("the model charges these and this constants file does not name them: "
               + ", ".join(f"{n} ({costs[n]['key']})" for n in missing))

st = reg["statement"]
priced = st.get("driver_flags", "")
if sorted(priced.split()) != sorted(statement.split()):
    bad.append(f"the registration prices `{priced}` and the run it is registered against "
               f"proves `{statement}`; a registration that prices another statement is "
               "another registration")
# The block is part of the registered quantity and not a detail of it: a segment
# over a shorter block is a different segment, and `predict-70b.sh` is told the
# same number on its own command line.
if st.get("block", 512) != block:
    bad.append(f"the registration is counted at a block of {st.get('block', 512)} and this "
               f"run registers {block}; the cells of a segment are not linear in the block")

# The counted side: one shape, counted and not priced, over the whole stack, at
# the one context its fields are stated for.
if sorted(reg["shapes"]) != [shape]:
    bad.append(f"the registration prices {', '.join(sorted(reg['shapes']))} and this run "
               f"registers {shape}")
if frozen.get("cells") != "exact":
    bad.append("the registration was priced and not counted; the committed cells of a "
               "shape nothing was fitted at are counted from the trace layout")
wfr = frozen.get("witness_fields", {})
if not wfr.get("synthetic") or not wfr.get("stated_from"):
    bad.append("the registration was not counted at a stated block of fields, so it is "
               "not this document: a synthetic segment has no dump and its fields are "
               "stated with where each one came from")
if wfr.get("file_sha256") != hashlib.sha256(
        pathlib.Path(fields_path).read_bytes()).hexdigest():
    bad.append("the fields file the registration froze is not the one this run wrote")
if any(r.get("dump_sha256") for r in wfr.get("layers", {}).values()):
    bad.append("a counted segment names a dump digest, and no dump of this shape exists")
counted = wfr.get("layers", {})
got_absent = sorted(wfr.get("absent") or ())
if got_absent:
    bad.append(f"the fields file names layers {got_absent} absent; nothing was extracted "
               f"here, so nothing refused to write a dump and no segment of this stack "
               f"is missing")
if len(counted) != nlay:
    bad.append(f"the fields file carries {len(counted)} segments and the stack has {nlay}")

entry = reg["shapes"][shape]
if sorted(entry["contexts"]) != [str(ctx)]:
    bad.append(f"the registration registers contexts {sorted(entry['contexts'])} and this "
               f"run registers {ctx} alone")
if not entry.get("contexts_not_registered"):
    bad.append("the registration names no context it does not register, and this shape's "
               "campaign measures two")

for source, names in sorted(by_source.items()):
    print(f"register-70b: {len(names):>2} cell cost(s) from {source}: {', '.join(names)}")
if bad:
    sys.exit("register-70b: " + "; ".join(bad))

doc = {
    "provenance": provenance.block(
        model=None, device="cpu", threads=1,
        module="harness.eval.predict.predict", argv=argv,
        # Fixed rather than probed: this run makes no proof, reads no card and
        # would be the same document on any machine, so the run id names no card
        # that did nothing.
        gpu="none",
        registration={"prediction_sha256": reg["prediction_sha256"],
                      "prediction_block_sha256": reg["prediction_block_sha256"]},
        constants={"file": "constants.json", "sha256": sha,
                   "zk_results_commit": zk_results_commit}),
    "result": reg,
}
with open(out / "registration.json", "w") as f:
    json.dump(doc, f, indent=1, sort_keys=True)
    f.write("\n")

c = entry["contexts"][str(ctx)]
# The one number the measurement is compared against. `per_layer_chunk_fresh` is
# the stack's average and carries the embedding segment, which this run's
# segment is not; every other segment of this stack is the same segment, so the
# layer segment's own count is one integer and it is stated here rather than
# read back out of the eighty rows.
layers = {r["fresh"] for r in c["layers"] if r["kind"] != "first segment"}
if len(layers) != 1:
    sys.exit(f"register-70b: the layer segments do not agree on a count: {sorted(layers)}")
config = {
    "driver": "register-70b", "label": label,
    "statement": statement, "block": block, "context": ctx,
    "shape": shape, "cfg": entry["cfg"], "segments_counted": len(counted),
    "cells": frozen.get("cells"),
    "constants": {"file": "constants.json", "sha256": sha,
                  "zk_results_commit": zk_results_commit},
    "cell_costs_by_source": {s: len(n) for s, n in sorted(by_source.items())},
    "cell_costs_not_priced": frozen["not_priced"],
    "reference_chunks": frozen["reference_chunks"],
    "cells_per_token_layers": {str(ctx): c["cells_per_token_layers"]},
    "per_layer_chunk_fresh": {str(ctx): c["per_layer_chunk_fresh"]},
    "layer_segment_fresh": {str(ctx): sorted(layers)[0]},
    "chunk_over_8b_l16_chunk": {str(ctx): c["chunk_over_8b_l16_chunk"]},
    "contexts_not_registered": entry["contexts_not_registered"],
    "fields_stated_from": wfr["stated_from"],
    "fields_sha256": wfr["file_sha256"],
    "prediction_sha256": reg["prediction_sha256"],
    "prediction_block_sha256": reg["prediction_block_sha256"],
    "measured_by": "tools/drivers/predict-70b.sh, which proves after this",
    "measures": "one synthetic layer segment at this shape's width per context: the "
                "shape and not the model, and no weight of it is read anywhere",
    "witness": "none, and none will exist: the segment is built by the prover's own "
               "fixed-seed generator, so every field it is counted at is stated in "
               "`fields_stated_from` and no dump backs any of them",
}
with open(out / "config.json", "w") as f:
    json.dump(config, f, indent=1, sort_keys=True)
    f.write("\n")
print(f"register-70b: one layer segment at C={ctx:,}, block {block}: "
      f"{sorted(layers)[0]:,} fresh cells")
print(f"register-70b: prediction_sha256 {reg['prediction_sha256']}")
print(f"register-70b: prediction_block_sha256 {reg['prediction_block_sha256']}")
PY
( cd "$ROOT" && uv run --project "$SRC/harness" --frozen python "$GATE" \
    "$ROOT" "$OUT" "$ARGS" "$STATEMENT" "$ZK_RESULTS_COMMIT" "$LABEL" "$SHAPE" "$NLAY" \
    "$BLOCK" "$CTX" "$FIELDS" )

# ---- the record --------------------------------------------------------------
python3 "$HERE/lib/manifest.py" --driver "tools/drivers/$NAME.sh" --fetched "$OUT" \
    --runs "$ROOT/runs" --prover-commit "$COMMIT" --harness-commit "$COMMIT" \
    --derived "$DERIVED" --date "$(date -u +%Y-%m-%d)"
(cd "$ROOT" && python3 tools/constants/check.py)

RUN=$(ls -d "$ROOT"/runs/*-"$NAME"-* | tail -1)
echo
echo "$NAME: recorded in runs/$(basename "$RUN")"
echo "next:  measure, with the registration already in this repository, at the card"
echo "       and the block length this registration was counted at:"
echo "         tools/drivers/predict-70b.sh <host> <prover commit> <harness commit> <card> $BLOCK"
echo "       The two commits are the ones the SEGMENT is built and proved at, which"
echo "       is zk-prover main -- not $COMMIT, which is only where this"
echo "       registration's counting code lives and which no proof needs."
echo "       The card is an argument and has no default: the memory answer is about"
echo "       one card and a rate on one is not a rate on the other. A call that"
echo "       names another block is refused by that driver, because this document"
echo "       counted a segment of $BLOCK positions and not of another length."
echo "       the comparison is not built for this shape yet: compare.py maps a slug"
echo "       to a registered shape and has no row for this one."
