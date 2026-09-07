#!/bin/sh
# reference-digest: the full-size reference segment, sound, on both backends.
#
#   tools/drivers/reference-digest.sh <host> <prover-commit> <harness-commit>
#
# One Llama-3.1-8B layer-16 segment, S = 512 output positions against a
# C = 16,384 key prefix, under the fixed quantization configuration
# `b10-final` that `zk-prover`'s reference row names, with the five GKR
# reductions the paper's configuration has on.  The witness is extracted with
# its own diagonal block and with the residual-stream columns, so every
# binding gadget the sound defaults switch on can be stated and no skip flag
# appears anywhere in this file.  The proof is made on the SIMD backend and
# then on the CUDA backend of the same commit; equal digests are the gate.
#
# This replaces the older reference dump, which was extracted without its own
# diagonal block and proved only with `--unsound-skip-kv-boundary`.  What a
# synthetic run leaves untested is what this one adds: the paper's shape, the
# model commitment, and a witness that came out of the model.
#
# Timing is not what this run is for: the digest is.  It adds no constant.
#
# The witness is kept under `~/witness/` on the host and reused, so a second
# run at another prover commit rebuilds, re-emits and re-proves, and does not
# extract again.  A dump is only reusable while the harness writes the same
# manifest keys; delete it on the host when the harness renames one.
#
# The first call pushes zk-prover at the two commits to the host, starts the
# job detached and prints the poll command.  Every later call with the same
# arguments prints the status; once the status says done it fetches the
# outputs into runs/<run-id>/, writes manifest.json from the prover's
# provenance block, and runs check.py.  Nothing measured is typed in here.
#
# Host time, from the run this driver recorded: the two builds about 5 and
# 11 minutes, the extraction and the three proofs minutes each.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
HOST=${1:?host alias}; PROVER=${2:?prover commit}; HARNESS=${3:?harness commit}
ZK_PROVER=${ZK_PROVER_DIR:-$ROOT/../zk-prover}     # a local clone to archive the commits from
NAME=reference-digest

# ---- the configuration: here and in the manifest, nowhere else ---------------
MODEL=${ZK_MODEL:-unsloth/Llama-3.1-8B-Instruct}
SPEC=b10-final             # the fixed quantization configuration the reference row names
CTX=16384; S=512; LAYER=16
THREADS=16                 # RAYON_NUM_THREADS, as the recorded reference command has it
GKR="--gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
# The statement's shape.  Three changes against the reference command recorded
# before the sound defaults, each of them forced:
#
#  1. `--diagonal-block` in place of the skip flag, on both sides, which is
#     what this run is for.
#  2. `--round even`.  `b10-final` rounds a half to even -- the norm's shared
#     table is built in one mode and the whole layer rounds that way -- so an
#     away-rounding prover builds tables this witness's values do not land in:
#     797 values off the table, the LogUp sums do not cancel, and the honest
#     proof is rejected.  The dump's own `dequant_round` says `even`; the
#     prover does not read it, so it is named here.
#  3. the five GKR reductions, which are the paper's configuration
#     (docs/decisions) and the layer flags of the headline driver.  Without
#     them this segment's interaction tree is 93,184 columns wide, and the
#     vendored library's out-of-domain sampling launches one thread block
#     grid per polynomial group with the polynomial count in the grid's y
#     dimension, which a device caps at 65,535: the CUDA backend stops in
#     `eval_at_point.cu` with an invalid configuration argument.  With the
#     five flags the interaction tree is 5,600 columns wide.
SHARED="--round even --numbits 9 --z-hi-bits 7 --variants intexp --table-bits 25 --head-groups 16,8,8 --diagonal-block $GKR"
EXTRACT_FLAGS="--residual-stream --diagonal-block"
KERNEL_FAMILIES=zk_chan_eval,zk_key_eval,zk_row_eval,zk_attn_out_eval,zk_dequant_eval,zk_freivalds_eval,zk_exp_table_eval,zk_table_eval,zk_residual_stream_eval,zk_residual_stream_table_eval

status() { ssh -o BatchMode=yes "$HOST" "cat ~/runs/$NAME.status 2>/dev/null || true"; }

