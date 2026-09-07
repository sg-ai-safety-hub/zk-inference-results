#!/bin/sh
# memory-probe-c16384: does the headline's segment loop fit an 80 GB card?
#
#   tools/drivers/memory-probe-c16384.sh <host> <prover-commit> <harness-commit>
#
# The headline sequence at context 16,384 is 33 token blocks of 32 layer
# segments.  A block's segments grow with the prefix the block reads, so the
# largest segments in the whole plan are the last block's, which read all
# 16,384 prompt keys; whatever the loop's peak card memory is, that block sets
# it.  This driver extracts that block alone, proves four of its 32 segments
# twice -- once with the pipeline off and once with it on, the same four
# segments in the same order both times -- and samples the card once a second
# while each loop runs.  Then it proves the block's layer 0 on its own, because
# that segment carries the embedding gadget and is the one segment shape the
# other four do not cover.  What it reports is the peak of each.
#
# The question is issue #16's.  The archive estimated the pipelined loop at
# this context at 85 GB, which does not fit an 80 GB card, and issue #5 asks
# for a probe before the campaign rather than a campaign that stops partway
# through with an out-of-memory failure.  The two loops are measured in one
# run because the choice between them is the thing being decided.
#
# It is a probe and not a sequence: four segments of one block prove no
# statement about a prompt and its output, the plan has no output head in it,
# and nothing here is a throughput row.  Its `label` is `probe`, so a reader of
# the run directory cannot mistake it for a headline.
#
# Everything the probe does with the extraction, the plan, the kernel store and
# the loop, `headline-c16384.sh` does the same way over all 33 blocks, and the
# two drivers share the host's build tree and kernel store at one prover
# commit.  A configuration flag that differs between them would make the probe
# answer a question about a loop nobody runs, so the block of flags below is
# the headline driver's, copied line for line.
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
NAME=memory-probe-c16384
. "$HERE/lib/driver.sh"

# ---- the configuration: the headline driver's, and the probe's own ----------
LABEL=probe                # neither a headline nor a control: a memory measurement
MODEL=${ZK_MODEL:-unsloth/Llama-3.1-8B-Instruct}
SPEC=y-delay-vw12          # the quantization variant the paper reports (docs/decisions)
CTX=16384; S=512
NBLOCK=$(( (CTX + S) / S ))  # 33: the prompt's 32 blocks and the output block
NLAY=32
SHARED="--round even --numbits 9 --z-hi-bits 7 --variants intexp --head-groups 16,8,8 --tight-table"
GKR="--gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
LAYER_FLAGS="--round even --diagonal-block $GKR"   # every binding gadget is on by default; no skip flag anywhere
L0_FLAGS=""
OFFSET=0                   # the corpus from its first token, as the headline reads it
XTHREADS=20                # torch threads for the extraction
IDS=${ZK_IDS:-}            # token ids (.npy) already on the host; empty = generate them
KERNEL_FAMILIES=zk_chan_eval,zk_key_eval,zk_row_eval,zk_attn_out_eval,zk_dequant_eval,zk_freivalds_eval,zk_exp_table_eval,zk_table_eval,zk_residual_stream_eval,zk_residual_stream_table_eval
# The block the probe extracts and the segments it proves.  The last block
# reads the longest prefix and therefore holds the plan's largest segments, so
# it is the block that sets the loop's peak.
#
# The two loops that are compared prove layers 1 to 4 of that block: four
# segments, which is two more than a pipelined loop needs to have two in
# flight, and they are the shape 1,023 of the plan's 1,056 segments have.
# Layer 0 is measured on its own and last, because its statement carries the
# embedding gadget and two open prover defects are about exactly that segment
# -- zk-prover #57 refuses to lower its generation kernels and #19 reports no
# margin in its attention output's no-wrap window.  Measured last, a layer-0
# failure costs the comparison nothing; measured inside it, it would cost the
# whole probe.
PROBE_BLOCK=$(( NBLOCK - 1 ))
PROBE_SLICE=1:5            # layers 1 to 4 of the block: the two loops compared
PROBE_L0_SLICE=0:1         # layer 0 alone, the segment that carries the embedding
# Layer 0 is the plan's largest segment, and a pipelined loop holds two at a
# time, so the pair that decides whether the campaign can be pipelined is the
# one containing it -- which the comparison above, run on layers 1 to 4, does
# not touch.  This is that pair.
PROBE_L0_PAIR_SLICE=0:2
PROBE_REF_SLICE=1:2        # one segment on the reference backend: the run's anchor
PROBE_SEGMENTS=4

