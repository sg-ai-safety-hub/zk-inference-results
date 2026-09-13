#!/bin/sh
# phase-split-c4096: the segment loop split into phases, and what the generated
# constraint kernels buy, on one token block.
#
#   tools/drivers/phase-split-c4096.sh <host> <prover-commit> <harness-commit>
#
# The paper's configuration at context 4,096 -- the five GKR reductions on, the
# shared pins of every campaign at this context, --tight-table among them, every
# binding gadget on and no skip flag anywhere -- over the 32 layer segments of
# the last token block of `headline-c4096`'s plan.  That is the block with the
# longest prefix, so a phase is priced where it weighs most, and it is the
# sample `gkr-ablation-c4096` already prices the reductions on.  The witnesses
# are the ones `headline-c4096` extracted; this driver refuses to run without
# them rather than extracting a second set.
#
# The sample is proved twice, both times with one segment in flight:
#
#   kernels     the paper's configuration as it runs
#   nokernels   the same, with every generated constraint kernel declining to
#               the host (ZK_KERNEL_SKIP, below)
#
# and the run records both loops' phase seconds, per segment and summed, and
# each phase's share of its loop.
#
# ---- why the pipeline is off ------------------------------------------------
#
# The headline row's loop overlaps one segment's generation with another's
# proving, and the two segments' phase spans then overlap in time: the four
# fields the post's phase split is drawn from -- trace_secs, interaction_secs,
# stwo_total and read_secs -- add to 144 per cent of that loop's own seconds
# (runs/2026-09-09-headline-c4096-h100), which is why
# `assumption.loop_split.c4096.*_frac` is asserted and quotes zk-prover #12
# rather than reading this repository's own outputs.
#
# With one segment in flight they stop overlapping.  On the pipeline-off run
# this repository already holds, runs/2026-09-11-control-flags-off-c4096-h100,
# the same four fields add to 85 per cent of the loop over all 290 segments and
# no segment's are inconsistent.  They are still not a split of it: 15 per cent
# is unnamed, and read_secs is one of the four kinds of work inside build_secs
# and not a peer of the other three.  So this driver records a split that does
# partition, and the header below says what each phase is.
#
# ---- the phases -------------------------------------------------------------
#
# One segment of a loop with one segment in flight costs chunk_secs, which runs
# from before the witness is read to after the statement and the proof are
# serialized, and the loop costs the segments' chunk_secs plus its own
# per-segment overhead.  Twelve terms, each measured, none inside another:
#
#   read decode check construct alloc   the witness loader's own four kinds of
#                                       work and the arrays they run in, which
#                                       are the parts of build_secs
#   build_rest                          build_secs less those five
#   trace                               generate_secs: the base trace, built
#                                       before the proving half begins
#   interaction                         interaction_secs: the LogUp interaction
#                                       columns
#   stwo                                stwo_total: the proof system's own
#                                       commitment path and prove call
#   serialize                           the statement and the proof written out
#   prove_rest                          the proving half less interaction, the
#                                       proof system and serialization: the
#                                       session, the commit calls' host work
#                                       and the trace span that runs inside the
#                                       proving half
#   loop_rest                           the loop's seconds outside any segment
#
# They add to loop_secs exactly.  Checked on the run above before this driver
# was written: over its 290 segments the twelve add to its loop_secs to the last
# microsecond and no segment leaves a negative term, with interaction at 40.9
# per cent, trace at 32.2, the proof system at 7.1 and the read at 5.3.  Those
# are that run's shares with the five reductions off and are not this one's.
#
# Two fields the post's split uses do not appear above, and this is why:
#
#   trace_secs      the sum of two spans, one covering nearly all of the trace
#                   build and one covering the head of the proving half before
#                   the proof session exists.  The output reports their sum, so
#                   it cannot be put on either side of that boundary.  What it
#                   costs to use generate_secs instead is small and the run
#                   records both: over the 290 segments above the two are 0.1
#                   per cent apart.
#   prove_secs      the whole proving window, from the session to the end of the
#                   proof system's call.  interaction_secs lies inside it, so
#                   the two double-count the interaction columns -- 40.9 per
#                   cent of the loop on the run above -- and a split that names
#                   both is not a split.  stwo_total is the part of that window
#                   the proof system itself accounts for, and it is what this
#                   run records.
#
# verify_secs is a thirteenth number and is deliberately not a phase: the
# prover verifies each proof from the serialized bytes after the loop has ended,
# so those seconds are outside loop_secs.  The run records them beside the
# split, never in it.
#
# ---- the kernels-off loop ---------------------------------------------------
#
# ZK_KERNEL_SKIP is the prover's switch, a comma-separated list of the kernel
# groups whose generated constraint kernel declines to the host on this run,
# exactly as an absent kernel does.  The list is not written here: it is read on
# the host out of the kernel store's own manifest, so the loop declines every
# group the store holds and nothing is typed in.  Each decline announces itself
# with a kernel fallback line, which is what every other driver's gate counts
# and fails on, so this run's gate is the other way round -- the kernels loop
# must announce none and the nokernels loop must announce some -- and the
# prover's own phase detail must agree: a CPU fallback with no calls in the
# nokernels loop means nothing declined.
#
# The host path evaluates the same AIR, so the two loops must produce the same
# proof: the gate compares the sample's 32 digests segment by segment and fails
# the run on one that moved.  That is what makes the pair a price for the
# kernels rather than two different proofs.
#
# What the switch does not cover: the generated witness-generation and LogUp
# builders, the kernel groups `genemit` writes.  Those are chosen by
# ZK_GENERATED_LOGUP, and it only has a host builder to fall back to where the
# component's columns are on the host; with the device columns on -- which is
# this configuration -- there is nothing to decline to and the demand stands.
# Switching them off therefore needs the device residency off as well, which
# prices the residency and not the kernels.  So this control is the constraint
# kernels alone, and it says so in the run's own config.json.
#
# The first call refuses a host another run is using, pushes zk-prover at the
# two commits, starts the job detached and prints the poll command.  Every later
# call with the same arguments prints the status; once the status says done it
# fetches the outputs into runs/<run-id>/, writes manifest.json from the
# prover's provenance block, and runs check.py.  Nothing measured is typed in
# here.
#
# Host time, from the run this driver recorded: see REPRODUCE.md.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
HOST=${1:?host alias}; PROVER=${2:?prover commit}; HARNESS=${3:?harness commit}
ZK_PROVER=${ZK_PROVER_DIR:-$ROOT/../zk-prover}     # a local clone to archive the commits from
NAME=phase-split-c4096
. "$HERE/lib/driver.sh"

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=control              # a sample of one token block, serial: not a row the paper cites
MODEL=${ZK_MODEL:-unsloth/Llama-3.1-8B-Instruct}
SPEC=y-delay-vw12          # the quantization variant the paper reports (docs/decisions)
CTX=4096; S=512
NBLOCK=$(( (CTX + S) / S ))  # 9: the prompt's 8 blocks and the output block
NLAY=32
SAMPLE=8                   # the plan's last token block: 32 layer segments at prefix c = $CTX
SHARED="--round even --numbits 9 --z-hi-bits 7 --variants intexp --head-groups 16,8,8 --tight-table"
GKR="--gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
LAYER_FLAGS="--round even --diagonal-block $GKR"   # every binding gadget is on by default; no skip flag anywhere
# ZK_PIPELINE: 0, one segment in flight.  The header says why, and nothing here
# has to be taken on trust from this file: the prover writes the value it ran
# under into every output, as modes.PIPELINE value 0 source env and
# result.summary.pipe false.
PIPELINE=0
# The two loops, in the order the job proves them.  The kernels loop first, so a
# run interrupted in the second has the first recorded and redoes only what it
# did not finish.
LOOPS="kernels nokernels"
KERNEL_FAMILIES=zk_chan_eval,zk_key_eval,zk_row_eval,zk_attn_out_eval,zk_dequant_eval,zk_freivalds_eval,zk_exp_table_eval,zk_table_eval,zk_residual_stream_eval,zk_residual_stream_table_eval
# The names of the twelve phases, in the order the record writes them.  The same
# list is in tools/constants/audit.py, which fails a run whose phases.json does
# not carry exactly these.
PHASES="read decode check construct alloc build_rest trace interaction stwo serialize prove_rest loop_rest"

