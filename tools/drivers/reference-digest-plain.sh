#!/bin/sh
# reference-digest-plain: the reference layer without the five GKR reductions,
# at a block length whose sampling axis fits an 80 GB card.
#
#   tools/drivers/reference-digest-plain.sh <host> <prover-commit> <harness-commit>
#
# Two statements about the same Llama-3.1-8B layer 16, under the fixed
# quantization configuration `b10-final`, each one's own diagonal block and the
# residual-stream columns, no skip flag anywhere:
#
#   the reference segment  S = 512   against C = 16,384, with the five GKR
#                          reductions, which is the paper's configuration and
#                          the digest `prover/README.md` records;
#   the short segment      S = 128   against C = 4,096, without any of them.
#
# The second is what this driver is for. Without the reductions a segment's
# interaction tree carries one polynomial per key tile lookup, and the vendored
# library's out-of-domain sampling evaluates the polynomials of one size in a
# single launch with their index in the thread block grid's y dimension, which a
# device caps at 65,535. zk-prover pull request 107 launches that axis in slices;
# what it needs from a card is a proof whose sampling axis is wider than the cap
# and whose digest is the reference backend's.
#
# The key tiles are what carries the axis past the cap, and their number is the
# key blocks -- the context and the block itself, in blocks of S keys -- times
# the head groups, not the context alone. So the short segment holds the 33 key
# blocks of the reference segment at a quarter of its context: 80,424 key tile
# polynomials of the 102,608 its interaction tree is wide, against the reference
# segment's 70,920 of 93,184, and 30 per cent of its committed cells.
#
# That last part is why the block length moves. The reference segment without
# the reductions does not prove on an 80 GB card: it commits 4.13e9 cells, and
# the CUDA backend reached 82.2 GB of the 85.0 GB the driver reports before
# the quotient stage asked for another 256 MB and the allocation failed
# (2026-09-08, this driver's first run; zk-prover #29 reports the same shape
# stopping on a 141 GB card for the launch cap this pull request fixes). Its
# SIMD digest is recorded here; its CUDA side is not attempted, and the job
# writes what it did not attempt and why into `out/plain-cuda-refused.json`.
#
# The gate is that each shape proves on both backends to one digest, that the
# short segment's sampling axis really is wider than 65,535 polynomials, that
# every proof accepts with every edge bound and no skip in effect, and that no
# proof took the host route for a lookup.
#
# Whether the reference segment's digest is still the `25741d12f315aae7` that
# `prover/README.md` records is a result and not a gate: the recorded one was
# taken at another prover commit and from a dump another harness commit wrote,
# and if this commit's is a different one, that is the run's finding to report
# rather than a reason to throw the run away.  The job writes the comparison
# into `out/full-digest.json` either way.
#
# Timing is not what this run is for: the digests are. It adds no constant.
#
# The witnesses are kept under `~/witness/` on the host and reused, so a second
# run at another prover commit rebuilds, re-emits and re-proves, and does not
# extract again.
#
# The first call pushes zk-prover at the two commits to the host, starts the job
# detached and prints the poll command. Every later call with the same arguments
# prints the status; once the status says done it fetches the outputs into
# runs/<run-id>/, writes manifest.json from the prover's provenance block, and
# runs check.py. Nothing measured is typed in here.
#
# Host time, from the run this driver recorded: the two builds about 5 and 17
# minutes, each extraction under two minutes, each proof one to four.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
HOST=${1:?host alias}; PROVER=${2:?prover commit}; HARNESS=${3:?harness commit}
ZK_PROVER=${ZK_PROVER_DIR:-$ROOT/../zk-prover}     # a local clone to archive the commits from
NAME=reference-digest-plain
. "$HERE/lib/driver.sh"