drv_finish "$(drv_status)"

# ---- start: push the pinned sources, then the job ----------------------------
drv_check_commits
BUILD=$(drv_build_root)
drv_push "$BUILD/src" "$PROVER"
drv_push "$BUILD/harness-src" "$HARNESS"

JOB=$(mktemp)
cat > "$JOB" <<JOBEOF
#!/bin/sh
# generated by $NAME.sh; runs on the host under tools/remote/run.sh
set -eu
B=\$HOME/$BUILD
R=\$HOME/runs/$NAME
SRC=\$B/src; HSRC=\$B/harness-src/harness; GEN=\$B/gen
OUT=\$R/out
WIT=\$HOME/witness/$(printf '%.12s' "$HARNESS")/$SPEC-c$CTX-probe-b$PROBE_BLOCK
# A directory of its own, not the headline's.  lib/sequence-job.sh decides an
# extraction is done by looking for the last block's dump, and the last block is
# the only one the probe writes; sharing the directory would tell the headline run
# that 33 blocks are on the host when one is.  The price is that a headline run
# extracts this block again, which is the cheaper mistake.
mkdir -p \$OUT \$GEN \$WIT
$(drv_job_preamble)
export RAYON_NUM_THREADS=\${RAYON_NUM_THREADS:-16} ZK_KERNEL_STORE=\$GEN
PY="uv run --project \$HSRC \$UVG python"

cat > \$OUT/config.json <<CFG
{"driver": "$NAME", "label": "$LABEL",
 "model": "$MODEL", "spec": "$SPEC",
 "context": $CTX, "s": $S, "positions": $((CTX + S)), "blocks": $NBLOCK, "layers": $NLAY,
 "probe_block": $PROBE_BLOCK, "probe_segments": $PROBE_SEGMENTS,
 "probe_slice": "$PROBE_SLICE", "probe_layer0_slice": "$PROBE_L0_SLICE",
 "probe_layer0_pair_slice": "$PROBE_L0_PAIR_SLICE",
 "shared_flags": "$SHARED", "layer_flags": "$LAYER_FLAGS", "layer0_flags": "$L0_FLAGS",
 "ids": "${IDS:-generated: the corpus's tokens $OFFSET to $((OFFSET + CTX)) and the model's own greedy continuation under $SPEC}",
 "corpus_offset": $OFFSET}
CFG

st "gpu: \$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader)"
st "nvcc: \$(nvcc --version | tail -2 | head -1)"

# 1. both backends of the pinned prover commit
st "build"
( cd \$SRC && CARGO_TARGET_DIR=\$B/t-simd cargo build --release --locked )
( cd \$SRC && CARGO_TARGET_DIR=\$B/t-cuda cargo build --release --locked -p zk-prover --features cuda )
SIMD=\$B/t-simd/release/zk-prover; CUDA=\$B/t-cuda/release/zk-prover

# 2. the harness at its pinned commit
( cd \$HSRC && uv sync --frozen \$UVG )

# 3. the statement's tokens, exactly as the headline driver generates them, so
#    the probe reads the block the headline run would read.
IDSFILE="$IDS"
if [ -z "\$IDSFILE" ]; then
  IDSFILE=\$WIT/ids.npy
  if [ ! -f \$IDSFILE ]; then
    st "ids: greedy continuation, $SPEC, corpus offset $OFFSET"
    # zk-prover #51: gen_ids imports the bare name ppl where every other caller
    # of that function writes the submodule, so running it with -m stops at the
    # import.  This shim binds the name to the submodule and changes nothing
    # else; it goes when the import is fixed.
    cat > \$R/gen_ids_shim.py <<'SHIM'
import runpy
import sys

