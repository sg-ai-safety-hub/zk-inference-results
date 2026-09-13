#!/bin/sh
# block-length-c4096: one token block of the headline plan at a block length
# this driver is told, instead of the 512 every recorded run proves.
#
#   tools/drivers/block-length-c4096.sh <host> <prover-commit> <harness-commit> <S>
#
# Every number this repository holds was measured at S = 512 positions a
# segment.  S is in the statement twice over: the prefix is tiled into key
# blocks of S, so the key tile term of a segment's cells moves with it, and the
# weights are committed once per segment whatever S is, so the per-position
# share of them is the model's weights over S.  The two pull opposite ways and
# nothing here has ever measured either.  This driver measures one point of that
# curve: the last token block of the context 4,096 plan at the block length it
# is given, on the card, under the configuration the paper reports.
#
# **The block length has no default, and that is the point.** A run at another S
# is a different quantity with the same name, so S is an argument, it is in the
# run id, it is in every constant this run backs, and a second call that names
# another S is refused rather than fetched.
#
# What is proved, per block length:
#
#   S = 256   the last block's 32 layer segments -- the whole block, which is
#             what makes its per-segment rows comparable with the last block of
#             `headline-c4096`.  The plan is 17 token blocks where the recorded
#             one is 9, and the block proved is the last, so its prefix is the
#             same 4,096 positions the recorded reference segment reads.
#   S = 512   the same 32 segments at the recorded block length: not a new
#             measurement, a repeat of one, and it is here so that the rows this
#             driver records can be read against a point it made itself.
#   S = 1024  the last block's layer 16 alone.  The exact count says that
#             segment is 2,631,844,976 cells against 1,393,069,168 at S = 512 --
#             1.889 times, counted at the recorded 8B fields -- and the recorded
#             S = 512 loop at this context peaked 73,723 MiB of the card's
#             81,559, so one segment is the cheapest test there is and the
#             expected answer is that it does not fit.  Layer 16 of the last
#             block is the segment `lib/seq5-reference.py` already treats as
#             this repository's reference segment at a context.
#
# **An out-of-memory is the result, not a failure of the run.** The card loop is
# not allowed to stop the job: its exit code, whether its stderr names an
# out-of-memory, the largest sample the card returned and the LAST sample before
# the process went are all recorded, and the job carries on.  What a run that
# ran out of memory then records is one row, `mem.block.c4096.s<S>.oom_last_
# sample_mib`, and nothing else for that block length: there are no cells, no
# seconds and no proof bytes, because no proof was made.
#
# The same segment is proved afterwards on the reference backend, which proves
# in host memory and cannot run the card out of it.  It is the run's provenance
# anchor -- `manifest.py` refuses a fetched directory whose outputs carry no
# provenance block, and a loop the card could not hold writes no output at all,
# so without it the answer most worth recording could not be recorded -- and it
# is a digest gate wherever the card also proved that segment, because a STARK
# proof is deterministic once the trace and the parameters are fixed and the two
# backends must agree byte for byte.  `memory-probe-c16384.sh` puts it there for
# the same two reasons.
#
# The configuration is `headline-c4096.sh`'s, copied line for line: the five GKR
# reductions on, `--tight-table`, the same shared pins, the same quantization
# variant, the same corpus window, and the segment loop pipelined one segment
# ahead as the headline runs it.  A flag that differed would make this answer a
# question about a loop nobody runs.  What is NOT the headline's is what one
# block cannot have: there is no output head segment in the plan, the verifier
# side is not run, and the run's label is `probe`, so a reader of the run
# directory cannot mistake one token block for a sequence.
#
# What the fetch records, and the names the audit re-derives them under.  With
# the card loop proved:
#
#   segments.block.c4096.s<S>                         measured
#   cells.block.c4096.s<S>.fresh                      measured
#   secs.block.c4096.s<S>.<scope>                     measured, the four scopes
#   secs_per_segment.block.c4096.s<S>.<scope>         derived, over the segments
#   mem.block.c4096.s<S>.peak_mib                     measured
#   proof.block.c4096.s<S>.bytes_per_segment_median   measured
#   cells.block.c4096.s<S>.exact_predicted            derived
#   cells.block.c4096.s<S>.rho                        derived, measured/counted
#
# and with the card out of memory, `mem.block.c4096.s1024.oom_last_sample_mib`
# alone.  `tools/constants/audit.py`'s `block_length_c4096` section reads them
# all off this run's own outputs.
#
# **How the counted side is made.** `cells.block.c4096.s<S>.exact_predicted` is
# the prover's trace layout counted at this block length over the very segments
# this run proves, which is `harness.eval.predict.predict.exact_segments` -- the
# function `predict.py --cells exact` counts a registration with -- called at
# `seq = S`.  Its `--witness-fields` file is written here, by
# `harness.eval.predict.witness_fields` over this run's own dumps, so every
# witness-calibrated field the count needs is the dump's own and none is
# assumed; the shape is `cost_model.LLAMA8B`, the model's published seven
# numbers, and the head grouping is the one this driver passes.  The command
# line of `predict.py` itself takes no block length -- its `S` is 512, the
# module constant -- so the count is made by calling that function, in step 7 of
# the job, and `predicted.json` records the per-layer counts, each layer's dump
# digest, and the harness commit that counted them.  The count reads no
# measurement: the fields exist before any proof of them does.
#
# The first call refuses a host that is busy, pushes zk-prover at the two
# commits, starts the job detached and prints the poll command.  Every later
# call with the same arguments prints the status; once the status says done it
# fetches the outputs into runs/<run-id>/, writes manifest.json from the
# prover's provenance block, and runs check.py.  Nothing measured is typed in
# here.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
HOST=${1:?host alias}
PROVER=${2:?prover commit}
HARNESS=${3:?harness commit}
S=${4:?the block length, in positions a segment; 512 is the recorded configuration and anything else is a different quantity and says so in every row}
ZK_PROVER=${ZK_PROVER_DIR:-$ROOT/../zk-prover}     # a local clone to archive the commits from
# One run directory, one status file and one run id per block length: two of
# these on one day are two measurements and `manifest.py` never overwrites a run
# directory.  The manifest still names this file, which is what DRV_DRIVER is
# for, and DRV_ARGS puts the block length back into the restart line.
NAME=block-length-c4096-s$S
DRV_DRIVER=block-length-c4096
DRV_ARGS=$S
. "$HERE/lib/driver.sh"

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=probe                # neither a headline nor a control: one token block
MODEL=${ZK_MODEL:-unsloth/Llama-3.1-8B-Instruct}
SPEC=y-delay-vw12          # the quantization variant the paper reports (docs/decisions)
CTX=4096
NBLOCK=$(( (CTX + S) / S ))  # the prompt's blocks and the one output block
BLOCK=$(( NBLOCK - 1 ))      # the last, whose prefix is the whole context
NLAY=32
REF_LAYER=16               # the segment lib/seq5-reference.py reads at a context
SHARED="--round even --numbits 9 --z-hi-bits 7 --variants intexp --head-groups 16,8,8 --tight-table"
HEAD_GROUPS=16,8,8         # the same grouping, as the counted side reads it
GKR="--gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
LAYER_FLAGS="--round even --diagonal-block $GKR"   # every binding gadget is on by default; no skip flag anywhere
L0_FLAGS=""
# The corpus window is the headline's: a 4,096-token prompt taken from token 0
# ends inside the front matter's list of illustrations, where the greedy
# continuation is a repeating index line, so the window is moved to the end of
# the 16,384-token prompt and this block reads the prose the recorded runs read.
OFFSET=$(( 16384 - CTX ))
PIPELINE=1                 # ZK_PIPELINE: generate segment k+1 while proving segment k
XTHREADS=20                # torch threads for the extraction
IDS=${ZK_IDS:-}            # token ids (.npy) already on the host; empty = generate them
SAMPLE_S=1                 # the card sampler's period, as every sequence run samples
KERNEL_FAMILIES=zk_chan_eval,zk_key_eval,zk_row_eval,zk_attn_out_eval,zk_dequant_eval,zk_freivalds_eval,zk_exp_table_eval,zk_table_eval,zk_residual_stream_eval,zk_residual_stream_table_eval

