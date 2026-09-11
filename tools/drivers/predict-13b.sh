#!/bin/sh
# predict-13b: the 13B model's layer segments, measured against a prediction.
#
#   tools/drivers/predict-13b.sh <host> <prover-commit> <harness-commit>
#
# CodeLlama-13b-hf, 40 layers, one 512-token block against a 4,096-token
# prefix, on the reference backend: one proof per layer, in its own process.
# The campaign's question is whether the cost model predicts a model shape it
# was never fitted on, so the shape is a different one -- 40 layers instead of
# 32, forty attention heads instead of thirty-two, a wider hidden size, one
# key/value head per attention head instead of one per four -- and the
# arithmetic is the fixed configuration.
#
# **This model stands in for Qwen2.5-14B-Instruct, which cannot be proved.**
# Qwen2.5 puts a bias on the q, k and v projections, the statement has no site
# for a projection bias, and the layer's derived integers are short by it, so an
# honest segment is rejected on the one equality that compares them: zk-prover
# #172 is the rejection and #174 is the component that would be needed to prove
# such a model at all. The extractor refuses a biased matmul by name now, so the
# 14B witnesses cannot even be rebuilt. What E4 needs at this scale is a shape,
# not a checkpoint, so the measurement moves to the nearest bias-free model of
# the same class: same hidden size, same head dimension, same forty heads, same
# inner width, eight layers fewer. Whether this becomes E4's third-scale row
# rather than the 14B is the owner's call (zk-prover PR 173, decision 3); the
# run is made either way, because the shape is the thing being predicted.
#
# Why this checkpoint and not Llama-2-13B, which is the same shape: the sequence
# proved here is 4,608 tokens and Llama-2's trained window is 4,096, while this
# one's is 16,384; and this one's published weights are bf16, which is what the
# harness loads and commits, where Llama-2's are fp16 and would be rounded on
# the way in. Nothing else separates them.
#
# **The registration comes first, and it is counted from these dumps.** A
# prediction written after the measurement is not a prediction, and the counted
# registration `tools/drivers/register-13b.sh` makes is read off the extracted
# witnesses -- before any proof of them exists, which is what makes it a
# prediction and not a fit. So this driver's job has two phases with the
# registration between them:
#
#   1. no registration recorded: the job extracts the forty layers, writes the
#      witness fields file beside the outputs and stops before the first proof.
#      It exits non-zero so that nothing is fetched and no run is recorded; the
#      message it prints is the instruction and not a failure.
#   2. the registration recorded: the job finds every dump in place, skips the
#      extraction and proves.
#
# Between the two, fetch the fields file and register:
#
#   scp <host>:runs/predict-13b/out/witness_fields.json .
#   tools/drivers/register-13b.sh witness_fields.json
#   ssh <host> rm -f '~/runs/predict-13b.status'
#
# and call this driver again with the same arguments.
#
# **The measured 8B reference the registration reads is derived here, from runs
# this repository already holds.** `harness.eval.predict.predict` states its
# shape ratios against one measured 8B layer chunk per context, which it reads
# from `<--artifacts>/seq5/seq_c<C>_L16.json` and takes `result.point` out of; a
# file that is not there is a hard exit, and no run writes that file. Both
# chunks were proved all the same, as segments of the two merged headline runs,
# so this driver reads them out of those runs' slice outputs and writes them
# into its own run directory under `seq5/` -- no card time, no edit to a merged
# run, and the manifest's `derived` block names the run, the slice output and
# the segment each one came from. What the file holds and what makes the
# derivation refuse are in `lib/seq5-reference.py`.
#
# **Layer 0 of this model cannot be dumped, so the measurement is layers 1 to
# 39.** The attention output's quotient term at that layer is 7 + 26 = 33 bits
# against the field's 31 in the widest form there is: `q_bits` is the fold's
# int8 target minus one and the divisor range is the layer's own, which a driver
# may only widen, so nothing moves it. The harness refuses to write the dump and
# the prover would not have said so -- it takes the wider form and proves on --
# which is why that refusal is where it is. The job records it, keeps going, and
# names the layer in the fields file, so the registration counts 39 segments and
# says which one it does not carry. The embedding segment is in neither: it is
# layer 0's.
#
# One process per layer, not one loop over all of them. The comparison reads a
# single-proof document per layer, which is what `compose` writes and what a
# chunk loop does not; and 40 separate processes each return their memory to
# the host when they exit, so the largest of them bounds the run rather than
# their sum.
#
# The head groups are the one flag that has to change for this shape. A key tile
# is a group of attention head instances sharing one column set, every group's
# size must be a power of two, and the groups must cover every head; forty heads
# take 16,16,8 where thirty-two take 16,8,8. Nothing else about the shape is
# named here: the head dimension, the table width and the two remainder widths
# are read off each witness, because 40 independent proofs need not agree on a
# shape the way a chunk loop does.
#
# The weights are fetched as safetensors only. This checkpoint publishes a
# second, complete copy of itself in the older pickle format, and a plain
# snapshot download takes both -- twice the bytes and twice the disk, for a copy
# nothing loads.
#
# The first call checks the two reference segments are there and pushes
# zk-prover at the two commits to the host, starts the job detached and prints
# the poll command. Every later call with the same arguments prints the status;
# once the status says done it fetches the outputs into runs/<run-id>/, derives
# the two reference chunks into `seq5/` beside them, writes manifest.json from
# the prover's provenance block, and runs check.py. Nothing measured is typed in
# here.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
HOST=${1:?host alias}; PROVER=${2:?prover commit}; HARNESS=${3:?harness commit}
ZK_PROVER=${ZK_PROVER_DIR:-$ROOT/../zk-prover}     # a local clone to archive the commits from
NAME=predict-13b
. "$HERE/lib/driver.sh"

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=prediction           # a shape the cost model was not fitted on
MODEL=${ZK_MODEL:-codellama/CodeLlama-13b-hf}
SPEC=b10-final             # the fixed configuration; the delayed-requantization
                           # variant is the 8B rows', and this shape is a test of
                           # the cost model rather than of the quantization
