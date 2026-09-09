#!/bin/sh
# control-flags-off-c4096: headline-c4096's plan with the five GKR reductions
# switched off.  A control, never a headline row (docs/decisions).
#
#   tools/drivers/control-flags-off-c4096.sh <host> <prover-commit> <harness-commit>
#
# The same 290 segments, the same witnesses, the same shared pins and the same
# binding gadgets as `headline-c4096.sh`; the five `--gkr-*` reductions are the
# only difference, and they choose the LogUp backend for a component without
# changing what is proved.  So the pair prices the reductions: what they remove
# from the committed cells and from the proving time, measured on one plan.
#
# The first segment of the first token block would not prove in this
# configuration until zk-prover #62: the placeholder claims the prover lowers
# its evaluators from were sized by a formula with a margin, and the segment
# with no prefix is the shape that ran the margin out.  Both kernel emitters ran
# out of the same margin on the same shape and both refusals are recorded beside
# the outputs whatever happens, because a refused lowering costs either nothing
# or a lookup evaluated on the host, and the gate fails the run on any of those.
#
# The paper's configuration has all five on.  Every constant this driver backs
# names the control it came from and no number here is a throughput the paper
# cites.
#
# `MODEL_ROOTS` below is the one optional part of the configuration and it is
# empty, exactly as it is in `headline-c4096.sh`: given a path to a recorded
# model commitment the grid also compares every segment's model root against it.
# The reductions are a backend choice for an interaction argument and the model
# tree is the weights' own columns, so this plan's model roots are the headline
# plan's; a root that is not the commitment's fails the run and names the
# segment, which is the answer the comparison exists to give.
#
# The job body is `lib/sequence-job.sh`, so this file differs from the headline
# driver in its flags and its label alone.  The witnesses, the prover build and
# the kernel store are the ones the headline campaign left on the host; the
# kernel store gains this configuration's shapes and the CUDA backend is
# rebuilt with them.
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
NAME=control-flags-off-c4096
. "$HERE/lib/driver.sh"
. "$HERE/lib/sequence-job.sh"

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=control              # not a configuration the paper cites
MODEL=${ZK_MODEL:-unsloth/Llama-3.1-8B-Instruct}
SPEC=y-delay-vw12
HEAD_SPEC=$SPEC            # the head proves the argmax of THIS variant's residual stream
CTX=4096; S=512
NBLOCK=$(( (CTX + S) / S ))
NLAY=32
SHARED="--round even --numbits 9 --z-hi-bits 7 --variants intexp --head-groups 16,8,8 --tight-table"
# no GKR here: that is the whole of the difference from headline-c4096
LAYER_FLAGS="--round even --diagonal-block"   # every binding gadget is still on; no skip flag anywhere
L0_FLAGS=""
HEAD_FLAGS=""              # no reduction here, and the pins come off the head dumps
HEAD_LAYER=16              # the layer the head dump is extracted at; the grid places the segment after the last layer
# The output head is proved over the last prompt block and over the generated
# block, exactly as `headline-c4096.sh` proves it: the two plans have to be the
# same plan or the pair does not price the reductions, and a control that proved
# one segment fewer than the row it is compared with would price that segment as
# well.  The decision that puts a head segment on the last prompt block is
# docs/decisions/2026-09-08-the-head-is-proved-over-the-last-prompt-block.md.
HEAD_BLOCKS="$((NBLOCK - 2)),$((NBLOCK - 1))"   # the last prompt block and the generated one
NHEAD=2
VERIFY=1                   # the same check the headline row's grid makes
# The corpus opens with front matter, and a 4,096-token prompt taken from token
# 0 ends inside its list of illustrations, where the greedy continuation is a
# repeating index line -- a real decode and a degenerate benchmark.  The window
# is moved to the end of the 16,384-token prompt instead, so this row and the
# context 16,384 row read the same prose (harness/witness/gen_ids.py).
OFFSET=$(( 16384 - CTX ))
PIPELINE=1
SLICE=64
XTHREADS=20
IDS=${ZK_IDS:-}
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
