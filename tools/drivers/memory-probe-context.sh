#!/bin/sh
# memory-probe-context: is the memory line through the two headline peaks straight?
#
#   tools/drivers/memory-probe-context.sh <host> <prover-commit> <harness-commit> <context>
#
# The two measured peaks -- 73,723 MiB at context 4,096 and 78,799 at 16,384, on
# a card of 81,559 -- are a line, and issue #115 reads three rows off it:
# `mem.projected.c32768.peak_mib`, `mem.projected.c131072.peak_mib` and
# `mem.projected.context_at_card_limit`, which says one card is full at a context
# of about 23,065.  Two points cannot show that a line is straight.  This driver
# is the third point: two segments of one token block at a context it is told,
# proved on the card with the pipeline off, with the card sampled once a second
# and each peak recorded.  The contexts issue #115 asks for are 24,576 and
# 32,768.
#
# It is `memory-probe-c16384.sh` with the context as an argument and two segments
# instead of six.  Everything that decides what is measured is copied from that
# driver line for line -- the shared flags, the five reductions, `--tight-table`,
# the extraction of the last block alone, the pins off that block's shape table
# -- because a probe whose configuration differs from the headline's answers a
# question about a loop nobody runs.  What differs:
#
#   * The context is an argument, so the run name and the run id carry it:
#     `memory-probe-c24576`, `runs/<date>-memory-probe-c24576-<gpu>`.  The
#     manifest names this file, which is the driver that made it.
#   * Two segments of that block, one at a time, each in its own process, and
#     neither a loop.  The first is layer 16, the reference layer -- the one
#     `reference-digest.sh` and `reference-digest-plain.sh` prove -- whose shape
#     is the shape 1,023 of the headline plan's 1,056 segments have.  The second
#     is layer 0, which carries the embedding gadget and is the plan's largest
#     segment.
#
#     Both, because the two answer different halves of the question.  The rows
#     issue #115 projects are a line through the headline loops' peaks, and at
#     16,384 that peak is 78,799 MiB where layer 0 on its own peaked 78,843 and
#     the common shape peaked 72,379: the headline peak is layer 0's segment, so
#     only a layer-0 measurement can be laid beside `mem.projected.c32768.peak_mib`
#     as the same quantity.  Layer 16 is the other half -- the shape almost every
#     segment has, and the one with a measured 16,384-token point to take a slope
#     against.
#
#     Layer 16 is proved first and layer 0 last, which is the order
#     `memory-probe-c16384.sh` gives them and for its reason: the line the
#     projection draws puts layer 0 above this card at both contexts this driver
#     is written for, so measured last a layer-0 failure costs the other
#     measurement nothing, and measured first it would cost the whole probe.
#   * The pipeline is off.  The headline loop runs with it on, and at 16,384 the
#     probe measured the same peak either way, so the cheaper of the two is what
#     a point on the line needs.
#
# A segment that does not fit is the answer and not a failure.  Its exit code,
# the last sample the card returned and the last 600 bytes of its stderr are
# recorded, the next segment is still proved, the reference backend then proves
# layer 16 in host memory, and the fetch records all of it: the run's provenance
# comes from that proof, so a card that ran out of memory still leaves a run
# directory with the number in it.  That is the whole reason the reference
# segment is here and is not optional.
#
# Two things this driver will find out and nothing in this repository can
# predict.  The attention output's no-wrap window and its quotient term are
# evaluated per shape at plan time (`harness/witness/shapes.py`), and the
# recorded 4,096- and 16,384-token sets both sit at `11 + 20 = 31` of 31 on the
# quotient half, which admits nothing wider: if this context's dumps need one
# bit more, `plan.py` refuses the pin with the numbers and names
# `--ao-rem-per-line` as what is left, and no segment is proved.  That refusal is
# a result worth having and it costs the extraction to get; it is not worked
# around here, because proving the segment at a narrower pin than the headline's
# would measure a different statement under the same name.
#
# The first call pushes zk-prover at the two commits to the host, starts the job
# detached and prints the poll command.  Every later call with the same
# arguments prints the status; once the status says done it fetches the outputs
# into runs/<run-id>/, writes manifest.json from the prover's provenance block,
# and runs check.py.  Nothing measured is typed in here.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
HOST=${1:?host alias}; PROVER=${2:?prover commit}; HARNESS=${3:?harness commit}
CTX=${4:?context, e.g. 24576 or 32768}
ZK_PROVER=${ZK_PROVER_DIR:-$ROOT/../zk-prover}     # a local clone to archive the commits from