# ---- the block lengths this driver measures, and what each one proves --------
# The prefix is tiled in blocks of S, so a context that is not a whole number of
# them is not a statement this prover makes; and `prover/src/layout.rs` names
# the block lengths whose trace layouts build today, of which these three are
# the ones at and around the recorded configuration.  What each proves is a
# decision and not a rule, so it is a table and not an inequality.
case $S in
  256)  PLAN_LAYERS="0-$(( NLAY - 1 ))"; NPROVE=$NLAY ;;   # the whole block
  512)  PLAN_LAYERS="0-$(( NLAY - 1 ))"; NPROVE=$NLAY ;;   # the recorded one, repeated
  1024) PLAN_LAYERS=$REF_LAYER;          NPROVE=1 ;;       # one segment: it is not expected to fit
  *) echo "$NAME: this driver measures block lengths 256, 512 and 1,024 and was given $S." >&2
     echo "        256 and 512 prove the last block's $NLAY layer segments; 1,024 proves" >&2
     echo "        layer $REF_LAYER of it alone, because a block that long is not expected to fit" >&2
     echo "        the card and one segment is the cheapest test of that. Another block" >&2
     echo "        length is another decision and belongs in the table above, with what" >&2
     echo "        it proves written beside it." >&2
     exit 2 ;;
esac
[ $(( CTX % S )) -eq 0 ] || { echo "$NAME: C=$CTX is not a whole number of $S-position blocks" >&2; exit 2; }

