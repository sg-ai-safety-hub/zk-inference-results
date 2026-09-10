#!/bin/sh
# The job script a sequence campaign runs on the host: extract the witnesses,
# write the plan, emit and install the device kernels for the plan's shapes,
# prove the segments in processes of `SLICE`, check every link on the verifier
# side, and gate the result.  Sourced by a driver, never run.
#
#     drv_sequence_job > "$JOB"
#
# The driver decides everything the job measures and sets it in variables
# first; this file names no flag and no shape of its own.  Two campaigns at one
# context therefore differ in their driver and nowhere else, which is the point:
# the configuration under test must be the only difference between them.
#
# Variables the driver sets: NAME BUILD MODEL SPEC HEAD_SPEC HEAD_LAYER CTX S
# NBLOCK NLAY OFFSET SHARED LAYER_FLAGS L0_FLAGS HEAD_FLAGS HEAD_BLOCKS NHEAD
# VERIFY PIPELINE SLICE XTHREADS IDS KERNEL_FAMILIES LAYER_LINKS TOKEN_LINKS
# HARNESS LABEL, and KEEP_SER.
#
# `MODEL_ROOTS` is the optional one and it is empty in every driver.  It is a
# path to a model commitment this repository recorded, and `drv_model_roots` has
# put the file beside the job and left its digest in MODEL_ROOTS_SUM before this
# body is written.  With it the final grid is given `--expect-model-roots` and
# compares every segment's model root against the commitment, and the gate fails
# the run on a segment whose root is not the commitment's or on a grid that was
# given the file and compared nothing.  Without it the job is what it was: the
# model each segment proves against stays an unchecked end the grid names, and
# `model-commitment.sh` makes the comparison afterwards over the proofs a run
# keeps.  Nothing is derived here either way; `lib/driver.sh` says why the shape
# roots are not compared this way.
#
# HEAD_FLAGS carries what the head segments' lines need beyond their own pins;
# the pins are read off the head dumps' shape rows here and appended to it,
# because a pin written by hand for one quantization variant is wrong under
# another and nothing catches that until the plan has been written.
#
# `KEEP_SER` is 1 when the serialized statements and proofs stay on the host
# after the link check has read them, and 0 -- the default -- when the run is
# done with them and they go.  A campaign that checks another campaign's proofs
# is what keeping them is for, and remaking them costs that campaign's whole
# price.  They are large, they hold the model's activations, and they stay on
# the host either way; the run records how many files and how many bytes.
#
# `HEAD_BLOCKS` is the token blocks that carry an output head segment, as the
# plan's `--head-blocks` spells them, and `NHEAD` is how many that is; empty and
# 0 is a plan with no head segment at all.  `LAYER_LINKS` follows `NHEAD`: a head
# segment sits at the layer coordinate after the last layer of its own block and
# commits the residual it consumed, so it adds one link on the layer axis and
# none on the token axis, where two head segments are put side by side by the
# grid's shape and have no boundary between them.
#
# `VERIFY` is 1 when the run has the grid verify every segment's proof and
# compare every published id against the prompt or against the argmax proved for
# the position before it.  A generated position's id is backed only where a head
# segment proved that argmax, so `VERIFY` is 1 exactly when `HEAD_BLOCKS` covers
# the last prompt block as well as the generated one; the position before the
# first generated one sits in the block before it (docs/decisions).
#
# The final grid is timed and its wall-clock seconds go into the run's
# timing.json as grid_seconds, the name headline-c16384.sh's job and
# model-commitment.sh already write that number under.  With VERIFY 1 the same
# pass replays every segment's proof as well as checking the links, so
# grid_seconds is the two together; grid.json carries each segment's own
# verify_secs under result.verified.chunks, and the link check on its own is
# grid_seconds less their sum.  The job records the seconds and makes no such
# subtraction: nothing is derived here.  The prover's four timing scopes are its
# own and live in the slice outputs, and the extraction is in extract.json, so no
# phase of the job is counted into another.
#
# `LABEL` is what the run is: `headline` for a configuration the paper cites,
# `control` for one it does not, and it goes into the run's own config.json so
# a reader of the run directory cannot mistake one for the other.
#
# The witnesses, the prover build and the kernel store live outside the run
# directory and are shared between campaigns at one context: the first campaign
# to run extracts and builds, and the ones after it find the work done.  A
# slice whose output is already written is not proved again, so a job that
# failed after the loop is restarted for the price of what it did not finish.