# ---- the configuration: the headline driver's, and the probe's own ----------
LABEL=probe                # neither a headline nor a control: a memory measurement
MODEL=${ZK_MODEL:-unsloth/Llama-3.1-8B-Instruct}
SPEC=y-delay-vw12          # the quantization variant the paper reports (docs/decisions)
S=512
# The context decides the run name, so the two probes issue #115 asks for are two
# runs and two run directories rather than one name measured twice.  It is
# checked here and not on the host: a context that is not a whole number of
# blocks has no last block, and the extractor's own refusal would come an hour
# in.
case "$CTX" in ''|*[!0-9]*) echo "$0: context must be a whole number of tokens, not '$CTX'" >&2; exit 2 ;; esac
[ "$CTX" -gt 0 ] && [ $((CTX % S)) -eq 0 ] ||
  { echo "$0: context $CTX is not a whole number of $S-token blocks" >&2; exit 2; }
NAME=memory-probe-c$CTX
DRV_DRIVER=memory-probe-context   # the file, where the run name carries the context
. "$HERE/lib/driver.sh"

NBLOCK=$(( (CTX + S) / S ))  # the prompt's blocks and the output block
NLAY=32
SHARED="--round even --numbits 9 --z-hi-bits 7 --variants intexp --head-groups 16,8,8 --tight-table"
GKR="--gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
LAYER_FLAGS="--round even --diagonal-block $GKR"   # every binding gadget is on by default; no skip flag anywhere
L0_FLAGS=""
OFFSET=0                   # the corpus from its first token, as the headline reads it
XTHREADS=20                # torch threads for the extraction
# How many jobs the two cargo builds and the rebuild after the kernel install may
# run at once.  It is not a speed knob.  A rented host can be a container whose
# memory cap is nothing like what `free` reports -- this campaign's was capped at
# 128 GiB by its cgroup while `free` showed 1.5 TB -- and after the generated
# constraint kernels are installed some of the translation units the rebuild
# compiles are megabytes of generated CUDA.
#
# It is only half a cap, and the driver says so rather than implying otherwise:
# `CARGO_BUILD_JOBS` bounds rustc, while the vendored library's build script
# asks cmake for sixteen jobs on its own command line, which neither
# `CMAKE_BUILD_PARALLEL_LEVEL` nor `MAKEFLAGS` overrides (zk-prover #190).  Both
# are set below all the same: they cost nothing and they work the day that
# script reads the environment.
CARGO_JOBS=${ZK_CARGO_JOBS:-4}
IDS=${ZK_IDS:-}            # token ids (.npy) already on the host; empty = generate them
KERNEL_FAMILIES=zk_chan_eval,zk_key_eval,zk_row_eval,zk_attn_out_eval,zk_dequant_eval,zk_freivalds_eval,zk_exp_table_eval,zk_table_eval,zk_residual_stream_eval,zk_residual_stream_table_eval
# The block the probe extracts and the two segments it proves.  The last block
# reads the longest prefix and therefore holds the plan's largest segments, so it
# is the block that sets the loop's peak.  All 32 of its layers are extracted and
# two of them are proved: the shape table is built over the whole block and the
# pins the segments are proved at are that block's worst case, which is the pin
# the headline loop would be launched with.  A plan pinned from one layer's own
# row would prove a narrower statement than the headline's and peak lower for
# that reason alone.
PROBE_BLOCK=$(( NBLOCK - 1 ))
PROBE_LAYER=16             # the reference layer; its shape is the plan's common one
PROBE_SLICE=$PROBE_LAYER:$(( PROBE_LAYER + 1 ))
PROBE_L0_SLICE=0:1         # layer 0 alone, the segment the headline's peak is
PIPELINE=0                 # the headline runs pipelined; at 16,384 the peak was the same either way

drv_finish "$(drv_status)"

# ---- the host's one job at a time -------------------------------------------
# `run.sh` takes the lock and refuses a busy host, but only after the two pushes
# and after this driver has spent minutes archiving commits.  A probe is hours
# long and the card is rented, so the refusal is made first, by name, with who
# holds it.  This is on the start path alone: the status file above has already
# answered for a job of this name that is running or done.
HELD=$(ssh -o BatchMode=yes "$HOST" "cat \$HOME/.zk-run.lock 2>/dev/null || true")
[ -z "$HELD" ] || {
    echo "$NAME: $HOST is busy and nothing was pushed: $HELD" >&2
    echo "one run per host: wait for that job to finish, then run this command again" >&2
    exit 1
}

