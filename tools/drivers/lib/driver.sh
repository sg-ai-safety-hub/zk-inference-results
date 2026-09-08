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

# ---- finish: fetch, manifest, check ------------------------------------------
# Called with the status line.  Returns only while the run is not finished; on
# a finished run it exits the driver.
drv_finish() {
    ST=$1
    case "$ST" in
      *"done exit=0"*)
        TMP=$(mktemp -d "$ROOT/runs/.fetch-$NAME.XXXXXX")
        "$ROOT/tools/remote/fetch.sh" "$HOST" "$NAME" "$TMP"
        # DRV_KIND, when the driver sets it, is what the run's outputs cannot say
        # for themselves: `verifier` for a run that makes no proof and checks
        # proofs another run made.  Unset is the prover's own answer.
        python3 "$HERE/lib/manifest.py" --driver "tools/drivers/$NAME.sh" --fetched "$TMP" \
            --runs "$ROOT/runs" --prover-commit "$PROVER" --harness-commit "$HARNESS" \
            ${DRV_KIND:+--kind "$DRV_KIND"} \
            --date "$(printf '%s\n' "$ST" | awk '/^done/ {print substr($3, 1, 10)}')"
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