# ---- the arguments the running job was started with --------------------------
# The run directory is per block length, so a second call cannot fetch a run
# that measured another one; what this catches is the rest of the configuration
# moving under a job that is already on the host.
WANT="s=$S ctx=$CTX block=$BLOCK layers=$PLAN_LAYERS spec=$SPEC"
HAVE=$(ssh -o BatchMode=yes "$HOST" "cat ~/runs/$NAME/params.txt 2>/dev/null || true")
if [ -n "$HAVE" ] && [ "$HAVE" != "$WANT" ]; then
    echo "$NAME: the job on this host was started as" >&2
    echo "          $HAVE" >&2
    echo "        and this call names" >&2
    echo "          $WANT" >&2
    echo "        Fetch that one with the arguments it was started with, or remove" >&2
    echo "        ~/runs/$NAME on the host and start this one." >&2
    exit 2
fi

drv_finish "$(drv_status)"

# ---- the host, before anything is pushed to it -------------------------------
# Both cards are rented by the hour and one run holds a host at a time.  The
# lock is what `run.sh` would refuse on, but it would refuse after the sources
# were pushed -- which overwrites the build tree the job holding the card is
# building from.  So the lock and the card are read first, and a host that is
# busy is refused here, with what is on it.
BUSY=$(ssh -o BatchMode=yes "$HOST" "cat ~/.zk-run.lock 2>/dev/null || true")
if [ -n "$BUSY" ]; then
    echo "$NAME: $HOST is busy: $BUSY" >&2
    echo "        Another run holds the host lock. Pushing now would overwrite the tree" >&2
    echo "        that run is building from, so nothing is pushed and nothing is started." >&2
    echo "        Wait for it, or run this on the other host." >&2
    exit 1
fi
APPS=$(ssh -o BatchMode=yes "$HOST" "nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader 2>/dev/null || true")
if [ -n "$APPS" ]; then
    echo "$NAME: $HOST holds no lock, and its card is running:" >&2
    printf '          %s\n' "$APPS" >&2
    echo "        A job that lost its lock is still a job. Nothing is pushed." >&2
    exit 1
fi

# ---- start: push the pinned sources, then the job ----------------------------
drv_check_commits
BUILD=$(drv_build_root)
drv_push "$BUILD/src" "$PROVER"
drv_push "$BUILD/harness-src" "$HARNESS"
printf '%s\n' "$WANT" | ssh -o BatchMode=yes "$HOST" "mkdir -p ~/runs/$NAME && cat > ~/runs/$NAME/params.txt"

JOB=$(mktemp)
cat > "$JOB" <<JOBEOF
#!/bin/sh
# generated by $DRV_DRIVER.sh at S=$S; runs on the host under tools/remote/run.sh
set -eu
B=\$HOME/$BUILD
R=\$HOME/runs/$NAME
SRC=\$B/src; HSRC=\$B/harness-src/harness; GEN=\$B/gen
OUT=\$R/out; SER=\$R/ser
# A witness directory of its own, per block length: the dumps of a 256-position
# block are not the dumps of a 512-position one, and the extraction is decided
# done by looking for this block's last layer.  Sharing the headline's directory
# would tell a headline run that its nine blocks are on the host when one block
# of another length is.
WIT=\$HOME/witness/$(printf '%.12s' "$HARNESS")/$SPEC-c$CTX-s$S-b$BLOCK
mkdir -p \$OUT \$GEN \$SER \$WIT
$(drv_job_preamble)
export RAYON_NUM_THREADS=\${RAYON_NUM_THREADS:-16} ZK_KERNEL_STORE=\$GEN
PY="uv run --project \$HSRC \$UVG python"

# the configuration, for the manifest
cat > \$OUT/config.json <<CFG
{"driver": "$DRV_DRIVER", "label": "$LABEL",
 "model": "$MODEL", "spec": "$SPEC",
 "context": $CTX, "s": $S, "positions": $((CTX + S)), "blocks": $NBLOCK, "layers": $NLAY,
 "block": $BLOCK, "plan_layers": "$PLAN_LAYERS", "segments": $NPROVE,
 "reference_layer": $REF_LAYER,
 "head_blocks": "", "heads": 0, "verify": 0,
 "pipeline": $PIPELINE, "sample_period_s": $SAMPLE_S,
 "shared_flags": "$SHARED", "layer_flags": "$LAYER_FLAGS", "layer0_flags": "$L0_FLAGS",
 "head_groups": "$HEAD_GROUPS",
 "ids": "${IDS:-generated: the corpus's tokens $OFFSET to $((OFFSET + CTX)) and the model's own greedy continuation under $SPEC}",
 "corpus_offset": $OFFSET}
CFG

st "gpu: \$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader)"
st "nvcc: \$(nvcc --version | tail -2 | head -1)"
TOTAL_MIB=\$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)