# ---- start: push the pinned sources, then the job ----------------------------
drv_check_commits
BUILD=$(drv_build_root)
drv_push "$BUILD/src" "$PROVER"
drv_push "$BUILD/harness-src" "$HARNESS"

JOB=$(mktemp)
cat > "$JOB" <<JOBEOF
#!/bin/sh
# generated by memory-probe-context.sh for context $CTX; runs on the host under tools/remote/run.sh
set -eu
B=\$HOME/$BUILD
R=\$HOME/runs/$NAME
SRC=\$B/src; HSRC=\$B/harness-src/harness; GEN=\$B/gen
OUT=\$R/out
WIT=\$HOME/witness/$(printf '%.12s' "$HARNESS")/$SPEC-c$CTX-probe-b$PROBE_BLOCK
# A directory of its own, keyed by the context: two probes at two contexts share
# the build tree and the kernel store and nothing else, because a block of one
# is not a block of the other.
mkdir -p \$OUT \$GEN \$WIT
$(drv_job_preamble)
export RAYON_NUM_THREADS=\${RAYON_NUM_THREADS:-16} ZK_KERNEL_STORE=\$GEN
PY="uv run --project \$HSRC \$UVG python"

cat > \$OUT/config.json <<CFG
{"driver": "memory-probe-context", "label": "$LABEL",
 "model": "$MODEL", "spec": "$SPEC",
 "context": $CTX, "s": $S, "positions": $((CTX + S)), "blocks": $NBLOCK, "layers": $NLAY,
 "probe_block": $PROBE_BLOCK, "probe_layer": $PROBE_LAYER, "probe_segments": 1,
 "probe_slice": "$PROBE_SLICE", "probe_layer0_slice": "$PROBE_L0_SLICE",
 "pipeline": $PIPELINE, "cargo_jobs": $CARGO_JOBS,
 "shared_flags": "$SHARED", "layer_flags": "$LAYER_FLAGS", "layer0_flags": "$L0_FLAGS",
 "ids": "${IDS:-generated: the corpus's tokens $OFFSET to $((OFFSET + CTX)) and the model's own greedy continuation under $SPEC}",
 "corpus_offset": $OFFSET}
CFG

st "gpu: \$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader)"
st "nvcc: \$(nvcc --version | tail -2 | head -1)"

# 1. the harness at its pinned commit.  It comes before the prover build, and the
#    two ids steps come before it too: this context's prompt is longer than any
#    this repository has read, and a corpus that cannot supply it is a refusal
#    worth having in two minutes rather than after an hour of cargo.
( cd \$HSRC && uv sync --frozen \$UVG )

# 2. the statement's tokens, exactly as the headline driver generates them, so
#    the probe reads the block a headline run at this context would read.
IDSFILE="$IDS"
if [ -z "\$IDSFILE" ]; then
  IDSFILE=\$WIT/ids.npy
  if [ ! -f \$IDSFILE ]; then
    st "ids: greedy continuation, $SPEC, corpus offset $OFFSET, prompt $CTX tokens"
    cat > \$R/gen_ids_shim.py <<'SHIM'
"""gen_ids, with the three limits a prompt of this length runs into lifted.

zk-prover #51: gen_ids imports the bare name ppl where every other caller of
that function writes the submodule, so running it with -m stops at the import.
Binding the name to the submodule changes nothing else.

zk-prover #187, both halves:

  * common.tokens cuts the eval corpus at 40 chunks, 20,480 tokens, so no prompt
    longer than that can be generated at all -- and the probe wants 24,576 and
    32,768.  ZK_EVAL_TOKENS is how many tokens of the same window of the same
    corpus to keep instead.  The window into the text does not move, so the
    tokens every earlier campaign read are a prefix of these, and the shim
    checks that rather than assuming it: a prompt that is not an extension of
    the 16,384-token one is a different prompt and the line through the peaks
    would not be one line.
  * gen_ids asserts the prefix is a power of two, which 24,576 is not.  What the
    extractor needs is that the prefix is a whole number of prefill chunks, and
    the line below that one already asserts exactly that, so the power-of-two
    line becomes a positivity check and nothing else changes.

The cache the wider slice is written to is keyed by its length, so the file
every other caller of tokens() reads is untouched and no other run on this host
sees a different eval set.
"""
import os
import sys

import numpy as np
import torch

import harness.witness.common as common
import harness.witness.ppl

sys.modules.setdefault("ppl", harness.witness.ppl)

NEED = int(os.environ["ZK_EVAL_TOKENS"])
_narrow = common.tokens


