#!/bin/sh
# cost-model: the frontier price table, projected from this repository's own
# constants and from nothing else.
#
#   tools/drivers/cost-model.sh <prover-commit> <harness-commit>
#   tools/drivers/cost-model.sh --dry-run <prover-commit> <harness-commit>
#
# The first driver that needs no host. The cost model prices a proof from a cell
# count and a measured rate, and both now have keys here: the two headline runs
# record what a proved position cost in cells and how fast each timing scope
# committed them. So this run reads `constants.json`, runs `frontier.py` at a
# pinned commit, and writes what the model projects. It touches no card, makes no
# proof and measures nothing, which is why its manifest says `harness`.
#
# What it records. Cards for a target throughput and dollars a million proved
# positions, for the eight frontier shapes at both contexts and at all four
# scopes; the mixture-of-experts ratios; and the calibration residual, which is
# what the model's own price for the sound statement misses the measured one by.
# Every one of them is grade `projected` and names the keys it was computed from.
#
# What it refuses. A projection is only worth recording when every number behind
# it is in this repository. The cost model reads each of its cell costs from the
# constants file where a key names it and from a micro-benchmark directory where
# none does, and it writes which of the two into its own output; this driver reads
# that block and refuses to record when any charged input came from anywhere but
# the constants file. It also runs the model with the two directory variables
# unset, so an environment that happens to name one cannot leak into a recorded
# run.
#
# The counted path moves what has to be in this repository rather than removing
# it. It reads no cell cost for a segment -- it builds the segment's trace layout
# and multiplies columns by rows -- and it charges nothing that is priced by
# analogy, because it builds the router's matmul like any other matmul and states
# the selection on top of it as a bound. What it assumes instead is the block of
# witness-calibrated fields a `params` block carries and a model shape does not:
# the exponential table's height, the attention output's ranges, the rounding.
# Every projected row names those keys in its `inputs`, so this driver refuses on
# one that is not an entry here for the same reason it refuses a cell cost from a
# directory outside this repository: the row would stand on a number nothing here
# holds.
#
# The dry run does the opposite on purpose: it lets the model fall back to the
# micro-benchmark directory (`ZK_ARTIFACTS` and `ZK_COSTMODEL_INPUTS` are passed
# through when they are set), prints the same rows, marks them not recordable and
# writes nothing under `runs/`. That is how the table is read while the keys the
# real run needs are still being recorded.
#
# Two commits and only one of them runs. Nothing here builds or runs the prover
# binary: the cost model is Python in the same repository, so the harness commit
# is the tree that produces every number and the prover commit is recorded beside
# it in `config.json`. They are normally the same commit and the driver says so
# when they are not.
#
# Host time: none. The sources are unpacked into a temporary directory, the
# harness's pinned environment is synchronized there, and the model runs on this
# machine's cores in seconds.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
DRY=no
if [ "${1:-}" = "--dry-run" ]; then DRY=yes; shift; fi
PROVER=${1:?prover commit}; HARNESS=${2:?harness commit}
ZK_PROVER=${ZK_PROVER_DIR:-$ROOT/../zk-prover}     # a local clone to archive the commits from
NAME=cost-model
. "$HERE/lib/driver.sh"

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=projection           # the model's own output, not a measurement
SEQ=512                    # positions a token block, the statement the runs proved
TARGET=20                  # the throughput a `cards_for_20` row is stated against
MODULE=harness.costmodel.frontier

drv_check_commits
if [ "$PROVER" != "$HARNESS" ]; then
  echo "cost-model: prover $PROVER and harness $HARNESS differ; only the harness"
  echo "  commit runs here and every number comes from it"
fi

