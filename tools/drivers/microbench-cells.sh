#!/bin/sh
# microbench-cells: what one operation of each kind costs in committed cells.
#
#   tools/drivers/microbench-cells.sh <host> <prover-commit> <harness-commit>
#
# The cost model prices a proof from a cell count and a rate.  `microbench.sh`
# measures the rates -- the vendored library's benchmarks of the primitives, and
# one composed segment's commitment and FRI parts -- and this measures the cell
# counts: what one dequantized accumulator, one requantized value, one
# residual-stream operation, one argmax comparison, one packed attention
# instance, one lookup at each accumulator width and one at each `kmax` cost,
# what one weight of the Freivalds check costs at a given row width, and what
# one lookup costs at each of the two LogUp batch sizes the prover uses.
# A cell count is the same on both backends, so they are read on the reference
# backend, on the host's cores, with no card involved.
#
# It is a sibling of `microbench.sh` rather than a second half of it, because
# the two answer different questions and the rates were measured at another
# prover commit: a run that re-derived them here would either re-point the
# constants that already name that run or leave two runs claiming one number.
# The cell-cost subcommands could not run at that commit at all (zk-prover #88),
# so there was nothing to record then, and the two newest of them did not exist
# there at all (zk-prover #139, #140).
#
# The composed segment is here for one reason: `compose` is the only subcommand
# that makes a proof and therefore the only one that writes a binding table,
# which is what makes the run admissible.  Its numbers are not what this run is
# for and it backs no constant of its own here.
#
# `pack` carries `--table-bits 23`.  The shared exponent table used to be sized
# from the data with a cap, so the instance counts above 4 could not be asked
# for; zk-prover #98 bounds it by the flag instead, and the counts at 1, 2 and 4
# do not move under it.
#
# `freivalds` is asked twice, because what it measures is a law and not a
# number: the check's three accumulator columns cost 12 cells a trace row and a
# row carries `p` weights, so it is `12/p` fresh cells per weight and `p` is a
# knob.  `b3-freivalds.json` is the prover's own default row width (`params_of`'s
# `--p 136`; `--nout 544` is the output width that tiles it exactly), and that
# point is what backs `model_constants.weight_freivalds_cells_per_weight`.
# `b3-freivalds-widths.json` is the same check at four widths, which is what says
# the closed form holds instead of assuming it.  Two things the record has to
# say beside the number: the private archive's 0.0902 is `12/133`, the same law
# at a shape whose grid padded 32,256 rows up to 2^15, and this subcommand
# refuses a ragged tiling and so reports the unpadded form; and a group of `n`
# matmuls shares one accumulator, so it costs `(4 + 8n)/(n p)` per weight and not
# `12/p` (zk-prover #139).
#
# The Freivalds outputs are not called `b3-width`.  The cost model reads its
# Freivalds sweep from `<inputs>/b3/width.json`, and this driver has written
# `b3-width.json` since its first run for the `width` subcommand, which sweeps
# the dequantization at six accumulators per row and is a different measurement
# backing two constants of its own.  An inputs directory assembled out of this
# run's outputs takes `b3/width.json` from `b3-freivalds-widths.json` and takes
# nothing at all from `b3-width.json`.
#
# `logup` measures what one lookup costs on its own, which every other
# subcommand here reports only from inside a gadget that has its own lookups.
# One output carries both batch sizes this prover uses: 1, which every table
# side finalizes with, and 2, which every use side does.  The constant it backs,
# `model_constants.logup_marginal_cells_per_lookup`, is therefore one figure per
# batch size, and the cost model's reader refuses a scalar under that key, so
# the record is an object keyed by the batch size written as a string.
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
NAME=microbench-cells
. "$HERE/lib/driver.sh"

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=microbench           # an input to the cost model, not a configuration the paper cites
# The composed segment: the prover's recorded sound synthetic shape, with the
# five GKR reductions on because that is the paper's configuration.
ARITH="--round away --variants intsplit6 --table-bits 16"
SHAPE="--s 32 --ctx 128 --hd 32 --head-groups 2,2 --nin 128 --nout 128 --residual-stream-a 32 --kmax 16 --synth-residual-stream --diagonal-block"
GKR="--gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
# The cell-cost subcommands, one line each: <output name>|<subcommand and flags>
CELL_COSTS='b6-dequant|dequant --n 1048576 --per-row 16 --variants limbs,round,pow2,chain,int8 --round even
b6-pack|pack --s 512 --ctx 1024 --hd 64 --insts 1,2,4,8,16 --variants intexp --table-bits 23
b65-requant|requant --round even
b65-residual-stream|residual-stream --rows 4096 --leaves 32 --per-row 16 --kmax 18 --round even
b10-argmax|argmax --tokens 8 --vocab 8192 --per-row 64
b3-width|width --n 1048576 --widths 4,8,16,32,64,128
b4-kmax|kmax --n 262144 --per-row 16 --kmax-sweep 10,12,14,16,18,21
b3-freivalds|freivalds --s 32 --nin 64 --nout 544 --widths 136
b3-freivalds-widths|freivalds --s 32 --nin 64 --nout 64 --widths 8,16,32,64
logup|logup --table-bits 12 --log-rows 10 --lookups-per-row 4'
XTHREADS=20

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
SRC=\$B/src
OUT=\$R/out
mkdir -p \$OUT
$(drv_job_preamble)
export RAYON_NUM_THREADS=\${RAYON_NUM_THREADS:-$XTHREADS}