def tokens():
    """The eval and calibration slices, with the eval one cut at NEED tokens."""
    cache = os.path.join(common.OUT, f"tokens_{NEED}.npz")
    if not os.path.exists(cache):
        from transformers import AutoTokenizer
        tok = AutoTokenizer.from_pretrained(common.MODEL)
        text = open(common.TEXT, encoding="utf-8").read()
        ev = np.array(tok(text[10_000:200_000]).input_ids[:NEED], dtype=np.int64)
        if len(ev) < NEED:
            sys.exit(f"the corpus window tokenizes to {len(ev)} tokens and this prompt "
                     f"needs {NEED}; a longer window is a decision, not a default")
        cal = np.array(tok(text[400_000:440_000]).input_ids[:4 * common.CHUNK],
                       dtype=np.int64)
        np.savez(cache, eval=ev, calib=cal)
    z = np.load(cache)
    ev, cal = torch.from_numpy(z["eval"]), torch.from_numpy(z["calib"])
    old, oldcal = _narrow()
    if not bool((ev[:len(old)] == old).all()) or not bool((cal == oldcal).all()):
        sys.exit("the wider eval slice is not an extension of the one the recorded "
                 "campaigns read; this prompt would be a different prompt")
    return ev, cal


common.tokens = tokens
harness.witness.ppl.tokens = tokens

import harness.witness.gen_ids as G  # noqa: E402

G.tokens = tokens
POW2 = ('    assert a.prefix > 0 and (a.prefix & (a.prefix - 1)) == 0, '
        '"prefix must be a power of two"\n')
KEEP = '    assert a.prefix > 0, "prefix must be positive"\n'
src = open(G.__file__, encoding="utf-8").read()
if POW2 not in src:
    sys.exit("gen_ids.py no longer holds the power-of-two line this shim replaces; "
             "read it and zk-prover #187 before changing this")
