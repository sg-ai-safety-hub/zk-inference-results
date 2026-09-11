#!/bin/sh
# register-14b: the prediction `predict-14b` is measured against, registered.
#
#   tools/drivers/register-14b.sh
#
# **The registration is recorded BEFORE `predict-14b.sh` measures.** That is the
# one rule the experiment has: a prediction written after the measurement is not
# a prediction, and the comparison, `harness/eval/predict/compare.py`, reads the
# registration this run records and compares the measured layer proofs against
# it.  So the order is register, measure, compare, and this driver refuses to
# run once a `predict-14b` run is in `runs/`, and once a registration is: the
# document that must not move after it is made is made once.
#
# It takes no host and no card.  A registration is a computation over this
# repository's `constants.json` and two layer chunks two recorded runs already
# proved, so it runs where the repository is: this is the only driver here that
# opens no ssh connection.
#
# What it does.  It archives zk-prover at the commit pinned below into a
# directory of its own, derives the two measured 8B reference chunks the
# prediction is anchored on out of the runs this repository holds, and runs
# `harness.eval.predict.predict` against `constants.json` with no
# micro-benchmark inputs directory anywhere on the command line or in the
# environment.  What comes back is checked before anything is written, and the
# run is refused when:
#
#   * any cell cost the prediction charged came from a micro-benchmark
#     directory rather than from a constants key.  The cost model reads
#     constants first and falls back to `--inputs DIR`, a directory that is in
#     no repository and that nothing here can reproduce; the prediction's own
#     `frozen_inputs.cell_costs` says which source each of its inputs came from,
#     and this reads that record rather than trusting the command line;
#   * an input the model charges names a constants key this file does not hold.
#     Those are the ones a run in this repository is supposed to back, and the
#     model would silently charge zero for them;
#   * the constants file the prediction froze by digest is not this
#     repository's, or that file has uncommitted changes.  A registration
#     against bytes that are in no commit cannot be reproduced;
#   * the statement the registration prices is not the statement
#     `predict-14b.sh` proves.  A registration that prices another statement is
#     another registration, so the two lists of flags are compared here and the
#     driver is the place they have to agree.
#
# What it does not refuse, and records instead: an input the model prices by
# analogy or by standing in a neighbouring one, the composed-prover figures the
# harness carries as a repository fixture of its own, and every input the model
# cannot price at all.  None of those is a number from outside the two
# repositories; all of them are in the registration by name, and the run's
# `config.json` counts them by source so a reader of the record sees the split
# without opening the registration.
#
# What it writes.  `runs/<run-id>/registration.json`, `config.json` and
# `manifest.json`.  The registration file is the run JSON this repository's
# manifest is written from: a `provenance` block saying which tree computed it,
# under which commit, and a `result` holding the registration document exactly
# as the harness emitted it, its own provenance block and both of its digests
# included.  `compare.py` reads a bare registration document from
# `harness/eval/predict/out/registration.json` in a checkout, so the comparison
# copies `result` back there; the last thing this driver prints is that command.
# The registration's identity is `prediction_sha256`, which is a digest of the
# content and not of the file, so it is the same number on either side of that
# copy.
#
# The two reference chunks are derived and not measured, the same derivation
# `predict-14b.sh` makes for the same two chunks; they are not written into this
# run, because the registration names the run, the slice output, the segment and
# the proof digest each came from, and the manifest's `derived` block says it
# again.  `lib/seq5-reference.py` holds what they are and what makes the
# derivation refuse.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
ZK_PROVER=${ZK_PROVER_DIR:-$ROOT/../zk-prover}     # a local clone to archive the commit from
NAME=register-14b

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=registration         # a prediction, not a measurement: this run proves nothing
# The pinned commit.  zk-prover #153 gave the cost model its constants-first
# reader, #152 priced the prediction at the statement the measurement proves,
# #156 gave the model the terms a composed chunk has, and #157 made the whole
# registration producible from a constants file with no stand-in for a key that
# is missing.  #160 then made the 8B anchor and the eight composed prices read
# the key names this repository records, and #163 gave the registration a shape
# selection whose default is the three shapes E4 registered, in E4's order.
# This is that repository's main, and it carries all six.
COMMIT=ed8de1a0f6e8afc72e4c2e849db7cd0b125123e6
# The statement the registration prices, which is what `predict-14b.sh` proves:
# its `LAYER_FLAGS`, and the two drivers have to name the same set.
STATEMENT="--diagonal-block --gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
# The measured 8B reference chunks the prediction is anchored on, one per
# context: the same two segments, named the same way, that `predict-14b.sh`
# derives.  A change here is a change to what the registration is anchored on.
LAYER=16
SEQ5="--from 2026-09-09-headline-c4096-h100:B8L16:4096
      --from 2026-09-08-headline-c16384-h100:B32L16:16384"

