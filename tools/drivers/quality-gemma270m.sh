#!/bin/sh
# quality-gemma270m: does the quantization configuration transfer to another
# architecture?
#
#   tools/drivers/quality-gemma270m.sh <host> <prover-commit> <harness-commit>
#
# Gemma-3-270M, on the host's cores, over the same fixed corpus and the same 40
# chunks of 512 tokens the other quality campaigns use.  The question is not
# how good this model is; it is whether the configuration the paper reports
# costs about the same on a model whose attention is not the one it was
# designed against.  Gemma-3 interleaves sliding-window layers with full
# attention, so its keys and values are not the shape the configuration was
# tuned on, and a variant that only works on Llama would show here.
#
# Two statistics, because a perplexity alone does not answer it.  The
# perplexity says what the configuration costs; the cosine similarity of the
# logits against fp32 says how far the whole distribution moved, which is the
# statistic a published comparison of quantized models reports and which a
# perplexity can hide.  Both are measured on the same chunks, and the paired
# standard error of every perplexity difference comes from the per-token
# losses.
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
NAME=quality-gemma270m
. "$HERE/lib/driver.sh"
. "$HERE/lib/quality-job.sh"

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=quality              # a measurement of the arithmetic, not of a proof
# The weights come from the mirror the harness has always used; the original
# repository is gated and cannot be fetched without an account.
MODEL=${ZK_MODEL:-unsloth/gemma-3-270m}
DEVICE=cpu                 # the transfer check is the CPU harness's
CHUNKS=40                  # 40 chunks of 512 tokens: 20,480 scored positions
XTHREADS=20
# Four variants, and only four: the float reference, the weakest int8 there is,
# the fixed configuration, and the variant the paper reports.  A transfer check
# does not need the whole sequence of configurations -- what it has to answer is
# whether the reported configuration costs here what it costs on the 8B model,
# and the two baselines are what that cost is read against.
SPECS="fp32 static b10-final y-delay-vw12"
# `y-delay-vw12` on this architecture has never been measured.  It is
# structurally supported and it is the variant the paper reports, so it is
# asked for; it is left out of the required set so that, if this model's
# attention will not take it, the three rows that do measure are still a run
# and the refusal is recorded rather than losing them.
REQUIRED="fp32 static b10-final"
COSINE_SPECS="static b10-final y-delay-vw12"

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
