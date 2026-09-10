#!/bin/sh
# predict-70b: one synthetic layer segment at the 70B width, per context,
# measured at a card and a block length this driver is told.
#
#   tools/drivers/predict-70b.sh <host> <prover-commit> <harness-commit> <card> <block>
#
# What this measures is the shape and not the model. A synthetic layer segment
# whose hidden size is 8,192, whose attention is 64 heads of 128 with 8
# key/value heads and whose FFN is 28,672: Llama-3.1-70B's own configuration,
# and the row zk-prover's cost model carries for it. No 70B weight is read here,
# none is downloaded and none exists on any host. What the cost model is being
# tested on is the arithmetic of a layer at that width, which is the half of the
# frontier that today rests on an extrapolation with nothing measured beside it.
#
# **The card and the block length have no default, and that is the point.** They
# are the two halves of the memory question the campaign has to answer before a
# host is booked, and a run made at the wrong one of either is a different
# measurement with the same name. So both are arguments, the card is checked
# against what the machine reports before anything is built, and a second call
# with arguments the running job was not started with is refused rather than
# fetched.
#
# The memory question, in the numbers the record already holds: the 8B layer
# segment at a 512-token block peaked 73,723 MiB at C=4,096 and 78,799 MiB at
# C=16,384 of the 81,559 MiB an 80 GB card reports, and with the five reductions
# off the same C=4,096 plan peaked 80,497 MiB and then ran out of memory in a
# Merkle commit. The 70B layer is twice as wide on every axis that drives the
# trace, and the registered prediction puts one 70B segment at 2.016 times the
# measured 8B segment's cells at C=4,096 and 2.010 times at C=16,384. So a
# 512-token block at this width does not fit an 80 GB card, and the run needs a
# bigger card, or a shorter block, or both -- which is exactly what the two
# arguments are. A rate measured on one card is not a rate on the other, and a
# block that is not 512 is a different quantity: every row this run backs names
# both, and the run id names the card the machine reported.
#
# The order is register, then measure, then compare. `tools/drivers/register-70b.sh`
# records the prediction; this driver refuses to run until that registration is
# in `runs/`, and writes the prediction's digest into its own `config.json`, so
# the measurement names the prediction it is measured against and a prediction
# written afterwards cannot be passed off as one.
#
# The backend is CUDA, and this is the one driver here where that is a
# measurement decision rather than a speed one: the number the memory question
# turns on is what the CARD holds, which only a run on the card reports. The
# device kernels are emitted for this shape and installed the way
# `synthetic-digests.sh` does it, because a CUDA backend without them evaluates
# constraints on the host and times something else. A cell count is the same on
# both backends, which is what lets that decision be free of the cell rows.
#
# One process per context, not a loop: each returns its memory to the host when
# it exits, so the larger of the two bounds the run rather than their sum, and
# the card sampler is started and stopped around each one on its own.
#
# The master exponent table's width is not guessed and is not derived here
# either: a width that is too small leaves keys off the table and the proof does
# not stand, so `TABLE_BITS` is the widths to try in order, the first that proves
# is the point, and every width that did not keeps its stderr under `out/`. The
# normalisation window `kmax` is one number and not a list of them: it is the
# prover's own blind bound for the widest matmul of this shape, so no seed can
# land outside it.
#
# The first call checks the registration, pushes zk-prover at the two commits to
# the host, starts the job detached and prints the poll command. Every later
# call with the same arguments prints the status; once the status says done it
# fetches the outputs into runs/<run-id>/, writes manifest.json from the
# prover's provenance block, and runs check.py. Nothing measured is typed in
# here.
#
# What the run backs, and what the audit re-derives from `measured.json`:
# cells.predict70b.c<ctx>.fresh and .key_tiles, secs.predict70b.c<ctx>.<scope>
# for commit, stwo_total, whole_wall and loop, the rate rows derived from those
# two, and mem.predict70b.c<ctx>.peak_mib, the card figure. This driver records
# no constant: it makes the run, and the constants are added against it.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
HOST=${1:?host alias}
PROVER=${2:?prover commit}
HARNESS=${3:?harness commit}
CARD=${4:?the card this run must be made on, as the machine reports it (H100, H200); it is checked against nvidia-smi before anything is built, and it names every row}
S=${5:?the block length, in decoded positions; 512 is the recorded configuration and anything else is a different quantity and says so in every row}
ZK_PROVER=${ZK_PROVER_DIR:-$ROOT/../zk-prover}     # a local clone to archive the commits from
NAME=predict-70b
. "$HERE/lib/driver.sh"

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=prediction           # a shape the cost model was never fitted on
SPEC=b10-final             # the fixed configuration: round even, all seven
                           # matmuls on the chain dequant rung, which is what
                           # the registration prices and what --layout b10 is
