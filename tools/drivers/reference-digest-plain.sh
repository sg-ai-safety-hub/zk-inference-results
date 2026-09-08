#!/bin/sh
# reference-digest-plain: the reference segment with and without the five GKR
# reductions, on both backends.
#
#   tools/drivers/reference-digest-plain.sh <host> <prover-commit> <harness-commit>
#
# The same statement `reference-digest.sh` proves -- one Llama-3.1-8B layer-16
# segment, S = 512 output positions against a C = 16,384 key prefix, under the
# fixed quantization configuration `b10-final`, its own diagonal block and the
# residual-stream columns, no skip flag anywhere -- proved twice on each
# backend: once with the five GKR reductions, which is the paper's
# configuration, and once without any of them.
#
# The shape without them is what this driver is for. Until zk-prover pull
# request 107 it could not be proved on the CUDA backend at all: without the
# reductions the segment's interaction tree is 93,184 columns wide, and the
# vendored library's out-of-domain sampling launched one thread block grid per
# polynomial group with the polynomial count in the grid's y dimension, which a
# device caps at 65,535, so the backend stopped in `eval_at_point.cu` with an
# invalid configuration argument. That pull request chunks the launch. This run
# is the evidence on a card: the plain shape proves on both backends and the two
# digests are equal.
#
# The run proves the paper's shape beside it in the same job, from the same
# witness, and checks that its digest is still the one `prover/README.md`
# records. A change that makes a new shape provable has to leave the recorded
# one alone, and this is where that is checked rather than asserted.
#
# Timing is not what this run is for: the digests are. It adds no constant.
#
# The witness is the one `reference-digest.sh` extracts, under `~/witness/` on
# the host, and is reused when it is already there.
#
# The first call pushes zk-prover at the two commits to the host, starts the job
# detached and prints the poll command. Every later call with the same arguments
# prints the status; once the status says done it fetches the outputs into
# runs/<run-id>/, writes manifest.json from the prover's provenance block, and
# runs check.py. Nothing measured is typed in here.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
HOST=${1:?host alias}; PROVER=${2:?prover commit}; HARNESS=${3:?harness commit}
ZK_PROVER=${ZK_PROVER_DIR:-$ROOT/../zk-prover}     # a local clone to archive the commits from
NAME=reference-digest-plain

# ---- the configuration: here and in the manifest, nowhere else ---------------
MODEL=${ZK_MODEL:-unsloth/Llama-3.1-8B-Instruct}
SPEC=b10-final             # the fixed quantization configuration the reference row names
CTX=16384; S=512; LAYER=16
THREADS=16                 # RAYON_NUM_THREADS, as the recorded reference command has it
GKR="--gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
# The statement's shape, without the reductions and with them.  Everything else
# is the recorded reference command: `--round even` because `b10-final` rounds a
# half to even, and `--diagonal-block` in place of the skip flag the older
# reference row was proved with.
BASE="--round even --numbits 9 --z-hi-bits 7 --variants intexp --table-bits 25 --head-groups 16,8,8 --diagonal-block"
PLAIN="$BASE"
FULL="$BASE $GKR"
# What `prover/README.md` records for the shape with the reductions.  The run
# fails if this run's proof of it is anything else.
FULL_DIGEST=25741d12f315aae7
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
WIT=\$HOME/witness/$SPEC-l$LAYER-c$CTX/witness      # the one reference-digest extracts
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
UVG="--no-group cpu --group cuda"
PY="uv run --project \$HSRC \$UVG python"

cat > \$OUT/config.json <<CFG
{"driver": "$NAME", "model": "$MODEL", "spec": "$SPEC",
 "context": $CTX, "s": $S, "layer": $LAYER, "tokens": $((CTX + S)),
 "plain_flags": "$PLAIN", "full_flags": "$FULL",
 "extract_flags": "$EXTRACT_FLAGS", "rayon_threads": $THREADS,
 "recorded_full_digest": "$FULL_DIGEST",
 "ids": "the evaluation corpus's first $((CTX + S)) tokens",
 "note": "the reference segment proved with the five GKR reductions and without them, on both backends; no skip flag"}
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

# 4. the two proofs on the SIMD backend
st "prove: simd, without the reductions"
\$SIMD compose $PLAIN --witness \$WIT > \$OUT/plain-simd.json 2> \$R/plain-simd.err
st "prove: simd, with the reductions"
\$SIMD compose $FULL --witness \$WIT > \$OUT/full-simd.json 2> \$R/full-simd.err