drv_sequence_job() {
# The head dumps, named here because the job needs the list and the extractor's
# block tagging is what decides it.
HEAD_DUMPS=""
for hb in $(echo "${HEAD_BLOCKS:-}" | tr ',' ' '); do
    HEAD_DUMPS="$HEAD_DUMPS \${HEADW}_B$hb"
done
# `--verify` needs `--prompt`, and the prompt is only checkable where the plan's
# head segments back every generated id; the driver decides that with VERIFY and
# this is the one place the two arguments are written.
VERIFY_ARGS=""
if [ "${VERIFY:-0}" = 1 ]; then
    VERIFY_ARGS='--verify --prompt $R/prompt_ids.json'
fi
# The published model commitment, when the driver was given one.  Both hold a
# leading space and are empty otherwise, so a job written without a commitment
# is the job that was written before there was one to give.
ROOTS_ARGS=""; ROOTS_CFG=""
if [ -n "${MODEL_ROOTS_SUM:-}" ]; then
    ROOTS_ARGS=' --expect-model-roots $R/model-roots.json'
    ROOTS_CFG=" \"model_roots\": \"$MODEL_ROOTS_SRC\", \"model_roots_sha256\": \"$MODEL_ROOTS_SUM\","
fi
cat <<JOBEOF
#!/bin/sh
# generated by $NAME.sh; runs on the host under tools/remote/run.sh
set -eu
B=\$HOME/$BUILD
R=\$HOME/runs/$NAME
SRC=\$B/src; HSRC=\$B/harness-src/harness; GEN=\$B/gen
OUT=\$R/out; SER=\$R/ser
WIT=\$HOME/witness/$(printf '%.12s' "$HARNESS")/$SPEC-c$CTX     # reused across campaigns
HEADW=\$HOME/witness/$(printf '%.12s' "$HARNESS")/head-$HEAD_SPEC-c$CTX/witness
mkdir -p \$OUT \$GEN \$SER \$WIT
$(drv_job_preamble)
export RAYON_NUM_THREADS=\${RAYON_NUM_THREADS:-16} ZK_KERNEL_STORE=\$GEN
PY="uv run --project \$HSRC \$UVG python"

# the configuration, for the manifest
cat > \$OUT/config.json <<CFG
{"driver": "$NAME", "label": "$LABEL",
 "model": "$MODEL", "spec": "$SPEC", "head_spec": "$HEAD_SPEC",
 "context": $CTX, "s": $S, "positions": $((CTX + S)), "blocks": $NBLOCK, "layers": $NLAY,
 "segments": $((NBLOCK * NLAY + ${NHEAD:-0})), "head_blocks": "${HEAD_BLOCKS:-}",
 "heads": ${NHEAD:-0}, "verify": ${VERIFY:-0},$ROOTS_CFG
 "slice": $SLICE, "pipeline": $PIPELINE,
 "shared_flags": "$SHARED", "layer_flags": "$LAYER_FLAGS", "layer0_flags": "$L0_FLAGS",
 "head_flags": "$HEAD_FLAGS",
 "expect_layer_links": $LAYER_LINKS, "expect_token_links": $TOKEN_LINKS,
 "ids": "${IDS:-generated: the corpus's tokens $OFFSET to $((OFFSET + CTX)) and the model's own greedy continuation under $SPEC}",
 "corpus_offset": $OFFSET}
CFG

st "gpu: \$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader)"
st "nvcc: \$(nvcc --version | tail -2 | head -1)"

# 1. both backends of the pinned prover commit
st "build"
( cd \$SRC && CARGO_TARGET_DIR=\$B/t-simd cargo build --release --locked )
( cd \$SRC && CARGO_TARGET_DIR=\$B/t-cuda cargo build --release --locked -p zk-prover --features cuda )
SIMD=\$B/t-simd/release/zk-prover; CUDA=\$B/t-cuda/release/zk-prover

# 2. the harness at its pinned commit
( cd \$HSRC && uv sync --frozen \$UVG )

# 3. the statement's tokens: the prompt is $CTX tokens of the corpus from
#    offset $OFFSET, and the output is the model's own greedy continuation
#    under $SPEC.  Decoded once
#    with 513 new tokens so the last row's next token is in the array, then
#    shifted into the extraction array; a 512-token decode must agree with it.
IDSFILE="$IDS"
if [ -z "\$IDSFILE" ]; then
  IDSFILE=\$WIT/ids.npy
  if [ ! -f \$IDSFILE ]; then
    st "ids: greedy continuation, $SPEC, corpus offset $OFFSET"
    # --help loads the module and nothing else, so it is the check that the
    # generator's imports resolve before the card is asked for anything.  It
    # used to need a shim, because the module imported one name outside its own
    # package and could not be run with -m at all (zk-prover #51); the pinned
    # commit has that import fixed and the shim is gone with it.
    ( cd \$HSRC && \$PY -m harness.witness.gen_ids --help > /dev/null )
    ( cd \$HSRC && ZK_MODEL=$MODEL ZK_DEVICE=cuda ZK_THREADS=$XTHREADS \$PY -m harness.witness.gen_ids --prefix $CTX --offset $OFFSET --new 513 --spec $SPEC --out \$WIT/ids_513.npy )
    ( cd \$HSRC && ZK_MODEL=$MODEL ZK_DEVICE=cuda ZK_THREADS=$XTHREADS \$PY -m harness.witness.gen_ids --prefix $CTX --offset $OFFSET --new $S --spec $SPEC --out \$WIT/ids_512.npy )
    ( cd \$HSRC && \$PY -m harness.witness.shift_ids --ids \$WIT/ids_513.npy --prefix $CTX --new $S --out \$IDSFILE )
    ( cd \$HSRC && \$PY -c "
import numpy as np
a, b = np.load('\$WIT/ids_512.npy'), np.load('\$WIT/ids_513.npy')
assert (a == b[:len(a)]).all(), 'greedy decoding is deterministic; the 512- and 513-token runs must agree'
print('ids: determinism check passed', len(a), 'tokens')" )
  fi
fi
IDSARG="--ids \$IDSFILE"
# 3b. the witnesses, unless this host already holds them.  Layer 0 carries the
#     embedding rows, which is what binds the first segment's residual stream to
#     the ids the statement publishes, and it is a pass of its own because
#     --embed writes the embedding table into every dump of the pass it is given
#     and the prover turns the gadget on for any dump that carries one.  The
#     block-invariant files are written once and shared between the blocks.
#     A pass whose last dump is already written is not run again, so an
#     interrupted extraction is restarted for the price of what it did not
#     finish.
LAST=$((NBLOCK - 1))
xpass() {   # xpass <tag> <layers> <last layer of the group> <extra flags>
  tag=\$1; group=\$2; last=\$3; shift 3
  [ ! -f \$WIT/witness_B\${LAST}_L\${last}/manifest.json ] || { st "extract: layers \$group are on this host"; return 0; }
  st "extract: layers \$group, $NBLOCK blocks, C=$CTX, $SPEC"
  T0=\$(date +%s)
  ( cd \$HSRC && ZK_MODEL=$MODEL ZK_DEVICE=cuda ZK_THREADS=$XTHREADS \$PY -m harness.witness.extract \
      --tokens $((CTX + S)) --chunk $S --layers \$group --spec $SPEC \
      --residual-stream --diagonal-block --slim --slim-num "\$@" \$IDSARG \
      --blocks all --share \$WIT/shared --out \$WIT/witness )
  T1=\$(date +%s)
  printf '{"pass": "%s", "layers": "%s", "device": "cuda", "threads": %d, "seconds": %d}\n' \
      "\$tag" "\$group" $XTHREADS \$((T1 - T0)) > \$WIT/extract_\$tag.json
  st "extract: layers \$group done in \$((T1 - T0))s"
}
# Layer 0's pass used to need a rename after it, because a one-layer pass
# wrote <base>_B<b> where the shape table and the plan both read
# <base>_B<b>_L<k> (zk-prover #55).  The pinned commit names every dump of a
# --layers pass the same way, one layer or eight, so the rename is gone.
xpass l0 0 0 --embed
xpass l1 1,2,3,4,5,6,7 7
xpass l2 8,9,10,11,12,13,14,15 15
xpass l3 16,17,18,19,20,21,22,23 23
xpass l4 24,25,26,27,28,29,30,31 31
if [ ! -f \$WIT/shapes_all.json ]; then
  st "shapes"
  b=0; LIST=""
  while [ \$b -lt $NBLOCK ]; do
    ( cd \$HSRC && \$PY -m harness.witness.shapes \$WIT/witness_B\${b}_L $NLAY \$WIT/shapes_B\$b.json ); LIST="\$LIST \$WIT/shapes_B\$b.json"; b=\$((b + 1))
  done
  ( cd \$HSRC && \$PY -m harness.witness.shapes --merge \$LIST --out \$WIT/shapes_all.json )
fi
python3 - \$WIT \$OUT/extract.json <<'PY'
import glob, json, os, sys
wit, out = sys.argv[1], sys.argv[2]
rows = [json.load(open(f)) for f in sorted(glob.glob(os.path.join(wit, "extract_*.json")))]
json.dump({"passes": rows, "seconds": sum(r["seconds"] for r in rows)}, open(out, "w"), indent=1)
print("extract:", sum(r["seconds"] for r in rows), "s over", len(rows), "passes")
PY
# One head dump per head block, block-tagged, because a head dump carries the
# position its block starts at and the plan reads block b's head from
# <base>_B<b>.  One extraction pass covers every head block: the pass costs what
# its highest block costs and the dumps are written from inside the forward loop.
#
# --diagonal-block is on the extraction and not on the head line.  A spec that
# delays the v matmul -- y-delay-vw12 does -- has the extractor check the v
# fold's identity against the diagonal block's vvc before it writes anything,
# and it refuses a dump made without the flag (harness/witness/extract.py,
# "the v fold's identity check reads the diagonal block's vvc").  b10-final
# delays nothing, which is why the head dump used to be made without it.  The
# head line must still not carry the flag: the head chunk performs no attention
# and reads no diagonal block (harness/witness/plan.py).
if [ -n "${HEAD_BLOCKS:-}" ]; then
  need=0
  for hb in $(echo "${HEAD_BLOCKS:-}" | tr ',' ' '); do
    [ -f "\${HEADW}_B\$hb/manifest.json" ] || need=1
  done
  if [ \$need = 1 ]; then
    st "extract: the output head over token blocks $HEAD_BLOCKS, $HEAD_SPEC"
    ( cd \$HSRC && ZK_MODEL=$MODEL ZK_DEVICE=cuda ZK_THREADS=$XTHREADS \$PY -m harness.witness.extract --tokens $((CTX + S)) --chunk $S \
        --layer $HEAD_LAYER --spec $HEAD_SPEC --head --slim --diagonal-block --blocks $HEAD_BLOCKS \$IDSARG --out \$HEADW )
  fi
fi
du -sh \$WIT | awk '{print "witness size: " \$1 "  " \$2}'
cp \$WIT/shapes_all.json \$OUT/shapes.json
PINS=\$(python3 - \$WIT/shapes_all.json <<'PY'
import json, sys
w = json.load(open(sys.argv[1]))["worst"]
print(f"--kmax {w['kmax']} --ao-rem-bits {w['ao_rem_bits']} --fold-rem-bits {w['fold_rem_bits']} --fold-alpha {w['fold_alpha']}")
PY
)
st "pins: \$PINS"

# The head segments' own pins.  A head dump is its layer's dump with the head's
# arrays beside it, so it has a shape row like any other, and that row is what
# says how many bits the attention output's remainder needs.  Reading it off the
# dump rather than writing it out by hand is the whole of it: a pin written for
# one quantization variant is wrong under another, and the assertion that
# catches that fires after the plan is written.  The layers' merged pins cover
# the rest, and the job stops here if they do not.
HEADPINS=""
if [ -n "${HEAD_BLOCKS:-}" ]; then
  HEADPINS=\$( cd \$HSRC && \$PY - \$OUT/shapes_head.json "\$PINS" $HEAD_DUMPS <<'HEADPY'
import json, sys
from harness.witness.shapes import shape_of, worst_of
out, pins, dumps = sys.argv[1], sys.argv[2].split(), sys.argv[3:]
rows = [shape_of(d) for d in dumps]
worst, _ = worst_of(rows)
json.dump({"rows": rows, "worst": worst, "dumps": dumps}, open(out, "w"), indent=1)
shared = {pins[i]: int(pins[i + 1]) for i in range(0, len(pins), 2)}
for flag, key in (("--kmax", "kmax"), ("--fold-rem-bits", "fold_rem_bits")):
    need, have = worst.get(key, 0), shared.get(flag, 0)
    assert need <= have, (
        f"the head dumps need {flag} {need} and the layers' merged pin is {have}; "
        "the shared pins do not cover the head")
print(f"--ao-rem-bits {worst['ao_rem_bits']}")
HEADPY
)
  st "head pins: \$HEADPINS"
fi

# 4. the plan: one line per segment, and the distinct kernel shapes
if [ -n "${HEAD_BLOCKS:-}" ]; then
  ( cd \$HSRC && \$PY -m harness.witness.plan --dir \$WIT --blocks $NBLOCK --with-block-0 --layers 0-$((NLAY - 1)) \
      --head \$HEADW --head-per-block --head-blocks $HEAD_BLOCKS \
      --layer-flags="$LAYER_FLAGS" --l0-flags="$L0_FLAGS" --l0-dir \$WIT \
      --head-flags="$HEAD_FLAGS \$HEADPINS" --out \$OUT/plan.txt --emit-out \$R/emit.txt )
else
  ( cd \$HSRC && \$PY -m harness.witness.plan --dir \$WIT --blocks $NBLOCK --with-block-0 --layers 0-$((NLAY - 1)) \
      --layer-flags="$LAYER_FLAGS" --l0-flags="$L0_FLAGS" --l0-dir \$WIT \
      --out \$OUT/plan.txt --emit-out \$R/emit.txt )
fi
N=\$(grep -cv '^#' \$OUT/plan.txt); st "plan: \$N segments"

# 5. the device kernels for every shape in the plan, compiled into the CUDA backend
K=\$SRC/prover/kernels
[ -d \$K ] || { st "no prover/kernels in this prover commit; the CUDA backend would evaluate constraints on the CPU"; exit 3; }
# Every head line of the plan, on top of the shapes plan.py listed.  plan.py
# keys an emit shape by (prefix, master table width, head, flags) and gives a
# head line no prefix, so two head blocks of one table width are one entry and
# only the first block's is emitted; the prover's feed kernels for a head chunk
# do depend on its block, and the second head panics on the one that is missing
# (zk-prover #131).  A kernel is looked up by fingerprint and the store dedups,
# so a line that is listed twice costs nothing the second time.
{ grep -v '^#' \$R/emit.txt
  grep -v '^#' \$OUT/plan.txt | grep -- '--ser-tag [A-Za-z0-9_]*head' || true
} | sort -u > \$R/emit-all.txt
# What the installed kernels were emitted for.  A marker carrying the list's own
# digest re-runs this step when the plan's shapes move and skips it when they
# have not, which an empty marker file cannot do.
EMITSUM=\$(sha256sum \$R/emit-all.txt | cut -c1-16)
if [ "\$(cat \$R/kernels.done 2>/dev/null)" != "\$EMITSUM" ]; then
  while read -r line; do
    case "\$line" in '#'*|'') continue ;; esac
    args=\$(printf '%s\n' "\$line" | sed 's/--ser-tag [A-Za-z0-9_]*//')
    # A refused lowering is recorded and never fatal here: a kernel is looked up
    # by fingerprint and the plan's shapes share theirs, so what a refusal costs
    # is either nothing or an announced kernel fallback line, and the gate below
    # fails the run on any such line.  Which shapes were refused is in the run
    # directory, not in an exit code.  The one refusal this used to see was the
    # segment with no prefix, whose placeholder claims were one entry short
    # (zk-prover #57, fixed by #62); a refusal at the pinned commit is a new one
    # and worth reading.
    for emit in cudaemit genemit; do
      case \$emit in
        cudaemit) opts="--block 256 --min-blocks 2" ;;
        genemit)  opts="--families $KERNEL_FAMILIES" ;;
      esac
      if ! \$SIMD \$emit $SHARED \$PINS \$args \$opts --out \$GEN > /dev/null; then
        printf '%s\n' "\$line" >> \$OUT/\$emit-refused.txt
        st "\$emit refused a shape (zk-prover #57); recorded in out/\$emit-refused.txt"
      fi
    done
  done < \$R/emit-all.txt
  python3 \$K/install_constraint_kernels.py --fork \$SRC/nitroo --gen \$GEN
  python3 \$K/install_witness_gen_kernels.py --fork \$SRC/nitroo --gen \$GEN --src \$K
  find \$SRC/nitroo/crates/stwo/src/stwo_cuda/cuda \( -name '*.cu' -o -name '*.cuh' \) -exec touch {} +
  cp \$GEN/cudakernels.rs \$GEN/gencudakernels.rs \$SRC/prover/src/
  # an installed tree is no longer the commit that was pushed, and says so
  grep -q ' dirty\$' \$SRC/.source-commit || sed -i 's/\$/ dirty/' \$SRC/.source-commit
  ( cd \$SRC && CARGO_TARGET_DIR=\$B/t-cuda cargo build --release --locked -p zk-prover --features cuda )
  printf '%s\n' "\$EMITSUM" > \$R/kernels.done