CONTEXTS="4096 16384"
# The shape, from Llama-3.1-70B's config.json. `d` is the hidden size, `dff` the
# FFN inner width, and the key/value width is the 8 key/value heads times the
# head dimension, which is what GQA commits per key.
D=8192; NH=64; NKV=8; HD=128; DFF=28672
KVW=$((NKV * HD))          # the k and v output width, which GQA makes narrower
# 64 heads as four key tile groups of 16. A group's size must be a power of two
# and the groups must cover every head, so 64 could be one group; 16 is the
# group size both headline runs and the 14B driver use, and it keeps the largest
# key tile the same size as the ones every recorded number was taken on.
HEAD_GROUPS=16,16,16,16
# The seven matmul widths, by name. Unnamed matmuls would take --nin and --nout,
# and all seven are named here: q and o are square in the hidden size, k and v
# are the GQA pair, gate and up widen to the FFN and down comes back.
DIMS="q:${D}x${D},k:${D}x${KVW},v:${D}x${KVW},o:${D}x${D},gate:${D}x${DFF},up:${D}x${DFF},down:${DFF}x${D}"
# The normalisation window. The prover sizes it from the largest accumulator a
# matmul can hold, and its own blind bound is 127*127*n_in for the widest, which
# is `down` at 28,672 inputs: 462,422,016, which is 29 bits, and the window is
# the bits above the 9 the mantissa carries. So 20, and no seed can produce an
# accumulator outside it.
KMAX=20
RSA=32                     # --residual-stream-a: the reduction tree's arity,
                           # 32 as in every other synthetic segment here; it
                           # divides both 8,192 and 28,672
# The master exponent table's width, as the widths to try in order. Two, and
# not a long list: a width that is too small is not caught until the proof is
# made, so every width tried costs a proof at this width. 24 is what the same synthetic
# generator needed at the 8B attention width at every point the prefill sweep
# measured -- a 64, a 128 and a 256-token block, at C = S and at C = 4,096 --
# and 25 is one step of headroom. A shape that needs more says so in the refusal
# this run keeps, and widening this list and running it again is then a
# deliberate act rather than an hour of card time spent climbing.
TABLE_BITS="24 25"
# The device kernel families to emit. The same list every CUDA driver here
# emits: a family that is not in the store is evaluated on the host, and the
# run's gate refuses a proof that fell back.
KERNEL_FAMILIES=zk_chan_eval,zk_key_eval,zk_row_eval,zk_attn_out_eval,zk_dequant_eval,zk_freivalds_eval,zk_exp_table_eval,zk_table_eval,zk_residual_stream_eval,zk_residual_stream_table_eval
VARIANT=intexp             # the arithmetic the paper reports
SHARED_ARITH="--round even --numbits 9 --z-hi-bits 7 --layout b10"
GKR="--gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
# --diagonal-block and --synth-residual-stream are what the sound defaults ask of
# a synthetic segment: without the first the keys and values cannot be bound to
# the next block and without the second the residual stream cannot be bound to
# the next layer, and either one missing would mean a skip flag. The attention
# output's remainder is not pinned: the flag may only widen what the witness
# needs, and each point records the width its own witness asked for.
SHAPE="--hd $HD --head-groups $HEAD_GROUPS --nin $D --nout $D --residual-stream-a $RSA --kmax $KMAX --synth-residual-stream --diagonal-block"
SAMPLE_MS=200              # the card sampler's period where nvidia-smi loops
XTHREADS=20                # rayon threads for witness generation