import harness.witness.ppl

sys.modules.setdefault("ppl", harness.witness.ppl)
runpy.run_module("harness.witness.gen_ids", run_name="__main__")
SHIM
    ( cd \$HSRC && ZK_MODEL=$MODEL ZK_DEVICE=cuda ZK_THREADS=$XTHREADS \$PY \$R/gen_ids_shim.py --prefix $CTX --offset $OFFSET --new 513 --spec $SPEC --out \$WIT/ids_513.npy )
    ( cd \$HSRC && ZK_MODEL=$MODEL ZK_DEVICE=cuda ZK_THREADS=$XTHREADS \$PY \$R/gen_ids_shim.py --prefix $CTX --offset $OFFSET --new $S --spec $SPEC --out \$WIT/ids_512.npy )
    ( cd \$HSRC && \$PY -m harness.witness.shift_ids --ids \$WIT/ids_513.npy --prefix $CTX --new $S --out \$IDSFILE )
    ( cd \$HSRC && \$PY -c "
import numpy as np
a, b = np.load('\$WIT/ids_512.npy'), np.load('\$WIT/ids_513.npy')
assert (a == b[:len(a)]).all(), 'greedy decoding is deterministic; the 512- and 513-token runs must agree'
print('ids: determinism check passed', len(a), 'tokens')" )
  fi
fi
IDSARG="--ids \$IDSFILE"

# 3b. block $PROBE_BLOCK's witnesses.  The forward pass is the whole sequence
#     either way -- a block reads the keys and values of every block before it
#     -- but only this block's dumps are written, which is what makes the probe
#     affordable on disk where the whole plan's extraction is not.  Layer 0 is
#     a pass of its own because --embed writes the embedding table into every
#     dump of the pass it is given.
xpass() {   # xpass <tag> <layers> <last layer of the group> <extra flags>
  tag=\$1; group=\$2; last=\$3; shift 3
  [ ! -f \$WIT/witness_B${PROBE_BLOCK}_L\${last}/manifest.json ] || { st "extract: layers \$group are on this host"; return 0; }
  st "extract: layers \$group, block $PROBE_BLOCK of $NBLOCK, C=$CTX, $SPEC"
  T0=\$(date +%s)
  ( cd \$HSRC && ZK_MODEL=$MODEL ZK_DEVICE=cuda ZK_THREADS=$XTHREADS \$PY -m harness.witness.extract \
      --tokens $((CTX + S)) --chunk $S --layers \$group --spec $SPEC \
      --residual-stream --diagonal-block --slim --slim-num "\$@" \$IDSARG \
      --blocks $PROBE_BLOCK --share \$WIT/shared --out \$WIT/witness )
  T1=\$(date +%s)
  printf '{"pass": "%s", "layers": "%s", "device": "cuda", "threads": %d, "seconds": %d}\n' \
      "\$tag" "\$group" $XTHREADS \$((T1 - T0)) > \$WIT/extract_\$tag.json
  st "extract: layers \$group done in \$((T1 - T0))s"
}
# zk-prover #55: a one-layer extraction writes <base>_B<b> where the shape table
# and the plan both read <base>_B<b>_L<k>, so layer 0's dump is moved into the
# name the next two steps look for.  Only the directory moves; no dump changes.
xpass l0 0 0 --embed
[ ! -d \$WIT/witness_B$PROBE_BLOCK ] || mv \$WIT/witness_B$PROBE_BLOCK \$WIT/witness_B${PROBE_BLOCK}_L0
xpass l1 1,2,3,4,5,6,7 7
xpass l2 8,9,10,11,12,13,14,15 15
xpass l3 16,17,18,19,20,21,22,23 23
xpass l4 24,25,26,27,28,29,30,31 31
if [ ! -f \$WIT/shapes_B$PROBE_BLOCK.json ]; then
  st "shapes"
  ( cd \$HSRC && \$PY -m harness.witness.shapes \$WIT/witness_B${PROBE_BLOCK}_L $NLAY \$WIT/shapes_B$PROBE_BLOCK.json )
fi
python3 - \$WIT \$OUT/extract.json <<'PY'
import glob, json, os, sys
wit, out = sys.argv[1], sys.argv[2]
rows = [json.load(open(f)) for f in sorted(glob.glob(os.path.join(wit, "extract_*.json")))]
json.dump({"passes": rows, "seconds": sum(r["seconds"] for r in rows)}, open(out, "w"), indent=1)
print("extract:", sum(r["seconds"] for r in rows), "s over", len(rows), "passes")
PY
cp \$WIT/shapes_B$PROBE_BLOCK.json \$OUT/shapes.json

# 3c. what one block of this context costs on disk, measured rather than
#     estimated: the whole plan's extraction is 33 of these plus the shared
#     files, and whether that fits the host is decided from this number.
python3 - \$WIT $PROBE_BLOCK \$OUT/disk.json <<'PY'
import json, os, shutil, sys
wit, b, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
def tree(p):
    n = 0
    for root, _, files in os.walk(p):
        for f in files:
            q = os.path.join(root, f)
            if not os.path.islink(q):
                n += os.path.getsize(q)
    return n
block = sum(tree(os.path.join(wit, f"witness_B{b}_L{k}")) for k in range(32))
shared = tree(os.path.join(wit, "shared")) if os.path.isdir(os.path.join(wit, "shared")) else 0
du = shutil.disk_usage(wit)
json.dump({"block": b, "block_bytes": block, "shared_bytes": shared,
           "filesystem_free_bytes": du.free, "filesystem_total_bytes": du.total},
          open(out, "w"), indent=1)
print(f"disk: block {b} is {block / 2**30:.1f} GiB, shared {shared / 2**30:.1f} GiB, "
      f"{du.free / 2**30:.1f} GiB free")
PY

PINS=\$(python3 - \$WIT/shapes_B$PROBE_BLOCK.json <<'PY'
import json, sys
w = json.load(open(sys.argv[1]))["worst"]
print(f"--kmax {w['kmax']} --ao-rem-bits {w['ao_rem_bits']} --fold-rem-bits {w['fold_rem_bits']} --fold-alpha {w['fold_alpha']}")
PY
)
st "pins: \$PINS"

# 4. the plan: block $PROBE_BLOCK's 32 layer segments, no output head.  --blocks
#    auto reads the shape tables that are on this host, which is this one block.
( cd \$HSRC && \$PY -m harness.witness.plan --dir \$WIT --blocks auto --with-block-0 --layers 0-$((NLAY - 1)) \
    --layer-flags="$LAYER_FLAGS" --l0-flags="$L0_FLAGS" --l0-dir \$WIT \
    --out \$OUT/plan.txt --emit-out \$R/emit.txt )
N=\$(grep -cv '^#' \$OUT/plan.txt); st "plan: \$N segments of block $PROBE_BLOCK"

# 5. the device kernels for every shape in the plan, compiled into the CUDA backend
K=\$SRC/prover/kernels
[ -d \$K ] || { st "no prover/kernels in this prover commit; the CUDA backend would evaluate constraints on the CPU"; exit 3; }
if [ ! -f \$R/kernels.done ]; then
  while read -r line; do
    case "\$line" in '#'*|'') continue ;; esac
    args=\$(printf '%s\n' "\$line" | sed 's/--ser-tag [A-Za-z0-9_]*//')
    \$SIMD cudaemit $SHARED \$PINS \$args --out \$GEN --block 256 --min-blocks 2 > /dev/null
    # zk-prover #57: genemit's placeholder claims are one entry short on a chunk
    # that carries the embedding gadget, so it cannot lower the layer-0 shapes.
    # A generation kernel is looked up by fingerprint and the plan's shapes share
    # theirs, so what a refused lowering costs is either nothing or an announced
    # kernel fallback line, and the gate below fails the run on any such line.
    if ! \$SIMD genemit $SHARED \$PINS \$args --families "$KERNEL_FAMILIES" --out \$GEN > /dev/null; then
      printf '%s\n' "\$line" >> \$OUT/genemit-refused.txt
      st "genemit refused a shape (zk-prover #57); recorded in out/genemit-refused.txt"
    fi
  done < \$R/emit.txt
  python3 \$K/m2b_kernels.py --fork \$SRC/nitroo --gen \$GEN
  python3 \$K/m4b_kernels.py --fork \$SRC/nitroo --gen \$GEN --src \$K
  find \$SRC/nitroo/crates/stwo/src/stwo_cuda/cuda \( -name '*.cu' -o -name '*.cuh' \) -exec touch {} +
  cp \$GEN/cudakernels.rs \$GEN/gencudakernels.rs \$SRC/prover/src/
  # an installed tree is no longer the commit that was pushed, and says so
  grep -q ' dirty\$' \$SRC/.source-commit || sed -i 's/\$/ dirty/' \$SRC/.source-commit
  ( cd \$SRC && CARGO_TARGET_DIR=\$B/t-cuda cargo build --release --locked -p zk-prover --features cuda )
  touch \$R/kernels.done
