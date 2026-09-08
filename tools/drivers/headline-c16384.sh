#!/bin/sh
# headline-c16384: the paper's headline configuration, proved in groups of blocks.
#
#   tools/drivers/headline-c16384.sh <host> <prover-commit> <harness-commit>
#
# One 16,384-token prompt and its 512 output tokens, every position proved from
# the embedding up: 33 token blocks of 32 layer segments and the output head,
# 1,057 segments, on the CUDA backend, in processes of 64 segments each.  Every layer segment binds its
# residual stream to the next layer's and its keys and values to the next
# block's; the verifier side checks every link afterwards.  The five GKR
# reductions are on, which is the paper's configuration (docs/decisions), and no
# skip flag appears anywhere.
#
# The same statement as `headline-c4096.sh` at four times the context.  It is
# not the same job.  `lib/sequence-job.sh` extracts the whole witness set, then
# proves it; at this context the whole witness set does not fit the host, so
# this driver carries its own job body and the two campaigns differ in it.  The
# four things issue #47 lists are all still here -- the build is marked dirty
# before the rebuild, the layer links are pinned at NBLOCK * (NLAY - 1) + the
# head, and the workarounds for zk-prover #51, #55 and #57 are copied from the
# shared body line for line.
#
# Why groups.  The memory probe measured one block's layer dumps at this
# context: 12.16 GiB, against about 76 GiB free.  Thirty-three of them is 302
# GiB plus 7.5 GiB of block-invariant files, so the witness set cannot exist at
# once and the job holds a few blocks at a time.  The extractor takes a range of
# blocks and dumps all of them from one forward pass (harness.witness.extract
# `--blocks 29-32`), and the pass costs what its highest block costs, so a group
# is no dearer to extract than its last block alone.
#
# The job therefore runs two sweeps over the blocks, highest block first:
#
#   - the survey sweep extracts a group, writes each block's shape table, emits
#     the device kernels for the group's shapes into one accumulating store, and
#     then deletes the group's dumps.  The kernels are emitted inside the group
#     and not after the sweep because an emitter reads the segment's dump to
#     lower its shape: a store built after the dumps were deleted is an empty
#     store, and the first proof stops on a fingerprint it cannot find.  A shape
#     table is a few kilobytes and they all stay.  Nothing is proved here.
#   - then, once, the store is installed into the vendored library and compiled
#     in, and the plan's 1,057 lines are written from the 33 shape tables.
#   - the prove sweep extracts a group again, proves the group's segments in
#     processes of 64, keeps their outputs and their serialized statements and
#     proofs, and deletes the group's dumps.
#
# The second extraction is what the arrangement costs: about an hour of card
# time, against the two hours of rebuilds that emitting kernels group by group
# would cost instead, and it buys one plan, one set of pins over the merge of
# every block's shape table, and one kernel store, which is what the context
# 4,096 campaign had.  Highest block first is not a preference either: the pins
# the emitters are given have to be the pins the proving processes are given,
# and `ao_rem_bits` and the table width grow with the prefix a block reads, so
# the first group has to be the one that holds the worst of them.  Every later
# group re-merges the tables and the job stops if the worst has moved.  The same
# order puts the largest segments first, so a card that cannot hold the loop
# fails in the first group rather than after eleven hours.
#
# The group size is not written here.  The job measures the free space and takes
# as many blocks as fit beside the block-invariant files and a reserve, up to
# `GROUP_MAX`; the numbers it measures go into the run's `disk.json` and
# `groups.json`.  At the free space the probe saw, that is four blocks and nine
# groups.  The survey sweep decides each group as it reaches it, because a
# survey group is only a set of shape tables and a restart that grouped the
# blocks differently would still write the same tables.  The prove sweep decides
# the whole split before its first group and writes it down, because a restart
# that grouped the blocks differently would put its process boundaries elsewhere
# and prove some segments twice.
#
# The loop scope is the c4096 campaign's and nothing about the grouping enters
# it: `loop`, `commit`, `stwo total` and `whole wall` are the prover's own sums
# over the segments of each process, and the extraction, the kernel work and the
# deletions happen between processes and are in none of them.  What the run
# reports as its end-to-end figure is the sum over the groups of the proving
# processes, and `timing.json` keeps the phases apart so the two cannot be
# confused.
#
# `PIPELINE` below is the memory probe's answer and not a preference: the loop
# peaks at 78,843 MiB of the 81,559 MiB the card reports, pipelined or not (the
# memory-probe-c16384 run, which settled issue #16).
#
# The first attempt of this run, at 02:04 on 2026-09-08, emitted the kernels
# after the survey sweep instead of inside it, and its first proof stopped with
# no feed kernel for a fingerprint: all 165 emit lines had been refused, because
# the dumps the emitters read had already been deleted.  That is what the survey
# sweep's emit step is for, and why the job now refuses any emitter refusal but
# the one zk-prover #57 makes on block 0's layer 0.
#
# The first call pushes zk-prover at the two commits to the host, starts the
# job detached and prints the poll command.  Every later call with the same
# arguments prints the status; once the status says done it fetches the
# outputs into runs/<run-id>/, writes manifest.json from the prover's
# provenance block, and runs check.py.  Nothing measured is typed in here.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
HOST=${1:?host alias}; PROVER=${2:?prover commit}; HARNESS=${3:?harness commit}
ZK_PROVER=${ZK_PROVER_DIR:-$ROOT/../zk-prover}     # a local clone to archive the commits from
NAME=headline-c16384
. "$HERE/lib/driver.sh"

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=headline             # a configuration the paper cites, not a control
MODEL=${ZK_MODEL:-unsloth/Llama-3.1-8B-Instruct}
SPEC=y-delay-vw12          # the quantization variant the paper reports (docs/decisions)
# The head's variant is the layers' variant.  It was `b10-final`, a default
# inherited from `headline-c4096.sh`, where it never mattered because that plan
# had no head segment.  The two specs give the `lm_head` matmul the same
# arithmetic -- `y-delay-vw12` is `b10-final` plus a delayed `v` requantize and a
# 12-bit attention output (harness/witness/common.py) -- but not the same
# residual stream, so a head extracted under `b10-final` proves the argmax of a
# model the 1,056 layer segments do not prove.  The first pass of this run did
# exactly that and its head dump said so in its own manifest: `emits_next_token`
# 477 of 511.
HEAD_SPEC=$SPEC
CTX=16384; S=512
NBLOCK=$(( (CTX + S) / S ))  # 33: the prompt's 32 blocks and the output block
NLAY=32
SHARED="--round even --numbits 9 --z-hi-bits 7 --variants intexp --head-groups 16,8,8 --tight-table"
GKR="--gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
LAYER_FLAGS="--round even --diagonal-block $GKR"   # every binding gadget is on by default; no skip flag anywhere
L0_FLAGS=""
# The head's own flags.  `--ao-rem-bits` is not pinned here: a head dump carries
# the o matmul of the layer it was extracted at, so its `ao_rem_bits` is a
# property of the dump and the job reads it off the dumps' own shape rows, the
# way the layer pins come off the layer shape tables.  Under `b10-final` it came
# out 15 against the 23 that used to be written here.
HEAD_FLAGS_BASE="$GKR"
HEAD_LAYER=16              # the layer the head dump is extracted at; the grid places the segment after the last layer
# Which blocks carry a head segment: the last block of the prompt and the
# generated block (docs/decisions/2026-09-08-the-head-is-proved-over-the-last-prompt-block.md).
# The first generated token's id is the argmax of the logits at the last prompt
# position, so a plan with a head over the generated block alone leaves that one
# id compared against nothing.
HEAD_BLOCKS=$((NBLOCK - 2)),$((NBLOCK - 1))
# The output head's segment is in the plan, so the token each position emits is
# bound to the logits computed for it.  It was out while an honest head segment
# was rejected under the sound defaults -- the seam between the attention output
# and the o matmul was checked on a chunk whose kernel group is the final norm
# and cannot state it (zk-prover #58) -- and zk-prover #61 fixed that.  A prover
# commit without the fix refuses the head segment and this variable goes back to
# 0; the plan, the extraction, the link count and the run's own segment count
# all follow it.
WITH_HEAD=1
OFFSET=0                   # the corpus from its first token; the c4096 row's window ends where this one ends
# ZK_PIPELINE.  Pipelining generates segment k+1 while segment k is proved and
# holds two segments' device memory at once.  The value below is the memory
# probe's answer (the memory-probe-c16384 run) and not a preference: the loop
# peaks at 78,843 MiB of the 81,559 MiB the card reports, pipelined or not, and
# pipelining is 23% faster.
PIPELINE=1
SLICE=64                   # segments per process: a group of 5 blocks is 160 segments, so 3 processes
XTHREADS=20                # torch threads for the extraction
IDS=${ZK_IDS:-}            # token ids (.npy) already on the host; empty = generate them
KERNEL_FAMILIES=zk_chan_eval,zk_key_eval,zk_row_eval,zk_attn_out_eval,zk_dequant_eval,zk_freivalds_eval,zk_exp_table_eval,zk_table_eval,zk_residual_stream_eval,zk_residual_stream_table_eval
# How many blocks a group holds.  The job measures the free space itself and
# divides; these are the ceiling and the three sizes the division needs.  The
# two witness sizes are the memory probe's measurement of block 32 at this
# context and not an estimate, and the job replaces them with its own
# measurement of its own first group as soon as it has one.  The reserve is what
# the run needs beside a group's dumps: the serialized statements and proofs,
# which accumulate over every group until the link check reads them, plus slack.
GROUP_MAX=5                # never more than this many blocks in flight, whatever the disk says
BLOCK_EST_MIB=12452        # 12.16 GiB, the probe's disk.json for block 32
SHARED_EST_MIB=7680        # 7.5 GiB of block-invariant files, written once and kept
RESERVE_MIB=10240          # 10 GiB kept free at all times
SAMPLE_MS=200              # the card's memory is sampled this often for the whole of every process
# The final link check always publishes the prompt, and asks the verifier to
# replay every chunk proof only where the proofs are still whole.
#
# --prompt costs nothing and is never off: the ids it compares are published in
# the statements, which this run keeps, so the grid checks every prompt
# position's id against the prompt and every generated position's against the
# token the head proved for the position before it.  Without it the grid says
# those positions are unchecked, which is what the c4096 row has.
#
# --verify replays the verifier over every chunk proof and needs the proof
# whole.  At this context 1,058 of them are 108 GiB against a 216 GiB volume
# that also holds the weights, the build trees and a group's layer dumps, so
# this run keeps a proof only until the verifier has accepted it and then
# shrinks it to the roots the grid reads; the per-group records are the evidence
# and they are in the run directory.  A host that can hold the proofs to the end
# sets this to 1 and the final grid does both at once.
GRID_VERIFY=0
# The links the grid implies, which the grid is told before it counts them.
# Inside a block, consecutive layers: 31 per block, and one more for each block
# that carries a head segment, because a head sits at the layer coordinate after
# the last layer and commits the residual it consumed as its own input side.
# Across blocks, at each of the 32 layers, consecutive blocks; a head performs no
# attention, holds no key/value cache and is never a token-axis edge.  With the
# two heads that is 1,025 and 1,024 over 1,058 segments; without them, the 1,023
# and 1,024 that issue #1 calls 2,047.
NHEAD=0
[ "$WITH_HEAD" = 1 ] && NHEAD=$(printf '%s' "$HEAD_BLOCKS" | tr ',' '\n' | grep -c .)
SEGMENTS=$(( NBLOCK * NLAY + NHEAD ))
LAYER_LINKS=$(( NBLOCK * (NLAY - 1) + NHEAD ))
TOKEN_LINKS=$(( (NBLOCK - 1) * NLAY ))