# ---- the arguments, before anything is done with them ------------------------
# The prefix is tiled in blocks of S, so a context that is not a multiple of the
# block is not a statement this prover makes; and the layouts that are built are
# the power-of-two block lengths.
case $S in
  16|32|64|128|256|512) ;;
  *) echo "$NAME: a block of $S is not one of the block lengths this prover builds" >&2
     echo "        layouts for (16, 32, 64, 128, 256, 512), and every context here" >&2
     echo "        has to be a multiple of it. 512 is the recorded configuration." >&2
     exit 2 ;;
esac
for C in $CONTEXTS; do
    [ $((C % S)) -eq 0 ] || { echo "$NAME: C=$C is not a multiple of the block $S" >&2; exit 2; }
done

# ---- the prediction comes first ---------------------------------------------
# A prediction written after the measurement is not a prediction. The
# registration is a desk run and costs no card time, so it is required here
# rather than recommended, and its digest goes into this run'"'"'s own config.
REG=
for d in "$ROOT"/runs/*-register-70b-*; do
    [ -d "$d" ] && REG=$d
done
if [ -z "$REG" ]; then
    echo "$NAME: no registration for this shape is recorded in runs/." >&2
    echo "        A prediction written after the measurement is not a prediction, so" >&2
    echo "        the order is register, measure, compare:" >&2
    echo "          tools/drivers/register-70b.sh" >&2
    echo "        It takes no host and no card." >&2
    exit 2
fi
PREDICTION=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"]["prediction_sha256"])' "$REG/registration.json")
echo "$NAME: measured against the prediction $PREDICTION"
echo "       registered in runs/$(basename "$REG")"

# ---- the arguments the running job was started with --------------------------
# One status file per driver, and the card and the block are arguments: a second
# call that named a different card or a different block would fetch a run that
# measured something else and record it under these rows. What the job was
# started with is on the host beside it, and the two have to agree.
WANT="card=$CARD block=$S contexts=$CONTEXTS spec=$SPEC"
HAVE=$(ssh -o BatchMode=yes "$HOST" "cat ~/runs/$NAME/params.txt 2>/dev/null || true")
if [ -n "$HAVE" ] && [ "$HAVE" != "$WANT" ]; then
    echo "$NAME: the job on this host was started as" >&2
    echo "          $HAVE" >&2
    echo "        and this call names" >&2
    echo "          $WANT" >&2
    echo "        A run at another card or another block length is another measurement." >&2
    echo "        Fetch that one with the arguments it was started with, or remove" >&2
    echo "        ~/runs/$NAME on the host and start this one." >&2
    exit 2
fi

drv_finish "$(drv_status)"

# ---- start: push the pinned sources, then the job ----------------------------
drv_check_commits
BUILD=$(drv_build_root)
drv_push "$BUILD/src" "$PROVER"
drv_push "$BUILD/harness-src" "$HARNESS"
printf '%s\n' "$WANT" | ssh -o BatchMode=yes "$HOST" "mkdir -p ~/runs/$NAME && cat > ~/runs/$NAME/params.txt"

JOB=$(mktemp)
cat > "$JOB" <<JOBEOF
#!/bin/sh
# generated by $NAME.sh; runs on the host under tools/remote/run.sh
set -eu
B=\$HOME/$BUILD
R=\$HOME/runs/$NAME
SRC=\$B/src
GEN=\$R/gen
OUT=\$R/out
mkdir -p \$OUT \$GEN
$(drv_job_preamble)
export RAYON_NUM_THREADS=\${RAYON_NUM_THREADS:-$XTHREADS}
# The seven matmul widths of the 70B layer, read by the synthetic layer builder.
export ZK_SYNTHETIC_DIMS=$DIMS

GPU=\$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader)
st "gpu: \$GPU"
st "cores: \$(nproc), threads \$RAYON_NUM_THREADS"
# The card this run was asked for, against the card the machine reports. A rate
# on one card is not a rate on the other and the memory answer is about a
# specific one, so this is checked before anything is built rather than read off
# the manifest afterwards.
case "\$GPU" in
  *"$CARD"*) st "card: the machine reports the $CARD this run was asked for" ;;
  *) st "card: this run was asked for a $CARD and the machine reports \$GPU"; exit 3 ;;
esac
TOTAL_MIB=\$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)

cat > \$OUT/config.json <<CFG
{"driver": "$NAME", "label": "$LABEL",
 "shape": "Llama-3.1-70B width, synthetic: L=1 segment per context, d=$D, nh=$NH, nkv=$NKV, hd=$HD, dff=$DFF",
 "model": "none: a synthetic layer at the 70B width, not the model and not a weight of it",
 "spec": "$SPEC", "card_asked_for": "$CARD", "s": $S, "contexts": "$CONTEXTS",
 "head_groups": "$HEAD_GROUPS", "matmul_widths": "$DIMS",
 "kmax": $KMAX, "residual_stream_a": $RSA, "table_bits_ladder": "$TABLE_BITS",
 "ao_rem_bits": "the witness's own; not pinned",
 "shared_arithmetic": "$SHARED_ARITH", "variant": "$VARIANT",
 "gkr_flags": "$GKR", "shape_flags": "$SHAPE",
 "backend": "cuda", "threads": $XTHREADS,
 "witness": "synthetic, the prover's own fixed-seed generator",
 "registered_prediction_sha256": "$PREDICTION",
 "registration_run": "$(basename "$REG")",
 "comparison": "not made here: this run measures, and the comparison reads the registration"}
CFG

# 1. the reference backend of the pinned prover commit. It emits the device
#    kernels below and it is the binary a cell count can be checked on.
st "build: simd"
( cd \$SRC && CARGO_TARGET_DIR=\$B/t-simd cargo build --release --locked )
SIMD=\$B/t-simd/release/zk-prover

# 2. the device kernels for this shape, into one store, installed into the fork.
#    Without them the CUDA backend evaluates constraints on the host, which is a
#    different measurement wearing the same name.
#    The kernels are shaped by the table width too, so every width the run may
#    try is emitted here: the store dedups by fingerprint and a kernel that
#    is present and unused costs nothing, while a width whose kernels are
#    missing would fall back to the host and be timed as if it had not. Each
#    emit builds the synthetic layer, so this step wants the same host memory
#    the proof does.
K=\$SRC/prover/kernels
[ -d \$K ] || { st "no prover/kernels in this prover commit"; exit 3; }
if [ ! -f \$R/install.done ]; then
  KT0=\$(date +%s)
  for C in $CONTEXTS; do
    for TB in $TABLE_BITS; do
      st "emit: C=\$C, --table-bits \$TB"
      \$SIMD cudaemit $SHARED_ARITH --variants $VARIANT --table-bits \$TB $SHAPE $GKR \
          --s $S --ctx \$C --out \$GEN --block 256 --min-blocks 2 > /dev/null
      \$SIMD genemit $SHARED_ARITH --variants $VARIANT --table-bits \$TB $SHAPE $GKR \
          --s $S --ctx \$C --families "$KERNEL_FAMILIES" --out \$GEN > /dev/null
    done
  done
  python3 \$K/install_constraint_kernels.py --fork \$SRC/nitroo --gen \$GEN
  python3 \$K/install_witness_gen_kernels.py --fork \$SRC/nitroo --gen \$GEN --src \$K
  find \$SRC/nitroo/crates/stwo/src/stwo_cuda/cuda \( -name '*.cu' -o -name '*.cuh' \) -exec touch {} +
  cp \$GEN/cudakernels.rs \$GEN/gencudakernels.rs \$SRC/prover/src/
  # an installed tree is no longer the commit that was pushed, and says so
  grep -q ' dirty\$' \$SRC/.source-commit || sed -i 's/\$/ dirty/' \$SRC/.source-commit
  echo \$((\$(date +%s) - KT0)) > \$R/install.done
fi
st "kernels installed"

# 3. the CUDA backend of the same commit, with the store compiled in
st "build: cuda"
( cd \$SRC && CARGO_TARGET_DIR=\$B/t-cuda cargo build --release --locked -p zk-prover --features cuda )
CUDA=\$B/t-cuda/release/zk-prover

# 4. the card's memory sampler. One nvidia-smi that loops in milliseconds where
#    this driver supports it, and a once-a-second shell loop where it does not;
#    which one ran is in every mem file beside the period it sampled at.
SAMPLER=loop; PERIOD=1
if [ "\$(timeout 3 nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -lms $SAMPLE_MS 2>/dev/null | wc -l)" -ge 3 ]; then
  SAMPLER=nvidia-smi-lms; PERIOD=\$(python3 -c "print($SAMPLE_MS / 1000)")
fi
st "memory sampler: \$SAMPLER, every \$PERIOD s"

# 5. one segment per context, one process each, the card sampled around it. A
#    context already proved is not proved again, so an interrupted job is
#    restarted for the price of what it did not finish. A context that runs out
#    of memory keeps its stderr and its samples and does not stop the other one:
#    that outcome is the answer to the memory question and not a failure of the
#    run.
#    The widths only ever climb: one that proved at one context is the first the
#    next context tries, so the more expensive context does not repeat a refusal
#    the cheaper one already paid for.
FROM=0
for C in $CONTEXTS; do
  if [ -s \$OUT/mem_c\$C.json ]; then st "C=\$C already measured"; continue; fi
  rm -f \$R/c\$C.mem
  if [ \$SAMPLER = nvidia-smi-lms ]; then
    nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -lms $SAMPLE_MS >> \$R/c\$C.mem 2>/dev/null &
  else
    ( while true; do nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits >> \$R/c\$C.mem; sleep 1; done ) &
  fi
  sampler=\$!
  rc=1; LAST=0; T0=\$(date +%s)
  for TB in $TABLE_BITS; do
    [ \$TB -ge \$FROM ] || continue
    st "prove: C=\$C, block $S, --table-bits \$TB"
    rc=0; LAST=\$TB
    \$CUDA compose $SHARED_ARITH --variants $VARIANT --table-bits \$TB $SHAPE $GKR \
        --s $S --ctx \$C > \$OUT/c\$C.json 2> \$R/c\${C}_t\$TB.err || rc=\$?
    if [ \$rc -eq 0 ]; then
      echo \$TB > \$OUT/tablebits_c\$C.txt
      grep -c 'kernel fallback:' \$R/c\${C}_t\$TB.err > \$OUT/c\$C.fallbacks || true
      FROM=\$TB
      break
    fi
    rm -f \$OUT/c\$C.json
    tail -c 2000 \$R/c\${C}_t\$TB.err > \$OUT/refused_c\${C}_t\$TB.txt
    st "C=\$C did not prove at --table-bits \$TB; the last of its stderr is in out/refused_c\${C}_t\$TB.txt"
    # A refusal that is not about the table width is not climbed past: the next
    # width would cost another proof and answer nothing.
    if ! grep -qi 'table' \$OUT/refused_c\${C}_t\$TB.txt; then
      st "C=\$C: that refusal does not name the table, so the widths stop here"
      break
    fi
  done
  T1=\$(date +%s)
  kill \$sampler 2>/dev/null || true
  tail -c 2000 \$R/c\${C}_t\$LAST.err > \$R/c\$C.tail 2>/dev/null || : > \$R/c\$C.tail
  python3 - \$R/c\$C.mem \$R/c\$C.tail \$OUT/mem_c\$C.json \$C \$rc \$((T1 - T0)) \$SAMPLER \$PERIOD \$TOTAL_MIB <<'PY'
import json, os, sys
mem, tail, out, ctx, rc, secs, sampler, period, total = sys.argv[1:10]
v = ([int(l.strip()) for l in open(mem) if l.strip().isdigit()]
     if os.path.exists(mem) else [])
t = open(tail, errors="replace").read()
oom = any(w in t.lower() for w in ("out of memory", "cudaerrormemoryallocation",
                                   "cuda_error_out_of_memory"))
json.dump({"context": int(ctx), "exit_code": int(rc), "loop_secs": int(secs),
           "samples": len(v), "sampler": sampler, "period_s": float(period),
           "max_mib": max(v, default=0), "card_total_mib": int(total),
           "mean_mib": round(sum(v) / len(v), 1) if v else 0,
           "out_of_memory": bool(oom),
           "stderr_tail": t[-600:] if int(rc) else ""},
          open(out, "w"), indent=1)
print(f"C={ctx}: exit {rc}, {secs}s, peak {max(v, default=0)} MiB of {total} MiB"
      + (", out of memory" if oom else ""))
PY
  st "C=\$C done"
done

# 6. the measured side, read back off the outputs, and the gate
python3 - \$OUT $S "$CONTEXTS" <<'PY'
import json, pathlib, sys
out, s = pathlib.Path(sys.argv[1]), int(sys.argv[2])
contexts = [int(c) for c in sys.argv[3].split()]
rows, bad, unproved = [], [], []
for c in contexts:
    mf = out / f"mem_c{c}.json"
    if not mf.exists():
        bad.append(f"C={c}: the job wrote no samples and no result for it")
        continue
    m = json.loads(mf.read_text())
    f = out / f"c{c}.json"
    if not f.exists():
        unproved.append(c)
        print(f"C={c}: no proof at any of the widths, peak {m['max_mib']} MiB of "
              f"{m['card_total_mib']} MiB" + (", out of memory" if m["out_of_memory"] else ""))
        rows.append({"context": c, "s": s, "proved": False, "peak_mib": m["max_mib"],
                     "card_total_mib": m["card_total_mib"],
                     "out_of_memory": m["out_of_memory"], "loop_secs": m["loop_secs"]})
        continue
    doc = json.loads(f.read_text())
    p, prov = doc["result"]["point"], doc["provenance"]
    fam = p["family_cells"]
    kt = fam["key_tiles"] + fam["interaction_by_family"].get("key_tiles", {}).get("cells", 0)
    ph = p["phases"]
    hp = p["host_phases"]
    def host(k):
        return hp.get(k, {}).get("secs", 0.0)
    # The four scopes, in the definitions the recorded sequence runs use. The
    # whole-wall scope is the expression the chunk loop writes into its own
    # whole_wall field, over this segment's fields: it does not count building
    # the layer, and this run serializes nothing, so its two serialization terms
    # are zero rather than missing. The loop scope is this process's own
    # wall-clock time, which does count the layer build, timed by the driver
    # around the process.
    stwo = ph["commit_secs"] + ph["prove_call_secs"]
    whole = (p["trace_secs"] + host("wall/cuda_init") + host("wall/twiddles")
             + ph["wall_secs"] + host("wall/ser_statement") + host("wall/ser_proof"))
    fresh = p["cells"]["fresh"]
    row = {"context": c, "s": s, "proved": True,
           "table_bits": p["params"]["log_table"], "kmax": p["params"]["kmax"],
           "ao_rem_bits": p["params"]["ao_rem_bits"],
           "grid_target": p["params"]["grid_target"],
           "chan_target": p["params"]["chan_target"],
           "accepts": p["accepts"], "off_table": p["off_table"],
           "ref_mismatch": p.get("ref_mismatch"),
           "fresh": fresh, "base": p["cells"]["base"],
           "interaction": p["cells"]["interaction"],
           "preprocessed": p["cells"]["preprocessed"],
           "key_tiles": fam["key_tiles"],
           "key_tiles_interaction":
               fam["interaction_by_family"].get("key_tiles", {}).get("cells", 0),
           "key_tiles_fresh": kt,
           "columns_total": p["columns"]["total"],
           "secs": {"commit": ph["commit_secs"], "stwo_total": stwo,
                    "whole_wall": whole, "loop": m["loop_secs"]},
           "mcell_s": {k: fresh / v / 1e6 for k, v in
                       (("commit", ph["commit_secs"]), ("stwo_total", stwo),
                        ("whole_wall", whole), ("loop", m["loop_secs"])) if v},
           "positions_per_s": {k: s / v for k, v in
                               (("commit", ph["commit_secs"]), ("stwo_total", stwo),
                                ("whole_wall", whole), ("loop", m["loop_secs"])) if v},
           "peak_mib": m["max_mib"], "card_total_mib": m["card_total_mib"],
           "peak_mib_pct_of_card": round(100 * m["max_mib"] / m["card_total_mib"], 1),
           "peak_rss_bytes": p["peak_rss_bytes"],
           "proof_bytes": p["proof_bytes"], "proof_sha256": p["proof_sha256"],
           "prove_secs": p["prove_secs"], "trace_secs": p["trace_secs"],
           "interaction_secs": p["interaction_secs"],
           "unsound_skips": prov["unsound_skips"],
           "all_bound": prov["binding"]["all_bound"],
           "unbound": prov["binding"]["unbound"],
           "kernel_fallback_lines": int((out / f"c{c}.fallbacks").read_text().strip())}
    print(f"C={c}, block {s}: fresh {fresh:,} cells, key tiles {kt:,}, table 2^"
          f"{row['table_bits']}, commit {ph['commit_secs']:.1f} s, stwo {stwo:.1f} s, "
          f"whole-wall {whole:.1f} s, loop {m['loop_secs']} s, peak {m['max_mib']} MiB of "
          f"{m['card_total_mib']} MiB ({row['peak_mib_pct_of_card']}%), host RSS "
          f"{p['peak_rss_bytes'] / 2 ** 30:.1f} GiB, accepts {p['accepts']}")
    if not p["accepts"]:
        bad.append(f"C={c}: the proof was rejected")
    if p["off_table"]:
        bad.append(f"C={c}: {p['off_table']} values off the table")
    if row["ref_mismatch"]:
        bad.append(f"C={c}: {row['ref_mismatch']} cells disagree with the reference "
                   "arithmetic")
    if prov["unsound_skips"]:
        bad.append(f"C={c}: unsound skips in effect")
    if not prov["binding"]["all_bound"]:
        bad.append(f"C={c}: unbound edges {prov['binding']['unbound']}")
    if row["kernel_fallback_lines"]:
        bad.append(f"C={c}: {row['kernel_fallback_lines']} kernel fallback lines, so "
                   "constraints were evaluated on the host and the seconds are not "
                   "the card's")
    rows.append(row)
json.dump({"points": rows, "s": s,
           "note": "one synthetic layer segment at the Llama-3.1-70B width per context. "
                   "The whole-wall scope counts trace generation, interaction "
                   "generation, the stwo call and serialization, of which this run does "
                   "none; the loop scope is the process's own wall-clock time and counts "
                   "building the layer."},
          open(out / "measured.json", "w"), indent=1)
if len(unproved) == len(contexts):
    bad.append("no context proved at any of the widths")
elif unproved:
    print(f"the contexts that did not prove: {unproved}. That is a measurement and not "
          "a failure: the run records what the card held and what it did not.")
if bad:
    sys.exit("; ".join(bad))
print("every segment that proved was accepted; no skip in effect; every edge bound")
PY
st "done"
JOBEOF
drv_start "$JOB"
rm -f "$JOB"
