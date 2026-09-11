#!/bin/sh
# predict-14b: the 14B model's layer segments, measured against a prediction.
#
#   tools/drivers/predict-14b.sh <host> <prover-commit> <harness-commit>
#
# Qwen2.5-14B-Instruct, 48 layers, one 512-token block against a 4,096-token
# prefix, on the reference backend: one proof per layer, in its own process.
# The campaign's question is whether the cost model predicts a model shape it
# was never fitted on, so the shape is a different one -- 48 layers instead of
# 32, forty attention heads instead of thirty-two, a wider inner dimension --
# and the arithmetic is the fixed configuration.
#
# **This driver runs second.** The registration is produced first: zk-prover
# #153 gave the cost model a constants-first reader, #157 made every input the
# prediction reads come off this repository's `constants.json` and its own
# recorded runs, and #160 gave the anchor and the composed prices the key names
# this repository records, so `tools/drivers/register-14b.sh` writes it here,
# with no card and without the private archive. A prediction registered after
# the measurement would not be a prediction, so the order is register, then
# measure, then compare: the registration run is recorded before this driver
# books a card, the card time is the measurement, and the comparison is made
# from the fetched outputs by the harness's `harness/eval/predict/compare.py`,
# which reads the registration out of the run that recorded it. That comparison
# costs no host time -- every field it reads is in the per-layer outputs -- so
# it is made here, before the outputs become a run, and the run carries it.
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
# One process per layer, not one loop over all of them. The comparison reads a
# single-proof document per layer, which is what `compose` writes and what a
# chunk loop does not; and 48 separate processes each return their memory to
# the host when they exit, so the largest of them bounds the run rather than
# their sum.
#
# The head groups are the one flag that has to change for this shape. A key tile
# is a group of attention head instances sharing one column set, every group's
# size must be a power of two, and the groups must cover every head; forty heads
# take 16,16,8 where thirty-two take 16,8,8. Nothing else about the shape is
# named here: the head dimension, the table width and the two remainder widths
# are read off each witness, because 48 independent proofs need not agree on a
# shape the way a chunk loop does.
#
# `--tight-table` is in the shared pins for the same reason it is in every other
# campaign at this context: it sizes the master exponent table by the largest
# key the key tiles look up rather than by the dump manifest's `d_bits +
# spread`, and the chunks this measurement is compared against were proved that
# way. The prediction charges five cells a table row over a master table of
# 2^23 rows, which is the modal width of the recorded 8B chunks (22 to 25 over
# their 32 layers); a run that left the table at the manifest's width would
# commit cells the prediction does not charge and the residual would be that
# difference and not the shape. The width is still read off each witness, one
# per layer, and each layer's proof reports it in `params.log_table`.
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
NAME=predict-14b
. "$HERE/lib/driver.sh"

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=prediction           # a shape the cost model was not fitted on
MODEL=${ZK_MODEL:-Qwen/Qwen2.5-14B-Instruct}
SPEC=b10-final             # the fixed configuration; the delayed-requantization
                           # variant is the 8B rows', and this shape is a test of
                           # the cost model rather than of the quantization
CTX=4096; S=512
NLAY=48
SHARED="--round even --numbits 9 --z-hi-bits 7 --variants intexp --head-groups 16,16,8 --tight-table"
GKR="--gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
# The rounding mode is in the shared flags and must not be repeated here: a
# flag that appears twice on one command line changes the digest
# (zk-prover #30), and the loader does not read the rounding the dump
# recorded (zk-prover #53), so it is named once and only once.
LAYER_FLAGS="--diagonal-block $GKR"   # every binding gadget is on by default; no skip flag anywhere
XTHREADS=20                # torch threads for the extraction, rayon threads for the proofs
# The registration this measurement is compared against, recorded by
# `register-14b.sh` before this driver books a card.  The run's config.json
# names it, so the record says which document the comparison read.
REGISTRATION=runs/2026-09-11-register-14b-none
SHAPE=qwen2p5_14b          # the registered shape, as the comparison names it
# The harness commit the comparison is made at.  It reads the outputs this run
# fetched and no witness, no card and no weight, so it need not be the commit
# that proved them; it is named here, and in the run's `derived` block, so the
# record says which reading made the comparison.
#
# It is NOT the commit that proves, and it is UNMERGED on purpose: zk-prover
# #175 (`predict-exact`) is what reads a counted registration -- it compares
# every layer's count against that layer's proved chunk and the fields the
# registration counted at against the fields the run proved at -- and it carries
# the one-line fix for the statement key the prover renamed (zk-prover #171),
# without which the comparison stops on the first chunk it opens.
COMPARE_COMMIT=b77703c2e6215a90ea05d6a32b75a17b4713b8ad
CARD="none: the proofs are the reference backend's, on the host's cores"
BACKEND="ref (SimdBackend)"

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