drv_finish "$(drv_status)"

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
SRC=\$B/src; HSRC=\$B/harness-src/harness; GEN=\$B/gen
OUT=\$R/out; SER=\$R/ser
WIT=\$HOME/witness/$(printf '%.12s' "$HARNESS")/$SPEC-c$CTX
HEADW=\$HOME/witness/$(printf '%.12s' "$HARNESS")/head-$HEAD_SPEC-c$CTX/witness
mkdir -p \$OUT \$GEN \$SER \$WIT
$(drv_job_preamble)
export RAYON_NUM_THREADS=\${RAYON_NUM_THREADS:-16} ZK_KERNEL_STORE=\$GEN
PY="uv run --project \$HSRC \$UVG python"
JOB_T0=\$(date +%s)

# the configuration, for the manifest
cat > \$OUT/config.json <<CFG
{"driver": "$NAME", "label": "$LABEL",
 "model": "$MODEL", "spec": "$SPEC", "head_spec": "$HEAD_SPEC",
 "context": $CTX, "s": $S, "positions": $((CTX + S)), "blocks": $NBLOCK, "layers": $NLAY,
 "segments": $SEGMENTS, "with_head": $WITH_HEAD, "head_blocks": "$HEAD_BLOCKS", "heads": $NHEAD,
 "slice": $SLICE, "pipeline": $PIPELINE,
 "grouped": true, "group_max": $GROUP_MAX, "group_order": "descending",
 "block_est_mib": $BLOCK_EST_MIB, "shared_est_mib": $SHARED_EST_MIB, "reserve_mib": $RESERVE_MIB,
 "sample_ms": $SAMPLE_MS,
 "shared_flags": "$SHARED", "layer_flags": "$LAYER_FLAGS", "layer0_flags": "$L0_FLAGS",
 "head_flags": "$HEAD_FLAGS_BASE plus an --ao-rem-bits read off the head dumps; see head.json",
 "expect_layer_links": $LAYER_LINKS, "expect_token_links": $TOKEN_LINKS,
 "ids": "${IDS:-generated: the corpus's tokens $OFFSET to $((OFFSET + CTX)) and the model's own greedy continuation under $SPEC}",
 "corpus_offset": $OFFSET}