# 5. the device kernels for both shapes, in one store, installed into the
#    vendored library.  A store dedups by fingerprint and only grows, so the
#    second shape adds what the first did not already carry.  An emitter that
#    refuses a shape is recorded and not fatal: what a refused lowering costs is
#    an announced kernel fallback line, and the gate below fails on any.
K=\$SRC/prover/kernels
[ -d \$K ] || { st "no prover/kernels in this prover commit; the CUDA backend would evaluate constraints on the CPU"; exit 3; }
for shape in plain full; do
  case \$shape in
    plain) flags="$PLAIN" ;;
    full)  flags="$FULL" ;;
  esac
  st "emit: \$shape"
  \$SIMD cudaemit \$flags --witness \$WIT --out \$GEN --block 256 --min-blocks 2 > /dev/null \
    || { printf '%s\n' "\$shape" >> \$OUT/cudaemit-refused.txt; st "cudaemit refused \$shape"; }
  \$SIMD genemit \$flags --witness \$WIT --families "$KERNEL_FAMILIES" --out \$GEN > /dev/null \
    || { printf '%s\n' "\$shape" >> \$OUT/genemit-refused.txt; st "genemit refused \$shape"; }
done
python3 \$K/m2b_kernels.py --fork \$SRC/nitroo --gen \$GEN
python3 \$K/m4b_kernels.py --fork \$SRC/nitroo --gen \$GEN --src \$K
find \$SRC/nitroo/crates/stwo/src/stwo_cuda/cuda \( -name '*.cu' -o -name '*.cuh' \) -exec touch {} +
cp \$GEN/cudakernels.rs \$GEN/gencudakernels.rs \$SRC/prover/src/
# an installed tree is no longer the commit that was pushed, and says so
grep -q ' dirty\$' \$SRC/.source-commit || sed -i 's/\$/ dirty/' \$SRC/.source-commit
st "kernels installed"

# 6. the CUDA backend of the same commit, with the store compiled in
st "build: cuda"
( cd \$SRC && CARGO_TARGET_DIR=\$R/t-cuda cargo build --release --locked -p zk-prover --features cuda )
CUDA=\$R/t-cuda/release/zk-prover
st "prove: cuda, without the reductions"
\$CUDA compose $PLAIN --witness \$WIT > \$OUT/plain-cuda.json 2> \$R/plain-cuda.err
grep -c 'kernel fallback:' \$R/plain-cuda.err > \$OUT/plain-cuda.fallbacks || true
st "prove: cuda, with the reductions"
\$CUDA compose $FULL --witness \$WIT > \$OUT/full-cuda.json 2> \$R/full-cuda.err
grep -c 'kernel fallback:' \$R/full-cuda.err > \$OUT/full-cuda.fallbacks || true

# 7. the gate: each shape's two backends agree, the paper's shape is still the
#    recorded digest, no skip is in effect and every edge the shape has is bound
python3 - \$OUT $FULL_DIGEST <<'PY'
import json, pathlib, sys
out, recorded = pathlib.Path(sys.argv[1]), sys.argv[2]
bad = {}
digest = {}
for shape in ("plain", "full"):
    for backend in ("simd", "cuda"):
        name = f"{shape}-{backend}"
        doc = json.loads((out / f"{name}.json").read_text())
        p, point = doc["provenance"], doc["result"]["point"]
        digest[name] = point["proof_sha256"]
        print(f"{name:<11s} digest {digest[name][:16]}  accepts {point['accepts']}  "
              f"skips {p['unsound_skips'] or 'none'}  all_bound {p['binding']['all_bound']}  "
              f"unbound {p['binding']['unbound']}")
        if not point["accepts"]:
            bad[name] = "did not accept"
        if p["unsound_skips"]:
            bad[name] = f"unsound skips in effect: {p['unsound_skips']}"
        if not p["binding"]["all_bound"]:
            bad[name] = f"unbound edges {p['binding']['unbound']}"
for shape in ("plain", "full"):
    if digest[f"{shape}-simd"] != digest[f"{shape}-cuda"]:
        bad[shape] = "the two backends disagree on the digest"
    else:
        print(f"{shape}: both backends agree on {digest[f'{shape}-simd'][:16]}")
if not digest["full-simd"].startswith(recorded):
    bad["full"] = (f"the shape with the reductions proved {digest['full-simd'][:16]}, "
                   f"not the recorded {recorded}")
else:
    print(f"full: the recorded digest {recorded} is reproduced")
for shape in ("plain", "full"):
    n = int((out / f"{shape}-cuda.fallbacks").read_text().strip())
    print(f"{shape}: kernel fallback lines on the CUDA backend: {n}")
    if n:
        bad[f"{shape}-cuda"] = f"{n} kernel fallback lines"
for name in ("cudaemit-refused.txt", "genemit-refused.txt"):
    if (out / name).exists():
        print(f"{name}: {(out / name).read_text().split()}")
if bad:
    sys.exit("; ".join(f"{k}: {v}" for k, v in sorted(bad.items())))
print("both shapes prove on both backends, digests equal, no skip, every edge bound")
PY
st "done"
JOBEOF
ssh -o BatchMode=yes "$HOST" "mkdir -p ~/runs/$NAME && cat > ~/runs/$NAME/job.sh" < "$JOB"
rm -f "$JOB"
"$ROOT/tools/remote/run.sh" "$HOST" "$NAME" "sh \$HOME/runs/$NAME/job.sh"
echo "when the status says done, run this command again with the same arguments"