fi
st "kernels installed"

# 6. the timed run: $SLICE segments per process, pipelined, the card sampled once
#    a second.  The samples stay on the host and what is fetched is their
#    summary, because a run directory holds outputs and not logs.
lo=0
while [ \$lo -lt \$N ]; do
  hi=\$((lo + $SLICE)); [ \$hi -gt \$N ] && hi=\$N
  tag=\$(printf 'slice_%04d' \$lo); mtag=\$(printf 'mem_%04d' \$lo)
  if [ -s \$OUT/\$tag.json ]; then st "\$tag already proved"; lo=\$hi; continue; fi
  rm -f \$R/\$tag.mem
  ( while true; do echo "\$(date +%s) \$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)" >> \$R/\$tag.mem; sleep 1; done ) & sampler=\$!
  ZK_PIPELINE=$PIPELINE \$CUDA compose-chunks $SHARED \$PINS --plan \$OUT/plan.txt --plan-slice \$lo:\$hi --ser-dir \$SER \
      > \$OUT/\$tag.json 2> \$R/\$tag.err || { kill \$sampler; rm -f \$OUT/\$tag.json; st "\$tag failed, see \$R/\$tag.err"; exit 4; }
  kill \$sampler
  grep -c 'kernel fallback:' \$R/\$tag.err > \$OUT/\$tag.fallbacks || true
  python3 - \$R/\$tag.mem \$OUT/\$mtag.json <<'PY'