CFG

st "gpu: \$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader)"
st "nvcc: \$(nvcc --version | tail -2 | head -1)"
df -h \$WIT | tail -1 | awk '{print "disk: " \$4 " free of " \$2 " on " \$6}'

# 1. both backends of the pinned prover commit
st "build"
( cd \$SRC && CARGO_TARGET_DIR=\$B/t-simd cargo build --release --locked )
( cd \$SRC && CARGO_TARGET_DIR=\$B/t-cuda cargo build --release --locked -p zk-prover --features cuda )
SIMD=\$B/t-simd/release/zk-prover; CUDA=\$B/t-cuda/release/zk-prover

# 2. the harness at its pinned commit
( cd \$HSRC && uv sync --frozen \$UVG )

# 3. the statement's tokens: the prompt is $CTX tokens of the corpus from
#    offset $OFFSET, and the output is the model's own greedy continuation
#    under $SPEC.  Decoded once with 513 new tokens so the last row's next token
#    is in the array, then shifted into the extraction array; a 512-token decode
#    must agree with it.
IDSFILE="$IDS"
if [ -z "\$IDSFILE" ]; then
  IDSFILE=\$WIT/ids.npy
  if [ ! -f \$IDSFILE ]; then
    st "ids: greedy continuation, $SPEC, corpus offset $OFFSET"
    # zk-prover #51: gen_ids imports the bare name ppl where every other caller
    # of that function writes the submodule, so running it with -m stops at the
    # import.  This shim binds the name to the submodule and changes nothing
    # else; it goes when the import is fixed.
    cat > \$R/gen_ids_shim.py <<'SHIM'
import runpy
import sys

import harness.witness.ppl