# ---- the configuration: here and in the manifest, nowhere else ---------------
MODEL=${ZK_MODEL:-unsloth/Llama-3.1-8B-Instruct}
SPEC=b10-final             # the fixed quantization configuration the reference row names
LAYER=16
CTX=16384; S=512           # the reference segment
CTX2=4096;  S2=128         # the short segment: the same 33 key blocks, a quarter of the context
THREADS=16                 # RAYON_NUM_THREADS, as the recorded reference command has it
GKR="--gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
# The statement's shape.  Everything but the reductions is the recorded
# reference command: `--round even` because `b10-final` rounds a half to even,
# and `--diagonal-block` in place of the skip flag the older reference row was
# proved with.
BASE="--round even --numbits 9 --z-hi-bits 7 --variants intexp --table-bits 25 --head-groups 16,8,8 --diagonal-block"
PLAIN="$BASE"
FULL="$BASE $GKR"
# What `prover/README.md` records for the reference segment with the
# reductions, taken at another prover commit.  This run's proof of it is
# compared against this and the comparison is recorded, either way.
FULL_DIGEST=25741d12f315aae7
# What the short segment is evidence for: an out-of-domain sampling axis wider
# than the grid dimension a device caps at.
GRID_CAP=65535
EXTRACT_FLAGS="--residual-stream --diagonal-block"
KERNEL_FAMILIES=zk_chan_eval,zk_key_eval,zk_row_eval,zk_attn_out_eval,zk_dequant_eval,zk_freivalds_eval,zk_exp_table_eval,zk_table_eval,zk_residual_stream_eval,zk_residual_stream_table_eval

drv_finish "$(drv_status)"

# ---- start: push the pinned sources, then the job ----------------------------
drv_check_commits
drv_push "runs/$NAME/src" "$PROVER"
drv_push "runs/$NAME/harness-src" "$HARNESS"

JOB=$(mktemp)
cat > "$JOB" <<JOBEOF
#!/bin/sh
# generated by $NAME.sh; runs on the host under tools/remote/run.sh
set -eu
R=\$HOME/runs/$NAME
SRC=\$R/src; HSRC=\$R/harness-src/harness
OUT=\$R/out; GEN=\$R/gen
WIT=\$HOME/witness/$SPEC-l$LAYER-c$CTX          # the one reference-digest extracts
WIT2=\$HOME/witness/$SPEC-l$LAYER-c$CTX2-s$S2
mkdir -p \$OUT \$GEN
$(drv_job_preamble)
export RAYON_NUM_THREADS=\${RAYON_NUM_THREADS:-$THREADS}
PY="uv run --project \$HSRC \$UVG python"

cat > \$OUT/config.json <<CFG
{"driver": "$NAME", "label": "digest", "model": "$MODEL", "spec": "$SPEC", "layer": $LAYER,
 "reference": {"context": $CTX, "s": $S, "tokens": $((CTX + S)), "flags": "$FULL"},
 "short": {"context": $CTX2, "s": $S2, "tokens": $((CTX2 + S2)), "flags": "$PLAIN"},
 "plain_flags": "$PLAIN", "full_flags": "$FULL",
 "extract_flags": "$EXTRACT_FLAGS", "rayon_threads": $THREADS,
 "recorded_full_digest": "$FULL_DIGEST", "grid_cap": $GRID_CAP,
 "ids": "the evaluation corpus's first tokens, at each segment's own length",
 "note": "the reference segment with the five GKR reductions on both backends, and the short segment without any of them on both backends; no skip flag"}
CFG

st "gpu: \$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader)"
st "nvcc: \$(nvcc --version | tail -2 | head -1)"

# 1. the SIMD backend of the pinned prover commit
st "build: simd"
( cd \$SRC && CARGO_TARGET_DIR=\$R/t-simd cargo build --release --locked )
SIMD=\$R/t-simd/release/zk-prover

# 2. the harness at its pinned commit
( cd \$HSRC && uv sync --frozen \$UVG )