drv_finish "$(drv_status)"

# ---- refuse a host another run is using, before anything is pushed -----------
# tools/remote/run.sh takes the lock, but it takes it after the sources have
# been pushed, and a push over a tree another campaign is building is the one
# thing that cannot be undone.  So the lock and the card are read first, and a
# host that is busy costs a second and not a build.
drv_refuse_busy() {
    held=$(ssh -o BatchMode=yes "$HOST" 'cat $HOME/.zk-run.lock 2>/dev/null || true')
    case "$held" in
      ""|"$NAME "*) ;;
      *) echo "$NAME: $HOST is busy: $held" >&2
         echo "  wait for that run, or start this one on a host that holds no lock" >&2
         exit 1 ;;
    esac
    apps=$(ssh -o BatchMode=yes "$HOST" \
             "nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader" || true)
    if [ -n "$apps" ]; then
        echo "$NAME: $HOST holds no lock and its card is in use:" >&2
        printf '  %s\n' "$apps" >&2
        echo "  find the process with: ssh $HOST ps -eo pid,etime,args" >&2
        exit 1
    fi
    echo "drv_refuse_busy: $HOST holds no run lock and no process is on the card"
}

# ---- start: push the pinned sources, then the job ----------------------------
drv_refuse_busy
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
WIT=\$HOME/witness/$(printf '%.12s' "$HARNESS")/$SPEC-c$CTX     # reused across campaigns
mkdir -p \$OUT \$GEN
$(drv_job_preamble)
export RAYON_NUM_THREADS=\${RAYON_NUM_THREADS:-16} ZK_KERNEL_STORE=\$GEN
PY="uv run --project \$HSRC \$UVG python"