sys.modules.setdefault("ppl", harness.witness.ppl)
runpy.run_module("harness.witness.gen_ids", run_name="__main__")
SHIM
    ( cd \$HSRC && ZK_MODEL=$MODEL ZK_DEVICE=cuda ZK_THREADS=$XTHREADS \$PY \$R/gen_ids_shim.py --prefix $CTX --offset $OFFSET --new 513 --spec $SPEC --out \$WIT/ids_513.npy )
    ( cd \$HSRC && ZK_MODEL=$MODEL ZK_DEVICE=cuda ZK_THREADS=$XTHREADS \$PY \$R/gen_ids_shim.py --prefix $CTX --offset $OFFSET --new $S --spec $SPEC --out \$WIT/ids_512.npy )
    ( cd \$HSRC && \$PY -m harness.witness.shift_ids --ids \$WIT/ids_513.npy --prefix $CTX --new $S --out \$IDSFILE )
    ( cd \$HSRC && \$PY -c "
import numpy as np
a, b = np.load('\$WIT/ids_512.npy'), np.load('\$WIT/ids_513.npy')
assert (a == b[:len(a)]).all(), 'greedy decoding is deterministic; the 512- and 513-token runs must agree'
print('ids: determinism check passed', len(a), 'tokens')" )
  fi
fi
IDSARG="--ids \$IDSFILE"
# The prompt the statement publishes, as the link check wants it: a JSON list.
# It is an output of the run and not a working file -- it is the input side of
# the statement, and the grid's id check is against this and nothing else.
if [ ! -f \$OUT/prompt.json ]; then
  ( cd \$HSRC && \$PY -c "
import json, sys
import numpy as np
a = np.load(sys.argv[1])[:$CTX]
json.dump({'ids': [int(x) for x in a]}, open(sys.argv[2], 'w'))
print('prompt:', len(a), 'ids')" \$IDSFILE \$OUT/prompt.json )
fi

# ---- the group machinery -----------------------------------------------------
# How many blocks fit beside the block-invariant files and the reserve, right
# now, on the volume that holds the witnesses.  The free space is measured; the
# size of a block's dumps is the memory probe's until this job has measured its
# own, which it does after its first group and writes into blocksize.json.
group_k() {   # group_k <highest block still to do> -> the blocks to take, or 0
  python3 - \$WIT $GROUP_MAX $BLOCK_EST_MIB $SHARED_EST_MIB $RESERVE_MIB \$1 <<'PY'
import json, os, shutil, sys
wit, kmax = sys.argv[1], int(sys.argv[2])
blk, shr, res, hi = (int(sys.argv[3]) << 20, int(sys.argv[4]) << 20,
                     int(sys.argv[5]) << 20, int(sys.argv[6]))
src = "the memory probe"
m = os.path.join(wit, "blocksize.json")
if os.path.exists(m):
    d = json.load(open(m))
    blk, shr, src = d["block_bytes"], d["shared_bytes"], "this run's own first group"
free = shutil.disk_usage(wit).free
# the block-invariant files are already off the free space once they are written
need_shared = 0 if os.path.isdir(os.path.join(wit, "shared")) else shr
budget = free - res - need_shared
k = max(0, min(kmax, hi + 1, budget // blk))
print(f"disk: {free / 2**30:.1f} GiB free, a block is {blk / 2**30:.2f} GiB "
      f"({src}), shared {need_shared / 2**30:.1f} GiB still to write, "
      f"{res / 2**30:.0f} GiB reserved -> {k} block(s) in this group",
      file=sys.stderr)
print(k)
PY
}

# One block's dumps, and the block-invariant files, as they are on disk now.
tree_bytes() {   # tree_bytes <path>...
  python3 - "\$@" <<'PY'
import os, sys
n = 0
for p in sys.argv[1:]:
    for root, _, files in os.walk(p):
        for f in files:
            q = os.path.join(root, f)
            if not os.path.islink(q):
                n += os.path.getsize(q)
print(n)
PY
}

# The group's dumps: one forward pass per layer group over the whole sequence,
# writing only blocks GB0 to GB1.  The pass costs what its highest block costs,
# so a group of four is no dearer than its last block alone.  Layer 0 is a pass
# of its own because --embed writes the embedding table into every dump of the
# pass it is given and the prover turns the gadget on for any dump that carries
# one.  The block-invariant files are written once and shared between blocks and
# between groups.  A pass whose last block's dump is already written is not run
# again, so an interrupted job is restarted for the price of what it did not
# finish.
xpass() {   # xpass <tag> <layers> <last layer of the group> <extra flags>
  tag=\$1; group=\$2; last=\$3; shift 3
  [ ! -f \$WIT/witness_B\${GB1}_L\${last}/manifest.json ] || { st "extract: layers \$group of blocks \$GB0-\$GB1 are on this host"; return 0; }
  st "extract: layers \$group, blocks \$GB0-\$GB1 of $NBLOCK, C=$CTX, $SPEC"
  T0=\$(date +%s)
  ( cd \$HSRC && ZK_MODEL=$MODEL ZK_DEVICE=cuda ZK_THREADS=$XTHREADS \$PY -m harness.witness.extract \
      --tokens $((CTX + S)) --chunk $S --layers \$group --spec $SPEC \
      --residual-stream --diagonal-block --slim --slim-num "\$@" \$IDSARG \
      --blocks \$GB0-\$GB1 --share \$WIT/shared --out \$WIT/witness )
  T1=\$(date +%s)
  printf '{"sweep": "%s", "blocks": "%d-%d", "pass": "%s", "layers": "%s", "device": "cuda", "threads": %d, "seconds": %d}\n' \
      "\$GSW" \$GB0 \$GB1 "\$tag" "\$group" $XTHREADS \$((T1 - T0)) \
      > \$WIT/extract_\${GSW}_b\${GB0}-\${GB1}_\$tag.json
  st "extract: layers \$group done in \$((T1 - T0))s"
}
xgroup() {   # xgroup <sweep> <first block> <last block>
  GSW=\$1; GB0=\$2; GB1=\$3
  # zk-prover #55: a one-layer extraction writes <base>_B<b> where the shape
  # table and the plan both read <base>_B<b>_L<k>, so layer 0's dumps are moved
  # into the name the next steps look for.  Only the directory moves; no dump
  # changes.
  xpass l0 0 0 --embed
  b=\$GB0
  while [ \$b -le \$GB1 ]; do
    [ ! -d \$WIT/witness_B\$b ] || mv \$WIT/witness_B\$b \$WIT/witness_B\${b}_L0
    b=\$((b + 1))
  done
  xpass l1 1,2,3,4,5,6,7 7
  xpass l2 8,9,10,11,12,13,14,15 15
  xpass l3 16,17,18,19,20,21,22,23 23
  xpass l4 24,25,26,27,28,29,30,31 31
}
xdrop() {   # xdrop <first block> <last block>: the dumps go, the shape tables stay
  b=\$1
  while [ \$b -le \$2 ]; do
    # witness_B3_L* is block 3 and not block 31: the underscore is in the glob
    rm -rf \$WIT/witness_B\${b}_L* \$WIT/witness_B\$b
    b=\$((b + 1))
  done
  st "dumps of blocks \$1-\$2 deleted"
}
# 4. the output head's dumps, one per block that carries a head segment, from
#    one forward pass.  Before the survey, because the plan reads the master
#    table width and the head's own ao_rem_bits out of these dumps.
HEAD_LAST=\$(printf '%s' "$HEAD_BLOCKS" | tr ',' ' ' | awk '{print \$NF}')
if [ "$WITH_HEAD" = 1 ] && [ ! -f \${HEADW}_B\${HEAD_LAST}/manifest.json ]; then
  st "extract: the output head over blocks $HEAD_BLOCKS, $HEAD_SPEC"
  ( cd \$HSRC && ZK_MODEL=$MODEL ZK_DEVICE=cuda ZK_THREADS=$XTHREADS \$PY -m harness.witness.extract --tokens $((CTX + S)) --chunk $S \
      --layer $HEAD_LAYER --spec $HEAD_SPEC --head --slim --blocks $HEAD_BLOCKS \$IDSARG --out \$HEADW )
fi
# The head line's own flags.  A head dump carries the o matmul of the layer it
# was extracted at, so ao_rem_bits is a property of the dump and is read off
# it, exactly as the layer pins are read off the layer shape tables; the pin on
# the command line is the layers' and a head that needs more says so here.
HEAD_FLAGS="$HEAD_FLAGS_BASE"
if [ "$WITH_HEAD" = 1 ]; then
  ( cd \$HSRC && \$PY -c "
import json, sys
from harness.witness.shapes import shape_of
rows = {d.rsplit('_B', 1)[1]: shape_of(d) for d in sys.argv[2:]}
ao = max(r['ao_rem_bits'] for r in rows.values())
json.dump({'blocks': sorted(rows), 'ao_rem_bits': ao, 'rows': rows,
           'note': 'A head dump carries the o matmul of the layer it was extracted at, '
                   'so ao_rem_bits is a property of the dump and the head line is pinned '
                   'from it rather than from a number written in the driver.'},
          open(sys.argv[1], 'w'), indent=1)
print(ao)
" \$OUT/head.json \$(for b in \$(printf '%s' "$HEAD_BLOCKS" | tr ',' ' '); do echo \${HEADW}_B\$b; done) )
  HEAD_AO=\$(python3 -c "
import json, sys
print(json.load(open(sys.argv[1]))['ao_rem_bits'])" \$OUT/head.json)
  HEAD_FLAGS="--ao-rem-bits \$HEAD_AO $HEAD_FLAGS_BASE"
  st "head: --ao-rem-bits \$HEAD_AO, from the head dumps' own shape rows (out/head.json)"
fi

# 5. the survey sweep: every block's shape table and every block's kernels, a
#    group at a time, highest block first.
#
#    A shape table is a few kilobytes and they all stay; the dumps they were
#    read from do not.  The kernels are emitted here, inside the group, and not
#    after the sweep: an emitter reads the segment's dump to lower its shape and
#    refuses a shape whose witness is not there, so a store built after the
#    dumps were deleted is an empty store and the first proof stops on a
#    fingerprint it cannot find.  The plan's distinct shapes span every block --
#    the table width follows the prefix the block reads -- so every group has
#    shapes of its own and every group emits.
#
#    The pins the emitters are given have to be the pins the proving processes
#    are given, and they are the worst case over every block.  Highest block
#    first is what makes that possible: ao_rem_bits and the table width grow
#    with the prefix a block reads, so the first group holds the worst of them,
#    and every later group re-merges and is refused if the worst has moved.
mkdir -p \$WIT/shapes \$R/emitted
# The shape tables live in a directory of their own, so that only the group
# being emitted is ever visible to the plan's --blocks auto.  A run that wrote
# them beside the dumps moves them here once and keeps its work.
for q in \$WIT/shapes_B*.json; do
  [ -e "\$q" ] || continue
  [ -e "\$WIT/shapes/\$(basename \$q)" ] || mv "\$q" "\$WIT/shapes/"
done
rm -f \$WIT/shapes_B*.json
# the marker of the run that emitted into an empty store: this job does not use
# the name and a stale one must not be read as an installed store
rm -f \$R/kernels.done
[ -d \$R/emitted ] && [ -n "\$(ls -A \$R/emitted 2>/dev/null)" ] ||
  rm -f \$OUT/cudaemit-refused.txt \$OUT/genemit-refused.txt

# The pins over every shape table written so far.  The first group writes them
# down and every group after it must agree: a store emitted under one set of
# pins and a loop launched under another do not meet.
pins_now() {
  ( cd \$HSRC && \$PY -m harness.witness.shapes --merge \$WIT/shapes/shapes_B*.json --out \$R/shapes-sofar.json ) > /dev/null
  python3 - \$R/shapes-sofar.json <<'PY'
import json, sys
w = json.load(open(sys.argv[1]))["worst"]
print(f"--kmax {w['kmax']} --ao-rem-bits {w['ao_rem_bits']} --fold-rem-bits {w['fold_rem_bits']} --fold-alpha {w['fold_alpha']}")
PY
}

# Every shape of one group, lowered into the one accumulating store.  A store
# dedups by fingerprint and only grows, so the groups add to it in turn and the
# install after the sweep installs all of them at once.
emit_lines() {   # emit_lines <file of plan lines> <what they are>
  ef=\$1; ewhat=\$2
  NS=\$(grep -cv '^#' \$ef); i=0
  st "kernels: \$ewhat, \$NS distinct shapes"
  while read -r line; do
    case "\$line" in '#'*|'') continue ;; esac
    args=\$(printf '%s\n' "\$line" | sed 's/--ser-tag [A-Za-z0-9_]*//')
    for emit in cudaemit genemit; do
      case \$emit in
        cudaemit) opts="--block 256 --min-blocks 2" ;;
        genemit)  opts="--families $KERNEL_FAMILIES" ;;
      esac
      if \$SIMD \$emit $SHARED \$PINS \$args \$opts --out \$GEN > /dev/null 2> \$R/emit.err; then
        continue
      fi
      printf '%s\n' "\$line" >> \$OUT/\$emit-refused.txt
      # zk-prover #57: the generation emitter's placeholder claims are one entry
      # short on the segment with no prefix, which is the one that also carries
      # the embedding gadget.  That is block 0's layer 0 and nothing else -- the
      # context 4,096 run refused that one line and no other -- and a kernel is
      # looked up by fingerprint, so a shape that shares its fingerprint with an
      # emitted one costs nothing.  Any other refusal is a hole in the store and
      # the loop stops on it hours later, so it stops the job here instead.
      case "\$emit \$line" in
        "genemit "*"--ser-tag B0L0")
          st "genemit refused block 0's layer 0 (zk-prover #57); recorded in out/genemit-refused.txt"
          continue ;;
      esac
      st "\$emit refused a shape that is not block 0's embedding segment; the store would be short a kernel and the loop would stop on it"
      st "the line: \$line"
      tail -5 \$R/emit.err
      exit 8
    done
    i=\$((i + 1))
    [ \$((i % 10)) -ne 0 ] || st "kernels: \$i of \$NS shapes of \$ewhat emitted"
  done < \$ef
}
emit_group() {   # emit_group <first block> <last block>
  el=\$1; eh=\$2
  # only this group's shape tables are visible, so --blocks auto writes this
  # group's lines and names this group's dumps, which are on disk right now
  rm -f \$WIT/shapes_B*.json
  b=\$el; while [ \$b -le \$eh ]; do cp \$WIT/shapes/shapes_B\$b.json \$WIT/; b=\$((b + 1)); done
  GPLAN=\$R/plan-g\$el-\$eh.txt; GEMIT=\$R/emit-g\$el-\$eh.txt
  # Layers only.  A head segment's shape comes off its own dump, which is kept
  # for the whole run, so it needs no layer dump and no group: it is emitted
  # once, after the whole plan is written, and a head that changes is re-emitted
  # without re-extracting anybody's layers.
  ( cd \$HSRC && \$PY -m harness.witness.plan --dir \$WIT --blocks auto --with-block-0 --layers 0-$((NLAY - 1)) \
      --layer-flags="$LAYER_FLAGS" --l0-flags="$L0_FLAGS" --l0-dir \$WIT \
      --out \$GPLAN --emit-out \$GEMIT )
  rm -f \$WIT/shapes_B*.json
  emit_lines \$GEMIT "blocks \$el-\$eh"
  b=\$el; while [ \$b -le \$eh ]; do touch \$R/emitted/B\$b; b=\$((b + 1)); done
  # a store that grew is a store that is not installed
  rm -f \$R/install.done
  st "kernels: blocks \$el-\$eh emitted"
}

st "survey: the $NBLOCK shape tables and their kernels, group by group, highest block first"
SURVEY_T0=\$(date +%s)
hi=$((NBLOCK - 1))
while [ \$hi -ge 0 ]; do
  GK=\$(group_k \$hi)
  [ "\$GK" -ge 1 ] || { st "disk: no room for even one block's dumps; the job stops here"; exit 5; }
  lo=\$((hi - GK + 1)); [ \$lo -ge 0 ] || lo=0
  # a group is done when every one of its blocks has a shape table and has been
  # emitted; a table without its kernels is the failure this arrangement fixes
  need=0; b=\$lo
  while [ \$b -le \$hi ]; do
    [ -f \$WIT/shapes/shapes_B\$b.json ] || need=1
    [ -f \$R/emitted/B\$b ] || need=1
    b=\$((b + 1))
  done
  if [ \$need = 0 ]; then
    st "survey: blocks \$lo-\$hi have their shape tables and their kernels"
  else
    xgroup survey \$lo \$hi
    b=\$lo
    while [ \$b -le \$hi ]; do
      [ -f \$WIT/shapes/shapes_B\$b.json ] ||
        ( cd \$HSRC && \$PY -m harness.witness.shapes \$WIT/witness_B\${b}_L $NLAY \$WIT/shapes/shapes_B\$b.json )
      b=\$((b + 1))
    done
    if [ ! -f \$WIT/blocksize.json ]; then
      # what a block of this context really costs on this host, measured on this
      # job's own first group; every later group's size is divided from it
      GBYTES=\$(tree_bytes \$WIT/witness_B\${hi}_L*)
      SBYTES=\$(tree_bytes \$WIT/shared)
      python3 - \$WIT/blocksize.json \$GBYTES \$SBYTES \$hi \$lo \$hi <<'PY'
import json, sys
out, gb, sb, b, lo, hi = (sys.argv[1], int(sys.argv[2]), int(sys.argv[3]),
                          int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6]))