# ---- the comparison, made on the outputs before they become a run -----------
# `harness/eval/predict/compare.py` reads the per-layer outputs and the
# registration and writes the two documents the run book asks for: the per-chunk
# record and the comparison. It runs here, on the fetched outputs and before the
# manifest is written, so both are outputs of this run like the proofs are, and
# the manifest says in `derived` which registration they were read against.
#
# The harness reads the registration from a path inside its own checkout, so the
# archive gets a copy and the run that recorded it keeps the original: a
# registration's identity is `prediction_sha256`, a digest of the content and
# not of the file, so it is the same document on either side of that copy.
drv_compare() {
    out=$1; record=$2
    reg=$ROOT/$REGISTRATION/registration.json
    src=$(mktemp -d "${TMPDIR:-/tmp}/$NAME-compare.XXXXXX")
    trap 'rm -rf "$src"' EXIT INT TERM
    git -C "$ZK_PROVER" cat-file -e "$COMPARE_COMMIT^{commit}" ||
      { echo "unknown comparison commit $COMPARE_COMMIT" >&2; exit 2; }
    git -C "$ZK_PROVER" archive --format=tar "$COMPARE_COMMIT" | tar -C "$src" -xf -
    echo "$COMPARE_COMMIT" > "$src/.source-commit"
    mkdir -p "$src/harness/eval/predict/out"
    python3 - "$reg" "$src/harness/eval/predict/out/registration.json" <<'REGPY'
import json, sys
json.dump(json.load(open(sys.argv[1]))["result"], open(sys.argv[2], "w"),
          indent=1, sort_keys=True)
REGPY
    ( cd "$src/harness" && uv sync --frozen )
    # The comparison's findings are what this run is for, and it exits non-zero
    # on one while writing both of its documents all the same, so its exit code
    # is not what is read here: what is read is whether the documents are there.
    # And a comparison that cannot be made does not cost the measurement its
    # record: every field it reads is in the outputs beside it, so it can be
    # made again from the recorded run, and the derived block says it was not
    # made and what stopped it.
    ( cd "$ROOT" && uv run --project "$src/harness" --frozen \
        python -m harness.eval.predict.compare --runs "$out" --shape "$SHAPE" \
        --ctx $CTX --card "$CARD" --backend "$BACKEND" --out "$out" ) 2>&1 | tee "$src/out.txt"
    cmp=$out/comparison_${SHAPE}_c$CTX.json
    python3 - "$record" "$reg" "$REGISTRATION" "$SHAPE" "$CTX" "$cmp" "$src/out.txt" \
             "$COMPARE_COMMIT" <<'CMPPY'
import json, os, sys
record, registration, run, shape, ctx, comparison, log, commit = sys.argv[1:9]
rec = json.load(open(record))
r = json.load(open(registration))["result"]
d = {"what": "the measured layer proofs against the registered prediction, made by "
             "harness/eval/predict/compare.py at the pinned harness commit",
     "registration_run": run,
     "compared_at": commit,
     "prediction_sha256": r["prediction_sha256"],
     "prediction_block_sha256": r["prediction_block_sha256"]}
if os.path.exists(comparison):
    c = json.load(open(comparison))
    d.update(made=True,
             files=[f"measured_{shape}_c{ctx}.json", f"comparison_{shape}_c{ctx}.json"],
             rho=c["b_rho"]["rho"], tier=c["c_tier"]["tier"],
             protocol=c["b_rho"]["protocol"],
             key_tiles_exact_on_every_chunk=c["a_key_tiles_exact"]["exact_on_every_chunk"],
             boundary_exact_on_every_chunk=c["a2_boundary_exact"]["exact_on_every_chunk"],
             void=c["void"])
else:
    lines = [l for l in open(log).read().splitlines() if l.strip()]
    d.update(made=False, files=[],
             why=" ".join(lines[-3:]) or "the comparison printed nothing")
rec["comparison"] = d
json.dump(rec, open(record, "w"), indent=1, sort_keys=True)
CMPPY
    [ -f "$cmp" ] || echo "$NAME: the comparison was not made; the run is recorded without \
it and the manifest's derived block says what stopped it" >&2
}

# the hook lib/driver.sh calls with the fetched directory and the record file
drv_derive() { drv_seq5 --out "$1" --record "$2"; drv_compare "$1" "$2"; }

drv_finish "$(drv_status)"