CTX=4096; S=512
NLAY=40
SHARED="--round even --numbits 9 --z-hi-bits 7 --variants intexp --head-groups 16,16,8"
GKR="--gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
# The rounding mode is in the shared flags and must not be repeated here: a
# flag that appears twice on one command line changes the digest
# (zk-prover #30), and the loader does not read the rounding the dump
# recorded (zk-prover #53), so it is named once and only once.
LAYER_FLAGS="--diagonal-block $GKR"   # every binding gadget is on by default; no skip flag anywhere
XTHREADS=20                # torch threads for the extraction, rayon threads for the proofs

# ---- the 8B reference chunks, derived rather than measured -------------------
# One segment per context, named by its `ser_tag` and never by the `layer` field
# beside it: that field is the segment's index in the composed sequence, and in
# the last slice of both runs a head segment shifts the two apart, so `layer`
# 16 there is the model's layer 15.
#
# Both are the layer 16 segment of their run's last token block, which is the
# only block whose prefix is the run's whole context: a decode run grows the
# prefix one 512-token block at a time, so block 8 of `headline-c4096`'s nine
# (tokens 4,096 to 4,607) is the one segment at C=4,096, and block 32 of
# `headline-c16384`'s thirty-three (tokens 16,384 to 16,895) the one at
# C=16,384. Every earlier block is a different C and would be a different
# reference.
drv_seq5() {
    python3 "$HERE/lib/seq5-reference.py" --runs "$ROOT/runs" --layer 16 \
        --from 2026-09-09-headline-c4096-h100:B8L16:4096 \
        --from 2026-09-08-headline-c16384-h100:B32L16:16384 "$@"
}
# the hook lib/driver.sh calls with the fetched directory and the record file
drv_derive() { drv_seq5 --out "$1" --record "$2"; }

drv_finish "$(drv_status)"

# ---- the gate on the reference, before the card is booked --------------------
# The same derivation, checking and writing nothing. A source segment that is
# not there, that did not accept, that fell off a table, that left an edge
# unbound or that was proved under an unsound skip refuses the run here, where
# it costs nothing, rather than after the measurement.
drv_seq5