fi
st "kernels installed"

# 6. the two loops over the same $PROBE_SEGMENTS segments, the card sampled once
#    a second.  Neither is allowed to stop the job: a loop that does not fit the
#    card is the probe's answer and not its failure, so the exit code and the
#    last lines of stderr are recorded and the next loop is tried.
probe() {   # probe <tag> <ZK_PIPELINE> <plan slice>
  tag=\$1; pipe=\$2; sl=\$3
  # a probe that has already reported is not run again, so the job can be
  # restarted for the price of what it did not measure
  if [ -s \$OUT/mem_\$tag.json ]; then st "\$tag: already measured"; return 0; fi
  st "\$tag: ZK_PIPELINE=\$pipe over plan segments \$sl"
  rm -rf \$R/ser-\$tag \$R/\$tag.mem; mkdir -p \$R/ser-\$tag
  ( while true; do echo "\$(date +%s) \$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)" >> \$R/\$tag.mem; sleep 1; done ) & sampler=\$!
  T0=\$(date +%s); rc=0
  ZK_PIPELINE=\$pipe \$CUDA compose-chunks $SHARED \$PINS --plan \$OUT/plan.txt --plan-slice \$sl \
      --ser-dir \$R/ser-\$tag > \$OUT/\$tag.json 2> \$R/\$tag.err || rc=\$?
  T1=\$(date +%s)
  kill \$sampler 2>/dev/null || true
  [ \$rc -eq 0 ] || rm -f \$OUT/\$tag.json
  grep -c 'kernel fallback:' \$R/\$tag.err > \$OUT/\$tag.fallbacks || true
  tail -c 2000 \$R/\$tag.err > \$R/\$tag.tail
  python3 - \$R/\$tag.mem \$R/\$tag.tail \$OUT/mem_\$tag.json \$tag \$pipe \$rc \$((T1 - T0)) <<'PY'
import json, sys
mem, tail, out, tag, pipe, rc, secs = sys.argv[1:8]
v = [int(l.split()[1]) for l in open(mem) if len(l.split()) == 2 and l.split()[1].isdigit()]
t = open(tail, errors="replace").read()
oom = any(w in t.lower() for w in ("out of memory", "cudaerrormemoryallocation", "cuda_error_out_of_memory"))
json.dump({"probe": tag, "pipeline": int(pipe), "exit_code": int(rc), "seconds": int(secs),
           "samples": len(v), "period_s": 1, "max_mib": max(v, default=0),
           "mean_mib": round(sum(v) / len(v), 1) if v else 0,
           "out_of_memory": bool(oom),
           "stderr_tail": t[-600:] if int(rc) else ""},
          open(out, "w"), indent=1)
print(f"{tag}: exit {rc}, {secs}s, peak {max(v, default=0)} MiB"
      + (", out of memory" if oom else ""))
PY
  st "\$tag done"
}
probe serial 0 $PROBE_SLICE
probe pipelined 1 $PROBE_SLICE
probe layer0 0 $PROBE_L0_SLICE
probe pipelined_l0 1 $PROBE_L0_PAIR_SLICE

