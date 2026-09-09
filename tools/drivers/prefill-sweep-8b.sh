#!/bin/sh
# prefill-sweep-8b: the key tiles' cost in the block length, at the 8B model's
# own attention width and under the arithmetic the paper reports.
#
#   tools/drivers/prefill-sweep-8b.sh <host> <prover-commit> <harness-commit>
#
# `prefill-sweep.sh` measures the same shape of cost at four heads of 32,
# because a synthetic layer at the 8B's 32 heads of 128 could not be proved: the
# exponential table was sized from the layer's own data and clamped, and
# `--table-bits` was not consulted on that path (zk-prover #72).  zk-prover #85
# sizes that table by the flag, so the paper's own arithmetic can now be proved
# at the 8B's width, and this is the sweep that measures it there.
#
# Two block lengths at C = S, and one point whose prefix is longer than its
# block.  At C = S the key-tile closed form's S*C and C terms multiply the same
# quantity, so two coefficients are observable and three are not; one point at
# C != S separates them, and `EXTRA_POINTS` is where such a point is written.
# Three points and three coefficients is an exact solve, so the residual it
# reports is zero by construction and says nothing about the form; a fourth
# point is what would make it a fit again.
#
# The table width is not constant in the shape here, and it is not guessed: the
# layer names the width it needs, and a point whose width is too small does not
# prove.  At C = S the width is written per point, from the refusal the layer
# raised the first time it was asked.  A point whose prefix is longer than its
# block has no earlier run to read it off, so its width is written as the widths
# to try in order and the first that proves is the point; every width that did
# not keeps its stderr under `out/`, so what was tried is in the record.
#
# The SIMD backend, not the CUDA one: this is a cell count and a shape, and the
# two backends prove the same statement to the same digest.
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
NAME=prefill-sweep-8b
. "$HERE/lib/driver.sh"

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=design               # a design measurement: neither a headline nor a control
# The points, as <block length>:<table bits>.  C = S at every one.  The width
# is the one the layer names in the refusal it raises when it is given less:
# at a 128-token block it asks for 24 in as many words, and 23 -- the width the
# campaign's brief expected there -- is refused.  The widths are written per
# point because there is no reason they should be constant in the block length.
POINTS="64:24 128:24"
# The points whose context is not the block length, as <block>:<context>:<table
# bits ladder>.  One of them is what separates the closed form's S*C term from
# its C term; with none the sweep is the two-coefficient measurement above.
EXTRA_POINTS="256:4096:24+25+26"
# The 8B model's attention shape: 32 heads of 128, as three key tile groups, and
# the matmul widths equal to their product so that every edge binds.
HD=128
HEAD_GROUPS=16,8,8
NIN=4096; NOUT=4096
RSA=32                     # --residual-stream-a
KMAX=19
# The attention output's remainder, at the two points whose context is their
# block length.  A point with a longer prefix is given no pin: the flag may only
# widen what the witness needs and what a 4,096-key prefix needs is not this, so
# the extra points take the witness's own and the run records it per point.
AO_REM_BITS=22
VARIANT=intexp             # the arithmetic the paper reports
SHARED_ARITH="--round even --numbits 9 --z-hi-bits 7"
GKR="--gkr-key-tiles --gkr-dequant --gkr-residual-stream --gkr-freivalds --gkr-attnout"
# --diagonal-block and --synth-residual-stream are what the sound defaults ask of
# a synthetic segment: without the first the keys and values cannot be bound to
# the next block and without the second the residual stream cannot be bound to
# the next layer, and either one missing would mean a skip flag.  They also fix
# what the key tiles of one segment are: the prefix in C/S blocks of S keys --
# `--kv-boundary` is on unless a skip flag turns it off -- and one square
# diagonal block, so at C = S the count is twice one attention score block and
# at C = 4,096 with a 256-token block it is seventeen times it.
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
 "points": "$POINTS", "extra_points": "$EXTRA_POINTS", "context_equals_s": false,
 "hd": $HD, "head_groups": "$HEAD_GROUPS", "nin": $NIN, "nout": $NOUT,
 "residual_stream_a": $RSA, "kmax": $KMAX,
 "ao_rem_bits": "$AO_REM_BITS at C = S, the witness's own at the extra points",
 "threads": $XTHREADS,
 "shared_arithmetic": "$SHARED_ARITH", "variant": "$VARIANT",
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