g = dict(G.__dict__)
g["__name__"] = "__main__"
exec(compile(src.replace(POW2, KEEP), G.__file__, "exec"), g)
SHIM
    GENIDS="ZK_MODEL=$MODEL ZK_DEVICE=cuda ZK_THREADS=$XTHREADS ZK_EVAL_TOKENS=$((OFFSET + CTX))"
    ( cd \$HSRC && env \$GENIDS \$PY \$R/gen_ids_shim.py --prefix $CTX --offset $OFFSET --new 513 --spec $SPEC --out \$WIT/ids_513.npy )
    ( cd \$HSRC && env \$GENIDS \$PY \$R/gen_ids_shim.py --prefix $CTX --offset $OFFSET --new $S --spec $SPEC --out \$WIT/ids_512.npy )
    ( cd \$HSRC && \$PY -m harness.witness.shift_ids --ids \$WIT/ids_513.npy --prefix $CTX --new $S --out \$IDSFILE )
    ( cd \$HSRC && \$PY -c "
import numpy as np
a, b = np.load('\$WIT/ids_512.npy'), np.load('\$WIT/ids_513.npy')
assert (a == b[:len(a)]).all(), 'greedy decoding is deterministic; the 512- and 513-token runs must agree'
print('ids: determinism check passed', len(a), 'tokens')" )
  fi
fi
IDSARG="--ids \$IDSFILE"

# 3. both backends of the pinned prover commit
st "build"
( cd \$SRC && CARGO_TARGET_DIR=\$B/t-simd CARGO_BUILD_JOBS=$CARGO_JOBS cargo build --release --locked )
( cd \$SRC && CARGO_TARGET_DIR=\$B/t-cuda CARGO_BUILD_JOBS=$CARGO_JOBS cargo build --release --locked -p zk-prover --features cuda )
SIMD=\$B/t-simd/release/zk-prover; CUDA=\$B/t-cuda/release/zk-prover

# 4. block $PROBE_BLOCK's witnesses.  The forward pass is the whole sequence
#    either way -- a block reads the keys and values of every block before it --
#    but only this block's dumps are written, which is what makes the probe
#    affordable on disk where the whole plan's extraction is not.  Layer 0 is a
#    pass of its own because --embed writes the embedding table into every dump
#    of the pass it is given.  All 32 layers are extracted although one is
#    proved: the pins come from the whole block's shape table.
xpass() {   # xpass <tag> <layers> <last layer of the group> <extra flags>
  tag=\$1; group=\$2; last=\$3; shift 3
  [ ! -f \$WIT/witness_B${PROBE_BLOCK}_L\${last}/manifest.json ] || { st "extract: layers \$group are on this host"; return 0; }
  st "extract: layers \$group, block $PROBE_BLOCK of $NBLOCK, C=$CTX, $SPEC"
  T0=\$(date +%s)
  ( cd \$HSRC && ZK_MODEL=$MODEL ZK_DEVICE=cuda ZK_THREADS=$XTHREADS \$PY -m harness.witness.extract \
      --tokens $((CTX + S)) --chunk $S --layers \$group --spec $SPEC \
      --residual-stream --diagonal-block --slim --slim-num "\$@" \$IDSARG \
      --blocks $PROBE_BLOCK --share \$WIT/shared --out \$WIT/witness )
  T1=\$(date +%s)
  printf '{"pass": "%s", "layers": "%s", "device": "cuda", "threads": %d, "seconds": %d}\n' \
      "\$tag" "\$group" $XTHREADS \$((T1 - T0)) > \$WIT/extract_\$tag.json
  st "extract: layers \$group done in \$((T1 - T0))s"
}
# zk-prover #55: a one-layer extraction writes <base>_B<b> where the shape table
# and the plan both read <base>_B<b>_L<k>, so layer 0's dump is moved into the
# name the next two steps look for.  Only the directory moves; no dump changes.
xpass l0 0 0 --embed
[ ! -d \$WIT/witness_B$PROBE_BLOCK ] || mv \$WIT/witness_B$PROBE_BLOCK \$WIT/witness_B${PROBE_BLOCK}_L0
xpass l1 1,2,3,4,5,6,7 7
xpass l2 8,9,10,11,12,13,14,15 15
xpass l3 16,17,18,19,20,21,22,23 23
xpass l4 24,25,26,27,28,29,30,31 31
if [ ! -f \$WIT/shapes_B$PROBE_BLOCK.json ]; then
  st "shapes"
  ( cd \$HSRC && \$PY -m harness.witness.shapes \$WIT/witness_B${PROBE_BLOCK}_L $NLAY \$WIT/shapes_B$PROBE_BLOCK.json )
fi
python3 - \$WIT \$OUT/extract.json <<'PY'
import glob, json, os, sys
wit, out = sys.argv[1], sys.argv[2]
rows = [json.load(open(f)) for f in sorted(glob.glob(os.path.join(wit, "extract_*.json")))]
json.dump({"passes": rows, "seconds": sum(r["seconds"] for r in rows)}, open(out, "w"), indent=1)
print("extract:", sum(r["seconds"] for r in rows), "s over", len(rows), "passes")
PY
cp \$WIT/shapes_B$PROBE_BLOCK.json \$OUT/shapes.json

# 4b. what one block of this context costs on disk, measured rather than
#     estimated: a campaign at this context is $NBLOCK of these plus the shared
#     files, and whether that fits a host is decided from this number.
python3 - \$WIT $PROBE_BLOCK $NLAY \$OUT/disk.json <<'PY'
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

PINS=\$(python3 - \$WIT/shapes_B$PROBE_BLOCK.json <<'PY'
import json, sys
w = json.load(open(sys.argv[1]))["worst"]
print(f"--kmax {w['kmax']} --ao-rem-bits {w['ao_rem_bits']} --fold-rem-bits {w['fold_rem_bits']} --fold-alpha {w['fold_alpha']}")
PY
)
st "pins: \$PINS"

# 5. the plan: block $PROBE_BLOCK's 32 layer segments, no output head.  --blocks
#    auto reads the shape tables that are on this host, which is this one block.
#    This is the step that refuses the run when the attention output's quotient
#    term no longer fits at this context; the refusal carries the numbers.
( cd \$HSRC && \$PY -m harness.witness.plan --dir \$WIT --blocks auto --with-block-0 --layers 0-$((NLAY - 1)) \
    --layer-flags="$LAYER_FLAGS" --l0-flags="$L0_FLAGS" --l0-dir \$WIT \
    --out \$OUT/plan.txt --emit-out \$R/emit.txt )
N=\$(grep -cv '^#' \$OUT/plan.txt); st "plan: \$N segments of block $PROBE_BLOCK"
# a slice is an index into the plan's segment lines and each measurement is of
# one named layer, so the lines those indices land on are checked and not assumed
planline() {   # planline <index> <layer>
  line=\$(grep -v '^#' \$OUT/plan.txt | sed -n "\$((\$1 + 1))p")
  case "\$line" in
    *"--ser-tag B${PROBE_BLOCK}L\$2") ;;
    *) st "plan line \$1 is not layer \$2 of block $PROBE_BLOCK: \$line"; exit 3 ;;
  esac
}
planline $PROBE_LAYER $PROBE_LAYER
planline 0 0

