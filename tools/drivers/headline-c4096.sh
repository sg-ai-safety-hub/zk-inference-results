#!/bin/sh
# headline-c4096: the paper's configuration at context 4,096.
#
#   tools/drivers/headline-c4096.sh <host> <prover-commit> <harness-commit>
#
# One 4,096-token prompt and its 512 output tokens, every position proved from
# the embedding up: 9 token blocks of 32 layer segments, and the output head over
# the last prompt block and the generated block, 290 segments, on the CUDA
# backend, pipelined one segment ahead, in processes of 64 segments each.  Every
# layer segment binds its residual stream to the next layer's and its keys and
# values to the next block's; the verifier side checks every link afterwards,
# verifies every segment's proof, and chains every published id to the prompt or
# to the argmax a head segment proved for the position before it.  The five GKR
# reductions are on, which is the paper's configuration (docs/decisions), and no
# skip flag appears anywhere.
#
# `MODEL_ROOTS` below is the one optional part of the configuration and it is
# empty: given a path to a recorded model commitment the grid also compares
# every segment's model root against it, and the run fails on a segment whose
# root is not the commitment's.  Nothing is derived for it.
#
# The same statement as `headline-c16384.sh` at a quarter of the context, and
# the first of the four campaigns at this context: it extracts the witnesses
# the control, the negative controls and the ablation re-prove, and it leaves
# the prover build and the kernel store where they find them.  The job itself
# is `lib/sequence-job.sh`, so this file is the configuration and nothing else.
#
# The first call pushes zk-prover at the two commits to the host, starts the
# job detached and prints the poll command.  Every later call with the same
# arguments prints the status; once the status says done it fetches the
# outputs into runs/<run-id>/, writes manifest.json from the prover's
# provenance block, and runs check.py.  Nothing measured is typed in here.
#
# Host time, from the run this driver recorded: see REPRODUCE.md.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
HOST=${1:?host alias}; PROVER=${2:?prover commit}; HARNESS=${3:?harness commit}
ZK_PROVER=${ZK_PROVER_DIR:-$ROOT/../zk-prover}     # a local clone to archive the commits from
NAME=headline-c4096
. "$HERE/lib/driver.sh"
. "$HERE/lib/sequence-job.sh"

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=headline             # a configuration the paper cites, not a control
MODEL=${ZK_MODEL:-unsloth/Llama-3.1-8B-Instruct}
SPEC=y-delay-vw12          # the quantization variant the paper reports (docs/decisions)
HEAD_SPEC=$SPEC            # the head proves the argmax of THIS variant's residual stream
CTX=4096; S=512
NBLOCK=$(( (CTX + S) / S ))  # 9: the prompt's 8 blocks and the output block
NLAY=32
SHARED="--round even --numbits 9 --z-hi-bits 7 --variants intexp --head-groups 16,8,8 --tight-table"
GKR="--gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
LAYER_FLAGS="--round even --diagonal-block $GKR"   # every binding gadget is on by default; no skip flag anywhere
L0_FLAGS=""
HEAD_FLAGS="$GKR"            # the head line's pins come off the head dumps, not from here
HEAD_LAYER=16              # the layer the head dump is extracted at; the grid places the segment after the last layer
# The output head is proved over the last prompt block and over the generated
# block, so every token the sequence emits is bound to a proved argmax
# (docs/decisions/2026-09-08-the-head-is-proved-over-the-last-prompt-block.md).
# A generated position's id has to equal the argmax the head proved for the
# position before it, and the position before the FIRST generated one is the
# last position of the last prompt block, so a plan with a head on the
# generated block alone leaves that one id backed by nothing. Two head
# segments, one head dump per block because a head dump carries the position its
# block starts at, and `boundary-grid --verify --prompt` then backs every
# generated id and verifies every segment's proof.
#
# The head segment needed zk-prover #61: an honest one was rejected under the
# sound defaults, because the seam between the attention output and the o matmul
# was checked on a chunk whose kernel group is the final norm and cannot state
# it (zk-prover #58). A prover commit without the fix refuses it and HEAD_BLOCKS
# goes back to empty; the plan, the extraction, the link count, the run's own
# segment count and the verifier's two arguments all follow it.
HEAD_BLOCKS="$((NBLOCK - 2)),$((NBLOCK - 1))"   # the last prompt block and the generated one
NHEAD=2
VERIFY=1                   # the head segments back every generated id, so the grid checks them
# The corpus opens with front matter, and a 4,096-token prompt taken from token
# 0 ends inside its list of illustrations, where the greedy continuation is a
# repeating index line -- a real decode and a degenerate benchmark.  The window
# is moved to the end of the 16,384-token prompt instead, so this row and the
# context 16,384 row read the same prose (harness/witness/gen_ids.py).
OFFSET=$(( 16384 - CTX ))
PIPELINE=1                 # ZK_PIPELINE: generate segment k+1 while proving segment k
# The serialized statements and proofs are kept after the link check instead of
# being deleted with the run, because the model-commitment campaign checks each
# of them against the published model commitment and cannot make them again for
# less than this run's price.  They are on the host, never here.
KEEP_SER=1
SLICE=64                   # segments per process: 289 -> 5 processes
XTHREADS=20                # torch threads for the extraction
IDS=${ZK_IDS:-}            # token ids (.npy) already on the host; empty = generate them
KERNEL_FAMILIES=zk_chan_eval,zk_key_eval,zk_row_eval,zk_attn_out_eval,zk_dequant_eval,zk_freivalds_eval,zk_exp_table_eval,zk_table_eval,zk_residual_stream_eval,zk_residual_stream_table_eval
# The published model commitment, empty by default.  Set it to a `model-roots`
# manifest this repository recorded and the final grid compares every segment's
# model root against that file and fails the run on a segment whose root is not
# in it; the commitment derived over this very plan is
# `runs/2026-09-09-model-commitment-h100/model-roots.json`, and a path is read
# from the repository root.  Nothing is derived here: that campaign derived the
# table once, at the price its REPRODUCE entry records, and this reuses it.
# Empty is what every run so far made -- the model each segment proves against
# stays an unchecked end the grid names, and `model-commitment.sh` makes the
# comparison afterwards over the proofs this run keeps.  `lib/driver.sh` says
# why the shape roots are not compared this way.
MODEL_ROOTS=${ZK_MODEL_ROOTS:-}
# The links the grid implies, which the grid is told before it counts them.
# Inside a block, consecutive layers: 31 per block, and one more on the last
# block when the head is in the plan, because the head sits at the layer
# coordinate after the last layer and commits the residual it consumed as its
# own input side.  Across blocks, at each of the 32 layers, consecutive blocks;
# the head performs no attention, holds no key/value cache and is never a
# token-axis edge.
LAYER_LINKS=$(( NBLOCK * (NLAY - 1) + NHEAD ))
TOKEN_LINKS=$(( (NBLOCK - 1) * NLAY ))

drv_finish "$(drv_status)"

# ---- start: push the pinned sources, then the job ----------------------------
drv_check_commits
BUILD=$(drv_build_root)
drv_push "$BUILD/src" "$PROVER"
drv_push "$BUILD/harness-src" "$HARNESS"
drv_model_roots            # a no-op unless MODEL_ROOTS names one

JOB=$(mktemp)
drv_sequence_job > "$JOB"
drv_start "$JOB"
rm -f "$JOB"