# 1. both backends of the pinned prover commit
st "build"
( cd \$SRC && CARGO_TARGET_DIR=\$B/t-simd cargo build --release --locked )
( cd \$SRC && CARGO_TARGET_DIR=\$B/t-cuda cargo build --release --locked -p zk-prover --features cuda )
SIMD=\$B/t-simd/release/zk-prover; CUDA=\$B/t-cuda/release/zk-prover

# 2. the harness at its pinned commit
( cd \$HSRC && uv sync --frozen \$UVG )

# 3. the statement's tokens, generated the way the headline driver generates
#    them and at this block length: the prompt is $CTX tokens of the corpus from
#    offset $OFFSET and the output is the model's own greedy continuation under
#    $SPEC.  Decoded once with one token more than the rectangle so the last
#    row's next token is in the array, then shifted into the extraction array;
#    a decode of the rectangle alone must agree with it.  The construction is
#    the headline's with $S where it writes 512, so at S = 512 it reproduces the
#    recorded array.
IDSFILE="$IDS"
if [ -z "\$IDSFILE" ]; then
  IDSFILE=\$WIT/ids.npy
  if [ ! -f \$IDSFILE ]; then
    st "ids: greedy continuation, $S positions, $SPEC, corpus offset $OFFSET"
    ( cd \$HSRC && \$PY -m harness.witness.gen_ids --help > /dev/null )
    ( cd \$HSRC && ZK_MODEL=$MODEL ZK_DEVICE=cuda ZK_THREADS=$XTHREADS \$PY -m harness.witness.gen_ids --prefix $CTX --offset $OFFSET --new $((S + 1)) --spec $SPEC --out \$WIT/ids_p1.npy )
    ( cd \$HSRC && ZK_MODEL=$MODEL ZK_DEVICE=cuda ZK_THREADS=$XTHREADS \$PY -m harness.witness.gen_ids --prefix $CTX --offset $OFFSET --new $S --spec $SPEC --out \$WIT/ids_s.npy )
    ( cd \$HSRC && \$PY -m harness.witness.shift_ids --ids \$WIT/ids_p1.npy --prefix $CTX --new $S --out \$IDSFILE )
    ( cd \$HSRC && \$PY -c "
import numpy as np
a, b = np.load('\$WIT/ids_s.npy'), np.load('\$WIT/ids_p1.npy')
assert (a == b[:len(a)]).all(), 'greedy decoding is deterministic; the two decodes must agree'
print('ids: determinism check passed', len(a), 'tokens')" )
  fi
fi
IDSARG="--ids \$IDSFILE"

# 3b. block $BLOCK's witnesses, all $NLAY layers.  The forward pass is the whole
#     sequence either way -- a block reads the keys and values of every block
#     before it -- and only this block's dumps are written, which is what makes
#     one block affordable on disk where the whole plan's extraction is not.
#     Every layer is extracted even where one segment is proved: the shape table
#     is what the loop's pins are taken over, and a pin read off one layer is
#     not the pin a plan at this block length would be proved at.  Layer 0 is a
#     pass of its own because --embed writes the embedding table into every dump
#     of the pass it is given, and the prover turns the gadget on for any dump
#     that carries one.  A pass whose last dump is written is not run again.
xpass() {   # xpass <tag> <layers> <last layer of the group> <extra flags>
  tag=\$1; group=\$2; last=\$3; shift 3
  [ ! -f \$WIT/witness_B${BLOCK}_L\${last}/manifest.json ] || { st "extract: layers \$group are on this host"; return 0; }
  st "extract: layers \$group, block $BLOCK of $NBLOCK, C=$CTX, S=$S, $SPEC"
  T0=\$(date +%s)
  ( cd \$HSRC && ZK_MODEL=$MODEL ZK_DEVICE=cuda ZK_THREADS=$XTHREADS \$PY -m harness.witness.extract \
      --tokens $((CTX + S)) --chunk $S --layers \$group --spec $SPEC \
      --residual-stream --diagonal-block --slim --slim-num "\$@" \$IDSARG \
      --blocks $BLOCK --share \$WIT/shared --out \$WIT/witness )
  T1=\$(date +%s)
  printf '{"pass": "%s", "layers": "%s", "device": "cuda", "threads": %d, "seconds": %d}\n' \
      "\$tag" "\$group" $XTHREADS \$((T1 - T0)) > \$WIT/extract_\$tag.json
  st "extract: layers \$group done in \$((T1 - T0))s"
}
xpass l0 0 0 --embed
xpass l1 1,2,3,4,5,6,7 7
xpass l2 8,9,10,11,12,13,14,15 15
xpass l3 16,17,18,19,20,21,22,23 23
xpass l4 24,25,26,27,28,29,30,31 31
if [ ! -f \$WIT/shapes_B$BLOCK.json ]; then
  st "shapes"
  ( cd \$HSRC && \$PY -m harness.witness.shapes \$WIT/witness_B${BLOCK}_L $NLAY \$WIT/shapes_B$BLOCK.json )
fi
python3 - \$WIT \$OUT/extract.json <<'PY'
import glob, json, os, sys
wit, out = sys.argv[1], sys.argv[2]
rows = [json.load(open(f)) for f in sorted(glob.glob(os.path.join(wit, "extract_*.json")))]
json.dump({"passes": rows, "seconds": sum(r["seconds"] for r in rows)}, open(out, "w"), indent=1)
print("extract:", sum(r["seconds"] for r in rows), "s over", len(rows), "passes")
PY
cp \$WIT/shapes_B$BLOCK.json \$OUT/shapes.json

# 3c. what one block of this block length costs on disk, measured rather than
#     estimated: a plan at this S is $NBLOCK of these plus the shared files, and
#     whether that fits a host is decided from this number.
python3 - \$WIT $BLOCK $NLAY \$OUT/disk.json <<'PY'
import json, os, shutil, sys
wit, b, nlay, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
def tree(p):
    n = 0
    for root, _, files in os.walk(p):
        for f in files:
            q = os.path.join(root, f)
            if not os.path.islink(q):
                n += os.path.getsize(q)
    return n
block = sum(tree(os.path.join(wit, f"witness_B{b}_L{k}")) for k in range(nlay))
shared = tree(os.path.join(wit, "shared")) if os.path.isdir(os.path.join(wit, "shared")) else 0
du = shutil.disk_usage(wit)
json.dump({"block": b, "block_bytes": block, "shared_bytes": shared,
           "filesystem_free_bytes": du.free, "filesystem_total_bytes": du.total},
          open(out, "w"), indent=1)
print(f"disk: block {b} is {block / 2**30:.1f} GiB, shared {shared / 2**30:.1f} GiB, "
      f"{du.free / 2**30:.1f} GiB free")
PY

# 4. the witness-calibrated fields of every dump of this block, read off the
#    dumps and never assumed: the master exponent table this block's keys ask
#    for, the normalisation window, the attention output's five widths and the
#    fold's pins.  They are properties of the forward pass and are fixed before
#    any proof exists, which is what lets the counted side below stand beside a
#    measurement rather than after it.
st "fields"
( cd \$HSRC && \$PY -m harness.eval.predict.witness_fields --dir \$WIT/witness_B$BLOCK \
    --layers $NLAY --numbits 9 --tight-table --head-groups $HEAD_GROUPS \
    --out \$OUT/witness_fields.json )

# 5. the plan: block $BLOCK's layer segments, no output head.  --blocks auto
#    reads the shape tables on this host, which is this one block; --layers is
#    what this block length proves, so the plan has exactly the lines the loop
#    below runs and the emit set is exactly their shapes.  The loop's pins are
#    taken over every row of the shape table, which is all $NLAY layers, because
#    that is the pin a plan at this block length would be proved at.
PINS=\$(python3 - \$WIT/shapes_B$BLOCK.json <<'PY'
import json, sys
w = json.load(open(sys.argv[1]))["worst"]
print(f"--kmax {w['kmax']} --ao-rem-bits {w['ao_rem_bits']} --fold-rem-bits {w['fold_rem_bits']} --fold-alpha {w['fold_alpha']}")
PY
)
st "pins: \$PINS"
( cd \$HSRC && \$PY -m harness.witness.plan --dir \$WIT --blocks auto --with-block-0 --layers $PLAN_LAYERS \
    --layer-flags="$LAYER_FLAGS" --l0-flags="$L0_FLAGS" --l0-dir \$WIT \
    --out \$OUT/plan.txt --emit-out \$R/emit.txt )
N=\$(grep -cv '^#' \$OUT/plan.txt)
st "plan: \$N segments of block $BLOCK at S=$S"
[ \$N -eq $NPROVE ] || { st "the plan has \$N segments and this run proves $NPROVE"; exit 3; }

# 6. the device kernels for every shape in the plan, compiled into the CUDA
#    backend.  Without them the CUDA backend evaluates constraints on the host
#    and the seconds are not the card's; the gate below fails the run on any
#    announced fallback line.
K=\$SRC/prover/kernels
[ -d \$K ] || { st "no prover/kernels in this prover commit; the CUDA backend would evaluate constraints on the CPU"; exit 3; }
EMITSUM=\$(sha256sum \$R/emit.txt | cut -c1-16)
if [ "\$(cat \$R/kernels.done 2>/dev/null)" != "\$EMITSUM" ]; then
  while read -r line; do
    case "\$line" in '#'*|'') continue ;; esac
    args=\$(printf '%s\n' "\$line" | sed 's/--ser-tag [A-Za-z0-9_]*//')
    for emit in cudaemit genemit; do
      case \$emit in
        cudaemit) opts="--block 256 --min-blocks 2" ;;
        genemit)  opts="--families $KERNEL_FAMILIES" ;;
      esac
      # A refused lowering is recorded and never fatal here: a kernel is looked
      # up by fingerprint and the plan's shapes share theirs, so what a refusal
      # costs is either nothing or an announced fallback line, and the gate
      # fails the run on one of those.
      if ! \$SIMD \$emit $SHARED \$PINS \$args \$opts --out \$GEN > /dev/null; then
        printf '%s\n' "\$line" >> \$OUT/\$emit-refused.txt
        st "\$emit refused a shape (zk-prover #57); recorded in out/\$emit-refused.txt"
      fi
    done
  done < \$R/emit.txt
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