# 6. the device kernels the two proved segments need, compiled into the CUDA
#    backend.  Those and not every shape of the plan, which is what the loop
#    drivers emit and what this driver emitted until it could not.
#
#    plan.py --emit-out writes one line per distinct shape of the whole block,
#    keyed by the master exponent table's width, and cudaemit builds that table
#    to emit a shape's kernels.  At 24,576 the block's widest is 2^28 rows, one
#    bit wider than anything the recorded campaigns have emitted, and emitting it
#    needs more memory than a 128 GiB container has: this host's cgroup killed
#    the job twice at exactly that shape (exit 137, memory.events oom_kill),
#    after the extraction and before a segment was proved.  That shape is layer
#    1's.  This probe proves layers 16 and 0, whose shapes are narrower, and a
#    kernel for a segment nobody proves buys the measurement nothing.
#
#    So the emit list is narrowed to the shapes those two lines carry, the whole
#    list is kept beside it, and out/emit.json says which shapes were emitted and
#    which were not.  A shape the store is missing would turn into an announced
#    kernel fallback that evaluates constraints on the host and measures
#    something else, so each segment's fallback count is carried into probe.json,
#    where a reader can refuse the number.
#
#    Each shape is marked done as it lands, so a host that kills one of them
#    costs that shape and not the ones already emitted.
K=\$SRC/prover/kernels
[ -d \$K ] || { st "no prover/kernels in this prover commit; the CUDA backend would evaluate constraints on the CPU"; exit 3; }
if [ ! -f \$R/kernels.done ]; then
  # the plan step above rewrites this list every time the job runs, so the
  # narrowing is done every time too rather than once
  WANT=\$(for i in $PROBE_LAYER 0; do
    grep -v '^#' \$OUT/plan.txt | sed -n "\$((i + 1))p" |
      sed -n 's/.*--table-bits \([0-9][0-9]*\).*/\1/p'
  done | sort -un)
  mv \$R/emit.txt \$R/emit-all.txt
  for tb in \$WANT; do grep "^--table-bits \$tb " \$R/emit-all.txt; done > \$R/emit.txt
  python3 - \$R/emit-all.txt \$R/emit.txt \$OUT/emit.json <<'EMITPY'
import json, sys
def rows(p):
    return [l.rstrip("\n") for l in open(p) if l.strip() and not l.startswith("#")]
def bits(l):
    return int(l.split("--table-bits ")[1].split()[0])
def tag(l):
    return l.split("--ser-tag ")[1].split()[0] if "--ser-tag " in l else None
every, kept = rows(sys.argv[1]), rows(sys.argv[2])
skipped = sorted({bits(l) for l in every} - {bits(l) for l in kept})
json.dump({"shapes_in_plan": [{"table_bits": bits(l), "a_segment_with_it": tag(l)} for l in every],
           "emitted": sorted({bits(l) for l in kept}), "skipped": skipped,
           "why": "the shapes the proved segments carry; a shape no proved segment "
                  "carries is not emitted, and the widest of this block's is one "
                  "this host cannot emit"},
          open(sys.argv[3], "w"), indent=1)
print(f"emit: {len(kept)} of {len(every)} shapes of the block, master table widths "
      f"{sorted({bits(l) for l in kept})}; not emitted: {skipped or 'none'}")
EMITPY
  while read -r line; do
    case "\$line" in '#'*|'') continue ;; esac
    tb=\$(printf '%s\n' "\$line" | sed -n 's/.*--table-bits \([0-9][0-9]*\).*/\1/p')
    [ ! -f \$R/emit-\$tb.done ] || { st "emit: the 2^\$tb shape is in the store"; continue; }
    st "emit: the 2^\$tb shape"
    args=\$(printf '%s\n' "\$line" | sed 's/--ser-tag [A-Za-z0-9_]*//')
    \$SIMD cudaemit $SHARED \$PINS \$args --out \$GEN --block 256 --min-blocks 2 > /dev/null
    # zk-prover #57: genemit's placeholder claims are one entry short on a chunk
    # that carries the embedding gadget, so it cannot lower the layer-0 shapes.
    # A generation kernel is looked up by fingerprint and the plan's shapes share
    # theirs, so what a refused lowering costs is either nothing or an announced
    # kernel fallback line, and the gate below fails the run on any such line.
    if ! \$SIMD genemit $SHARED \$PINS \$args --families "$KERNEL_FAMILIES" --out \$GEN > /dev/null; then
      printf '%s\n' "\$line" >> \$OUT/genemit-refused.txt
      st "genemit refused a shape (zk-prover #57); recorded in out/genemit-refused.txt"
    fi
    touch \$R/emit-\$tb.done
  done < \$R/emit.txt
  python3 \$K/install_constraint_kernels.py --fork \$SRC/nitroo --gen \$GEN
  python3 \$K/install_witness_gen_kernels.py --fork \$SRC/nitroo --gen \$GEN --src \$K
  find \$SRC/nitroo/crates/stwo/src/stwo_cuda/cuda \( -name '*.cu' -o -name '*.cuh' \) -exec touch {} +
  cp \$GEN/cudakernels.rs \$GEN/gencudakernels.rs \$SRC/prover/src/
  # an installed tree is no longer the commit that was pushed, and says so
  grep -q ' dirty\$' \$SRC/.source-commit || sed -i 's/\$/ dirty/' \$SRC/.source-commit
  ( cd \$SRC && CARGO_TARGET_DIR=\$B/t-cuda CARGO_BUILD_JOBS=$CARGO_JOBS CMAKE_BUILD_PARALLEL_LEVEL=$CARGO_JOBS MAKEFLAGS=-j$CARGO_JOBS cargo build --release --locked -p zk-prover --features cuda )
  touch \$R/kernels.done
