#!/bin/sh
# The machinery every campaign driver repeats: the status file, the finish
# path (fetch, manifest, check), the pinned push, and the job start.  Sourced,
# never run.  It holds no configuration: what a run measures is written in the
# driver that sources this, and nowhere else.
#
#     . "$HERE/lib/driver.sh"
#
# The driver sets HERE, ROOT, HOST, PROVER, HARNESS, ZK_PROVER and NAME first.
#
# The four campaign drivers at context 4096 share one prover build, one kernel
# store and one witness set on the host, because host time is rented and a
# rebuild per campaign buys nothing: `drv_build_root` names that directory and
# `drv_push` leaves a tree that is already at the pinned commit alone, so the
# second campaign to run finds the sources, the target directories and the
# store where the first left them.  The kernel store only grows -- a store
# dedups by fingerprint and a kernel that is present and unused costs nothing
# -- so each campaign adds its own shapes and rebuilds incrementally.

# ---- the shared build tree, one per pinned prover commit ---------------------
# A path under the remote home, written without `$HOME` because `push.sh`
# quotes its destination and the remote shell would not expand it.  Twelve hex
# digits are enough to read and enough not to collide; the manifest carries the
# full hash either way.
drv_build_root() {
    echo "build/$(printf '%.12s' "$PROVER")"
}

drv_status() {
    ssh -o BatchMode=yes "$HOST" "cat ~/runs/$NAME.status 2>/dev/null || true"
}

# ---- finish: fetch, derive, manifest, check ----------------------------------
# Called with the status line.  Returns only while the run is not finished; on
# a finished run it exits the driver.
drv_finish() {
    ST=$1
    case "$ST" in
      *"done exit=0"*)
        TMP=$(mktemp -d "$ROOT/runs/.fetch-$NAME.XXXXXX")
        "$ROOT/tools/remote/fetch.sh" "$HOST" "$NAME" "$TMP"
        # A run may need an output that no host makes, because it is derived
        # from runs this repository already holds.  A driver with one defines
        # `drv_derive`, called with the fetched directory and a file to write
        # its record to; the record goes into the manifest under `derived`, so
        # what a run took from an earlier run is stated in the run's own
        # manifest and nowhere else.  A derivation that refuses stops the
        # finish: the outputs stay in the fetch directory and no run directory
        # is written.
        DERIVED=
        if command -v drv_derive >/dev/null 2>&1; then
            DERIVED=$(mktemp)
            drv_derive "$TMP" "$DERIVED"
        fi
        # DRV_KIND, when the driver sets it, is what the run's outputs cannot say
        # for themselves: `verifier` for a run that makes no proof and checks
        # proofs another run made.  Unset is the prover's own answer.
        # The run name and the driver's file name are the same thing for every
        # driver but one.  `memory-probe-context.sh` takes the context as an
        # argument and names its runs after it, so that two contexts are two
        # status files, two host directories and two run ids; `DRV_DRIVER` is
        # then the file it lives in, because a manifest has to name a driver
        # that exists, and `--run-name` keeps the run id the run's own name.
        # Unset, both are `$NAME`, which is what every other driver has.
        python3 "$HERE/lib/manifest.py" --driver "tools/drivers/${DRV_DRIVER:-$NAME}.sh" \
            --run-name "$NAME" --fetched "$TMP" \
            --runs "$ROOT/runs" --prover-commit "$PROVER" --harness-commit "$HARNESS" \
            ${DRV_KIND:+--kind "$DRV_KIND"} ${DERIVED:+--derived "$DERIVED"} \
            --date "$(printf '%s\n' "$ST" | awk '/^done/ {print substr($3, 1, 10)}')"
        [ -z "$DERIVED" ] || rm -f "$DERIVED"
        rmdir "$TMP" 2>/dev/null || true
        (cd "$ROOT" && python3 tools/constants/check.py)
        exit 0 ;;
      *"done exit="*)
        echo "$NAME on $HOST failed: $ST"
        echo "log:     ssh $HOST tail -50 '~/runs/$NAME.log'"
        echo "restart: ssh $HOST rm -f '~/runs/$NAME.status' && $0 $HOST $PROVER $HARNESS"
        echo "         (a job re-run keeps the witnesses, the build and any slice"
        echo "          whose output is already written, and redoes the rest)"
        exit 1 ;;
      running*)
        echo "$NAME on $HOST: $ST"
        echo "poll: ssh $HOST cat '~/runs/$NAME.status'"
        exit 0 ;;
    esac
}