# the configuration, for the manifest
cat > \$OUT/config.json <<CFG
{"driver": "$NAME", "label": "$LABEL",
 "model": "$MODEL", "spec": "$SPEC",
 "context": $CTX, "s": $S, "blocks": $NBLOCK, "layers": $NLAY,
 "sample_block": $SAMPLE, "sample_segments": $NLAY,
 "loops": ["kernels", "nokernels"], "pipeline": $PIPELINE,
 "shared_flags": "$SHARED", "layer_flags": "$LAYER_FLAGS",
 "phases": "$PHASES",
 "kernels_off_switch": "ZK_KERNEL_SKIP",
 "kernels_off_scope": "the generated constraint kernels, every kernel group the store holds. The generated witness-generation and LogUp builders are not switched by it: with the device columns on there is no host builder to decline to, so turning those off would price the device residency as well.",
 "note": "the 32 layer segments of token block $SAMPLE of headline-c4096's plan, proved twice with one segment in flight; the witnesses are headline-c4096's"}
CFG

st "gpu: \$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader)"
st "nvcc: \$(nvcc --version | tail -2 | head -1)"

[ -f \$WIT/shapes_all.json ] || { st "no witnesses at \$WIT: run headline-c4096 on this host at this harness commit first"; exit 5; }

# 1. both backends of the pinned prover commit
st "build"
( cd \$SRC && CARGO_TARGET_DIR=\$B/t-simd cargo build --release --locked )
SIMD=\$B/t-simd/release/zk-prover
( cd \$HSRC && uv sync --frozen \$UVG )
cp \$WIT/shapes_all.json \$OUT/shapes.json
PINS=\$(python3 - \$WIT/shapes_all.json <<'PY'
import json, sys
w = json.load(open(sys.argv[1]))["worst"]
print(f"--kmax {w['kmax']} --ao-rem-bits {w['ao_rem_bits']} --fold-rem-bits {w['fold_rem_bits']} --fold-alpha {w['fold_alpha']}")
PY
)
st "pins: \$PINS"