fi
st "kernels installed"

# 7. the two segments, one process each, the card sampled once a second.  Neither
#    is allowed to stop the job: a segment that does not fit the card is the
#    probe's answer and not its failure, so the exit code, the samples and the
#    last lines of stderr are recorded and the next segment is still proved.
#    Each process returns its memory to the host when it exits, so the larger of
#    the two bounds the run rather than their sum.
probe() {   # probe <tag> <ZK_PIPELINE> <plan slice>
  tag=\$1; pipe=\$2; sl=\$3
  # a probe that has already reported is not run again, so the job can be
  # restarted for the price of what it did not measure
  if [ -s \$OUT/mem_\$tag.json ]; then st "\$tag: already measured"; return 0; fi
  st "\$tag: ZK_PIPELINE=\$pipe over plan segments \$sl"
  rm -rf \$R/ser-\$tag \$R/\$tag.mem; mkdir -p \$R/ser-\$tag
  ( while true; do echo "\$(date +%s) \$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)" >> \$R/\$tag.mem; sleep 1; done ) & sampler=\$!
  T0=\$(date +%s); rc=0
  ZK_PIPELINE=\$pipe \$CUDA compose-chunks $SHARED \$PINS --plan \$OUT/plan.txt --plan-slice \$sl \
      --ser-dir \$R/ser-\$tag > \$OUT/\$tag.json 2> \$R/\$tag.err || rc=\$?
  T1=\$(date +%s)
  kill \$sampler 2>/dev/null || true
  [ \$rc -eq 0 ] || rm -f \$OUT/\$tag.json
  grep -c 'kernel fallback:' \$R/\$tag.err > \$OUT/\$tag.fallbacks || true
  tail -c 2000 \$R/\$tag.err > \$R/\$tag.tail
  python3 - \$R/\$tag.mem \$R/\$tag.tail \$OUT/mem_\$tag.json \$tag \$pipe \$rc \$((T1 - T0)) <<'PY'
import json, sys
mem, tail, out, tag, pipe, rc, secs = sys.argv[1:8]
v = [int(l.split()[1]) for l in open(mem) if len(l.split()) == 2 and l.split()[1].isdigit()]
t = open(tail, errors="replace").read()
oom = any(w in t.lower() for w in ("out of memory", "cudaerrormemoryallocation", "cuda_error_out_of_memory"))
json.dump({"probe": tag, "pipeline": int(pipe), "exit_code": int(rc), "seconds": int(secs),
           "samples": len(v), "period_s": 1, "max_mib": max(v, default=0),
           "last_mib": v[-1] if v else 0,
           "mean_mib": round(sum(v) / len(v), 1) if v else 0,
           "out_of_memory": bool(oom),
           "stderr_tail": t[-600:] if int(rc) else ""},
          open(out, "w"), indent=1)
print(f"{tag}: exit {rc}, {secs}s, peak {max(v, default=0)} MiB"
      + (", out of memory" if oom else ""))
PY
  st "\$tag done"
}
probe decode $PIPELINE $PROBE_SLICE
probe layer0 $PIPELINE $PROBE_L0_SLICE