import json, sys
v = [int(l.split()[1]) for l in open(sys.argv[1]) if len(l.split()) == 2 and l.split()[1].isdigit()]
json.dump({"samples": len(v), "period_s": 1, "max_mib": max(v, default=0),
           "mean_mib": round(sum(v) / len(v), 1) if v else 0}, open(sys.argv[2], "w"))
PY
  st "\$tag done"
  lo=\$hi
done

# 7. the prompt the statement publishes, written out for the grid to compare
#    every block's ids against.  The ids stay on the host with the witnesses --
#    they are the corpus -- and the run records how many there are and their
#    digest.
\$PY - \$IDSFILE $CTX \$R/prompt_ids.json \$OUT/prompt.json <<'PROMPTPY'
import hashlib, json, sys
import numpy as np
ids = [int(x) for x in np.load(sys.argv[1])[:int(sys.argv[2])]]
body = json.dumps({"ids": ids})
open(sys.argv[3], "w").write(body)
json.dump({"positions": len(ids), "sha256": hashlib.sha256(body.encode()).hexdigest(),
           "note": "the ids the statement publishes for the prompt's positions. They stay "
                   "on the host, because they are the corpus. boundary-grid --prompt "
                   "compares every one of them against the ids the block's layer-0 segment "
                   "committed, and every later position against the token the head segment "
                   "proved for the position before it."},
          open(sys.argv[4], "w"), indent=1)