# 2. the plan, written over the whole sequence so every line is the line the
#    headline plan carries, and then the sample block's lines taken out of it.
#    The output head is not in it: this sample is the block's layer segments and
#    a head segment is not one of them.
( cd \$HSRC && \$PY -m harness.witness.plan --dir \$WIT --blocks $NBLOCK --with-block-0 \
    --layers 0-$((NLAY - 1)) --layer-flags="$LAYER_FLAGS" --out \$R/plan.full.txt )
grep -- '--ser-tag B${SAMPLE}L' \$R/plan.full.txt > \$OUT/plan.txt
N=\$(grep -cv '^#' \$OUT/plan.txt)
[ "\$N" = "$NLAY" ] || { st "the sample has \$N lines, not $NLAY"; exit 6; }
st "plan: \$N segments of token block $SAMPLE"

# 3. the device kernels for every shape in the sample, compiled into the CUDA
#    backend.  A kernel is looked up by fingerprint and the store dedups, so a
#    line whose shape is already there costs the lowering and nothing else, and
#    every line is emitted rather than a guess at which of them are distinct.
K=\$SRC/prover/kernels
[ -d \$K ] || { st "no prover/kernels in this prover commit; the CUDA backend would evaluate constraints on the CPU"; exit 3; }
PLANSUM=\$(sha256sum \$OUT/plan.txt | cut -c1-16)
if [ "\$(cat \$R/kernels.done 2>/dev/null)" != "\$PLANSUM" ]; then
  while read -r line; do
    case "\$line" in '#'*|'') continue ;; esac
    args=\$(printf '%s\n' "\$line" | sed 's/--ser-tag [A-Za-z0-9_]*//')
    for emit in cudaemit genemit; do
      case \$emit in
        cudaemit) opts="--block 256 --min-blocks 2" ;;
        genemit)  opts="--families $KERNEL_FAMILIES" ;;
      esac
      if ! \$SIMD \$emit $SHARED \$PINS \$args \$opts --out \$GEN > /dev/null; then
        printf '%s\n' "\$line" >> \$OUT/\$emit-refused.txt
        st "\$emit refused a shape (zk-prover #57); recorded in out/\$emit-refused.txt"
      fi
    done
  done < \$OUT/plan.txt
  # The install copies the store into the vendored fork and touches its CUDA
  # tree, which rebuilds every generated kernel.  Where the store has not moved
  # since the build already on this host was made -- the headline campaign
  # emitted these very shapes -- the two dispatch tables are identical and the
  # rebuild would produce the binary that is already there, so it is skipped.
  if cmp -s \$GEN/cudakernels.rs \$SRC/prover/src/cudakernels.rs &&
     cmp -s \$GEN/gencudakernels.rs \$SRC/prover/src/gencudakernels.rs; then
    st "kernels: the store is the one this build was installed from; not reinstalled"
  else
    python3 \$K/install_constraint_kernels.py --fork \$SRC/nitroo --gen \$GEN
    python3 \$K/install_witness_gen_kernels.py --fork \$SRC/nitroo --gen \$GEN --src \$K
    find \$SRC/nitroo/crates/stwo/src/stwo_cuda/cuda \( -name '*.cu' -o -name '*.cuh' \) -exec touch {} +
    cp \$GEN/cudakernels.rs \$GEN/gencudakernels.rs \$SRC/prover/src/
    # an installed tree is no longer the commit that was pushed, and says so
    grep -q ' dirty\$' \$SRC/.source-commit || sed -i 's/\$/ dirty/' \$SRC/.source-commit
  fi
  printf '%s\n' "\$PLANSUM" > \$R/kernels.done
fi
( cd \$SRC && CARGO_TARGET_DIR=\$B/t-cuda cargo build --release --locked -p zk-prover --features cuda )
CUDA=\$B/t-cuda/release/zk-prover
st "kernels installed"