# 3. the witnesses: one layer, one token block each, its own diagonal block and
#    the residual-stream columns
extract() {
  dir=\$1; ctx=\$2; s=\$3; tag=\$4
  if [ -f \$dir/witness/manifest.json ]; then
    st "extract: \$dir is already on this host"
    return
  fi
  mkdir -p \$dir/witness
  st "extract: layer $LAYER, C=\$ctx, S=\$s, $SPEC"
  T0=\$(date +%s)
  ( cd \$HSRC && ZK_MODEL=$MODEL ZK_DEVICE=cuda \$PY -m harness.witness.extract \
      --tokens \$((ctx + s)) --chunk \$s --layer $LAYER --spec $SPEC $EXTRACT_FLAGS --out \$dir/witness )
  T1=\$(date +%s)
  printf '{"device": "cuda", "seconds": %d, "layer": %d, "spec": "%s", "context": %d, "s": %d, "tokens": %d, "flags": "%s"}\n' \
      \$((T1 - T0)) $LAYER "$SPEC" \$ctx \$s \$((ctx + s)) "$EXTRACT_FLAGS" > \$OUT/extract-\$tag.json
  st "extract done in \$((T1 - T0))s"
}
extract \$WIT $CTX $S reference
extract \$WIT2 $CTX2 $S2 short
du -sh \$WIT \$WIT2 | awk '{print "witness size: " \$1 "  " \$2}'

# 4. the proofs on the SIMD backend.  The reference segment without the
#    reductions is proved here and nowhere else: see 7.
st "prove: simd, the reference segment with the reductions"
\$SIMD compose $FULL --witness \$WIT/witness > \$OUT/full-simd.json 2> \$R/full-simd.err
st "prove: simd, the reference segment without them"
\$SIMD compose $PLAIN --witness \$WIT/witness > \$OUT/plain-simd.json 2> \$R/plain-simd.err
st "prove: simd, the short segment without them"
\$SIMD compose $PLAIN --witness \$WIT2/witness > \$OUT/short-simd.json 2> \$R/short-simd.err

# 5. the device kernels for the two shapes that run on the card, in one store,
#    installed into the vendored library.  A store dedups by fingerprint and
#    only grows, so the second shape adds what the first did not already carry.
#    An emitter that refuses a shape is recorded and not fatal: what a refused
#    lowering costs is an announced kernel fallback line, and the gate fails on
#    any.
K=\$SRC/prover/kernels
[ -d \$K ] || { st "no prover/kernels in this prover commit; the CUDA backend would evaluate constraints on the CPU"; exit 3; }
emit() {
  shape=\$1; wit=\$2; shift 2
  st "emit: \$shape"
  \$SIMD cudaemit "\$@" --witness \$wit/witness --out \$GEN --block 256 --min-blocks 2 > /dev/null \
    || { printf '%s\n' "\$shape" >> \$OUT/cudaemit-refused.txt; st "cudaemit refused \$shape"; }
  \$SIMD genemit "\$@" --witness \$wit/witness --families "$KERNEL_FAMILIES" --out \$GEN > /dev/null \
    || { printf '%s\n' "\$shape" >> \$OUT/genemit-refused.txt; st "genemit refused \$shape"; }
}
emit full \$WIT $FULL
emit short \$WIT2 $PLAIN
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
st "prove: cuda, the reference segment with the reductions"
\$CUDA compose $FULL --witness \$WIT/witness > \$OUT/full-cuda.json 2> \$R/full-cuda.err
grep -c 'kernel fallback:' \$R/full-cuda.err > \$OUT/full-cuda.fallbacks || true
st "prove: cuda, the short segment without them"
\$CUDA compose $PLAIN --witness \$WIT2/witness > \$OUT/short-cuda.json 2> \$R/short-cuda.err
grep -c 'kernel fallback:' \$R/short-cuda.err > \$OUT/short-cuda.fallbacks || true