print("prompt:", len(ids), "ids")
PROMPTPY

# 8. every link between segments, checked on the verifier side over the
#    serialized statements and proofs.  With VERIFY the grid also runs the
#    verifier on every segment's proof and chains the published ids: each
#    prompt position against the prompt above, each generated position against
#    the token a head segment proved for the position before it.  With
#    MODEL_ROOTS it also compares every segment's model root against the
#    commitment the driver put beside this job.
GRIDT0=\$(date +%s)
\$SIMD boundary-grid --dir \$SER --plan \$OUT/plan.txt \
    --expect-layer-links $LAYER_LINKS --expect-token-links $TOKEN_LINKS $VERIFY_ARGS$ROOTS_ARGS \
    > \$OUT/grid.json 2> \$R/grid.err
GRID_SECS=\$((\$(date +%s) - GRIDT0))
st "links checked in \${GRID_SECS}s"

# 8b. what that pass cost.  The four proving scopes are the prover's own and are
#     in the slice outputs, and the extraction is in extract.json; this file is
#     the grid alone, so a verifier-side second can never be read into the loop.
#     With the verifier on, the pass is the link check and the replay together
#     and the header of this file says what the difference is read from.
python3 - \$OUT \$GRID_SECS ${VERIFY:-0} <<'TIMEPY'
import json, os, sys
out, grid, verify = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
json.dump({"grid_seconds": grid, "grid_verify": bool(verify),
           "note": "Wall-clock seconds of the final grid pass, which checks every link "
                   "between the segments over their serialized statements and proofs. "
                   "With grid_verify true the same pass also replayed every segment's "
                   "proof and chained the published ids, so these seconds are the link "
                   "check and the verification together; grid.json carries each segment's "
                   "own verify_secs under result.verified.chunks. The prover's own loop, "
                   "commit, stwo total and whole wall scopes are in the slice outputs and "
                   "the extraction is in extract.json."},
          open(os.path.join(out, "timing.json"), "w"), indent=1)
