#!/bin/sh
# register-70b: the prediction `predict-70b` is measured against, registered.
#
#   tools/drivers/register-70b.sh
#
# **The registration is recorded BEFORE `predict-70b.sh` measures.** That is the
# one rule the experiment has: a prediction written after the measurement is not
# a prediction. `predict-70b.sh` refuses to start until this run is in `runs/`
# and writes this prediction's digest into its own config, so the order is
# register, measure, compare and the record says so from both ends.
#
# It takes no host and no card. A registration is a computation over this
# repository's `constants.json` and two layer chunks two recorded runs already
# proved, so it runs where the repository is: this and `register-14b.sh` are the
# only drivers here that open no ssh connection.
#
# A driver of its own and not a shape argument on `register-14b.sh`. The run id
# a manifest writes is `<date>-<driver>-<gpu>`, taken from the driver's own file
# name, so a 70B registration made by that driver would be recorded under
# `register-14b` -- the wrong campaign, in the one field a reader uses to find
# the run. The two drivers therefore differ in what they pin and what they
# register, and share the shape of everything else.
#
# What it registers. The `Llama-3.1-70B` row of `harness/eval/predict/predict.py`
# in zk-prover, named with `--shape`, which is the shape and not the model: what
# `predict-70b.sh` proves against it is a synthetic layer segment at that width.
# The prediction's own acceptance range was registered for a comparison against
# extracted witnesses, and the document says in its provenance block that a
# synthetic segment does not meet that clause; what this registration fixes in
# advance is the cell counts, the key tile integers and the statement they are
# priced at.
#
# What it does. It archives zk-prover at the commit pinned below into a
# directory of its own, derives the two measured 8B reference chunks the
# prediction is anchored on out of the runs this repository holds, and runs
# `harness.eval.predict.predict` against `constants.json` with no
# micro-benchmark inputs directory anywhere on the command line or in the
# environment. What comes back is checked before anything is written, and the
# run is refused when:
#
#   * any cell cost the prediction charged came from a micro-benchmark
#     directory rather than from a constants key;
#   * an input the model charges names a constants key this file does not hold,
#     which the model would otherwise charge zero for;
#   * the constants file the prediction froze by digest is not this
#     repository's, or that file has uncommitted changes;
#   * the statement the registration prices is not the statement
#     `predict-70b.sh` proves;
#   * the document registers anything other than the one shape asked for here. A
#     registration is the document that must not move after it is made, and a
#     run that recorded three other shapes under this name would be the wrong
#     document under the right run id.
#
# What it writes. `runs/<run-id>/registration.json`, `config.json` and
# `manifest.json`, the same three `register-14b.sh` writes and in the same
# shape: a `provenance` block saying which tree computed it, under which commit,
# and a `result` holding the registration document exactly as the harness
# emitted it, both of its digests included. The registration's identity is
# `prediction_sha256`, a digest of the content and not of the file.
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
# The pinned commit. It has to carry the `Llama-3.1-70B` row in the cost model's
# shape table and the `--shape` selection in the registration document, which is
# zk-prover#163; that pull request is open, so there is no commit on main to pin
# yet and this driver refuses rather than registering a document from a tree
# that cannot name the shape.
COMMIT=
# The statement the registration prices, which is what `predict-70b.sh` proves:
# its GKR flags and its diagonal block, and the two drivers have to name the
# same set.
STATEMENT="--diagonal-block --gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
# The measured 8B reference chunks the prediction is anchored on, one per
# context. The anchor is the 8B layer block whatever shape is registered: it is
# what says how far the same predictor is from a measurement at the one width
# anything was ever measured at. The same two segments `predict-14b.sh` and
# `register-14b.sh` derive, named the same way.
LAYER=16
SEQ5="--from 2026-09-09-headline-c4096-h100:B8L16:4096
      --from 2026-09-08-headline-c16384-h100:B32L16:16384"

# ---- the refusals that cost nothing, before anything is built ----------------
# 1. the pinned commit has to exist.
if [ -z "$COMMIT" ]; then
    echo "$NAME: no zk-prover commit is pinned." >&2
    echo "        The registration needs a tree that carries the Llama-3.1-70B shape" >&2
    echo "        row and the --shape selection (zk-prover#163). Pin that commit in" >&2
    echo "        this driver once it is on main, and register then." >&2
    exit 2
fi
# 2. the measurement must not have happened yet, and the registration must not
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
# 3. a micro-benchmark inputs directory in the environment would be read at
#    import by the cost model and would put numbers from outside both
#    repositories into the prediction.
if [ -n "${ZK_COSTMODEL_INPUTS:-}" ]; then
    echo "$NAME: ZK_COSTMODEL_INPUTS is set.  The registration is made from" >&2
    echo "        constants.json alone; unset it and run this again." >&2
    exit 2
fi
# 4. the constants file has to be the one in the repository's history: the
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
SRC=$(mktemp -d "${TMPDIR:-/tmp}/$NAME.XXXXXX")
ART=$ROOT/runs/.$NAME-ref
OUT=$(mktemp -d "$ROOT/runs/.$NAME-out.XXXXXX")
rm -rf "$ART"
mkdir "$ART"
DERIVED=$(mktemp)
GATE=$(mktemp)
trap 'rm -rf "$SRC" "$ART" "$OUT"; rm -f "$DERIVED" "$GATE"' EXIT INT TERM
git -C "$ZK_PROVER" archive --format=tar "$COMMIT" | tar -C "$SRC" -xf -
echo "$COMMIT" > "$SRC/.source-commit"
echo "$NAME: zk-prover@$COMMIT -> $SRC"