# 2. the sweep, as <block>:<context>:<table bits ladder>.  A point already
#    proved is not proved again, so an interrupted sweep is restarted for the
#    price of what it did not finish.  A width that refuses keeps its stderr,
#    because the refusal names what the layer wanted and that is the record of
#    what the ladder climbed past.
ALL=""
for P in $POINTS; do ALL="\$ALL \${P%%:*}:\${P%%:*}:\${P##*:}:$AO_REM_BITS"; done
for P in $EXTRA_POINTS; do ALL="\$ALL \$P:auto"; done
for P in \$ALL; do
  S=\$(echo \$P | cut -d: -f1); C=\$(echo \$P | cut -d: -f2); LADDER=\$(echo \$P | cut -d: -f3)
  case \$(echo \$P | cut -d: -f4) in
    auto) AOF="" ;;
    *)    AOF="--ao-rem-bits \$(echo \$P | cut -d: -f4)" ;;
  esac
  f=\$OUT/dd_s\${S}_c\${C}.json
  if [ -s \$f ]; then st "S=\$S C=\$C already proved"; continue; fi
  for TB in \$(echo \$LADDER | tr '+' ' '); do
    st "measure: S = \$S, C = \$C, --table-bits \$TB \$AOF"
    T0=\$(date +%s)
    if \$SIMD compose $SHARED_ARITH --variants $VARIANT --table-bits \$TB $SHAPE \$AOF $GKR \
        --s \$S --ctx \$C > \$f 2> \$R/dd_s\${S}_c\${C}_t\${TB}.err; then
      T1=\$(date +%s); st "S=\$S C=\$C proved at --table-bits \$TB in \$((T1 - T0))s"
      echo \$TB > \$OUT/tablebits_s\${S}_c\${C}.txt
      break
    fi
    rm -f \$f
    tail -20 \$R/dd_s\${S}_c\${C}_t\${TB}.err > \$OUT/refused_s\${S}_c\${C}_t\${TB}.txt
    st "S=\$S C=\$C did not prove at --table-bits \$TB; the last of its stderr is in \
out/refused_s\${S}_c\${C}_t\${TB}.txt"
  done
done

# 3. the sweep, read back off the outputs, and the gate
python3 - \$OUT "\$ALL" <<'PY'
import json, pathlib, sys
from fractions import Fraction
out = pathlib.Path(sys.argv[1])
points = [tuple(int(x) for x in p.split(":")[:2]) for p in sys.argv[2].split()]
rows, bad, missing = [], [], []
for s, c in points:
    f = out / f"dd_s{s}_c{c}.json"
    if not f.exists():
        missing.append((s, c))
        print(f"S={s} C={c}: no proof at any width of its ladder")
        continue
    doc = json.loads(f.read_text())
    p, prov = doc["result"]["point"], doc["provenance"]
    fam = p["family_cells"]
    # the key tile family's two halves.  the key tile entry of family_cells is the
    # committed side; the interaction side is the same family's entry in the
    # rollup, and the two together are what the cost model calls fresh.
    kt_base = fam["key_tiles"]
    kt_inter = fam["interaction_by_family"].get("key_tiles", {}).get("cells", 0)
    row = {"s": s, "c": c, "table_bits": p["params"]["log_table"],
           "accepts": p["accepts"], "off_table": p["off_table"],
           "fresh": p["cells"]["fresh"], "base": p["cells"]["base"],
           "interaction": p["cells"]["interaction"],
           "preprocessed": p["cells"]["preprocessed"],
           "key_tiles": kt_base, "key_tiles_interaction": kt_inter,
           "key_tiles_fresh": kt_base + kt_inter,
           "key_tile_split": [{"component": e["component"], "cells": e["cells"],
                               "columns": e["columns"]}
                              for e in fam["interaction_split"]
                              if e["component"].startswith("key_tile")],
           "grid_target": p["params"]["grid_target"],
           "chan_target": p["params"]["chan_target"],
           "columns_total": p["columns"]["total"],
           "ao_rem_bits": p["params"]["ao_rem_bits"],
           "ref_mismatch": p.get("ref_mismatch"),
           "prove_secs": p["prove_secs"], "trace_secs": p["trace_secs"],
           "commit_secs": p["phases"]["commit_secs"],
           "fri_secs": p["phases"]["fri_secs"],
           "peak_rss_bytes": p["peak_rss_bytes"],
           "proof_sha256": p["proof_sha256"],
           "unsound_skips": prov["unsound_skips"],
           "all_bound": prov["binding"]["all_bound"],
           "unbound": prov["binding"]["unbound"]}
    print(f"S={s} C={c}: key tiles {kt_base:,} committed + {kt_inter:,} interaction, "
          f"fresh {row['fresh']:,} cells, table 2^{row['table_bits']}, "
          f"{row['prove_secs']:.1f} s, accepts {row['accepts']}, "
          f"skips {row['unsound_skips'] or 'none'}, unbound {row['unbound']}, "
          f"reference mismatch {row['ref_mismatch']}")
    if not p["accepts"]:
        bad.append(f"S={s} C={c}: the proof was rejected")
    if p["off_table"]:
        bad.append(f"S={s} C={c}: {p['off_table']} values off the table")
    if prov["unsound_skips"]:
        bad.append(f"S={s} C={c}: unsound skips in effect")
    if not prov["binding"]["all_bound"]:
        bad.append(f"S={s} C={c}: unbound edges {prov['binding']['unbound']}")
    if row["ref_mismatch"]:
        bad.append(f"S={s} C={c}: {row['ref_mismatch']} cells disagree with the "
                   "reference arithmetic")
    # the evidence for the form the fit assumes: the prefix is C/S sub-key-tiles
    # of the same S by S shape as the diagonal block, so their interaction cells
    # should take one value each
    kt = row["key_tile_split"]
    pre = sorted({e["cells"] for e in kt if "diagonal" not in e["component"]})
    dia = sorted({e["cells"] for e in kt if "diagonal" in e["component"]})
    print(f"    {len(kt)} key tile components: prefix interaction cells {pre}, "
          f"diagonal block {dia}")
    rows.append(row)