# ---- the pinned sources ------------------------------------------------------
drv_check_commits() {
    # a git directory, not a `.git` directory: a linked work tree has a `.git` file
    git -C "$ZK_PROVER" rev-parse --git-dir >/dev/null 2>&1 ||
      { echo "no zk-prover clone at $ZK_PROVER (set ZK_PROVER_DIR)" >&2; exit 2; }
    git -C "$ZK_PROVER" cat-file -e "$PROVER^{commit}" || { echo "unknown prover commit $PROVER" >&2; exit 2; }
    git -C "$ZK_PROVER" cat-file -e "$HARNESS^{commit}" || { echo "unknown harness commit $HARNESS" >&2; exit 2; }
}

# drv_push <dest> <commit>
#
# Push the tree at <commit> to <dest> on the host, unless <dest> already holds
# it.  `push.sh` extracts with `-m`, so every pushed file gets the host's
# current time and cargo rebuilds the world; a tree whose `.source-commit`
# already names the pinned commit is the tree the last campaign built, and
# pushing over it would throw that build away.  A tree marked `dirty` by an
# installed kernel store still names its commit and is still that tree.
drv_push() {
    dest=$1; commit=$2
    have=$(ssh -o BatchMode=yes "$HOST" "cat \"\$HOME/$dest/.source-commit\" 2>/dev/null || true")
    case "$have" in
      "$commit"|"$commit "*)
        echo "drv_push: $HOST:$dest is already at $commit${have#$commit}; not pushed" ;;
      *)
        "$ROOT/tools/remote/push.sh" "$HOST" "$ZK_PROVER" "$dest" "$commit" ;;
    esac
}