json.dump({"measured_on_block": b, "group": f"{lo}-{hi}",
           "block_bytes": gb, "shared_bytes": sb}, open(out, "w"), indent=1)
print(f"disk: one block of this context is {gb / 2**30:.2f} GiB, "
      f"the block-invariant files are {sb / 2**30:.2f} GiB")
PY
    fi
    P=\$(pins_now)
    if [ -f \$R/pins.txt ]; then
      [ "\$P" = "\$(cat \$R/pins.txt)" ] ||
        { st "pins: blocks \$lo-\$hi ask for \$P and the store was emitted under \$(cat \$R/pins.txt). The worst case is not the highest block's; delete the kernel store and the emitted markers and run the job again"; exit 9; }
    else
      printf '%s\n' "\$P" > \$R/pins.txt
      st "pins: \$P, from the group that holds the highest block"
    fi
    PINS=\$P
    emit_group \$lo \$hi
    xdrop \$lo \$hi
  fi
  hi=\$((lo - 1))
done
SURVEY_SECS=\$((\$(date +%s) - SURVEY_T0))
PINS=\$(cat \$R/pins.txt)
st "survey done in \${SURVEY_SECS}s; pins: \$PINS"

# 6. one shape table over all $NBLOCK blocks, and the plan the proving processes
#    and the link check read.  The dumps the tables came from are gone and the
#    plan does not open them, it names them.
cp \$WIT/shapes/shapes_B*.json \$WIT/
if [ ! -f \$WIT/shapes_all.json ]; then
  st "shapes: the merge over $NBLOCK blocks"
  ( cd \$HSRC && \$PY -m harness.witness.shapes --merge \$WIT/shapes/shapes_B*.json --out \$WIT/shapes_all.json )