# 6b. one of those segments on the reference backend, which proves in host
#     memory and cannot run the card out of it.  Two reasons it is here and not
#     optional.  It is the run's anchor: the manifest is copied from a
#     prover's provenance block and refuses a fetched directory that has none,
#     and a loop the card could not hold writes no output at all, so without
#     this a probe whose answer is "neither loop fits" could not be recorded --
#     which is the answer most worth recording.  And it freezes a digest for a
#     segment of the headline plan at this context under the variant the paper
#     reports, where the run that froze one before it used the head's variant
#     on a single layer.
if [ ! -s \$OUT/reference-simd.json ]; then
  st "reference backend: plan segment $PROBE_REF_SLICE, in host memory"
  T0=\$(date +%s)
  # not allowed to stop the job either: the card's three peaks are the
  # measurement and they are already written by the time this runs.
  if \$SIMD compose-chunks $SHARED \$PINS --plan \$OUT/plan.txt --plan-slice $PROBE_REF_SLICE \
      --ser-dir \$R/ser-ref > \$OUT/reference-simd.json 2> \$R/reference-simd.err; then
    st "reference backend done in \$(( \$(date +%s) - T0 ))s"
  else
    rm -f \$OUT/reference-simd.json
    st "the reference backend did not prove the segment; see \$R/reference-simd.err"
  fi