# 7. the counted side, at this block length and over these very segments.
#    harness.eval.predict.predict.exact_segments is what --cells exact counts a
#    registration with; its seq argument is the block length, and predict.py's
#    own command line has no such argument -- its S is the module's 512 -- so
#    the count is made here, by calling it.  It reads the fields file above, the
#    model's published seven numbers out of cost_model.LLAMA8B, and this run's
#    head grouping; it opens no card, makes no proof and reads no measurement.
#    It is written BEFORE the loop runs, so what it says is not a function of
#    what the loop reports.
if [ ! -s \$OUT/predicted.json ]; then
  st "counted: the trace layout at S=$S over the segments this run proves"
  ( cd \$HSRC && \$PY - \$OUT/witness_fields.json \$OUT/predicted.json $CTX $S "$PLAN_LAYERS" "$HARNESS" <<'PY'
import json, sys
from harness.costmodel import cost_model as cm
from harness.eval.predict import predict as P
from harness.eval.predict import witness_fields as wf
src, out, ctx, seq, spec, commit = sys.argv[1:7]
ctx, seq = int(ctx), int(seq)
want = []
for part in spec.split(","):
    if "-" in part:
        lo, hi = part.split("-")
        want.extend(range(int(lo), int(hi) + 1))
    else:
        want.append(int(part))
fields = wf.load(src)
groups = (fields.get("knobs") or {}).get("head_groups")
rows = P.exact_segments(cm.LLAMA8B, ctx, fields, seq=seq, head_groups=groups)
mine = [r for r in rows if r["layer"] in want]
assert len(mine) == len(want), f"counted {len(mine)} of the {len(want)} segments this run proves"
total = sum(r["fresh"] for r in mine)
json.dump({"shape": "Llama-3.1-8B", "cfg": list(cm.LLAMA8B), "context": ctx, "s": seq,
           "head_groups": groups, "counted_at": commit, "layers_proved": want,
           "layers": [{k: r[k] for k in ("layer", "kind", "fresh", "base", "interaction",
                                         "boundary", "bound_fresh", "table_rows",
                                         "dump_sha256")} for r in mine],
           "segments": len(mine), "fresh_sum": total,
           "fresh_per_segment": total / len(mine),
           "fresh_per_position": total / seq,
           "note": "The prover's trace layout, counted segment by segment at this block "
                   "length, each segment at the witness-calibrated fields its own dump "
                   "carries (witness_fields.json, whose per-layer dump_sha256 name the "
                   "dumps). harness.eval.predict.predict.exact_segments at seq = s, which "
                   "is what predict.py --cells exact counts a registration with; its "
                   "command line takes no block length. No card, no proof, no measurement: "
                   "written before the segment loop ran. fresh_sum and fresh_per_position "
                   "are over the segments THIS RUN PROVES and not over the stack: the "
                   "block's layer segments where the whole block is proved, and the one "
                   "segment where one is."},
          open(out, "w"), indent=1)
print(f"counted: {len(mine)} segment(s), {total:,} fresh cells, {total / seq:,.0f} a position")
PY
)
fi