# ---- the reference chunks, derived from runs this repository holds -----------
# shellcheck disable=SC2086
python3 "$HERE/lib/seq5-reference.py" --runs "$ROOT/runs" --layer "$LAYER" $SEQ5 \
    --out "$ART" --record "$DERIVED"

# ---- the prediction ----------------------------------------------------------
( cd "$SRC/harness" && uv sync --frozen )
ARTREL=runs/$(basename "$ART")
ARGS="--constants constants.json --artifacts $ARTREL --shape $SHAPE --json"
# shellcheck disable=SC2086
if ! ( cd "$ROOT" && uv run --project "$SRC/harness" --frozen \
        python -m harness.eval.predict.predict $ARGS ); then
    echo >&2
    echo "$NAME: the harness did not produce a registration from constants.json alone." >&2
    echo "        Every cell cost the model charges is a key this file names, an input" >&2
    echo "        the model prices for itself, or an input it records as unpriced; a key" >&2
    echo "        that is missing is where it stops, and today the two it stops on are" >&2
    echo "        the LogUp marginal and the weight Freivalds cost, which the" >&2
    echo "        microbench-cells driver measures.  Record the constants the campaign" >&2
    echo "        is measuring first, then register." >&2
    exit 3
fi

# ---- the gate, and the run's two outputs -------------------------------------
cat > "$GATE" <<'PY'
"""Refuse a registration that was not computed from this repository, or that
registers another shape, and write the run's outputs.  Nothing here recomputes a
prediction: what is read is the registration's own record of what it read."""
import hashlib
import importlib.util
import json
import pathlib
import sys

from harness import provenance

root, out, args, statement, zk_results_commit, label, shape, regfile = sys.argv[1:9]
root, out = pathlib.Path(root), pathlib.Path(out)
# The file `--json` wrote, found through the module rather than guessed: it is
# written beside `predict.py`, and where that is depends on how the harness's
# environment installed the project.
spec = importlib.util.find_spec("harness.eval.predict.predict")
reg = json.loads((pathlib.Path(spec.origin).parent / "out" / regfile).read_text())
argv = args.split()
bad = []

if reg.get("schema") != "e4-registration/1":
    bad.append(f"the document's schema is {reg.get('schema')!r} and not e4-registration/1")

# The one shape this run registers, from both places the document names it.
registers = reg["provenance"].get("registers")
if registers != [shape] or sorted(reg["shapes"]) != [shape]:
    bad.append(f"this run registers {shape} and the document registers "
               f"{registers} / {sorted(reg['shapes'])}")

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

priced = reg["statement"].get("driver_flags", "")
if sorted(priced.split()) != sorted(statement.split()):
    bad.append(f"the registration prices `{priced}` and the run it is registered against "
               f"proves `{statement}`; a registration that prices another statement is "
               "another registration")

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

e = reg["shapes"][shape]
config = {
    "driver": "register-70b", "label": label,
    "shape": shape, "cfg": e["cfg"],
    "statement": statement,
    "constants": {"file": "constants.json", "sha256": sha,
                  "zk_results_commit": zk_results_commit},
    "cell_costs_by_source": {s: len(n) for s, n in sorted(by_source.items())},
    "cell_costs_not_priced": frozen["not_priced"],
    "reference_chunks": frozen["reference_chunks"],
    "cells_per_token_layers": {c: p["cells_per_token_layers"]
                               for c, p in e["contexts"].items()},
    "per_layer_chunk_fresh": {c: p["per_layer_chunk_fresh"]
                              for c, p in e["contexts"].items()},
    "chunk_over_8b_l16_chunk": {c: p["chunk_over_8b_l16_chunk"]
                                for c, p in e["contexts"].items()},
    "prediction_sha256": reg["prediction_sha256"],
    "prediction_block_sha256": reg["prediction_block_sha256"],
    "measured_by": "tools/drivers/predict-70b.sh, which runs after this",
    "measures": "a synthetic layer segment at this shape's width, one per context: "
                "the shape and not the model, and no weight of it is read anywhere",
    "witness": "none: no witness, no proof and no cell count exists at this width, "
               "which is what makes this a prediction",
}
with open(out / "config.json", "w") as f:
    json.dump(config, f, indent=1, sort_keys=True)
    f.write("\n")
print(f"register-70b: prediction_sha256 {reg['prediction_sha256']}")
print(f"register-70b: prediction_block_sha256 {reg['prediction_block_sha256']}")
PY
( cd "$ROOT" && uv run --project "$SRC/harness" --frozen python "$GATE" \
    "$ROOT" "$OUT" "$ARGS" "$STATEMENT" "$ZK_RESULTS_COMMIT" "$LABEL" "$SHAPE" "$REGFILE" )

# ---- the record --------------------------------------------------------------
python3 "$HERE/lib/manifest.py" --driver "tools/drivers/$NAME.sh" --fetched "$OUT" \
    --runs "$ROOT/runs" --prover-commit "$COMMIT" --harness-commit "$COMMIT" \
    --derived "$DERIVED" --date "$(date -u +%Y-%m-%d)"
(cd "$ROOT" && python3 tools/constants/check.py)

RUN=$(ls -d "$ROOT"/runs/*-"$NAME"-* | tail -1)
echo
echo "$NAME: recorded in runs/$(basename "$RUN")"
echo "next:  measure, with the registration already in this repository, at the card"
echo "       and the block length the campaign decided on:"
echo "         tools/drivers/predict-70b.sh <host> $COMMIT $COMMIT <card> <block>"
echo "       the comparison is not built for this shape yet: compare.py maps a slug"
echo "       to a registered shape and has no row for this one."