# 7. what the run did not attempt, and the two numbers that decision rests on:
#    the shape's own committed cells, from the proof of it made above, and the
#    memory the card reports.  The same shape's CUDA proof was attempted once,
#    on 2026-09-08 at this commit, and stopped in the quotient stage with 82.2
#    of 85.0 GB in use; it is not attempted again.
python3 - \$OUT "\$(nvidia-smi --query-gpu=memory.total --format=csv,noheader)" <<'PY'
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
cells = json.loads((out / "plain-simd.json").read_text())["result"]["point"]["cells"]
committed = sum(cells[k] for k in ("shape", "model", "base", "interaction"))
(out / "plain-cuda-refused.json").write_text(json.dumps({
    "shape": "the reference segment without the five GKR reductions, C = 16,384, S = 512",
    "backend": "cuda",
    "attempted": False,
    "committed_cells": committed,
    "card_memory_total": sys.argv[2],
    "why": "this shape's CUDA proof was attempted once at this prover commit and "
           "stopped in the quotient stage for want of card memory, with 82.2 GB of "
           "the 85.0 GB the driver reports in use at the composition commitment; "
           "the short segment carries the same evidence at 30 per cent of the "
           "committed cells and is proved on both backends instead",
}, indent=1) + "\n")
print(f"plain: {committed:,} committed cells; the CUDA side is not attempted")
PY

# 8. the gate: the short segment's two backends agree and its sampling axis is
#    wider than the cap, the paper's shape is still the recorded digest on both
#    backends, no skip is in effect and every edge each shape has is bound
python3 - \$OUT $FULL_DIGEST $GRID_CAP <<'PY'
import json, pathlib, sys
out, recorded, cap = pathlib.Path(sys.argv[1]), sys.argv[2], int(sys.argv[3])
bad = {}
digest = {}
names = ["full-simd", "full-cuda", "short-simd", "short-cuda", "plain-simd"]
for name in names:
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
for shape in ("full", "short"):
    if digest[f"{shape}-simd"] != digest[f"{shape}-cuda"]:
        bad[shape] = "the two backends disagree on the digest"
    else:
        print(f"{shape}: both backends agree on {digest[f'{shape}-simd'][:16]}")
moved = not digest["full-simd"].startswith(recorded)
if moved:
    print(f"full: prover/README.md records {recorded}; this commit proves "
          f"{digest['full-simd'][:16]} on both backends. The recorded one was "
          f"taken at another prover commit and from another harness commit's "
          f"dump; which change moved it is not this run's to say.")
else:
    print(f"full: the recorded digest {recorded} is reproduced")
(out / "full-digest.json").write_text(json.dumps({
    "shape": "the reference segment with the five GKR reductions, C = 16,384, S = 512",
    "page_records": recorded,
    "proved_here": digest["full-simd"][:16],
    "both_backends_agree": digest["full-simd"] == digest["full-cuda"],
    "moved": moved,
}, indent=1) + "\n")
# what the short segment is evidence for: one launch of more polynomials than a
# grid dimension holds.  The key tiles are what carries it past the cap.
for name in ("short-simd", "short-cuda"):
    point = json.loads((out / f"{name}.json").read_text())["result"]["point"]
    tiles = point["family_cells"]["interaction_by_family"]["key_tiles"]["columns"]
    wide = point["columns"]["interaction"]
    print(f"{name}: interaction tree {wide:,} columns, {tiles:,} of them key tiles, cap {cap:,}")
    if tiles <= cap:
        bad[name] = (f"the key tiles are {tiles} polynomials, which is not more than "
                     f"the {cap} a grid dimension holds: this run is not evidence "
                     f"for the sliced launch")
for name in ("full-cuda", "short-cuda"):
    n = int((out / f"{name}.fallbacks").read_text().strip())
    print(f"{name}: kernel fallback lines: {n}")
    if n:
        bad[name] = f"{n} kernel fallback lines"
for name in ("cudaemit-refused.txt", "genemit-refused.txt"):
    if (out / name).exists():
        print(f"{name}: {(out / name).read_text().split()}")
if bad:
    sys.exit("; ".join(f"{k}: {v}" for k, v in sorted(bad.items())))
print("the short segment proves on both backends past the grid cap, the reference "
      "segment proves on both, no skip, every edge bound")
PY
st "done"
JOBEOF
drv_start "$JOB"
rm -f "$JOB"
