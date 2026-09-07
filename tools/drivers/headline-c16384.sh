#!/bin/sh
# headline-c16384: the paper's headline configuration.
#
#   tools/drivers/headline-c16384.sh <host> <prover-commit> <harness-commit>
#
# One 16,384-token prompt and its 512 output tokens, every position proved from
# the embedding up: 33 token blocks of 32 layer segments, 1,056 segments, on the
# CUDA backend, in processes of 64 segments each.  Every layer segment binds its
# residual stream to the next layer's and its keys and values to the next
# block's; the verifier side checks every link afterwards.  The five GKR
# reductions are on, which is the paper's configuration (docs/decisions), and no
# skip flag appears anywhere.
#
# The same statement as `headline-c4096.sh` at four times the context, and the
# same job body: `lib/sequence-job.sh` is what runs on the host, so this file is
# the configuration and nothing else.  Rewriting it on that body is what issue
# #47 asks for; the four things it lists -- an unmarked dirty build, a layer
# link count that assumed the head chunk was an unchecked end, and the
# workarounds for zk-prover #55 and #57 -- are all in the shared body, which the
# context 4,096 campaign ran.
#
# Not yet run.  Two things stand between this driver and the run it describes,
# and both are measured rather than assumed:
#
#   - The card, which is settled: it fits.  `memory-probe-c16384.sh` measured
#     the plan's largest segment at 78,843 MiB of this card's 81,559, pipelined
#     or not, so the loop has 2,716 MiB to spare and `PIPELINE` below is 1.
#   - The extraction's size, which is not settled and is what this driver waits
#     on.  A block's witness grows with the prefix the block reads.  The probe
#     measured the last block of this context at 12.16 GiB and the block-invariant
#     files at 7.49 GiB, and the same per-layer growth fitted on the nine blocks
#     of `headline-c4096` gives 302.4 GiB for the 33 blocks this plan reads, so
#     the extraction is 310 GiB before a single segment is proved.  A host with
#     that much free space runs this driver as it stands; a host without one
#     needs the extraction and the loop interleaved a few blocks at a time, which
#     is a change to `lib/sequence-job.sh` and not to this file.
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
. "$HERE/lib/sequence-job.sh"

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=headline             # a configuration the paper cites, not a control
MODEL=${ZK_MODEL:-unsloth/Llama-3.1-8B-Instruct}
SPEC=y-delay-vw12          # the quantization variant the paper reports (docs/decisions)
HEAD_SPEC=b10-final        # the output head's variant; both variants give the head the same arithmetic
CTX=16384; S=512
NBLOCK=$(( (CTX + S) / S ))  # 33: the prompt's 32 blocks and the output block
NLAY=32
SHARED="--round even --numbits 9 --z-hi-bits 7 --variants intexp --head-groups 16,8,8 --tight-table"
GKR="--gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
LAYER_FLAGS="--round even --diagonal-block $GKR"   # every binding gadget is on by default; no skip flag anywhere
L0_FLAGS=""
HEAD_FLAGS="--ao-rem-bits 23 $GKR"
HEAD_LAYER=16              # the layer the head dump is extracted at; the grid places the segment after the last layer
# The output head's segment is out of the plan (zk-prover #58): an honest head
# segment is rejected under the sound defaults, because the seam between the
# attention output and the o matmul is checked on a chunk whose family is the
# final norm and cannot state it.  Nothing in a driver gets past that -- the
# loader refuses a head dump without its layer's o matmul -- so the sequence is
# proved from the embedding up to the last layer's residual, and the token the
# head emits is bound by nothing until the prover is fixed.  One variable back
# to 1 when it is.
WITH_HEAD=0
OFFSET=0                   # the corpus from its first token; the c4096 row's window ends where this one ends
# ZK_PIPELINE.  Pipelining generates segment k+1 while segment k is proved and
# holds two segments' device memory at once, so at this context it is what
# decides whether the loop fits the card at all.  It is on because a probe
# measured it, not because it is faster: in
# `runs/2026-09-07-memory-probe-c16384-h100`, four segments of the last block
# peaked at 72,379 MiB whether the pipeline was on or off, and layer 0 -- the
# plan's largest segment, the only one carrying the embedding gadget -- peaked
# at 78,843 MiB both on its own and paired with layer 1 under the pipeline.
# The card has 81,559 MiB.  So the second segment in flight costs this card
# nothing, and the pipeline takes 23 per cent off the loop.
PIPELINE=1
SLICE=64                   # segments per process: 1,056 -> 17 processes
XTHREADS=20                # torch threads for the extraction
IDS=${ZK_IDS:-}            # token ids (.npy) already on the host; empty = generate them
KERNEL_FAMILIES=zk_chan_eval,zk_key_eval,zk_row_eval,zk_attn_out_eval,zk_dequant_eval,zk_freivalds_eval,zk_exp_table_eval,zk_table_eval,zk_residual_stream_eval,zk_residual_stream_table_eval
# The links the grid implies, which the grid is told before it counts them.
# Inside a block, consecutive layers: 31 per block, and one more on the last
# block when the head is in the plan, because the head sits at the layer
# coordinate after the last layer and commits the residual it consumed as its
# own input side.  Across blocks, at each of the 32 layers, consecutive blocks;
# the head performs no attention, holds no key/value cache and is never a
# token-axis edge.  Without the head that is 1,023 and 1,024, the 2,047 links
# issue #1 names.
LAYER_LINKS=$(( NBLOCK * (NLAY - 1) + WITH_HEAD ))
TOKEN_LINKS=$(( (NBLOCK - 1) * NLAY ))

drv_finish "$(drv_status)"

# ---- start: push the pinned sources, then the job ----------------------------
drv_check_commits
BUILD=$(drv_build_root)
drv_push "$BUILD/src" "$PROVER"
drv_push "$BUILD/harness-src" "$HARNESS"

JOB=$(mktemp)
drv_sequence_job > "$JOB"
drv_start "$JOB"
rm -f "$JOB"