DATE=$(date -u +%F)
# The run id manifest.py will give this run, from manifest.py's own rule, so that
# every recorded entry can name it before the manifest exists. A run that touches
# no card reports no GPU and the slug is that answer.
RUN_ID=$(python3 - "$HERE/lib" "$DATE" "$NAME" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import manifest
print(f"{sys.argv[2]}-{sys.argv[3]}-{manifest.gpu_slug(None)}")
PY
)
echo "cost-model: run id $RUN_ID"
if [ "$DRY" = no ] && [ -e "$ROOT/runs/$RUN_ID" ]; then
  echo "cost-model: runs/$RUN_ID exists; a run directory is never overwritten" >&2
  exit 2
fi

# ---- the pinned sources, unpacked here rather than pushed --------------------
TMP=$(mktemp -d "${TMPDIR:-/tmp}/zk-cost-model.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
SRC=$TMP/src
OUT=$TMP/out
mkdir -p "$SRC" "$OUT"
# The same tree `push.sh` would send a host, with the same `.source-commit`
# beside it, which is what the harness reads into `provenance.commit`.
git -C "$ZK_PROVER" archive --format=tar "$HARNESS" | tar -C "$SRC" -xmf -
git -C "$ZK_PROVER" rev-parse --verify "$HARNESS^{commit}" > "$SRC/.source-commit"

cat > "$OUT/config.json" <<CFG
{"driver": "$NAME", "label": "$LABEL",
 "prover_commit": "$PROVER", "harness_commit": "$HARNESS",
 "module": "$MODULE", "seq": $SEQ, "target_positions_per_s": $TARGET,
 "constants": "constants.json",
 "artifacts": $([ "$DRY" = yes ] && echo '"the fallback directory, where the environment names one"' || echo 'null'),
 "recordable": $([ "$DRY" = yes ] && echo false || echo true),
 "card": "none: the model reads a recorded rate and touches no card",
 "witness": "none: no proof is made and nothing is measured"}
CFG

# ---- the model, at the pinned commit ----------------------------------------
echo "cost-model: syncing the harness at $HARNESS"
( cd "$SRC/harness" && uv sync --frozen )

# `--project` and not a `cd`: the working directory stays this repository, so the
# constants file is named relative to it in everything the run writes.
if [ "$DRY" = yes ]; then
  echo "cost-model: DRY RUN -- the archive fallback is allowed and nothing is recorded"
  ( cd "$ROOT" && uv run --project "$SRC/harness" python -m $MODULE \
      --constants constants.json --seq $SEQ --target $TARGET \
      --json "$OUT/frontier.json" ) | tee "$OUT/frontier.txt"
else
  ( cd "$ROOT" && env -u ZK_ARTIFACTS -u ZK_COSTMODEL_INPUTS \
      uv run --project "$SRC/harness" python -m $MODULE \
      --constants constants.json --seq $SEQ --target $TARGET \
      --json "$OUT/frontier.json" ) | tee "$OUT/frontier.txt"
fi

# ---- the gate, and the entries this run backs -------------------------------
# The refusal is made here and not taken on trust: this reads the model's own
# provenance block, input by input, and a charged input that did not come from
# the constants file ends the run before anything is written under runs/.
python3 - "$OUT" "$RUN_ID" "$DRY" "$HARNESS" "$ROOT" <<'PY'
import json, pathlib, sys
out, run_id, dry, harness = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3] == "yes", sys.argv[4]
root = pathlib.Path(sys.argv[5])
doc = json.loads((out / "frontier.json").read_text())
prov, res = doc["provenance"], doc["result"]
bad = []
c = prov.get("commit") or ""
if not c or not (c.startswith(harness) or harness.startswith(c)):
    bad.append(f"the model ran at {c or 'no commit'}, not at the pinned {harness}")
if prov.get("dirty"):
    bad.append("the pinned tree was dirty")
# How the cell side was counted decides which of the model's inputs a row read.
# The counted path charges no number priced by analogy: it builds the router's
# matmul like any other matmul and bounds the selection on top of it, so the two
# routing inputs are read by the fitted path alone and a counted row that names
# them names nothing.  Every other input is judged the same way in both.
exact = res.get("cells") == "exact"
for name, e in sorted(res["provenance"]["cost_model"].items()):
    if not e.get("charged", True) or (exact and e.get("source") == "analogy"):
        continue
    if e.get("source") != "constants":
        bad.append(f"{name} came from {e['source']}"
                   + (f", and {e['key']} would back it" if e.get("key") else
                      ", and no key names it"))