print("grid:", grid, "s, verifier", "on" if verify else "off")
TIMEPY

# 9. the gate: no skip in effect, every edge bound, every link run and passed,
#    no lookup evaluated on the host instead of by its generated kernel, and --
#    where the run was given a model commitment -- every segment's model root
#    the commitment's
python3 - \$OUT <<'PY'
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
bad, fresh, n = [], 0.0, 0
for f in sorted(out.glob("slice_*.json")):
    doc = json.loads(f.read_text())
    p = doc["provenance"]
    s = doc["result"]["summary"]
    n += s["n"]
    fresh += s["fresh_sum"]
    print(f"{f.name}: {s['n']} segments, loop {s['loop_secs']:.1f} s, "
          f"fresh {s['fresh_sum']:,.0f} cells, skips {p['unsound_skips'] or 'none'}, "
          f"all_bound {p['binding']['all_bound']}, unbound {p['binding']['unbound']}")
    if p["unsound_skips"]:
        bad.append(f"{f.name}: unsound skips in effect")
    if not p["binding"]["all_bound"]:
        bad.append(f"{f.name}: unbound edges {p['binding']['unbound']}")
    k = int((out / f.name.replace(".json", ".fallbacks")).read_text().strip())
    if k:
        bad.append(f"{f.name}: {k} kernel fallback lines")