fi
cp \$WIT/shapes_all.json \$OUT/shapes.json
ALLPINS=\$(python3 - \$WIT/shapes_all.json <<'PY'
import json, sys
w = json.load(open(sys.argv[1]))["worst"]
print(f"--kmax {w['kmax']} --ao-rem-bits {w['ao_rem_bits']} --fold-rem-bits {w['fold_rem_bits']} --fold-alpha {w['fold_alpha']}")
PY
)
[ "\$ALLPINS" = "\$PINS" ] ||
  { st "pins: the merge over every block asks for \$ALLPINS and the store was emitted under \$PINS"; exit 9; }
if [ "$WITH_HEAD" = 1 ]; then
  ( cd \$HSRC && \$PY -m harness.witness.plan --dir \$WIT --blocks auto --with-block-0 --layers 0-$((NLAY - 1)) \
      --head \$HEADW --head-blocks $HEAD_BLOCKS --head-per-block \
      --layer-flags="$LAYER_FLAGS" --l0-flags="$L0_FLAGS" --l0-dir \$WIT \
      --head-flags="\$HEAD_FLAGS" --out \$OUT/plan.txt --emit-out \$R/emit.txt )
else
  ( cd \$HSRC && \$PY -m harness.witness.plan --dir \$WIT --blocks auto --with-block-0 --layers 0-$((NLAY - 1)) \
      --layer-flags="$LAYER_FLAGS" --l0-flags="$L0_FLAGS" --l0-dir \$WIT \
      --out \$OUT/plan.txt --emit-out \$R/emit.txt )
fi
N=\$(grep -cv '^#' \$OUT/plan.txt); st "plan: \$N segments"
[ "\$N" = "$SEGMENTS" ] ||
  { st "plan: \$N segments, and this configuration is $SEGMENTS; the shape tables or the head dumps are not all here"; exit 6; }
# Every segment of the plan the run will prove must be a segment some group
# emitted the kernels for.  The groups' plans and this one are written from the
# same shape tables with the same flags, so they are the same lines; if they are
# not, the store is short and the loop would stop on a fingerprint.
# The head segments, which no group emitted for: their shape comes off their own
# dump and not off a layer's.  head-plan.txt is every head line of the plan and
# emit-head.txt the distinct shapes among them, which is what plan.py's own
# emit list already holds -- two head dumps of one master table width are one
# shape and are emitted once.
grep -v '^#' \$OUT/plan.txt | grep -- '--ser-tag [A-Za-z0-9]*head' > \$R/head-plan.txt || true
grep -v '^#' \$R/emit.txt | grep -- '--ser-tag [A-Za-z0-9]*head' > \$R/emit-head.txt || true
NH=\$(grep -c . \$R/head-plan.txt || true)
[ "\$NH" = "$NHEAD" ] ||
  { st "plan: \$NH head segments, and this configuration is $NHEAD"; exit 6; }
if [ "$NHEAD" != 0 ] && [ ! -f \$R/emitted/head ]; then
  emit_lines \$R/emit-head.txt "the head segments"
  touch \$R/emitted/head
  rm -f \$R/install.done
fi
python3 - \$OUT/plan.txt \$R/emit.txt \$R <<'PY'
import glob, os, sys
plan, emit, r = sys.argv[1], sys.argv[2], sys.argv[3]
def body(p):
    return [l.rstrip("\n") for l in open(p) if l.strip() and not l.startswith("#")]
whole = body(plan)
parts = [l for p in sorted(glob.glob(os.path.join(r, "plan-g*.txt"))) for l in body(p)]
parts += body(os.path.join(r, "head-plan.txt")) if os.path.exists(os.path.join(r, "head-plan.txt")) else []
missing = sorted(set(whole) - set(parts))
if missing:
    for l in missing[:3]:
        print("  ", l[:160])
    sys.exit(f"{len(missing)} of the plan's segments are segments no group emitted for; "
             f"the store would be short a kernel and the loop would stop on a fingerprint")
# A shape the groups emitted and the plan no longer names costs nothing: a store
# dedups by fingerprint and only grows, and an unused kernel is never looked up.
# It happens when a plan is rewritten -- a head re-extracted under another
# variant, say -- and it is worth saying, not worth stopping for.
extra = sorted(set(parts) - set(whole))
if extra:
    print(f"note: {len(extra)} shape(s) were emitted for a plan line this plan does not "
          f"have; an unused kernel in the store costs nothing")
print(f"every one of the {len(whole)} plan segments is a segment its group emitted for; "
      f"{len(body(emit))} distinct shapes in the plan")
PY