# 8. the card loop: the plan's $NPROVE segment(s) in one process, at ZK_PIPELINE
#    $PIPELINE, the card sampled once a second.  It is NOT allowed to stop the
#    job: a loop that does not fit the card is this run's answer and not its
#    failure, so the exit code, the samples and the last lines of stderr are
#    recorded and the job carries on to the anchor below.
if [ ! -s \$OUT/mem_card.json ]; then
  st "card: ZK_PIPELINE=$PIPELINE over the plan's \$N segment(s)"
  rm -f \$R/card.mem
  ( while true; do echo "\$(date +%s) \$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)" >> \$R/card.mem; sleep $SAMPLE_S; done ) & sampler=\$!
  T0=\$(date +%s); rc=0
  ZK_PIPELINE=$PIPELINE \$CUDA compose-chunks $SHARED \$PINS --plan \$OUT/plan.txt --ser-dir \$SER \
      > \$OUT/card.json 2> \$R/card.err || rc=\$?
  T1=\$(date +%s)
  kill \$sampler 2>/dev/null || true
  [ \$rc -eq 0 ] || rm -f \$OUT/card.json
  grep -c 'kernel fallback:' \$R/card.err > \$OUT/card.fallbacks || true
  tail -c 2000 \$R/card.err > \$R/card.tail
  python3 - \$R/card.mem \$R/card.tail \$OUT/mem_card.json \$rc \$((T1 - T0)) $SAMPLE_S \$TOTAL_MIB <<'PY'