if res["statement"]["source"] != "constants":
    bad.append("the statement's own layout is not read from the constants file")
# What the counted path assumes in place of the cell costs it no longer reads:
# the witness-calibrated fields of a `params` block, which every projected row
# names in its `inputs`.  A name that is not an entry of this file is a row
# standing on a number this repository does not hold, so it refuses here and the
# missing keys are named one by one.
asm = res.get("assumptions") or {}
if asm.get("rows"):
    held = json.loads((root / "constants.json").read_text())["constants"]
    for r in asm["rows"]:
        key = asm["key"].format(field=r["field"])
        if key not in held:
            bad.append(f"{key} is what the count assumes for `{r['field']}` "
                       f"({r['value']}, graded {r['grade']}), and this file does "
                       f"not hold it")
for name, seq in sorted(res["provenance"]["sequence"].items()):
    if seq.get("read_from") != "constants":
        bad.append(f"the measured rate for {name} came from {seq.get('read_from')}")
rows = res["projected"]
print(f"\n{len(rows)} rows, {sum(1 for r in rows if r['recordable'])} of them recordable")
print(f"  {'key':<58} {'value':>14}  unit")
for r in rows:
    v = r["entry"]["value"]
    print(f"  {r['key']:<58} "
          + (f"{v:>14,.4f}" if isinstance(v, float) else f"{str(v):>14}")
          + f"  {r['entry']['unit']}"
          + ("" if r["recordable"] else "   [not recordable]"))
cal = {r["key"]: r["entry"]["value"] for r in rows if "calibration" in r["key"]}
print("  calibration: " + ", ".join(f"{k.split('.')[-2]} {v:+.2f} per cent"
                                    for k, v in sorted(cal.items())))
# The model makes the same judgement on its own rows.  The two must agree: a
# table the model marks not recordable is never recorded here, whatever this
# gate found, and a reason only the model knows is still a reason to refuse.
if not res.get("recordable") and not bad:
    bad.append("the model marks its own table not recordable and this gate found "
               "no reason of its own; the run's printed output says which")
if bad:
    print("\nnot recordable:")
    for b in bad:
        print(f"  {b}")
    if not dry:
        sys.exit("cost-model: the projection read a number this repository does not "
                 "hold; nothing is recorded")
    print("\ndry run: the rows above are printed and nothing is written under runs/")
    sys.exit(0)
if dry:
    print("\ndry run: every input is a key of this file, and still nothing is written "
          "under runs/")
    sys.exit(0)
# The entries, in the shape constants.json takes them, each naming the run and the
# artifact it came out of.  Nothing is transcribed: the recording reads this file.
entries = {}
for r in rows:
    e = dict(r["entry"])
    e["run"], e["artifact"] = run_id, "frontier.json"
    entries[r["key"]] = e
(out / "constants.json").write_text(json.dumps(
    {"provenance": prov, "result": entries}, indent=1) + "\n")
print(f"\ncost-model: {len(entries)} entries in out/constants.json")
PY

[ "$DRY" = no ] || exit 0

# ---- the manifest, from the model's own provenance block --------------------
python3 "$HERE/lib/manifest.py" --driver "tools/drivers/$NAME.sh" --fetched "$OUT" \
    --runs "$ROOT/runs" --prover-commit "$PROVER" --harness-commit "$HARNESS" \
    --date "$DATE"
rmdir "$OUT" 2>/dev/null || true
( cd "$ROOT" && python3 tools/constants/check.py )
echo "cost-model: the entries are in runs/$RUN_ID/constants.json, in the shape"
echo "  constants.json takes them and naming this run. The recording merges them"
echo "  under \`constants\` and regenerates the index:"
echo "    python3 tools/constants/index.py"
echo "    python3 tools/constants/check.py"