# 7. the emitted kernels, installed into the vendored library and compiled into
#    the CUDA backend.  Once, after the sweep: the store only grows, so one
#    install carries every group's shapes.
K=\$SRC/prover/kernels
[ -d \$K ] || { st "no prover/kernels in this prover commit; the CUDA backend would evaluate constraints on the CPU"; exit 3; }
if [ ! -f \$R/install.done ]; then
  KT0=\$(date +%s)
  python3 \$K/install_constraint_kernels.py --fork \$SRC/nitroo --gen \$GEN
  python3 \$K/install_witness_gen_kernels.py --fork \$SRC/nitroo --gen \$GEN --src \$K
  find \$SRC/nitroo/crates/stwo/src/stwo_cuda/cuda \( -name '*.cu' -o -name '*.cuh' \) -exec touch {} +
  cp \$GEN/cudakernels.rs \$GEN/gencudakernels.rs \$SRC/prover/src/
  # an installed tree is no longer the commit that was pushed, and says so
  grep -q ' dirty\$' \$SRC/.source-commit || sed -i 's/\$/ dirty/' \$SRC/.source-commit
  ( cd \$SRC && CARGO_TARGET_DIR=\$B/t-cuda cargo build --release --locked -p zk-prover --features cuda )
  echo \$((\$(date +%s) - KT0)) > \$R/install.done
fi
KERNEL_SECS=\$(cat \$R/install.done 2>/dev/null || echo 0)
[ -n "\$KERNEL_SECS" ] || KERNEL_SECS=0
st "kernels installed"
# 8. the card's memory sampler.  One nvidia-smi that loops in milliseconds if
#    this driver supports it, and a once-a-second shell loop if it does not;
#    which one ran is in every mem_*.json beside the period it sampled at.
SAMPLER=loop; PERIOD=1
if [ "\$(timeout 3 nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -lms $SAMPLE_MS 2>/dev/null | wc -l)" -ge 3 ]; then
  SAMPLER=nvidia-smi-lms; PERIOD=\$(python3 -c "print($SAMPLE_MS / 1000)")
fi
st "memory sampler: \$SAMPLER, every \$PERIOD s"
sample_start() {   # sample_start <file>
  rm -f \$1
  if [ \$SAMPLER = nvidia-smi-lms ]; then
    nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -lms $SAMPLE_MS >> \$1 2>/dev/null &
  else
    ( while true; do nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits >> \$1; sleep 1; done ) &
  fi
  sampler=\$!
}
sample_stop() { kill \$sampler 2>/dev/null || true; }

# Which lines of the plan a group of blocks is.  Read off the plan's own
# --ser-tag rather than multiplied out of the block index, and refused if the
# group is not one contiguous range: the plan-slice the proving process is given
# counts the plan's non-comment lines and nothing else.
plan_range() {   # plan_range <first block> <last block> -> "<lo> <hi>"
  python3 - \$OUT/plan.txt \$1 \$2 <<'PY'
import re, sys
plan, b0, b1 = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
tag = re.compile(r"--ser-tag B(\d+)L")
idx, n, last = [], 0, None
for line in open(plan):
    s = line.strip()
    if not s or s.startswith("#"):
        continue
    m = tag.search(s)
    if m:
        last = int(m.group(1))
    # the head chunk carries no block in its tag and sits after the last block's
    # layers, which is the block it belongs to
    if last is not None and b0 <= last <= b1:
        idx.append(n)
    n += 1
assert idx, f"the plan has no line for blocks {b0}-{b1}"
lo, hi = idx[0], idx[-1] + 1
assert hi - lo == len(idx), f"blocks {b0}-{b1} are not one contiguous range of the plan"
print(lo, hi)
PY
}

# 9. the prove sweep: extract a group, prove its segments in processes of
#    $SLICE pipelined one segment ahead, keep the outputs and the serialized
#    statements and proofs, delete the group's dumps.  The serialized proofs are
#    small and they are what the link check reads at the end, so they cross the
#    groups; the dumps do not.
# The split is decided once, from the free space measured before the first
# group, and written down.  A job that is restarted takes the same split: a
# second run that grouped the blocks differently would put its process
# boundaries elsewhere and prove some segments twice.
if [ ! -s \$R/prove-groups.txt ]; then
  rm -f \$R/prove-groups.txt
  hi=$((NBLOCK - 1))
  while [ \$hi -ge 0 ]; do
    GK=\$(group_k \$hi)
    [ "\$GK" -ge 1 ] || { st "disk: no room for even one block's dumps; the job stops here"; exit 5; }
    lo=\$((hi - GK + 1)); [ \$lo -ge 0 ] || lo=0
    printf '%s %s %s\n' \$lo \$hi \$GK >> \$R/prove-groups.txt
    hi=\$((lo - 1))
  done
fi
st "prove: \$(wc -l < \$R/prove-groups.txt) groups, highest block first, ZK_PIPELINE=$PIPELINE"
while read -r lo hi GK <&3; do
  RANGE=\$(plan_range \$lo \$hi); PLO=\${RANGE%% *}; PHI=\${RANGE##* }
  st "group: blocks \$lo-\$hi, plan segments \$PLO to \$PHI"
  # a group every process of which is already proved needs no dumps at all
  todo=0; p=\$PLO
  while [ \$p -lt \$PHI ]; do
    [ -s \$OUT/\$(printf 'slice_%04d' \$p).json ] || todo=1
    p=\$((p + $SLICE))
  done
  GT0=\$(date +%s); GEXTRACT=0; GBYTES=0
  if [ \$todo = 0 ]; then
    st "group: blocks \$lo-\$hi are already proved"
  else
    ET0=\$(date +%s)
    xgroup prove \$lo \$hi
    GEXTRACT=\$((\$(date +%s) - ET0))
    GBYTES=\$(tree_bytes \$WIT/witness_B\${hi}_L*)
    p=\$PLO
    while [ \$p -lt \$PHI ]; do
      q=\$((p + $SLICE)); [ \$q -gt \$PHI ] && q=\$PHI
      tag=\$(printf 'slice_%04d' \$p); mtag=\$(printf 'mem_%04d' \$p)
      if [ -s \$OUT/\$tag.json ]; then st "\$tag already proved"; p=\$q; continue; fi
      sample_start \$R/\$tag.mem
      ZK_PIPELINE=$PIPELINE \$CUDA compose-chunks $SHARED \$PINS --plan \$OUT/plan.txt --plan-slice \$p:\$q --ser-dir \$SER \
          > \$OUT/\$tag.json 2> \$R/\$tag.err || { sample_stop; rm -f \$OUT/\$tag.json; st "\$tag failed, see \$R/\$tag.err"; exit 4; }
      sample_stop
      grep -c 'kernel fallback:' \$R/\$tag.err > \$OUT/\$tag.fallbacks || true
      python3 - \$R/\$tag.mem \$OUT/\$mtag.json \$PERIOD \$SAMPLER <<'PY'
import json, sys
src, out, period, sampler = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]
v = [int(t[-1]) for t in (l.split() for l in open(src)) if t and t[-1].isdigit()]
json.dump({"samples": len(v), "period_s": period, "sampler": sampler,
           "max_mib": max(v, default=0),
           "mean_mib": round(sum(v) / len(v), 1) if v else 0}, open(out, "w"))