import json, os, sys
mem, tail, out, rc, secs, period, total = sys.argv[1:8]
v = ([int(l.split()[1]) for l in open(mem) if len(l.split()) == 2 and l.split()[1].isdigit()]
     if os.path.exists(mem) else [])
t = open(tail, errors="replace").read()
oom = any(w in t.lower() for w in ("out of memory", "cudaerrormemoryallocation",
                                   "cuda_error_out_of_memory"))
json.dump({"exit_code": int(rc), "loop_secs": int(secs), "samples": len(v),
           "period_s": float(period), "max_mib": max(v, default=0),
           "last_mib": v[-1] if v else 0,
           "mean_mib": round(sum(v) / len(v), 1) if v else 0,
           "card_total_mib": int(total), "out_of_memory": bool(oom),
           "stderr_tail": t[-600:] if int(rc) else "",
           "note": "The card sampled once a period while the segment loop ran. max_mib is "
                   "the largest sample, last_mib the sample before the process left -- "
                   "which is what a loop that ran out of memory has instead of a peak, "
                   "because the allocation that failed was never held."},
          open(out, "w"), indent=1)
print(f"card: exit {rc}, {secs}s, peak {max(v, default=0)} MiB of {total} MiB, "
      f"last sample {v[-1] if v else 0} MiB" + (", out of memory" if oom else ""))
PY
fi

# 9. the same segment on the reference backend, which proves in host memory and
#    cannot run the card out of it.  Two reasons it is here and not optional.
#    It is the run's provenance anchor: the manifest is copied from a prover's
#    provenance block and refuses a fetched directory that has none, and a loop
#    the card could not hold writes no output at all, so without this the answer
#    most worth recording -- that it does not fit -- could not be recorded.  And
#    where the card did prove that segment it is a digest gate: a STARK proof is
#    deterministic once the trace and the parameters are fixed, so the two
#    backends must agree byte for byte.
REF_SLICE=\$(python3 - \$OUT/plan.txt $REF_LAYER <<'PY'
import sys
tags = [l.split("--ser-tag ")[1].split()[0] for l in open(sys.argv[1])
        if not l.startswith("#") and "--ser-tag " in l]
want = f"L{sys.argv[2]}"
i = [k for k, t in enumerate(tags) if t.endswith(want)]
assert len(i) == 1, f"the plan names {len(i)} segments ending {want}: {tags}"
print(f"{i[0]}:{i[0] + 1}")
PY
)
if [ ! -s \$OUT/reference-simd.json ]; then
  st "reference backend: plan segment \$REF_SLICE, in host memory"
  T0=\$(date +%s)
  if \$SIMD compose-chunks $SHARED \$PINS --plan \$OUT/plan.txt --plan-slice \$REF_SLICE \
      --ser-dir \$R/ser-ref > \$OUT/reference-simd.json 2> \$R/reference-simd.err; then
    st "reference backend done in \$(( \$(date +%s) - T0 ))s"
  else
    rm -f \$OUT/reference-simd.json
    tail -c 2000 \$R/reference-simd.err > \$OUT/reference-refused.txt
    st "the reference backend did not prove the segment; the last of its stderr is in out/reference-refused.txt"
  fi
fi
rm -rf \$SER \$R/ser-ref

# 10. the answer, from the run's own outputs, and the gate.  An out-of-memory is
#     not a failure here; a proof that was made and is not sound is.
python3 - \$OUT $S $NPROVE $REF_LAYER <<'PY'
import json, pathlib, statistics, sys
out, s, want, ref_layer = pathlib.Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
bad = []
m = json.loads((out / "mem_card.json").read_text())
pred = json.loads((out / "predicted.json").read_text())
card = out / "card.json"
row = {"s": s, "segments_asked_for": want, "proved": card.exists(),
       "peak_mib": m["max_mib"], "last_mib": m["last_mib"],
       "card_total_mib": m["card_total_mib"], "out_of_memory": m["out_of_memory"],
       "exit_code": m["exit_code"], "counted_fresh": pred["fresh_sum"],
       "counted_per_position": pred["fresh_per_position"]}