def solve(rows, field):
    """The key tile family's three coefficients, least squares with no intercept.

    The sound defaults tile the prefix in blocks of S -- C/S sub-key-tiles over
    the same heads, the per-token component on the first of them -- and add one
    square diagonal block.  So the family is C/S + 1 copies of one S by S tile
    plus that per-token component, and with T(S) = a S^2 + b S,

        cells(S, C) = (C/S + 1) T(S) + r S = a (S*C + S^2) + b C + g S

    where g = b + r.  a and b are the S*C and C coefficients the cost model
    reads, and the prefix key tile's own triple is (a, b, g - b).

    At C = S the first column is 2 S^2 and the other two are both S: every C = S
    point lies in the plane b and g cannot be told apart in, which is why one
    point at C != S is what separates them.
    """
    xs = [(r["s"] * r["c"] + r["s"] ** 2, r["c"], r["s"]) for r in rows]
    ys = [r[field] for r in rows]
    n = 3
    # exact rationals: the normal equations at these sizes carry entries near
    # 2^80 and a float solve loses the low digits of a coefficient that is
    # supposed to be an integer count of cells
    m = [[Fraction(sum(x[i] * x[j] for x in xs)) for j in range(n)]
         + [Fraction(sum(x[i] * y for x, y in zip(xs, ys)))] for i in range(n)]
    for i in range(n):                       # Gauss-Jordan
        pr = next((r_ for r_ in range(i, n) if m[r_][i]), None)
        if pr is None:
            return None
        m[i], m[pr] = m[pr], m[i]
        pv = m[i][i]
        m[i] = [v / pv for v in m[i]]
        for r_ in range(n):
            if r_ != i and m[r_][i]:
                fac = m[r_][i]
                m[r_] = [v - fac * w for v, w in zip(m[r_], m[i])]
    a, b, g = (m[i][n] for i in range(n))
    resid = [y - (a * x[0] + b * x[1] + g * x[2]) for x, y in zip(xs, ys)]
    return {"s_times_c": float(a), "c": float(b), "s": float(g), "points": len(rows),
            "family_coeffs": [float(a), float(b), float(g)],
            "prefix_tile_coeffs": [float(a), float(b), float(g - b)],
            "per_token_component": float(g - b),
            "exact": [str(a), str(b), str(g)],
            "residual_cells": [float(v) for v in resid],
            "max_abs_residual_cells": float(max(abs(v) for v in resid))}


fit = None
off_diagonal = [r for r in rows if r["c"] != r["s"]]
if len(rows) >= 3 and off_diagonal:
    fit = {f: solve(rows, f) for f in ("key_tiles", "key_tiles_interaction",
                                       "key_tiles_fresh")}
    fit["model"] = ("cells(S, C) = a (S*C + S^2) + b C + g S over the key tile "
                    "family: the prefix, tiled in C/S blocks of S keys, and the "
                    "square diagonal block. The prefix key tile's own (S*C, C, S) "
                    "triple, which is what the cost model reads, is (a, b, g - b).")
    fit["points"] = len(rows)
    fit["off_diagonal_points"] = len(off_diagonal)
    fit["exactly_determined"] = len(rows) == 3
    fit["note"] = ("three coefficients over three points is an exact solve, so the "
                   "residual is zero by construction and is not a check of the form; "
                   "a fourth point is what would make it one. What the form assumes "
                   "is that the prefix's C/S sub-key-tiles and the diagonal block are "
                   "the same S by S tile, which the per-key-tile interaction split "
                   "below is the evidence for.")
    for f in ("key_tiles", "key_tiles_interaction", "key_tiles_fresh"):
        v = fit[f]
        if v["max_abs_residual_cells"]:
            bad.append(f"{f}: the three-coefficient form leaves a residual of "
                       f"{v['max_abs_residual_cells']:,.0f} cells")
        print(f"fit {f}: a {v['s_times_c']:.6f} S*C, b {v['c']:.3f} C, g {v['s']:.3f} S "
              f"over {v['points']} points, largest residual "
              f"{v['max_abs_residual_cells']:,.0f} cells; prefix key tile "
              f"{v['prefix_tile_coeffs']}")
elif len(rows) >= 2:
    print("fit: no point with C != S, so the S*C and C terms are one variable")
json.dump({"points": rows, "fit": fit, "missing": missing},
          open(out / "sweep.json", "w"), indent=1)
if missing:
    bad.append(f"the sweep is missing {len(missing)} of its {len(points)} points: {missing}")
if fit is None:
    bad.append("the three coefficients are not separable: the sweep has fewer than "
               "three points, or no point with C != S")
if bad:
    sys.exit("; ".join(bad))
print(f"{len(rows)} points, every proof accepted, no skip in effect")
PY
st "done"
JOBEOF
drv_start "$JOB"
rm -f "$JOB"