# ---- which phase this call starts --------------------------------------------
# The registration is counted from the dumps, so the extraction comes before it
# and the proofs after it. Whether it exists is the whole of the difference
# between the two phases, and the job is told which one it is running.
REG=
for d in "$ROOT"/runs/*-register-13b-*; do
    [ -d "$d" ] && REG=$d
done
if [ -z "$REG" ]; then
    PROVE=0
    PREDICTION=none
    echo "$NAME: no registration is recorded yet, so this call extracts and stops"
    echo "       before the first proof. The registration is counted from the dumps"
    echo "       this phase writes, and a prediction made after a proof is not one."
else
    PROVE=1
    PREDICTION=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"]["prediction_sha256"])' "$REG/registration.json")
    echo "$NAME: measured against the prediction $PREDICTION"
    echo "       registered in runs/$(basename "$REG")"
fi

# ---- start: push the pinned sources, then the job ----------------------------
drv_check_commits
BUILD=$(drv_build_root)
drv_push "$BUILD/src" "$PROVER"
drv_push "$BUILD/harness-src" "$HARNESS"

JOB=$(mktemp)
cat > "$JOB" <<JOBEOF
#!/bin/sh
# generated by $NAME.sh; runs on the host under tools/remote/run.sh
set -eu
B=\$HOME/$BUILD
R=\$HOME/runs/$NAME
SRC=\$B/src; HSRC=\$B/harness-src/harness
OUT=\$R/out
WIT=\$HOME/witness/$(printf '%.12s' "$HARNESS")/$SPEC-13b-c$CTX
mkdir -p \$OUT \$WIT
$(drv_job_preamble)
export RAYON_NUM_THREADS=\${RAYON_NUM_THREADS:-$XTHREADS}
# A calibration file is named for neither the model nor the context, so this
# model gets an output directory of its own; sharing one would silently reuse
# another model's attention ranges, which have the wrong number of heads.
export ZK_MODEL=$MODEL ZK_DEVICE=cuda ZK_THREADS=$XTHREADS ZK_OUT=\$R/work
mkdir -p \$R/work
PY="uv run --project \$HSRC \$UVG python"

st "gpu: \$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader)"
st "cores: \$(nproc), threads $XTHREADS"

# 1. the reference backend of the pinned prover commit
st "build"
( cd \$SRC && CARGO_TARGET_DIR=\$B/t-simd cargo build --release --locked )
SIMD=\$B/t-simd/release/zk-prover

# 2. the harness at its pinned commit
( cd \$HSRC && uv sync --frozen \$UVG )

# 3. the weights, measured rather than assumed.  Safetensors only: the older
#    pickle copy of this checkpoint is a second complete set of the same
#    tensors, and nothing here loads it.
WEIGHTS=\$( cd \$HSRC && \$PY - <<'PY'
import json, os, time
t0 = time.time()
from huggingface_hub import snapshot_download
p = snapshot_download(os.environ["ZK_MODEL"],
                      ignore_patterns=["*.bin", "*.pth", "*.h5", "*.msgpack"])
n = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(p) for f in fs)
print(json.dumps({"bytes": n, "seconds": round(time.time() - t0, 1)}))
PY
)
st "weights: \$WEIGHTS"

# 4. the witnesses: the last block of a $((CTX + S))-token sequence, all $NLAY layers.
#    Layer 0 is its own pass because the embedding table is written into every
#    dump of the pass it is given, and the prover turns the gadget on for any
#    dump that carries one.  Its pass writes to the same base as the others: a
#    one-layer pass whose out path already ends in L0 gets the layer tagged in twice
#    (zk-prover #55), which is a directory nothing downstream reads.
if [ ! -f \$WIT/witness_L$((NLAY - 1))/manifest.json ]; then
  st "extract: layers 1 to $((NLAY - 1)), C=$CTX, $SPEC"
  T0=\$(date +%s)
  ( cd \$HSRC && \$PY -m harness.witness.extract --tokens $((CTX + S)) --chunk $S \
      --layers \$(seq -s, 1 $((NLAY - 1))) --spec $SPEC \
      --residual-stream --diagonal-block --slim --slim-num --out \$WIT/witness )
  st "extract: layers 1 to $((NLAY - 1)) done in \$(( \$(date +%s) - T0 ))s"
fi
#    Layer 0 is also the one layer of this model the harness refuses to write,
#    so its refusal is recorded and the run goes on with the other 39. The
#    record is the marker a restart reads, so the refusal costs its forward
#    pass once and not once per call.
if [ ! -f \$WIT/witness_L0/manifest.json ] && [ ! -f \$OUT/layer0-refused.txt ]; then
  st "extract: layer 0 with the embedding table"
  T0=\$(date +%s)
  if ( cd \$HSRC && \$PY -m harness.witness.extract --tokens $((CTX + S)) --chunk $S \
      --layers 0 --spec $SPEC \
      --residual-stream --diagonal-block --slim --slim-num --embed --out \$WIT/witness \
      > \$R/L0.extract.log 2>&1 ); then
    st "extract: layer 0 done in \$(( \$(date +%s) - T0 ))s"
  else
    grep -E "AssertionError|Error|error:" \$R/L0.extract.log > \$OUT/layer0-refused.txt ||
      tail -n 4 \$R/L0.extract.log > \$OUT/layer0-refused.txt
    st "extract: layer 0 refused, see out/layer0-refused.txt"
  fi
fi

# 4b. which layers there are a dump for. Every layer but one is the expected
#     case and the one is layer 0; anything else stops the run here, because a
#     gap the driver did not expect is a failed extraction and not a refusal.
LAYERS=
ABSENT=
k=0
while [ \$k -lt $NLAY ]; do
  if [ -f \$WIT/witness_L\$k/manifest.json ]; then LAYERS="\$LAYERS \$k"
  else ABSENT="\${ABSENT:+\$ABSENT,}\$k"; fi
  k=\$((k + 1))
done
NPROVE=\$(echo \$LAYERS | wc -w)
st "dumps: \$NPROVE of $NLAY layers; absent \${ABSENT:-none}"
if [ "\${ABSENT:-}" != "" ] && [ "\${ABSENT:-}" != "0" ]; then
  st "stop: the absent layers are \$ABSENT and this driver expects at most layer 0"
  exit 5
fi

cat > \$OUT/config.json <<CFG
{"driver": "$NAME", "label": "$LABEL",
 "model": "$MODEL", "spec": "$SPEC",
 "context": $CTX, "s": $S, "layers": $NLAY, "segments": \$NPROVE,
 "layers_absent": "\${ABSENT:-none}",
 "shared_flags": "$SHARED", "layer_flags": "$LAYER_FLAGS",
 "backend": "simd", "threads": $XTHREADS, "weights": \$WEIGHTS,
 "registered_prediction_sha256": "$PREDICTION",
 "replaces": "Qwen2.5-14B-Instruct, whose layers cannot be proved: zk-prover #172, #174",
 "comparison": "not made here: harness/eval/predict/compare.py reads the registration"}
CFG

du -sh \$WIT | awk '{print "witness size: " \$1 "  " \$2}'
python3 - \$WIT \$OUT/extract.json <<'PY'
import json, os, sys
wit, out = sys.argv[1], sys.argv[2]
n = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(wit) for f in fs)
json.dump({"witness_bytes": n}, open(out, "w"), indent=1)
print("witness:", n, "bytes")
PY

# 5. the witness fields, read off the dumps and never assumed.  The registration
#    counts every segment at the calibration its own dump asks for -- the master
#    table, the accumulator widths, the fold's pins -- and at a new model the
#    8B's modal values are wrong by a whole table.  Written before any proof
#    exists, which is what the counted registration's standing rests on, and the
#    table is the size the dump asks for because this run passes no tight-table
#    flag.
st "fields"
( cd \$HSRC && \$PY -m harness.eval.predict.witness_fields --dir \$WIT/witness \
    --layers $NLAY --numbits 9 --no-tight-table --head-groups 16,16,8 \
    \${ABSENT:+--absent \$ABSENT} --out \$OUT/witness_fields.json )

if [ $PROVE -eq 0 ]; then
  st "stop: extracted, not proved"
  echo
  echo "$NAME: \$NPROVE dumps of $NLAY layers are written and \$OUT/witness_fields.json"
  echo "       with them; absent \${ABSENT:-none}."
  echo "       Nothing is proved yet, on purpose: the registration is counted from"
  echo "       these dumps and has to be recorded before the first proof."
  echo "         scp $HOST:runs/$NAME/out/witness_fields.json ."
  echo "         tools/drivers/register-13b.sh witness_fields.json"
  echo "         ssh $HOST rm -f '~/runs/$NAME.status'"
  echo "       then call the driver again with the same arguments."
  exit 3
fi

# 6. one proof per layer, one process each.  A layer whose proof is already
#    written is not proved again, so a job that was interrupted is restarted for
#    the price of what it did not finish.
for k in \$LAYERS; do
  f=\$OUT/L\$k.json
  if [ -s \$f ]; then st "L\$k already proved"; continue; fi
  st "prove: layer \$k, \$NPROVE segments in this run"
  T0=\$(date +%s)
  if \$SIMD compose $SHARED $LAYER_FLAGS --witness \$WIT/witness_L\$k > \$f 2> \$R/L\$k.err; then
    st "L\$k proved in \$(( \$(date +%s) - T0 ))s, peak \$(python3 -c 'import json,sys; print(round(json.load(open(sys.argv[1]))["result"]["point"]["peak_rss_bytes"]/2**30,1))' \$f) GiB"
  else
    rm -f \$f; st "L\$k did not prove, see \$R/L\$k.err"; exit 4
  fi
done

# 7. the gate, and the measured side of the comparison
python3 - \$OUT $S \$LAYERS <<'PY'
import json, pathlib, sys
out, s = pathlib.Path(sys.argv[1]), int(sys.argv[2])
layers = [int(x) for x in sys.argv[3:]]
bad, rows = [], []
for k in layers:
    f = out / f"L{k}.json"
    if not f.exists():
        bad.append(f"layer {k} has no proof"); continue
    doc = json.loads(f.read_text())
    p, prov = doc["result"]["point"], doc["provenance"]
    rows.append({"layer": k, "fresh": p["cells"]["fresh"],
                 "key_tiles": p["family_cells"]["key_tiles"],
                 "prove_secs": p["prove_secs"], "trace_secs": p["trace_secs"],
                 "interaction_secs": p["interaction_secs"],
                 "commit_secs": p["phases"]["commit_secs"],
                 "stwo_total": p["phases"]["commit_secs"] + p["phases"]["prove_call_secs"],
                 "peak_rss_bytes": p["peak_rss_bytes"],
                 "log_table": p["params"]["log_table"],
                 "kmax": p["params"]["kmax"],
                 "ao_rem_bits": p["params"]["ao_rem_bits"],
                 "proof_sha256": p["proof_sha256"], "accepts": p["accepts"]})
    if not p["accepts"]:
        bad.append(f"layer {k}: the proof was rejected")
    for field in ("off_table", "ref_mismatch"):
        if p.get(field):
            bad.append(f"layer {k}: {field} is {p[field]}")
    if prov["unsound_skips"]:
        bad.append(f"layer {k}: unsound skips in effect")
    if not prov["binding"]["all_bound"]:
        bad.append(f"layer {k}: unbound edges {prov['binding']['unbound']}")
fresh = sum(r["fresh"] for r in rows)
summary = {"layers": len(rows), "positions": s,
           "fresh_sum": fresh,
           "cells_per_token_layers": fresh / s,
           "key_tiles_sum": sum(r["key_tiles"] for r in rows),
           "fresh_mean": fresh / len(rows) if rows else 0,
           "fresh_min": min((r["fresh"] for r in rows), default=0),
           "fresh_max": max((r["fresh"] for r in rows), default=0),
           "prove_secs_sum": sum(r["prove_secs"] for r in rows),
           "stwo_total_sum": sum(r["stwo_total"] for r in rows),
           "commit_secs_sum": sum(r["commit_secs"] for r in rows),
           "peak_rss_bytes_max": max((r["peak_rss_bytes"] for r in rows), default=0),
           "log_table_values": sorted({r["log_table"] for r in rows}),
           "kmax_values": sorted({r["kmax"] for r in rows}),
           "ao_rem_bits_values": sorted({r["ao_rem_bits"] for r in rows})}
json.dump({"layers": rows, "summary": summary}, open(out / "measured.json", "w"), indent=1)
print(f"{summary['layers']} layers, {fresh:,.0f} fresh cells, "
      f"{summary['cells_per_token_layers']:,.0f} per token over all layers")
print(f"key tiles {summary['key_tiles_sum']:,.0f} cells; "
      f"proving {summary['prove_secs_sum']:.0f} s; "
      f"largest process {summary['peak_rss_bytes_max'] / 2 ** 30:.1f} GiB")
print(f"table widths {summary['log_table_values']}, kmax {summary['kmax_values']}, "
      f"remainder bits {summary['ao_rem_bits_values']}")
if bad:
    sys.exit("; ".join(bad))
print("every layer proved and accepted; no skip; every edge bound")
PY
st "done"
JOBEOF
drv_start "$JOB"
rm -f "$JOB"