if card.exists():
    doc = json.loads(card.read_text())
    p, sm = doc["provenance"], doc["result"]["summary"]
    chunks = doc["result"]["chunks"]
    ser = [c["proof_ser_bytes"] for c in chunks]
    inmem = [c["proof_bytes"] for c in chunks]
    row.update(segments=sm["n"], fresh=sm["fresh_sum"],
               fresh_per_segment=sm["fresh_sum"] / sm["n"],
               fresh_per_position=sm["fresh_sum"] / s,
               secs={"commit": sm["commit_sum"], "stwo_total": sm["stwo_sum"],
                     "whole_wall": sm["whole_sum"], "loop": sm["loop_secs"]},
               secs_per_segment={"commit": sm["commit_sum"] / sm["n"],
                                 "stwo_total": sm["stwo_sum"] / sm["n"],
                                 "whole_wall": sm["whole_sum"] / sm["n"],
                                 "loop": sm["loop_secs"] / sm["n"]},
               proof_ser_bytes_median=statistics.median(ser),
               proof_ser_bytes_total=sum(ser),
               proof_bytes_median=statistics.median(inmem),
               rho=sm["fresh_sum"] / pred["fresh_sum"],
               peak_mib_pct_of_card=round(100 * m["max_mib"] / m["card_total_mib"], 1),
               digests=[c.get("proof_sha256") for c in chunks])
    print(f"card: {sm['n']} segments, loop {sm['loop_secs']:.1f} s, "
          f"fresh {sm['fresh_sum']:,.0f} cells, counted {pred['fresh_sum']:,.0f}, "
          f"measured over counted {row['rho']:.6f}")
    print(f"card: commit {sm['commit_sum']:.1f} s, stwo {sm['stwo_sum']:.1f} s, "
          f"whole-clock {sm['whole_sum']:.1f} s; median proof {statistics.median(ser):,} bytes; "
          f"peak {m['max_mib']} MiB of {m['card_total_mib']} ({row['peak_mib_pct_of_card']}%)")
    if sm["n"] != want:
        bad.append(f"the loop proved {sm['n']} segments and the plan has {want}")
    for c in chunks:
        if not c["accepts"]:
            bad.append(f"segment {c['ser_tag']}: the proof was rejected, "
                       f"prove_error {c.get('prove_error')}")
        for field in ("off_table", "ref_mismatch"):
            if c.get(field):
                bad.append(f"segment {c['ser_tag']}: {field} is {c[field]}")
    if p["unsound_skips"]:
        bad.append(f"unsound skips in effect: {p['unsound_skips']}")
    if not p["binding"]["all_bound"]:
        bad.append(f"unbound edges {p['binding']['unbound']}")
    k = int((out / "card.fallbacks").read_text().strip())
    if k:
        bad.append(f"{k} kernel fallback lines, so constraints were evaluated on the host "
                   "and the seconds are not the card's")
else:
    print(f"card: no proof. exit {m['exit_code']}, peak {m['max_mib']} MiB of "
          f"{m['card_total_mib']} MiB, last sample {m['last_mib']} MiB"
          + (", out of memory" if m["out_of_memory"] else ""))
    if not m["out_of_memory"]:
        bad.append(f"the loop wrote no output and its stderr does not name an "
                   f"out-of-memory: {m['stderr_tail'][-300:]!r}")
ref = out / "reference-simd.json"
if ref.exists():
    d = json.loads(ref.read_text())
    rp, rs = d["provenance"], d["result"]["summary"]
    rc = d["result"]["chunks"][0]
    row["reference"] = {"backend": rp["backend"], "segment": rc["ser_tag"],
                        "fresh": rs["fresh_sum"], "loop_secs": rs["loop_secs"],
                        "proof_sha256": rc.get("proof_sha256"),
                        "unsound_skips": rp["unsound_skips"],
                        "all_bound": rp["binding"]["all_bound"]}
    print(f"reference backend: {rc['ser_tag']}, {rs['fresh_sum']:,.0f} cells, "
          f"{rs['loop_secs']:.1f} s, digest {str(rc.get('proof_sha256'))[:16]}")
    if not rc["accepts"]:
        bad.append(f"reference backend: segment {rc['ser_tag']} was rejected, "
                   f"prove_error {rc.get('prove_error')}")
    if rp["unsound_skips"]:
        bad.append(f"reference backend: unsound skips in effect {rp['unsound_skips']}")
    if not rp["binding"]["all_bound"]:
        bad.append(f"reference backend: unbound edges {rp['binding']['unbound']}")
    if card.exists():
        same = [c for c in json.loads(card.read_text())["result"]["chunks"]
                if c["ser_tag"] == rc["ser_tag"]]
        if same and same[0].get("proof_sha256") != rc.get("proof_sha256"):
            bad.append(f"segment {rc['ser_tag']} hashes to "
                       f"{same[0].get('proof_sha256')} on the card and "
                       f"{rc.get('proof_sha256')} on the reference backend")
        elif same:
            print(f"digests: the two backends agree on {rc['ser_tag']}")
            row["backends_agree"] = True
else:
    bad.append("the reference backend proved nothing, so this run has no provenance "
               "anchor and cannot be recorded")
json.dump(row, open(out / "summary.json", "w"), indent=1)
if bad:
    sys.exit("; ".join(bad))
print("no skip; every edge bound; no kernel fallback")
PY
st "done"
JOBEOF
drv_start "$JOB"
rm -f "$JOB"