# ---- the published model commitment, when the driver was given one ------------
# `MODEL_ROOTS` is a path to a `model-roots` manifest this repository recorded --
# `runs/<run-id>/model-roots.json`, written by `tools/drivers/model-commitment.sh`
# -- and it is empty in every driver.  Set it and the run's own grid compares
# every segment's model root against that manifest and fails the run on a
# segment whose root is not in it; leave it and the run makes the comparisons it
# always made, with the model each segment proves against an unchecked end the
# grid names.  Nothing is derived either way: deriving the table costs what
# `model-commitment` records for it, and it is the same table for every run of
# one model.
#
# The file travels to the host beside the job rather than being named on the
# host, because the commitment worth checking against is the published one, the
# file in this repository whose digest the run's `config.json` then records.  A
# relative path is taken from the repository root, so a driver reads the path a
# REPRODUCE entry writes.
#
# Only the model root is compared this way.  `boundary-grid --expect-pre-roots`
# reads the same file, but its rows are keyed by `(layer, prefix width)` and a
# shape root is a function of the chunk's own shape and arguments, so a table
# derived over one plan covers another plan's cells only where the two plans
# have the same cells.  A model root is keyed by the layer alone and is a
# function of the model, which is what a commitment reused across plans can
# check.  `model-commitment.sh` makes both comparisons, over the one plan its
# table was derived from.
#
# Sets MODEL_ROOTS_SRC and MODEL_ROOTS_SUM, which the job body writes into the
# run's config.json; both are empty when the driver was given no commitment.
drv_model_roots() {
    MODEL_ROOTS_SRC=""; MODEL_ROOTS_SUM=""
    [ -n "${MODEL_ROOTS:-}" ] || return 0
    case "$MODEL_ROOTS" in
      /*) file=$MODEL_ROOTS ;;
      *)  file=$ROOT/$MODEL_ROOTS ;;
    esac
    [ -f "$file" ] || { echo "MODEL_ROOTS: no model commitment at $file" >&2; exit 2; }
    # What the file has to be is checked here and not two hours into the run:
    # `boundary-grid` reads a list of rows, or an object with a `roots` field,
    # and every row it looks up carries a layer and that layer's model root.
    layers=$(python3 - "$file" <<'MRPY'
import json, sys
d = json.load(open(sys.argv[1]))
rows = d.get("roots", d) if isinstance(d, dict) else d
if not isinstance(rows, list) or not rows:
    sys.exit(f"{sys.argv[1]}: not a model-roots manifest; want a list of rows or a `roots` field")
bad = [i for i, r in enumerate(rows)
       if not isinstance(r, dict) or not r.get("model_root") or "layer" not in r]
if bad:
    sys.exit(f"{sys.argv[1]}: {len(bad)} row(s) carry no layer and model root")
# `model-commitment.sh` derives two forms and records both. The verifier's is a
# cross-check over one token block, so it has no row for the layer coordinate a
# head segment sits at and a grid given it fails on the head. The published one
# is the commitment.
if any(r.get("weights_only") for r in rows):
    sys.exit(f"{sys.argv[1]}: this is the verifier's cross-check form of the derivation; "
             "a grid is given the published commitment, model-roots.json")
print(len({r["layer"] for r in rows}))
MRPY
) || exit 2
    MODEL_ROOTS_SRC=$MODEL_ROOTS
    MODEL_ROOTS_SUM=$(sha256sum "$file" | cut -d' ' -f1)
    ssh -o BatchMode=yes "$HOST" "mkdir -p ~/runs/$NAME && cat > ~/runs/$NAME/model-roots.json" < "$file"
    echo "drv_model_roots: $MODEL_ROOTS_SRC -> $HOST:~/runs/$NAME/model-roots.json"
    echo "                 $layers layer coordinates, sha256 $MODEL_ROOTS_SUM"
}

# ---- the published calibration the verifier derives shape roots with ---------
# `CALIBRATION` is a path to a document this repository publishes: the manifest
# `tools/drivers/model-commitment.sh` recorded, `runs/<run-id>/model-roots.json`,
# whose row for a statement's `(layer, c)` carries that segment's per-head
# calibration beside its model root.  A relative path is read from the
# repository root, as `MODEL_ROOTS` is.
#
# Since zk-prover #95 the verifier derives every segment's shape root from the
# statement's own parameters and that calibration and compares it with the root
# the statement declares, so `boundary-grid --verify` refuses to run without one:
# without it the shape root is asserted by the prover and checked by nothing.  A
# run that verifies therefore needs a published calibration, and a driver that
# sets `VERIFY` 1 and no `CALIBRATION` is refused here rather than at the grid,
# which on a sequence run is hours in.
#
# What makes an earlier campaign's manifest usable: the calibration is a
# property of the weights and the quantization variant and not of the prover, so
# two runs of one model at one context under one variant have the same
# calibration whatever prover commit proved them.  What it is not portable
# across is the plan: a row is found at `(layer, c)`, so a manifest derived over
# one context publishes nothing about another, and the grid refuses by name on a
# statement it has no row for.
#
# Sets CALIBRATION_SRC and CALIBRATION_SUM, which the job body writes into the
# run's config.json; both are empty when the driver names none.
drv_calibration() {
    CALIBRATION_SRC=""; CALIBRATION_SUM=""
    if [ -z "${CALIBRATION:-}" ]; then
        [ "${VERIFY:-0}" = 1 ] || return 0
        echo "$NAME: VERIFY is 1 and CALIBRATION is empty. Since zk-prover #95 the grid's" >&2
        echo "--verify derives each segment's shape root from the published calibration and" >&2
        echo "refuses to run without one. Set CALIBRATION to the model manifest whose rows" >&2
        echo "cover this plan's (layer, c) coordinates, or set VERIFY 0." >&2
        exit 2
    fi
    case "$CALIBRATION" in
      /*) file=$CALIBRATION ;;
      *)  file=$ROOT/$CALIBRATION ;;
    esac
    [ -f "$file" ] || { echo "CALIBRATION: no calibration at $file" >&2; exit 2; }
    # What the file has to be is checked here and not hours into the run.
    cover=$(python3 - "$file" <<'CALPY'
import json, sys
d = json.load(open(sys.argv[1]))
rows = d.get("rows", d) if isinstance(d, dict) else d
if not isinstance(rows, list) or not rows:
    sys.exit(f"{sys.argv[1]}: not a model manifest; want a list of rows or a `rows` field")
bad = [i for i, r in enumerate(rows)
       if not isinstance(r, dict) or "layer" not in r or "c" not in r
       or not (r.get("frac_per_head") or r.get("calibration"))]
if bad:
    sys.exit(f"{sys.argv[1]}: {len(bad)} row(s) carry no layer, context and calibration")
# The same refusal `drv_model_roots` makes, for the same reason: the verifier's
# cross-check form covers one token block, so it publishes no calibration for
# most of a sequence's coordinates and none at all for the head.
if any(r.get("weights_only") for r in rows):
    sys.exit(f"{sys.argv[1]}: this is the verifier's cross-check form of the derivation; "
             "a grid is given the published manifest, model-roots.json")
print(len({(r["layer"], r["c"]) for r in rows}))
CALPY
) || exit 2
    CALIBRATION_SRC=$CALIBRATION
    CALIBRATION_SUM=$(sha256sum "$file" | cut -d' ' -f1)
    ssh -o BatchMode=yes "$HOST" "mkdir -p ~/runs/$NAME && cat > ~/runs/$NAME/calibration.json" < "$file"
    echo "drv_calibration: $CALIBRATION_SRC -> $HOST:~/runs/$NAME/calibration.json"
    echo "                 $cover (layer, context) coordinates, sha256 $CALIBRATION_SUM"
}

# ---- the job's shell preamble ------------------------------------------------
# Written into every generated job script: the CUDA toolkit the vendored
# library's build script needs, the harness's CUDA torch group, and `st`, the
# one line each job step prints into the log that stays on the host.
drv_job_preamble() {
    cat <<'PREAMBLE'
st() { echo "$(date -u +%H:%M:%S) $*"; }

# CUDA: the fork's build script hardcodes /usr/local/cuda/lib64; the binaries link libcudart
for d in ${CUDA_HOME:-} $HOME/cuda-12.9 /usr/local/cuda-12.9 /usr/local/cuda; do
  [ -n "$d" ] && [ -x "$d/bin/nvcc" ] && CUDA_HOME=$d && break
done
# `uv` is installed under ~/.local/bin, so the harness needs it on the path too
export CUDA_HOME PATH="$CUDA_HOME/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"
export CUDAARCHS=${CUDAARCHS:-90} CUDAHOSTCXX=${CUDAHOSTCXX:-$(command -v g++-14 || command -v g++)}
# The harness's default torch is the CPU build; the extraction runs on the card,
# so every uv call selects the harness's cuda group.  uv syncs the environment
# back to the default on any call that leaves the flags out.
UVG="--no-group cpu --group cuda"
PREAMBLE
}

# ---- start -------------------------------------------------------------------
# drv_start <job file>
drv_start() {
    ssh -o BatchMode=yes "$HOST" "mkdir -p ~/runs/$NAME && cat > ~/runs/$NAME/job.sh" < "$1"
    "$ROOT/tools/remote/run.sh" "$HOST" "$NAME" "sh \$HOME/runs/$NAME/job.sh"
    echo "when the status says done, run this command again with the same arguments"
}
