#!/bin/sh
# quality-0p5b: the perplexity of every quantization variant on the small model.
#
#   tools/drivers/quality-0p5b.sh <host> <prover-commit> <harness-commit>
#
# Qwen2.5-0.5B-Instruct, on the host's cores, over the fixed corpus: one
# perplexity per quantization variant, on the same 40 chunks of 512 tokens for
# every variant, and the per-token losses each was measured from, so that the
# difference between two variants carries a standard error paired over
# positions rather than an assumed one.
#
# This is a harness run and not a prover run.  Nothing here proves anything: it
# measures the arithmetic the prover constrains, which is what makes
# `docs/quantization.md`'s claim -- that the quality numbers describe exactly
# the arithmetic that is proved -- a claim about measured things on both sides.
# So its outputs carry no binding table and no proof digest, and its manifest
# says `kind` `harness` and names no prover commit.  `lib/manifest.py` grew that
# second path for this run; see issue #51.
#
# The prover commit argument is therefore unused: no prover is built, pushed or
# run, and the manifest records none.  It stays in the signature because every
# driver in this repository takes the same three arguments.
#
# The harness commit must be one whose outputs carry a provenance block
# (zk-prover pull request 63).  An earlier commit writes none, and a run whose
# outputs say nothing about where they came from is not admissible.
#
# The job itself is `lib/quality-job.sh`, so this file is the configuration and
# nothing else.
#
# The first call pushes zk-prover at the harness commit to the host, starts the
# job detached and prints the poll command.  Every later call with the same
# arguments prints the status; once the status says done it fetches the outputs
# into runs/<run-id>/, writes manifest.json from the harness's provenance
# block, and runs check.py.  Nothing measured is typed in here.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
HOST=${1:?host alias}; PROVER=${2:?prover commit}; HARNESS=${3:?harness commit}
ZK_PROVER=${ZK_PROVER_DIR:-$ROOT/../zk-prover}     # a local clone to archive the commits from
NAME=quality-0p5b
. "$HERE/lib/driver.sh"
. "$HERE/lib/quality-job.sh"

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=quality              # a measurement of the arithmetic, not of a proof
MODEL=${ZK_MODEL:-Qwen/Qwen2.5-0.5B-Instruct}
DEVICE=cpu                 # the small model's rows are the CPU harness's
CHUNKS=40                  # 40 chunks of 512 tokens: 20,480 scored positions
XTHREADS=20
# The variants `docs/quantization.md` names, in the order it names them: the
# three baselines, the int8 variant a reader would actually deploy, the sequence
# of configurations that led to the reported one, the four attention-output
# probes, the three delay probes, and the reported variant itself.
SPECS="fp32 dynamic-int8 static w8a16 b6-design-p2o b10-design b10-residual-stream b10-final y-attnout-w10 y-attnout-w11 y-attnout-w12 y-attnout-w16 y-delay-v y-delay-up y-delay-all y-delay-vw12"
REQUIRED="$SPECS"          # this model takes every variant; all of them are rows
COSINE_SPECS=""            # the cosine similarity is the transfer check's, not this one's

drv_finish "$(drv_status)"

# ---- start: push the pinned harness, then the job ----------------------------
drv_check_commits
# The shared build tree is keyed on the prover commit, because the campaigns
# that share it share a prover build.  This run has no prover build and pins a
# harness commit of its own, so it keys its tree on that instead: pushing a
# different harness tree into the prover campaigns' directory would replace the
# tree they are built against.
BUILD="build/$(printf '%.12s' "$HARNESS")"
drv_push "$BUILD/harness-src" "$HARNESS"

JOB=$(mktemp)
drv_quality_job > "$JOB"
drv_start "$JOB"
rm -f "$JOB"