# ---- finish: fetch, manifest, check ------------------------------------------
ST=$(status)
case "$ST" in
  *"done exit=0"*)
    TMP=$(mktemp -d "$ROOT/runs/.fetch-$NAME.XXXXXX")
    "$ROOT/tools/remote/fetch.sh" "$HOST" "$NAME" "$TMP"
    python3 "$HERE/lib/manifest.py" --driver "tools/drivers/$NAME.sh" --fetched "$TMP" \
        --runs "$ROOT/runs" --prover-commit "$PROVER" --harness-commit "$HARNESS" \
        --date "$(printf '%s\n' "$ST" | awk '/^done/ {print substr($3, 1, 10)}')"
    rmdir "$TMP" 2>/dev/null || true
    (cd "$ROOT" && python3 tools/constants/check.py)
    exit 0 ;;
  *"done exit="*)
    echo "$NAME on $HOST failed: $ST"; echo "log: ssh $HOST tail -50 '~/runs/$NAME.log'"; exit 1 ;;
  running*)
    echo "$NAME on $HOST: $ST"; echo "poll: ssh $HOST cat '~/runs/$NAME.status'"; exit 0 ;;
esac

# ---- start: push the pinned sources, then the job ----------------------------
# a git directory, not a `.git` directory: a linked work tree has a `.git` file
git -C "$ZK_PROVER" rev-parse --git-dir >/dev/null 2>&1 ||
  { echo "no zk-prover clone at $ZK_PROVER (set ZK_PROVER_DIR)" >&2; exit 2; }
git -C "$ZK_PROVER" cat-file -e "$PROVER^{commit}" || { echo "unknown prover commit $PROVER" >&2; exit 2; }
git -C "$ZK_PROVER" cat-file -e "$HARNESS^{commit}" || { echo "unknown harness commit $HARNESS" >&2; exit 2; }
"$ROOT/tools/remote/push.sh" "$HOST" "$ZK_PROVER" "runs/$NAME/src" "$PROVER"
"$ROOT/tools/remote/push.sh" "$HOST" "$ZK_PROVER" "runs/$NAME/harness-src" "$HARNESS"

JOB=$(mktemp)
cat > "$JOB" <<JOBEOF
#!/bin/sh
# generated by $NAME.sh; runs on the host under tools/remote/run.sh
set -eu
R=\$HOME/runs/$NAME
SRC=\$R/src; HSRC=\$R/harness-src/harness
OUT=\$R/out; GEN=\$R/gen
WIT=\$HOME/witness/$SPEC-l$LAYER-c$CTX/witness      # reused across runs
mkdir -p \$OUT \$GEN
st() { echo "\$(date -u +%H:%M:%S) \$*"; }

# CUDA: the fork's build script hardcodes /usr/local/cuda/lib64; the binaries link libcudart
for d in \${CUDA_HOME:-} \$HOME/cuda-12.9 /usr/local/cuda-12.9 /usr/local/cuda; do
  [ -n "\$d" ] && [ -x "\$d/bin/nvcc" ] && CUDA_HOME=\$d && break
done
# uv installs under ~/.local/bin, so the harness needs it on the path too
export CUDA_HOME PATH="\$CUDA_HOME/bin:\$HOME/.cargo/bin:\$HOME/.local/bin:\$PATH" LD_LIBRARY_PATH="\$CUDA_HOME/lib64:\${LD_LIBRARY_PATH:-}"
export CUDAARCHS=\${CUDAARCHS:-90} CUDAHOSTCXX=\${CUDAHOSTCXX:-\$(command -v g++-14 || command -v g++)}
export RAYON_NUM_THREADS=\${RAYON_NUM_THREADS:-$THREADS}
# the extractor reads the card, and the harness's default torch is the CPU
# build, so every uv call selects the harness's cuda group.  uv syncs the
# environment back to the CPU build without them.
UVG="--no-group cpu --group cuda"
PY="uv run --project \$HSRC \$UVG python"

# the configuration, for the manifest
cat > \$OUT/config.json <<CFG
{"driver": "$NAME", "model": "$MODEL", "spec": "$SPEC",
 "context": $CTX, "s": $S, "layer": $LAYER, "tokens": $((CTX + S)),
 "shared_flags": "$SHARED", "extract_flags": "$EXTRACT_FLAGS",
 "rayon_threads": $THREADS,
 "ids": "the evaluation corpus's first $((CTX + S)) tokens",
 "note": "the reference segment; no skip flag, the diagonal block in, both backends"}
CFG

st "gpu: \$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader)"
st "nvcc: \$(nvcc --version | tail -2 | head -1)"

# 1. the SIMD backend of the pinned prover commit
st "build: simd"
( cd \$SRC && CARGO_TARGET_DIR=\$R/t-simd cargo build --release --locked )
SIMD=\$R/t-simd/release/zk-prover

# 2. the harness at its pinned commit
( cd \$HSRC && uv sync --frozen \$UVG )

