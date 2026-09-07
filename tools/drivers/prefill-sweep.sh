#!/bin/sh
# prefill-sweep: what one attention segment costs as the prompt block grows.
#
#   tools/drivers/prefill-sweep.sh <host> <prover-commit> <harness-commit>
#
# One synthetic layer segment at S = C for S in 256, 512, 1024 and 2048, on the
# SIMD backend, under the paper's arithmetic.  The segment is the prover's own:
# without a witness it draws the queries, keys, values, weights and the
# residual-stream columns from a pseudorandom generator with a fixed seed, so
# nothing here comes from a model and no extraction runs.  What the sweep
# measures is the shape's price -- committed cells, and how many of them the
# attention key tiles account for -- as the only thing that moves is the block
# length.
#
# A key tile is the group of attention head instances that share one column
# set, and its cell count is what the cost model's attention grid is a closed
# form for.  The sweep is issue #14's: it fixes the head groups at the 8B
# model's 16,8,8 and moves S alone.
#
# The sweep cannot be run under the arithmetic the paper reports.  A synthetic
# layer's master table is sized from its own data and clamped to 2^22 rows
# (`prover/src/layer.rs`), `--table-bits` is not read on that path and
# `--tight-table` only ever narrows a table; under `intexp` the exponential key
# passes 2^22 somewhere below a 256-token block, at any head configuration, and
# the honest proof is rejected.  zk-prover #72 has the reproduction.
#
# So the run asks a question first and sweeps second.  The exponential table is
# its own component and the key tiles are counted apart from it, so the key-tile
# family may not depend on the softmax variant at all.  The run proves one small
# block under both variants and compares their key-tile cell counts, and records
# what it found: that they agree, that they differ, or that the paper's variant
# would not prove even there and the two could not be compared.  The sweep runs
# under the variant that can prove these block lengths either way, and every
# number it produces names that variant, so nobody reads it as the paper's
# arithmetic by accident.
#
# Every pin is named in this file and none is left to the layer, so the points
# differ in the block length and in nothing else.

# The SIMD backend, not the CUDA one: this is a cell count and a shape, the two
# backends prove the same statement to the same digest, and the sweep's largest
# point is bounded by host memory rather than by the card.
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
NAME=prefill-sweep
. "$HERE/lib/driver.sh"

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=design               # a design measurement: neither a headline nor a control
POINTS="256 512 1024 2048" # S, and C = S at every point, as the issue asks
# The shape is the prover's own aligned synthetic one, four heads of 32, and not
# the 8B model's 32 heads of 128.  That is not a preference: a synthetic layer at
# the 8B's attention width cannot be proved at this prover commit.  Its
# exponential table is sized from its own data and clamped to 2^22 rows
# (`prover/src/layer.rs`), the 8B width needs 24 bits of key, `--table-bits` is
# not consulted on that path and `--tight-table` only ever narrows a table; the
# honest proof is rejected.  Narrowing the matmuls instead leaves the attention
# output and the o matmul at different widths, the rotation is not built, and
# two edges do not bind.  zk-prover #72 has both halves and the reproduction.
#
# So this sweep measures the shape of the key tiles' cost in the block length at
# a smaller head count, and the campaign's pull request says plainly that the
# 8B's own coefficients are not what was measured.
HD=32                      # the aligned shape's head dimension
HEAD_GROUPS=2,2            # nh = 4 as two key tiles
NIN=128; NOUT=128          # nh * hd = 128: the widths line up and every edge binds
RSA=32                     # --residual-stream-a
KMAX=16
# The paper's arithmetic.  The table width is left to the layer, which sizes it
# from its own data: at this shape it stays inside the clamp that stopped the 8B
# width, and the width each point chose is recorded beside that point's numbers.
# It moves the table's own cells only, and the key tiles -- which is what this
# sweep is for -- are counted separately from them.
SHARED_ARITH="--round even --numbits 9 --z-hi-bits 7"
VARIANT_PAPER=intexp       # the arithmetic the paper reports; it cannot sweep
VARIANT_SWEEP=intsplit6    # the one that needs no exponential table
CHECK_S=128                # the block length both variants can prove, where they are compared
GKR="--gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
# --diagonal-block and --synth-residual-stream are what the sound defaults ask of
# a synthetic segment: without the first the keys and values cannot be bound to
# the next block and without the second the residual stream cannot be bound to
# the next layer, and either one missing would mean a skip flag.  At C = S the
# diagonal block is one more tile per prefix tile, so the key-tile count here is
# twice that of the attention score block on its own, which is a factor every
# number below carries and the pull request states.
SHAPE="--hd $HD --head-groups $HEAD_GROUPS --nin $NIN --nout $NOUT --residual-stream-a $RSA --kmax $KMAX --synth-residual-stream --diagonal-block"
XTHREADS=20                # RAYON_NUM_THREADS for the SIMD backend

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
 "points": "$POINTS", "context_equals_s": true,
 "hd": $HD, "head_groups": "$HEAD_GROUPS", "nin": $NIN, "nout": $NOUT,
 "residual_stream_a": $RSA, "kmax": $KMAX, "threads": $XTHREADS,
 "shared_arithmetic": "$SHARED_ARITH", "paper_variant": "$VARIANT_PAPER",
 "sweep_variant": "$VARIANT_SWEEP", "check_s": $CHECK_S,
 "gkr_flags": "$GKR", "shape_flags": "$SHAPE",
 "backend": "simd", "witness": "synthetic, the prover's own fixed-seed generator"}