# 7b. layer 16 again on the reference backend, which proves in host memory and
#     cannot run the card out of it.  It is the run's anchor: the manifest is
#     copied from a prover's provenance block and refuses a fetched directory
#     that has none, and a segment the card could not hold writes no output at
#     all, so without this a probe whose answer is "neither fits" could not be
#     recorded -- which is the answer most worth recording.  It also freezes a
#     digest for a segment of a plan at this context under the variant the paper
#     reports.
if [ ! -s \$OUT/reference-simd.json ]; then
  st "reference backend: plan segment $PROBE_SLICE, in host memory"
  T0=\$(date +%s)
  # not allowed to stop the job either: the card's peak is the measurement and it
  # is already written by the time this runs.
  if \$SIMD compose-chunks $SHARED \$PINS --plan \$OUT/plan.txt --plan-slice $PROBE_SLICE \
      --ser-dir \$R/ser-ref > \$OUT/reference-simd.json 2> \$R/reference-simd.err; then
    st "reference backend done in \$(( \$(date +%s) - T0 ))s"
  else
    rm -f \$OUT/reference-simd.json
    st "the reference backend did not prove the segment; see \$R/reference-simd.err"
  fi
fi
rm -rf \$R/ser-decode \$R/ser-layer0 \$R/ser-ref

# 8. the answer, from the segment's own outputs.  The card's size is read off the
#    card, like every other fact about a host.
TOTAL=\$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
python3 - \$OUT $CTX \$TOTAL $PROBE_LAYER <<'PY'
import json, pathlib, sys
out, ctx, card, layer = pathlib.Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
rows = []
for tag, k in (("decode", layer), ("layer0", 0)):
    m = json.loads((out / f"mem_{tag}.json").read_text())
    s = None
    f = out / f"{tag}.json"
    if f.exists():
        doc = json.loads(f.read_text())
        p, s = doc["provenance"], doc["result"]["summary"]
        print(f"{tag}: {s['n']} segment(s), loop {s['loop_secs']:.1f} s, "
              f"fresh {s['fresh_sum']:,.0f} cells, skips {p['unsound_skips'] or 'none'}, "
              f"all_bound {p['binding']['all_bound']}, unbound {p['binding']['unbound']}")
    print(f"{tag}: layer {k}, peak {m['max_mib']} MiB of {card} MiB, exit {m['exit_code']}"
          + (", out of memory" if m["out_of_memory"] else ""))
    fb = out / f"{tag}.fallbacks"
    nfb = int(fb.read_text().strip() or 0) if fb.exists() else 0
    if nfb:
        print(f"{tag}: {nfb} kernel fallback line(s): this segment evaluated constraints "
              "on the host and its peak is not a card measurement")
    rows.append({"probe": tag, "layer": k, "pipeline": m["pipeline"],
                 "exit_code": m["exit_code"], "peak_mib": m["max_mib"],
                 "last_mib": m["last_mib"], "out_of_memory": m["out_of_memory"],
                 "kernel_fallbacks": nfb,
                 "fits": m["exit_code"] == 0 and not m["out_of_memory"],
                 "segments": s["n"] if s else 0,
                 "loop_secs": s["loop_secs"] if s else None,
                 "fresh_cells": s["fresh_sum"] if s else None})
ref = out / "reference-simd.json"
refrow = None
if ref.exists():
    d = json.loads(ref.read_text())
    p, s2 = d["provenance"], d["result"]["summary"]
    refrow = {"backend": p["backend"], "segments": s2["n"], "loop_secs": s2["loop_secs"],
              "fresh_cells": s2["fresh_sum"], "digests": s2["digests"],
              "unsound_skips": p["unsound_skips"], "all_bound": p["binding"]["all_bound"],
              "unbound": p["binding"]["unbound"]}
    print(f"reference backend: {s2['n']} segment(s), {s2['loop_secs']:.1f} s, "
          f"digest {s2['digests'][0][:16]}, skips {p['unsound_skips'] or 'none'}, "
          f"all_bound {p['binding']['all_bound']}, unbound {p['binding']['unbound']}")
json.dump({"context": ctx, "card_total_mib": card, "probe_layer": layer,
           "probes": rows, "reference": refrow},
          open(out / "probe.json", "w"), indent=1)
for r in rows:
    if r["fits"]:
        print(f"layer {r['layer']} at C={ctx} peaks at {r['peak_mib']} MiB of {card}: it fits")
    else:
        print(f"layer {r['layer']} at C={ctx} does not fit this card; the last sample was "
              f"{r['last_mib']} MiB of {card} and the exit code was {r['exit_code']}")
fit = [str(r["layer"]) for r in rows if r["fits"]]
print(f"the segments of this block that fit this card at C={ctx}: {', '.join(fit) or 'neither'}")
PY
st "done"
JOBEOF
drv_start "$JOB"
rm -f "$JOB"