g = json.loads((out / "grid.json").read_text())["result"]
print(f"grid: {g['links_passed']}/{g['links_run']} of {g['links_expected']} implied links passed; "
      f"all_chain {g['all_chain']}")
# The published model commitment, where the driver was given one: config.json
# names the file the grid was told to compare against, so a run that was given
# one and a grid that compared nothing is a failure and not a silent pass.
cfg = json.loads((out / "config.json").read_text())
if cfg.get("model_roots"):
    mr = (g.get("model_roots") or {}).get("chunks") or []
    off = sum(1 for x in mr if not x["ok"] or not x["model_ok"])
    print(f"commitment {cfg['model_roots']}: {len(mr)} segments' model roots compared, "
          f"{off} not the commitment's")
    if not mr:
        bad.append(f"the run was given the commitment {cfg['model_roots']} and the grid "
                   "compared no model root")
    if off:
        bad.append(f"{off} segment(s) do not name the commitment's model root")
v, tk = g.get("verified", {}), g.get("tokens", {})
print(f"grid: {v.get('accepted', 0)}/{v.get('run', 0)} segment proofs verified; ids "
      f"{tk.get('prompt_positions', 0)} prompt + {tk.get('generated_positions', 0)} generated, "
      f"{len(tk.get('mismatches') or [])} wrong, "
      f"{len(tk.get('unbacked') or [])} with no argmax behind them")