# 4. the kernel groups the nokernels loop declines: every group the store holds,
#    read off the store's own manifest.  Nothing is typed in, so a group the
#    prover gains is declined by the next run without this file changing.
SKIPLIST=\$(python3 - \$GEN/manifest.json \$OUT/kernels-declined.json <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
names = sorted({f["family"] for f in d["families"]})
kernels = sum(len(f["shapes"]) for f in d["families"])
json.dump({"switch": "ZK_KERNEL_SKIP", "groups": names, "kernels_in_store": kernels,
           "note": "the kernel groups the nokernels loop declines to the host, read out of "
                   "the constraint kernel store's own manifest. Each decline announces "
                   "itself with a kernel fallback line and the host path evaluates the same "
                   "AIR, so the two loops must produce the same proof."},
          open(sys.argv[2], "w"), indent=1)
print(",".join(names))
PY
)
st "declining \$(printf '%s' "\$SKIPLIST" | tr ',' ' ' | wc -w) kernel groups in the nokernels loop"

# 5. the two timed loops, one process each, one segment in flight, the card
#    sampled once a second.  A loop whose output is already written is not
#    proved again, so a run interrupted in the second is restarted for the price
#    of the second alone.
for lp in $LOOPS; do
  if [ -s \$OUT/\$lp.json ]; then st "\$lp already proved"; continue; fi
  rm -f \$R/\$lp.mem
  ( while true; do echo "\$(date +%s) \$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)" >> \$R/\$lp.mem; sleep 1; done ) & sampler=\$!
  st "\$lp: proving \$N segments"
  (
    export ZK_PIPELINE=$PIPELINE
    if [ "\$lp" = nokernels ]; then export ZK_KERNEL_SKIP="\$SKIPLIST"; fi
    \$CUDA compose-chunks $SHARED \$PINS --plan \$OUT/plan.txt > \$OUT/\$lp.json 2> \$R/\$lp.err
  ) || { kill \$sampler; rm -f \$OUT/\$lp.json; st "\$lp failed, see \$R/\$lp.err"; exit 4; }
  kill \$sampler
  grep -c 'kernel fallback:' \$R/\$lp.err > \$OUT/\$lp.fallbacks || true
  python3 - \$R/\$lp.mem \$OUT/\$lp.mem.json <<'PY'
import json, sys
v = [int(l.split()[1]) for l in open(sys.argv[1]) if len(l.split()) == 2 and l.split()[1].isdigit()]
json.dump({"samples": len(v), "period_s": 1, "max_mib": max(v, default=0),
           "mean_mib": round(sum(v) / len(v), 1) if v else 0}, open(sys.argv[2], "w"))
PY
  st "\$lp done"
done

# 6. the split: twelve phases per segment, summed over each loop, and each
#    phase's share of its own loop.  Nothing here is a fitted number -- every
#    term is a field of the loop's own output or a difference of two of them --
#    and the record fails rather than publishing a split that does not add up.
python3 - \$OUT "$PHASES" $NLAY <<'PHASEPY'
import json, pathlib, sys

out, phases, want = pathlib.Path(sys.argv[1]), sys.argv[2].split(), int(sys.argv[3])
BUILD = ("read", "decode", "check", "construct", "alloc")
SER = ("wall/ser_statement", "wall/ser_proof", "wall/ser_write")