# ---- the gate on the reference, before the card is booked --------------------
# The same derivation, checking and writing nothing. A source segment that is
# not there, that did not accept, that fell off a table, that left an edge
# unbound or that was proved under an unsound skip refuses the run here, where
# it costs nothing, rather than after the measurement.
drv_seq5
# And the registration, for the same price: a prediction written after the
# measurement is not a prediction, so a measurement whose registration is not
# recorded here yet is refused before it books a card.
[ -f "$ROOT/$REGISTRATION/registration.json" ] || {
    echo "$NAME: no registration at $REGISTRATION." >&2
    echo "        The prediction is registered first, by tools/drivers/register-14b.sh," >&2
    echo "        and its run is recorded in this repository before this one measures." >&2
    exit 2
}

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
WIT=\$HOME/witness/$(printf '%.12s' "$HARNESS")/$SPEC-14b-c$CTX
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

# 3. the weights, measured rather than assumed
WEIGHTS=\$( cd \$HSRC && \$PY - <<'PY'
import json, os, time
t0 = time.time()
from huggingface_hub import snapshot_download
p = snapshot_download(os.environ["ZK_MODEL"])
n = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(p) for f in fs)
print(json.dumps({"bytes": n, "seconds": round(time.time() - t0, 1)}))
PY
)
st "weights: \$WEIGHTS"

cat > \$OUT/config.json <<CFG
{"driver": "$NAME", "label": "$LABEL",
 "model": "$MODEL", "spec": "$SPEC",
 "context": $CTX, "s": $S, "layers": $NLAY, "segments": $NLAY,
 "shared_flags": "$SHARED", "layer_flags": "$LAYER_FLAGS",
 "backend": "simd", "threads": $XTHREADS, "weights": \$WEIGHTS,
 "comparison": "made after the fetch, by the harness's compare.py against the registration in $REGISTRATION"}
CFG

# 4. the witnesses: the last block of a $((CTX + S))-token sequence, all $NLAY layers.
#    Layer 0 is its own pass because the embedding table is written into every
#    dump of the pass it is given, and the prover turns the gadget on for any
#    dump that carries one.  Its pass writes to the same base as the others:
#    a one-layer pass used to write a directory without the layer in its name
#    (zk-prover #55), and at the pinned commit every dump of a layers pass is
#    named the same way, one layer or forty-seven.
if [ ! -f \$WIT/witness_L$((NLAY - 1))/manifest.json ]; then
  st "extract: layers 1 to $((NLAY - 1)), C=$CTX, $SPEC"
  T0=\$(date +%s)
  ( cd \$HSRC && \$PY -m harness.witness.extract --tokens $((CTX + S)) --chunk $S \
      --layers \$(seq -s, 1 $((NLAY - 1))) --spec $SPEC \
      --residual-stream --diagonal-block --slim --slim-num --out \$WIT/witness )
  st "extract: layers 1 to $((NLAY - 1)) done in \$(( \$(date +%s) - T0 ))s"
fi
if [ ! -f \$WIT/witness_L0/manifest.json ]; then
  st "extract: layer 0 with the embedding table"
  T0=\$(date +%s)
  ( cd \$HSRC && \$PY -m harness.witness.extract --tokens $((CTX + S)) --chunk $S \
      --layers 0 --spec $SPEC \
      --residual-stream --diagonal-block --slim --slim-num --embed --out \$WIT/witness )
  st "extract: layer 0 done in \$(( \$(date +%s) - T0 ))s"
fi
du -sh \$WIT | awk '{print "witness size: " \$1 "  " \$2}'
python3 - \$WIT \$OUT/extract.json <<'PY'
import json, os, sys
wit, out = sys.argv[1], sys.argv[2]
n = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(wit) for f in fs)
json.dump({"witness_bytes": n}, open(out, "w"), indent=1)
print("witness:", n, "bytes")
PY

# 5. one proof per layer, one process each.  A layer whose proof is already
#    written is not proved again, so a job that was interrupted is restarted for
#    the price of what it did not finish.
k=0
while [ \$k -lt $NLAY ]; do
  f=\$OUT/L\$k.json
  if [ -s \$f ]; then st "L\$k already proved"; k=\$((k + 1)); continue; fi
  st "prove: layer \$k of $NLAY"
  T0=\$(date +%s)
  if \$SIMD compose $SHARED $LAYER_FLAGS --witness \$WIT/witness_L\$k > \$f 2> \$R/L\$k.err; then
    st "L\$k proved in \$(( \$(date +%s) - T0 ))s"
  else
    rm -f \$f; st "L\$k did not prove, see \$R/L\$k.err"; exit 4
  fi
  k=\$((k + 1))
done

# 6. the gate, and the measured side of the comparison
python3 - \$OUT $NLAY $S <<'PY'
import json, pathlib, sys
out, nlay, s = pathlib.Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
bad, rows = [], []
for k in range(nlay):
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