# ---- the refusals that cost nothing, before anything is built ----------------
# 1. the measurement must not have happened yet, and the registration must not
#    have been made already.  A prediction written after the measurement is not
#    a prediction, and a second registration beside the first is two documents
#    where the record needs one: replacing a registration means removing the run
#    that holds it, deliberately.
set -- "$ROOT"/runs/*-predict-14b-* "$ROOT"/runs/*-register-14b-*
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
#    repositories into the prediction.  It is refused here rather than caught
#    afterwards, so the message says what to do about it.
if [ -n "${ZK_COSTMODEL_INPUTS:-}" ]; then
    echo "$NAME: ZK_COSTMODEL_INPUTS is set.  The registration is made from" >&2
    echo "        constants.json alone; unset it and run this again." >&2
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
trap 'rm -rf "$SRC" "$ART" "$OUT"; rm -f "$DERIVED" "$GATE"' EXIT INT TERM
git -C "$ZK_PROVER" archive --format=tar "$COMMIT" | tar -C "$SRC" -xf -
echo "$COMMIT" > "$SRC/.source-commit"
echo "$NAME: zk-prover@$COMMIT -> $SRC"

# ---- the reference chunks, derived from runs this repository holds -----------
# shellcheck disable=SC2086
python3 "$HERE/lib/seq5-reference.py" --runs "$ROOT/runs" --layer "$LAYER" $SEQ5 \
    --out "$ART" --record "$DERIVED"

# ---- the prediction ----------------------------------------------------------
# The harness's own environment, its default (host) torch group: nothing here
# reads a weight or a card.  The command runs from the repository root so that
# what it records as its arguments is a path this repository has, and `--inputs`
# is named nowhere.
( cd "$SRC/harness" && uv sync --frozen )
ARTREL=runs/$(basename "$ART")
ARGS="--constants constants.json --artifacts $ARTREL --json"
# shellcheck disable=SC2086
if ! ( cd "$ROOT" && uv run --project "$SRC/harness" --frozen \
        python -m harness.eval.predict.predict $ARGS ); then
    echo >&2
    echo "$NAME: the harness did not produce a registration from constants.json alone." >&2
    echo "        Every cell cost the model charges is a key this file names, an input" >&2
    echo "        the model prices for itself, or an input it records as unpriced; a key" >&2
    echo "        that is missing is where it stops.  Record the constants the campaign" >&2
    echo "        is measuring first, then register." >&2
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

root, out, args, statement, zk_results_commit, label = sys.argv[1:7]
root, out = pathlib.Path(root), pathlib.Path(out)
# The file `--json` wrote, found through the module rather than guessed: it is
# written beside `predict.py`, and where that is depends on how the harness's
# environment installed the project.
spec = importlib.util.find_spec("harness.eval.predict.predict")
reg = json.loads((pathlib.Path(spec.origin).parent / "out" / "registration.json").read_text())
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

priced = reg["statement"].get("driver_flags", "")
if sorted(priced.split()) != sorted(statement.split()):
    bad.append(f"the registration prices `{priced}` and the run it is registered against "
               f"proves `{statement}`; a registration that prices another statement is "
               "another registration")

for source, names in sorted(by_source.items()):
    print(f"register-14b: {len(names):>2} cell cost(s) from {source}: {', '.join(names)}")
if bad:
    sys.exit("register-14b: " + "; ".join(bad))

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

shapes = {n: {c: p["cells_per_token_layers"] for c, p in e["contexts"].items()}
          for n, e in reg["shapes"].items()}
config = {
    "driver": "register-14b", "label": label,
    "statement": statement,
    "constants": {"file": "constants.json", "sha256": sha,
                  "zk_results_commit": zk_results_commit},
    "cell_costs_by_source": {s: len(n) for s, n in sorted(by_source.items())},
    "cell_costs_not_priced": frozen["not_priced"],
    "reference_chunks": frozen["reference_chunks"],
    "cells_per_token_layers": shapes,
    "prediction_sha256": reg["prediction_sha256"],
    "prediction_block_sha256": reg["prediction_block_sha256"],
    "measured_by": "tools/drivers/predict-14b.sh, which runs after this",
    "compared_by": "harness/eval/predict/compare.py, which reads this registration",
    "witness": "none: no witness, no proof and no cell count exists at the registered "
               "shape, which is what makes this a prediction",
}
with open(out / "config.json", "w") as f:
    json.dump(config, f, indent=1, sort_keys=True)
    f.write("\n")
print(f"register-14b: prediction_sha256 {reg['prediction_sha256']}")
print(f"register-14b: prediction_block_sha256 {reg['prediction_block_sha256']}")
PY
( cd "$ROOT" && uv run --project "$SRC/harness" --frozen python "$GATE" \
    "$ROOT" "$OUT" "$ARGS" "$STATEMENT" "$ZK_RESULTS_COMMIT" "$LABEL" )

# ---- the record --------------------------------------------------------------
python3 "$HERE/lib/manifest.py" --driver "tools/drivers/$NAME.sh" --fetched "$OUT" \
    --runs "$ROOT/runs" --prover-commit "$COMMIT" --harness-commit "$COMMIT" \
    --derived "$DERIVED" --date "$(date -u +%Y-%m-%d)"
(cd "$ROOT" && python3 tools/constants/check.py)

RUN=$(ls -d "$ROOT"/runs/*-"$NAME"-* | tail -1)
echo
echo "$NAME: recorded in runs/$(basename "$RUN")"
echo "next:  measure, with the registration already in this repository:"
echo "         tools/drivers/predict-14b.sh <host> $COMMIT $COMMIT"
echo "       then put the registration where the comparison reads it, and compare:"
echo "         python3 -c 'import json,sys; json.dump(json.load(open(sys.argv[1]))[\"result\"],"
echo "           open(sys.argv[2], \"w\"), indent=1, sort_keys=True)' \\"
echo "           runs/$(basename "$RUN")/registration.json \\"
echo "           <zk-prover@$COMMIT>/harness/eval/predict/out/registration.json"
echo "         uv run python -m harness.eval.predict.compare --runs <the run's outputs> \\"
echo "           --shape qwen2p5_14b --ctx 4096"