for u in g.get("unchecked_ends", []):
    print(f"unchecked end: {u['what']} -- {u['why']}")
if not v.get("all", True):
    bad.append(f"{v.get('run', 0) - v.get('accepted', 0)} segment proof(s) did not verify")
if not tk.get("all", True):
    bad.append(f"the published ids do not chain: {tk.get('mismatches')}, "
               f"unbacked {tk.get('unbacked')}")
if not g["all_chain"]:
    bad.append(f"the grid did not chain: {g['failures']}")
peak = max((json.loads(f.read_text())["max_mib"] for f in out.glob("mem_*.json")), default=0)
print(f"total: {n} segments, {fresh:,.0f} fresh cells, the card held at most {peak} MiB")
if bad:
    sys.exit("; ".join(bad))
print("no skip; every edge bound; every implied link passed; no kernel fallback")
PY
if [ "${KEEP_SER:-0}" = 1 ]; then
  python3 - \$SER \$OUT/ser.json <<'SERPY'
import json, os, sys
ser = sys.argv[1]
n = b = 0
for root, _, files in os.walk(ser):
    for f in files:
        n += 1
        b += os.path.getsize(os.path.join(root, f))
json.dump({"kept": True, "files": n, "bytes": b}, open(sys.argv[2], "w"))
print(f"serialized statements and proofs: {n} files, {b / 2 ** 30:.1f} GiB, kept on the host")
SERPY
else
  rm -rf \$SER
  printf '{"kept": false}\n' > \$OUT/ser.json
fi
st "done"
JOBEOF
}