# 3. the witness: one layer, one token block, its own diagonal block and the
#    residual-stream columns
if [ ! -f \$WIT/manifest.json ]; then
  mkdir -p \$WIT
  st "extract: layer $LAYER, C=$CTX, S=$S, $SPEC"
  T0=\$(date +%s)
  ( cd \$HSRC && ZK_MODEL=$MODEL ZK_DEVICE=cuda \$PY -m harness.witness.extract \
      --tokens $((CTX + S)) --chunk $S --layer $LAYER --spec $SPEC $EXTRACT_FLAGS --out \$WIT )
  T1=\$(date +%s)
  printf '{"device": "cuda", "seconds": %d, "layer": %d, "spec": "%s", "tokens": %d, "flags": "%s"}\n' \
      \$((T1 - T0)) $LAYER "$SPEC" $((CTX + S)) "$EXTRACT_FLAGS" > \$OUT/extract.json
  st "extract done in \$((T1 - T0))s"
else
  st "extract: \$WIT is already on this host"
fi
du -sh \$WIT | awk '{print "witness size: " \$1}'

# 4. the shape row this witness needs, for the record
( cd \$HSRC && \$PY -c "
import json
from harness.witness.shapes import shape_of, worst_of
row = shape_of('\$WIT')
worst, _ = worst_of([row])
json.dump({'row': row, 'worst': worst}, open('\$OUT/shapes.json', 'w'), indent=1)
print('shapes:', json.dumps(worst))" )

# 5. the SIMD proof, with no skip flag
st "prove: simd"
\$SIMD compose $SHARED --witness \$WIT > \$OUT/reference-simd.json 2> \$R/reference-simd.err

# 6. the device kernels for this one shape, installed into the vendored library
K=\$SRC/prover/kernels
[ -d \$K ] || { st "no prover/kernels in this prover commit; the CUDA backend would evaluate constraints on the CPU"; exit 3; }
st "emit"
\$SIMD cudaemit $SHARED --witness \$WIT --out \$GEN --block 256 --min-blocks 2 > /dev/null
\$SIMD genemit $SHARED --witness \$WIT --families "$KERNEL_FAMILIES" --out \$GEN > /dev/null
python3 \$K/m2b_kernels.py --fork \$SRC/nitroo --gen \$GEN
python3 \$K/m4b_kernels.py --fork \$SRC/nitroo --gen \$GEN --src \$K
find \$SRC/nitroo/crates/stwo/src/stwo_cuda/cuda \( -name '*.cu' -o -name '*.cuh' \) -exec touch {} +
cp \$GEN/cudakernels.rs \$GEN/gencudakernels.rs \$SRC/prover/src/
# an installed tree is no longer the commit that was pushed, and says so
grep -q ' dirty\$' \$SRC/.source-commit || sed -i 's/\$/ dirty/' \$SRC/.source-commit
st "kernels installed"

# 7. the CUDA backend of the same commit, with the store compiled in
st "build: cuda"
( cd \$SRC && CARGO_TARGET_DIR=\$R/t-cuda cargo build --release --locked -p zk-prover --features cuda )
CUDA=\$R/t-cuda/release/zk-prover
st "prove: cuda"
\$CUDA compose $SHARED --witness \$WIT > \$OUT/reference-cuda.json 2> \$R/reference-cuda.err
grep -c 'kernel fallback:' \$R/reference-cuda.err > \$OUT/reference-cuda.fallbacks || true

# 8. the gate: equal digests, no skip in effect, every edge bound
python3 - \$OUT <<'PY'
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
d = {b: json.loads((out / f"reference-{b}.json").read_text()) for b in ("simd", "cuda")}
bad = []
for b, doc in d.items():
    p = doc["provenance"]
    print(f"{b}: digest {doc['result']['point']['proof_sha256'][:16]} "
          f"skips {p['unsound_skips'] or 'none'} all_bound {p['binding']['all_bound']} "
          f"unbound {p['binding']['unbound']}")
    if p["unsound_skips"]:
        bad.append(f"{b}: unsound skips in effect")
    if not p["binding"]["all_bound"]:
        bad.append(f"{b}: unbound edges {p['binding']['unbound']}")
if d["simd"]["result"]["point"]["proof_sha256"] != d["cuda"]["result"]["point"]["proof_sha256"]:
    bad.append("the two backends disagree on the digest")
n = int((out / "reference-cuda.fallbacks").read_text().strip())
print(f"kernel fallback lines on the CUDA backend: {n}")
if n:
    bad.append(f"{n} kernel fallback lines")
if bad:
    sys.exit("; ".join(bad))
print("both backends agree; no skip; every edge bound")
PY
st "done"
JOBEOF
ssh -o BatchMode=yes "$HOST" "mkdir -p ~/runs/$NAME && cat > ~/runs/$NAME/job.sh" < "$JOB"
rm -f "$JOB"
"$ROOT/tools/remote/run.sh" "$HOST" "$NAME" "sh \$HOME/runs/$NAME/job.sh"
echo "when the status says done, run this command again with the same arguments"