CFG

st "gpu: \$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader)"
st "cores: \$(nproc), threads \$RAYON_NUM_THREADS"

# 1. the SIMD backend of the pinned prover commit.  The vendored library links
#    its CUDA library on every Linux build, so the toolkit is needed here too.
st "build"
( cd \$SRC && CARGO_TARGET_DIR=\$B/t-simd cargo build --release --locked )
SIMD=\$B/t-simd/release/zk-prover

# 2. the question the sweep depends on: do the two variants count the same key
#    tiles?  One small block, proved under each.
for v in $VARIANT_PAPER $VARIANT_SWEEP; do
  f=\$OUT/check_\$v.json
  if [ -s \$f ]; then st "check \$v: already proved"; continue; fi
  st "check: $CHECK_S under \$v"
  if \$SIMD compose $SHARED_ARITH --variants \$v $SHAPE $GKR --s $CHECK_S --ctx $CHECK_S \
      > \$f 2> \$R/check_\$v.err; then
    st "check \$v: proved"
  else
    rm -f \$f; st "check \$v: did not prove, see \$R/check_\$v.err"
  fi
done
AGREE=\$(python3 - \$OUT $VARIANT_PAPER $VARIANT_SWEEP <<'PY'
import json, os, sys
out, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
def tiles(v):
    f = os.path.join(out, f"check_{v}.json")
    if not os.path.exists(f):
        return None
    return json.load(open(f))["result"]["point"]["family_cells"]["key_tiles"]
ta, tb = tiles(a), tiles(b)
print(json.dumps({"paper_variant": a, "sweep_variant": b, "key_tiles_paper": ta,
                  "key_tiles_sweep": tb, "agree": ta is not None and ta == tb}))
PY
)
printf '%s\n' "\$AGREE" > \$OUT/variant_check.json
st "variant check: \$AGREE"

# 3. the sweep, under the variant that can prove these block lengths.  A point
#    already proved is not proved again, so an interrupted sweep is restarted
#    for the price of what it did not finish.
for S in $POINTS; do
  f=\$OUT/dd_s\$S.json
  if [ -s \$f ]; then st "S=\$S already proved"; continue; fi
  st "measure: S = C = \$S"
  T0=\$(date +%s)
  if \$SIMD compose $SHARED_ARITH --variants $VARIANT_SWEEP $SHAPE $GKR --s \$S --ctx \$S \
      > \$f 2> \$R/dd_s\$S.err; then
    T1=\$(date +%s); st "S=\$S proved in \$((T1 - T0))s"
  else
    rm -f \$f; st "S=\$S did not prove; see \$R/dd_s\$S.err"
    if [ "\$S" = "$(set -- $POINTS; echo $1)" ]; then
      st "the smallest point did not prove; the rest would not either, so the sweep stops here"
      exit 5
    fi
  fi
done