PY
      st "\$tag done"
      p=\$q
    done
  fi
  SBYTES=\$(tree_bytes \$SER)
  printf '{"blocks": "%d-%d", "k": %d, "plan_lo": %d, "plan_hi": %d, "extract_seconds": %d, "group_seconds": %d, "block_bytes": %s, "ser_bytes_after": %s}\n' \
      \$lo \$hi \$GK \$PLO \$PHI \$GEXTRACT \$((\$(date +%s) - GT0)) \$GBYTES \$SBYTES >> \$R/groups.jsonl
  st "group: blocks \$lo-\$hi done; serialized proofs so far \$SBYTES bytes"
  xdrop \$lo \$hi
done 3< \$R/prove-groups.txt

# 10. every link between segments, checked on the verifier side over the
#     serialized statements and proofs of every group at once.  This is what the
#     groups were kept for: the dumps are gone and the grid does not need them.
NSER=\$(find \$SER -type f | wc -l)
st "serialized statements and proofs: \$NSER files for \$N segments"
[ "\$NSER" -ge "\$N" ] ||
  { st "the serialized statements and proofs are \$NSER files for \$N segments. A restart skips a group whose slice outputs are already written, so proofs deleted after those outputs were written are never made again; delete out/slice_*.json for the groups whose proofs are gone and run the job again"; exit 7; }
GRIDT0=\$(date +%s)
GRIDV=""
[ "$GRID_VERIFY" != 1 ] || GRIDV="--verify"
st "links: over $SEGMENTS segments, with the prompt\${GRIDV:+ and the verifier}"
\$SIMD boundary-grid --dir \$SER --plan \$OUT/plan.txt --prompt \$OUT/prompt.json \$GRIDV \
    --expect-layer-links $LAYER_LINKS --expect-token-links $TOKEN_LINKS \
    > \$OUT/grid.json 2> \$R/grid.err
GRID_SECS=\$((\$(date +%s) - GRIDT0))
st "links checked in \${GRID_SECS}s"

# 11. what the job spent where.  The four timing scopes the constants use are
#     the prover's own and are in the slice outputs; this file is the phases
#     around them, so that the extraction and the kernel work can never be
#     read into the loop.
python3 - \$WIT \$OUT \$KERNEL_SECS \$GRID_SECS \$((\$(date +%s) - JOB_T0)) \$R/groups.jsonl <<'PY'
import glob, json, os, sys
wit, out, kernel, grid, job, gjson = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), sys.argv[6]
rows = [json.load(open(f)) for f in sorted(glob.glob(os.path.join(wit, "extract_*.json")))]
rows_g = [json.loads(l) for l in open(gjson)] if os.path.exists(gjson) else []
# a restarted job writes a second row for a group it did again; the last wins
groups = list({g["blocks"]: g for g in rows_g}.values())
groups.sort(key=lambda g: -g["plan_lo"])
by = {}
for r in rows:
    by[r.get("sweep", "extract")] = by.get(r.get("sweep", "extract"), 0) + r["seconds"]
json.dump({"passes": rows, "seconds": sum(r["seconds"] for r in rows), "by_sweep": by},
          open(os.path.join(out, "extract.json"), "w"), indent=1)
json.dump({"groups": groups,
           "extract_seconds": by, "kernel_seconds": kernel, "grid_seconds": grid,
           "job_seconds": job,
           "note": "The loop, commit, stwo total and whole wall scopes are the prover's "
                   "own and live in the slice outputs. The extraction, the kernel work "
                   "and the deletions between the groups are here and are in none of them."},
          open(os.path.join(out, "timing.json"), "w"), indent=1)
json.dump(groups, open(os.path.join(out, "groups.json"), "w"), indent=1)
print("extract:", sum(r["seconds"] for r in rows), "s over", len(rows), "passes,", by)
print("kernels:", kernel, "s; grid:", grid, "s; job:", job, "s")
PY
python3 - \$WIT \$OUT/disk.json <<'PY'
import json, os, shutil, sys
wit, out = sys.argv[1], sys.argv[2]
m = os.path.join(wit, "blocksize.json")
d = json.load(open(m)) if os.path.exists(m) else {}
du = shutil.disk_usage(wit)
d.update({"filesystem_free_bytes": du.free, "filesystem_total_bytes": du.total})
json.dump(d, open(out, "w"), indent=1)
print(f"disk: {du.free / 2**30:.1f} GiB free of {du.total / 2**30:.1f} GiB at the end")
PY

# 12. the gate: every segment of the plan proved, no skip in effect, every edge
#     bound, every link run and passed, and no lookup evaluated on the host
#     instead of by its generated kernel
python3 - \$OUT \$N <<'PY'
import json, pathlib, sys
out, expect = pathlib.Path(sys.argv[1]), int(sys.argv[2])
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
if n != expect:
    bad.append(f"the outputs hold {n} segments and the plan has {expect}")
for g in json.loads((out / "groups.json").read_text()):
    print(f"group blocks {g['blocks']}: plan {g['plan_lo']}:{g['plan_hi']}, "
          f"extract {g['extract_seconds']} s, group {g['group_seconds']} s, "
          f"one block {g['block_bytes'] / 2**30:.1f} GiB")
g = json.loads((out / "grid.json").read_text())["result"]
print(f"grid: {g['links_passed']}/{g['links_run']} of {g['links_expected']} implied links passed; "
      f"all_chain {g['all_chain']}")
t = g.get("tokens") or {}
print(f"ids: {t.get('prompt_positions')} prompt and {t.get('generated_positions')} generated "
      f"positions checked, {len(t.get('mismatches') or [])} bad, "
      f"{len(t.get('unbacked') or [])} unbacked; verified {(g.get('verified') or {}).get('run', 0)}")
if not g["all_chain"]:
    bad.append(f"the grid did not chain: {g['failures'][:3]}")
peak = max((json.loads(f.read_text())["max_mib"] for f in out.glob("mem_*.json")), default=0)
print(f"total: {n} segments, {fresh:,.0f} fresh cells, the card held at most {peak} MiB")
if bad:
    sys.exit("; ".join(bad))
print("no skip; every edge bound; every implied link passed; no kernel fallback")
PY
rm -rf \$SER
st "done"
JOBEOF
drv_start "$JOB"
rm -f "$JOB"
