#!/bin/sh
# control-flags-off-c4096: headline-c4096's plan with the five GKR reductions
# switched off.  A control, never a headline row (docs/decisions).
#
#   tools/drivers/control-flags-off-c4096.sh <host> <prover-commit> <harness-commit>
#
# The same 289 segments, the same witnesses, the same shared pins and the same
# binding gadgets as `headline-c4096.sh`; the five `--gkr-*` reductions are the
# only difference, and they choose the LogUp backend for a component without
# changing what is proved.  So the pair prices the reductions: what they remove
# from the committed cells and from the proving time, measured on one plan.
#
# The paper's configuration has all five on.  Every constant this driver backs
# names the control it came from and no number here is a throughput the paper
# cites.
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
HEAD_SPEC=b10-final
CTX=4096; S=512
NBLOCK=$(( (CTX + S) / S ))
NLAY=32
SHARED="--round even --numbits 9 --z-hi-bits 7 --variants intexp --bands 16,8,8 --tight-table"
# no GKR here: that is the whole of the difference from headline-c4096
LAYER_FLAGS="--round even --diagonal-block"   # every binding gadget is still on; no skip flag anywhere
L0_FLAGS=""
HEAD_FLAGS="--ao-rem-bits 23"
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
KERNEL_FAMILIES=b65_chan_eval,b65_key_eval,b65_row_eval,b65_attn_out_eval,b65_dequant_eval,b65_freivalds_eval,b65_exp_table_eval,b65_table_eval,b65_residual_stream_eval,b65_residual_stream_table_eval
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