# 4. the sweep, read back off the outputs, and the gate
python3 - \$OUT "$POINTS" <<'PY'
import json, pathlib, sys
out, points = pathlib.Path(sys.argv[1]), [int(x) for x in sys.argv[2].split()]
rows, bad = [], []
for s in points:
    f = out / f"dd_s{s}.json"
    if not f.exists():
        bad.append(f"S={s} did not prove"); continue
    doc = json.loads(f.read_text())
    p, prov = doc["result"]["point"], doc["provenance"]
    fam = p["family_cells"]
    row = {"s": s, "c": s, "accepts": p["accepts"], "off_table": p["off_table"],
           "fresh": p["cells"]["fresh"], "base": p["cells"]["base"],
           "interaction": p["cells"]["interaction"],
           "preprocessed": p["cells"]["preprocessed"],
           "key_tiles": fam["key_tiles"],
           "columns_total": p["columns"]["total"],
           "log_table": p["params"]["log_table"],
           "ao_rem_bits": p["params"]["ao_rem_bits"],
           "prove_secs": p["prove_secs"], "trace_secs": p["trace_secs"],
           "interaction_secs": p["interaction_secs"],
           "commit_secs": p["phases"]["commit_secs"],
           "fri_secs": p["phases"]["fri_secs"],
           "stwo_total": p["phases"]["commit_secs"] + p["phases"]["prove_call_secs"],
           "peak_rss_bytes": p["peak_rss_bytes"],
           "proof_sha256": p["proof_sha256"],
           "unsound_skips": prov["unsound_skips"],
           "all_bound": prov["binding"]["all_bound"],
           "unbound": prov["binding"]["unbound"]}
    print(f"S=C={s}: fresh {row['fresh']:,} cells, key tiles {row['key_tiles']:,}, "
          f"{row['prove_secs']:.1f} s, accepts {row['accepts']}, "
          f"skips {row['unsound_skips'] or 'none'}, unbound {row['unbound']}")
    if not p["accepts"]:
        bad.append(f"S={s}: the proof was rejected")
    if p["off_table"]:
        bad.append(f"S={s}: {p['off_table']} values off the table")
    if prov["unsound_skips"]:
        bad.append(f"S={s}: unsound skips in effect")
    if not prov["binding"]["all_bound"]:
        bad.append(f"S={s}: unbound edges {prov['binding']['unbound']}")
    rows.append(row)
# The fit the sweep supports.  At C = S the key-tile closed form's S*C and C
# terms are the same variable, so two coefficients are observable and three are
# not; the sweep reports what it can separate and names what it cannot.
fit = None
if len(rows) >= 3:
    n = len(rows)
    sx = [r["s"] for r in rows]
    y = [r["key_tiles"] for r in rows]
    # least squares on key_tiles = g*S^2 + d*S, two unknowns, no intercept
    a11 = sum(s ** 4 for s in sx); a12 = sum(s ** 3 for s in sx); a22 = sum(s ** 2 for s in sx)
    b1 = sum(s ** 2 * v for s, v in zip(sx, y)); b2 = sum(s * v for s, v in zip(sx, y))
    det = a11 * a22 - a12 * a12
    g = (b1 * a22 - b2 * a12) / det
    d = (a11 * b2 - a12 * b1) / det
    resid = [v - (g * s * s + d * s) for s, v in zip(sx, y)]
    fit = {"model": "key_tiles = gamma * S^2 + delta * S at C = S",
           "gamma": g, "delta": d, "points": n,
           "max_abs_residual_cells": max(abs(r) for r in resid),
           "note": "at C = S the S*C and C terms of the three-coefficient grid "
                   "are not separable; separating them needs points with C != S"}
    print(f"fit: key_tiles = {g:.6f} S^2 + {d:.3f} S, "
          f"largest residual {max(abs(r) for r in resid):,.0f} cells")
json.dump({"points": rows, "fit": fit}, open(out / "sweep.json", "w"), indent=1)
chk = json.loads((out / "variant_check.json").read_text())
if chk["key_tiles_paper"] is None:
    print(f"variant check: {chk['paper_variant']} did not prove even at the smallest block, "
          f"so the two variants could not be compared; the sweep is under "
          f"{chk['sweep_variant']} and every number here says so")
elif chk["agree"]:
    print(f"variant check: both variants count {chk['key_tiles_sweep']} key-tile cells, "
          f"so the sweep measures the same key tiles the paper's arithmetic would")
else:
    print(f"variant check: {chk['paper_variant']} counts {chk['key_tiles_paper']} key-tile "
          f"cells and {chk['sweep_variant']} counts {chk['key_tiles_sweep']}; they differ")
if bad:
    sys.exit("; ".join(bad))
print(f"{len(rows)} points, every proof accepted, no skip in effect")
PY
st "done"
JOBEOF
drv_start "$JOB"
rm -f "$JOB"