fi
rm -rf \$R/ser-serial \$R/ser-pipelined \$R/ser-layer0 \$R/ser-pipelined_l0 \$R/ser-ref

# 7. the answer, from the two loops' own outputs.  The card's size is read off
#    the card, like every other fact about a host.
TOTAL=\$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
python3 - \$OUT $CTX \$TOTAL <<'PY'
import json, pathlib, sys
out, ctx, card = pathlib.Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
rows = []
for tag in ("serial", "pipelined", "layer0", "pipelined_l0"):
    m = json.loads((out / f"mem_{tag}.json").read_text())
    s = None
    f = out / f"{tag}.json"
    if f.exists():
        doc = json.loads(f.read_text())
        p, s = doc["provenance"], doc["result"]["summary"]
        print(f"{tag}: {s['n']} segments, loop {s['loop_secs']:.1f} s, "
              f"fresh {s['fresh_sum']:,.0f} cells, skips {p['unsound_skips'] or 'none'}, "
              f"all_bound {p['binding']['all_bound']}, unbound {p['binding']['unbound']}")
    print(f"{tag}: peak {m['max_mib']} MiB of {card} MiB, exit {m['exit_code']}"
          + (", out of memory" if m["out_of_memory"] else ""))
    rows.append({"probe": tag, "pipeline": m["pipeline"], "exit_code": m["exit_code"],
                 "peak_mib": m["max_mib"], "out_of_memory": m["out_of_memory"],
                 "fits": m["exit_code"] == 0 and not m["out_of_memory"],
                 "segments": s["n"] if s else 0,
                 "loop_secs": s["loop_secs"] if s else None,
                 "fresh_cells": s["fresh_sum"] if s else None})
ref = out / "reference-simd.json"
refrow = None
if ref.exists():
    d = json.loads(ref.read_text())
    p, s2 = d["provenance"], d["result"]["summary"]
    refrow = {"backend": p["backend"], "segments": s2["n"], "loop_secs": s2["loop_secs"],
              "fresh_cells": s2["fresh_sum"], "digests": s2["digests"],
              "unsound_skips": p["unsound_skips"], "all_bound": p["binding"]["all_bound"],
              "unbound": p["binding"]["unbound"]}
    print(f"reference backend: {s2['n']} segment(s), {s2['loop_secs']:.1f} s, "
          f"digest {s2['digests'][0][:16]}, skips {p['unsound_skips'] or 'none'}, "
          f"all_bound {p['binding']['all_bound']}, unbound {p['binding']['unbound']}")
json.dump({"context": ctx, "card_total_mib": card, "probes": rows, "reference": refrow},
          open(out / "probe.json", "w"), indent=1)
fit = [r["probe"] for r in rows if r["fits"]]
print(f"the loops that fit this card at C={ctx}: {', '.join(fit) or 'neither'}")
if not fit:
    print("neither loop fits; the headline campaign at this context does not run on this card")
PY
st "done"
JOBEOF
drv_start "$JOB"
rm -f "$JOB"