cat > \$OUT/config.json <<CFG
{"driver": "$NAME", "label": "$LABEL",
 "compose_arith": "$ARITH", "compose_shape": "$SHAPE", "compose_gkr": "$GKR",
 "cell_cost_commands": "$(printf '%s' "$CELL_COSTS" | tr '\n' ';')",
 "threads": $XTHREADS,
 "witness": "synthetic, the prover's own fixed-seed generator; no model and no extraction"}
CFG

# The card is logged where there is one and the run goes on where there is not:
# every number here is a cell count, nothing is timed against a card, and the
# host this lands on need not have one.  What the manifest records as the run's
# GPU is whatever the prover reported in its own provenance block.
if command -v nvidia-smi > /dev/null 2>&1; then
  st "gpu: \$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader)"
else
  st "gpu: none reported; this run counts cells and times nothing against a card"
fi
st "cores: \$(nproc), threads \$RAYON_NUM_THREADS"

# 1. the reference backend of the pinned prover commit.  The vendored library
#    links its CUDA library on every Linux build, so the toolkit is needed here
#    too, but nothing in this run proves on the card.
st "build"
( cd \$SRC && CARGO_TARGET_DIR=\$B/t-simd cargo build --release --locked )
SIMD=\$B/t-simd/release/zk-prover

# 2. the composed segment, which is what carries the binding table
if [ ! -s \$OUT/compose-simd.json ]; then
  st "compose on the reference backend"
  \$SIMD compose $ARITH $SHAPE $GKR > \$OUT/compose-simd.json 2> \$R/compose-simd.err
fi

# 3. the cell-cost subcommands, on the reference backend.  A subcommand that
#    refuses is recorded and the run goes on: the cost model reads each of
#    these on its own, and which of them the pinned commit cannot answer is
#    part of the record.
printf '%s\n' '$CELL_COSTS' | while IFS='|' read -r out cmd; do
  [ -n "\$out" ] || continue
  if [ -s \$OUT/\$out.json ]; then st "\$out already run"; continue; fi
  st "\$out: \$cmd"
  if \$SIMD \$cmd > \$OUT/\$out.json 2> \$R/\$out.err; then
    st "\$out done"
  else
    rm -f \$OUT/\$out.json
    printf '%s\n' "\$out: \$cmd" >> \$OUT/refused.txt
    st "\$out did not run; recorded in out/refused.txt, see \$R/\$out.err"
  fi
done

# 4. what was measured, and the gate: the composed segment accepts with no skip
#    in effect, and every cell-cost subcommand this driver names wrote a record.
python3 - \$OUT <<'PY'
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
bad, rows = [], {}
digests = {}
cfg = json.loads((out / "config.json").read_text())
asked = [line.split("|")[0] for line in cfg["cell_cost_commands"].split(";") if line]
for tag in ("compose-simd",):
    f = out / f"{tag}.json"
    if not f.exists():
        bad.append(f"{tag}: the composed segment did not prove"); continue
    doc = json.loads(f.read_text())
    p, prov = doc["result"]["point"], doc["provenance"]
    digests[tag] = p["proof_sha256"]
    ph = p["phases"]
    rows[tag] = {"backend": prov["backend"], "accepts": p["accepts"],
                 "fresh_cells": p["cells"]["fresh"],
                 "commit_secs": ph["commit_secs"], "fri_secs": ph["fri_secs"],
                 "prove_call_secs": ph["prove_call_secs"],
                 "wall_secs": ph["wall_secs"],
                 "unsound_skips": prov["unsound_skips"],
                 "all_bound": prov["binding"]["all_bound"],
                 "unbound": prov["binding"]["unbound"]}
    print(f"{tag}: {p['cells']['fresh']:,} fresh cells, accepts {p['accepts']}, "
          f"skips {prov['unsound_skips'] or 'none'}, unbound {prov['binding']['unbound']}")
    if not p["accepts"]:
        bad.append(f"{tag}: the proof was rejected")
    if prov["unsound_skips"]:
        bad.append(f"{tag}: unsound skips in effect")
made = sorted(f.name for f in out.glob("*.json"))
refused = (out / "refused.txt").read_text().split("\n") if (out / "refused.txt").exists() else []
refused = [r for r in refused if r]
missing = [t for t in asked if not (out / f"{t}.json").exists()]
json.dump({"compose": rows, "digests": digests, "outputs": made,
           "cell_costs_asked": asked, "cell_costs_missing": missing,
           "refused": refused},
          open(out / "summary.json", "w"), indent=1)
print(f"{len(made)} JSON outputs, {len(asked) - len(missing)} of {len(asked)} "
      f"cell-cost subcommands answered, {len(refused)} refused")
for r in refused:
    print(f"refused: {r}")
if bad:
    sys.exit("; ".join(bad))
print("the composed segment accepts; no skip in effect")
PY
st "done"
JOBEOF
drv_start "$JOB"
rm -f "$JOB"