def split_of(doc):
    """One loop's twelve phases, per segment and summed.

    Every term is measured. build_rest is what the loader's own four kinds of
    work and their arrays leave of the segment's build, prove_rest is what the
    interaction columns, the proof system's own call and the serialization leave
    of the proving half, and loop_rest is what the segments leave of the
    loop. A negative term would mean two of these overlap and is a failure.
    """
    s, rows, tot = doc["result"]["summary"], [], dict.fromkeys(phases, 0.0)
    for c in doc["result"]["chunks"]:
        hp = c["host_phases"]
        row = {k: c[k + "_secs"] for k in BUILD}
        row["build_rest"] = c["build_secs"] - sum(row[k] for k in BUILD)
        row["trace"] = c["generate_secs"]
        row["interaction"] = c["interaction_secs"]
        row["stwo"] = c["stwo_total"]
        row["serialize"] = sum(hp.get(k, {}).get("secs", 0.0) for k in SER)
        row["prove_rest"] = (c["chunk_secs"] - c["build_secs"] - c["generate_secs"]
                             - row["interaction"] - row["stwo"] - row["serialize"])
        row["loop_rest"] = 0.0
        for k in phases:
            tot[k] += row[k]
        rows.append({"ser_tag": c["ser_tag"], "plan_index": c["plan_index"],
                     "chunk_secs": c["chunk_secs"], "secs": row})
    tot["loop_rest"] = s["loop_secs"] - sum(r["chunk_secs"] for r in rows)
    return s, rows, tot


def detail(doc, name):
    v = [c["phases"]["detail"].get(name, {"calls": 0, "secs": 0.0})
         for c in doc["result"]["chunks"]]
    return {"calls": sum(x["calls"] for x in v), "secs": sum(x["secs"] for x in v)}


def host_phases(doc):
    """The prover's own named host phases, summed over the sample.

    The twelve above say how much of the loop is generation; this says which
    components it is, which is what zk-prover #12 moves onto the card one group
    at a time and what its acceptance criteria read. Every name the prover
    reports, no selection here.
    """
    tot = {}
    for c in doc["result"]["chunks"]:
        for k, e in c["host_phases"].items():
            row = tot.setdefault(k, {"calls": 0, "secs": 0.0})
            row["calls"] += e["calls"]
            row["secs"] += e["secs"]
    return dict(sorted(tot.items()))


loops, bad = {}, []
for name in json.loads((out / "config.json").read_text())["loops"]:
    doc = json.loads((out / f"{name}.json").read_text())
    s, rows, tot = split_of(doc)
    if s["n"] != want:
        bad.append(f"{name}: {s['n']} segments, not the sample's {want}")
    if s["pipe"]:
        bad.append(f"{name}: the loop overlapped two segments and its phases do not partition")
    for k, x in sorted(tot.items()):
        if x < 0:
            bad.append(f"{name}: phase {k} is {x:.6f} s, so two phases overlap")
    err = sum(tot.values()) - s["loop_secs"]
    if abs(err) > 1e-6:
        bad.append(f"{name}: the phases add to {sum(tot.values()):.6f} s and the loop is "
                   f"{s['loop_secs']:.6f} s")
    loops[name] = {
        "segments": s["n"], "pipe": s["pipe"], "loop_secs": s["loop_secs"],
        "secs": tot,
        "share": {k: x / s["loop_secs"] for k, x in tot.items()},
        "fallback_lines": int((out / f"{name}.fallbacks").read_text().strip()),
        "constraint_eval": {
            "gpu": detail(doc, "constraint_eval_gpu"),
            "cpu_fallback": detail(doc, "constraint_eval_cpu_fallback"),
            "cpu_autofallback": detail(doc, "constraint_eval_cpu_autofallback"),
        },
        # The field the post's split calls the trace, beside the one this record
        # uses: the two are the same span but for the part of it that runs
        # inside the proving half, which the output does not report on its own.
        "trace_secs_field": sum(c["trace_secs"] for c in doc["result"]["chunks"]),
        "host_phases": host_phases(doc),
        # After the loop, never in it: the prover verifies each proof from the
        # serialized bytes once the loop has ended.
        "verify_after_loop_secs": sum(c["verify_secs"] for c in doc["result"]["chunks"]),
        "digests": [c["proof_sha256"] for c in doc["result"]["chunks"]],
        "segment_rows": rows,
    }

names = list(loops)
first = loops[names[0]]["digests"]
same = all(loops[n]["digests"] == first for n in names)
json.dump({
    "sample": {"block": json.loads((out / "config.json").read_text())["sample_block"],
               "segments": want, "context": 4096, "pipeline": 0},
    "phases": phases,
    "loops": loops,
    "digests_match": same,
    "note": "Twelve phases of the segment loop, measured with one segment in flight so that "
            "no two of them overlap. They add to the loop's own seconds exactly. The post's "
            "split is drawn from trace_secs, interaction_secs, stwo_total and read_secs, of "
            "which the first two overlap the proving window and the last is one of the four "
            "kinds of work inside the build; this record uses generate_secs for the trace, "
            "interaction_secs for the interaction columns, stwo_total for the proof system "
            "and the loader's own read for the read, and names what is left.",
}, open(out / "phases.json", "w"), indent=1)

for name in names:
    lo = loops[name]
    print(f"{name}: {lo['segments']} segments, loop {lo['loop_secs']:.1f} s, "
          f"{lo['fallback_lines']} kernel fallback lines")
    for k in phases:
        print(f"    {k:12s} {lo['secs'][k]:9.1f} s  {100 * lo['share'][k]:5.2f}%")
print(f"digests match across the loops: {same}")
if bad:
    sys.exit("; ".join(bad))
PHASEPY

# 7. the gate: both loops proved the sample, no skip in effect, every edge
#    bound, the kernels loop took no fallback and the nokernels loop took some,
#    and the two loops made the same proof segment by segment
python3 - \$OUT <<'PY'
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
cfg = json.loads((out / "config.json").read_text())
ph = json.loads((out / "phases.json").read_text())
bad = []
for name in cfg["loops"]:
    doc = json.loads((out / f"{name}.json").read_text())
    p, s = doc["provenance"], doc["result"]["summary"]
    lo = ph["loops"][name]
    ce = lo["constraint_eval"]
    host_calls = ce["cpu_fallback"]["calls"] + ce["cpu_autofallback"]["calls"]
    print(f"{name:10s} {s['n']} segments, loop {s['loop_secs']:.1f} s, "
          f"fresh {s['fresh_sum']:,.0f} cells, skips {p['unsound_skips'] or 'none'}, "
          f"all_bound {p['binding']['all_bound']}, "
          f"{lo['fallback_lines']} fallback lines, constraint evaluation "
          f"{ce['gpu']['secs']:.2f} s on the card and {host_calls} call(s) on the host")
    if p["unsound_skips"]:
        bad.append(f"{name}: unsound skips in effect")
    if not p["binding"]["all_bound"]:
        bad.append(f"{name}: unbound edges {p['binding']['unbound']}")
    if s["pipe"]:
        bad.append(f"{name}: the loop overlapped two segments")
    if name == "nokernels":
        if not lo["fallback_lines"]:
            bad.append("nokernels: no kernel fallback line, so no generated kernel declined")
        if not host_calls:
            bad.append("nokernels: the prover evaluated no constraint on the host, so the "
                       "switch changed nothing")
    elif lo["fallback_lines"] or host_calls:
        bad.append(f"{name}: {lo['fallback_lines']} kernel fallback line(s) and {host_calls} "
                   "host constraint evaluation(s); this loop is the configuration with every "
                   "generated kernel in place")
if not ph["digests_match"]:
    a, b = (ph["loops"][n]["digests"] for n in cfg["loops"][:2])
    moved = [i for i, (x, y) in enumerate(zip(a, b)) if x != y]
    bad.append(f"the two loops proved different bytes at segment index(es) {moved}; the host "
               "path evaluates the same AIR and the proof must not move")
k = ph["loops"]["kernels"]["loop_secs"]
n = ph["loops"]["nokernels"]["loop_secs"]
print(f"the generated constraint kernels: loop {k:.1f} s with them and {n:.1f} s without, "
      f"{n - k:+.1f} s")
if bad:
    sys.exit("; ".join(bad))
print("both loops proved the sample; no skip; every edge bound; the same proof either way")
PY
st "done"
JOBEOF
drv_start "$JOB"
rm -f "$JOB"
