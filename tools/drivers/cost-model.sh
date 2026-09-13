#!/bin/sh
# cost-model: the frontier price table, projected from this repository's own
# constants and from nothing else.
#
#   tools/drivers/cost-model.sh <prover-commit> <harness-commit>
#   tools/drivers/cost-model.sh --dry-run <prover-commit> <harness-commit>
#   tools/drivers/cost-model.sh --routing <run-id>:<row> <prover> <harness>
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
# The measured routing, and it is an argument because it is a decision. Without
# `--routing` every mixture row is priced at the uniform assumption, which is what
# it has always been. With it, the run reads the per-expert token counts a
# `moe-routing` run recorded, re-keys them from the model they were measured on to
# the frontier row the argument names, and prices THAT row a second time at them.
# The re-keying is what the argument states: `--routing <run-id>:<row>` says whose
# routing is being applied to which row, it is refused unless the run's own
# artifact holds a table and the frontier holds that row, and the manifest records
# it under `derived`, because a run that took a number from an earlier run says so
# there. The measured rows are recorded BESIDE the uniform ones under names ending
# `_routing_measured`, never instead of them, and each one names in its `inputs`
# both the routing constants it read and the uniform row it sits beside. The run
# also prices the uniform table in the same process and refuses if a row of any
# other shape moved: a routing measured on one model may price one row, and the
# gate checks that it priced no other.
#
# Host time: none. The sources are unpacked into a temporary directory, the
# harness's pinned environment is synchronized there, and the model runs on this
# machine's cores in seconds.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
DRY=no
ROUTING=
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=yes; shift ;;
    --routing) ROUTING=${2:?--routing <run-id>:<row>}; shift 2 ;;
    *) break ;;
  esac
done
PROVER=${1:?prover commit}; HARNESS=${2:?harness commit}
ZK_PROVER=${ZK_PROVER_DIR:-$ROOT/../zk-prover}     # a local clone to archive the commits from
NAME=cost-model
. "$HERE/lib/driver.sh"

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=projection           # the model's own output, not a measurement
SEQ=512                    # positions a token block, the statement the runs proved
TARGET=20                  # the throughput a `cards_for_20` row is stated against
MODULE=harness.costmodel.frontier
SUFFIX=_routing_measured   # what a row priced at a measured routing is named
RUN_NAME=$NAME             # the configuration the run id names, and this is the default

# ---- the measured routing, where the run was given one ----------------------
ROUTING_RUN=; ROUTING_ROW=
if [ -n "$ROUTING" ]; then
  case "$ROUTING" in
    *:*) ROUTING_RUN=${ROUTING%%:*}; ROUTING_ROW=${ROUTING#*:} ;;
    *) echo "cost-model: --routing takes <run-id>:<row>, the run whose routing.json" >&2
       echo "  holds the measured table and the frontier row it is applied to" >&2
       exit 2 ;;
  esac
  if [ -z "$ROUTING_RUN" ] || [ -z "$ROUTING_ROW" ]; then
    echo "cost-model: --routing $ROUTING names no run or no row" >&2; exit 2
  fi
  if [ ! -f "$ROOT/runs/$ROUTING_RUN/routing.json" ]; then
    echo "cost-model: runs/$ROUTING_RUN/routing.json does not exist; the measured" >&2
    echo "  table is an artifact of a recorded run and is read from nowhere else" >&2
    exit 2
  fi
  RUN_NAME=$NAME-routing
  echo "cost-model: the routing of runs/$ROUTING_RUN, applied to the $ROUTING_ROW row"
fi

drv_check_commits
if [ "$PROVER" != "$HARNESS" ]; then
  echo "cost-model: prover $PROVER and harness $HARNESS differ; only the harness"
  echo "  commit runs here and every number comes from it"
fi

DATE=$(date -u +%F)
# The run id manifest.py will give this run, from manifest.py's own rule, so that
# every recorded entry can name it before the manifest exists. A run that touches
# no card reports no GPU and the slug is that answer.
RUN_ID=$(python3 - "$HERE/lib" "$DATE" "$RUN_NAME" <<'PY'
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
 "routing": $([ -n "$ROUTING" ] && echo "\"$ROUTING_RUN -> $ROUTING_ROW\"" || echo 'null'),
 "card": "none: the model reads a recorded rate and touches no card",
 "witness": "none: no proof is made and nothing is measured"}
CFG

# ---- the measured table, re-keyed to the row the argument names --------------
# The table is read out of the recorded run's own artifact and re-keyed here,
# once, in the open: the run that measured it keys it by the model it was measured
# on, which the frontier holds no row for, so `--routing` refuses it until someone
# says which row it is for. That is this argument, and the record of it is the
# `derived` block of the manifest. One file per context the run measured, because
# the model holds one routing at a time and each context's rows are priced at the
# table that context's prompts produced.
CONTEXTS=
if [ -n "$ROUTING" ]; then
  CONTEXTS=$(python3 - "$ROOT/runs/$ROUTING_RUN" "$ROUTING_RUN" "$ROUTING_ROW" "$TMP" "$SEQ" <<'PY'
import json, pathlib, sys
run, run_id, row, tmp, seq = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], pathlib.Path(sys.argv[4]), int(sys.argv[5])
doc = json.loads((run / "routing.json").read_text())
res = doc["result"]
table = res.get("routing_table") or {}
if len(table) != 1:
    sys.exit(f"cost-model: runs/{run_id}/routing.json holds {len(table)} routing tables; "
             "a run measures one model and this reads that one")
measured_slug, per_ctx = next(iter(table.items()))
rec = dict(run=run_id, artifact="routing.json", measured=res.get("model"),
           measured_slug=measured_slug, measured_key_slug=res.get("key_slug"),
           row=row, seq=seq, contexts={})
for name, dist in sorted(per_ctx.items()):
    ctx = int(str(name).lstrip("c"))
    slots = sum(int(a) * int(b) for a, b in dist)
    if slots != seq * int(res["topk"]):
        sys.exit(f"cost-model: the table at {name} spreads {slots} token slots and a "
                 f"block of {seq} at top-{res['topk']} has {seq * int(res['topk'])}")
    (tmp / f"routing-c{ctx}.json").write_text(
        json.dumps({row: [[int(a), int(b)] for a, b in dist]}, indent=1) + "\n")
    # WHICH block: the run writes the representative one, the median block by
    # distinct experts over every layer and every prompt, and a row priced at it
    # is priced at that block's routing for every block of every layer
    rep = ((res.get("contexts") or {}).get(str(ctx), {})
           .get("blocks", {}).get(str(seq), {}).get("representative") or {})
    rec["contexts"][f"c{ctx}"] = dict(
        # the table itself, re-keyed: the exact input the row was priced at, in
        # the run's own manifest, so the price is readable without re-deriving it
        distribution=[[int(a), int(b)] for a, b in dist],
        experts=sum(int(b) for _, b in dist), token_slots=slots,
        busiest=max(int(a) for a, _ in dist), quietest=min(int(a) for a, _ in dist),
        experts_uniform=int(res["experts"]), topk=int(res["topk"]),
        block=dict(layer=rep.get("layer"), prompt=rep.get("prompt"),
                   block=rep.get("block"), distinct_experts=rep.get("distinct_experts"),
                   which="the median block by distinct experts over every mixture "
                         "layer and every prompt, which is the block the run's table "
                         "carries; a row priced at it is priced at that one block's "
                         "routing for every block of every layer"))
    print(ctx)
rec["note"] = (f"the per-expert token counts of runs/{run_id}, measured on "
               f"{res.get('model')} at S={seq}, re-keyed to the {row} row: the two "
               f"shapes route alike ({res['experts']} experts, top-{res['topk']}, no "
               f"shared expert, every layer a mixture layer) and the weights are not "
               f"the same weights. Every row this run records at them says so in its "
               f"name and carries the assumption in its note.")
(tmp / "derived.json").write_text(json.dumps(rec, indent=1) + "\n")
PY
) || exit 2
  echo "cost-model: contexts measured: $(echo "$CONTEXTS" | tr '\n' ' ')"
fi

# ---- the model, at the pinned commit ----------------------------------------
echo "cost-model: syncing the harness at $HARNESS"
( cd "$SRC/harness" && uv sync --frozen )

# `--project` and not a `cd`: the working directory stays this repository, so the
# constants file is named relative to it in everything the run writes.
run_model() {
  json=$1; txt=$2; shift 2
  if [ "$DRY" = yes ]; then
    ( cd "$ROOT" && uv run --project "$SRC/harness" python -m $MODULE \
        --constants constants.json --seq $SEQ --target $TARGET "$@" \
        --json "$json" ) | tee "$txt"
  else
    ( cd "$ROOT" && env -u ZK_ARTIFACTS -u ZK_COSTMODEL_INPUTS \
        uv run --project "$SRC/harness" python -m $MODULE \
        --constants constants.json --seq $SEQ --target $TARGET "$@" \
        --json "$json" ) | tee "$txt"
  fi
}
[ "$DRY" = no ] ||
  echo "cost-model: DRY RUN -- the archive fallback is allowed and nothing is recorded"
# the uniform table first, and every run makes it: it is what a measured row is
# recorded beside, and what the gate holds every other shape's row against
run_model "$OUT/frontier.json" "$OUT/frontier.txt"
for ctx in $CONTEXTS; do
  echo "cost-model: the $ROUTING_ROW row at the routing measured at context $ctx"
  run_model "$OUT/frontier-routing-c$ctx.json" "$OUT/frontier-routing-c$ctx.txt" \
      --routing "$TMP/routing-c$ctx.json"
done

# ---- the gate, and the entries this run backs -------------------------------
# The refusal is made here and not taken on trust: this reads the model's own
# provenance block, input by input, and a charged input that did not come from
# the constants file ends the run before anything is written under runs/.
python3 - "$OUT" "$RUN_ID" "$DRY" "$HARNESS" "$ROOT" "$ROUTING_ROW" "$SUFFIX" "$TMP" <<'PY'
import json, pathlib, sys
out, run_id, dry, harness = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3] == "yes", sys.argv[4]
root, row_slug, suffix, tmp = pathlib.Path(sys.argv[5]), sys.argv[6], sys.argv[7], pathlib.Path(sys.argv[8])
held = json.loads((root / "constants.json").read_text())["constants"]
bad = []


def judge(name, doc):
    """Every refusal this driver makes about one table the model printed."""
    prov, res = doc["provenance"], doc["result"]
    c = prov.get("commit") or ""
    if not c or not (c.startswith(harness) or harness.startswith(c)):
        bad.append(f"{name}: the model ran at {c or 'no commit'}, not at the pinned {harness}")
    if prov.get("dirty"):
        bad.append(f"{name}: the pinned tree was dirty")
    # How the cell side was counted decides which of the model's inputs a row read.
    # The counted path charges no number priced by analogy: it builds the router's
    # matmul like any other matmul and bounds the selection on top of it, so the two
    # routing inputs are read by the fitted path alone and a counted row that names
    # them names nothing.  Every other input is judged the same way in both.
    exact = res.get("cells") == "exact"
    for input_name, e in sorted(res["provenance"]["cost_model"].items()):
        if not e.get("charged", True) or (exact and e.get("source") == "analogy"):
            continue
        if e.get("source") != "constants":
            bad.append(f"{name}: {input_name} came from {e['source']}"
                       + (f", and {e['key']} would back it" if e.get("key") else
                          ", and no key names it"))
    if res["statement"]["source"] != "constants":
        bad.append(f"{name}: the statement's own layout is not read from the constants file")
    # What the counted path assumes in place of the cell costs it no longer reads:
    # the witness-calibrated fields of a `params` block, which every projected row
    # names in its `inputs`.  A name that is not an entry of this file is a row
    # standing on a number this repository does not hold, so it refuses here and the
    # missing keys are named one by one.
    asm = res.get("assumptions") or {}
    for r in asm.get("rows") or []:
        key = asm["key"].format(field=r["field"])
        if key not in held:
            bad.append(f"{name}: {key} is what the count assumes for `{r['field']}` "
                       f"({r['value']}, graded {r['grade']}), and this file does "
                       f"not hold it")
    for seq_name, seq in sorted(res["provenance"]["sequence"].items()):
        if seq.get("read_from") != "constants":
            bad.append(f"{name}: the measured rate for {seq_name} came from {seq.get('read_from')}")
    # The model makes the same judgement on its own rows.  The two must agree: a
    # table the model marks not recordable is never recorded here, whatever this
    # gate found, and a reason only the model knows is still a reason to refuse.
    if not res.get("recordable") and not bad:
        bad.append(f"{name}: the model marks its own table not recordable and this gate "
                   f"found no reason of its own; the run's printed output says which")


def value_of(res, slug, ctx, field):
    """One priced row's own figure, out of the model's table and not off a note."""
    for r in res["rows"]:
        if r["slug"] == slug:
            return r["contexts"][str(ctx)][field]
    sys.exit(f"cost-model: the table holds no {slug} row at C={ctx}")


docs = {"frontier.json": None}
for p in sorted(out.glob("frontier-routing-c*.json")):
    docs[p.name] = int(p.name[len("frontier-routing-c"):-len(".json")])
loaded = {}
for name in docs:
    loaded[name] = json.loads((out / name).read_text())
    judge(name, loaded[name])
uniform = loaded["frontier.json"]["result"]

if not row_slug:
    rows = [dict(r, artifact="frontier.json") for r in uniform["projected"]]
else:
    # The entries a measured routing backs, and they sit BESIDE the uniform rows:
    # each one is the uniform row's own key with `_routing_measured` on the end, so
    # what a row was priced against is its own name, and it names that row and the
    # routing constants it read in its `inputs`.
    rec = json.loads((tmp / "derived.json").read_text())
    # a table the model never priced is a row this run would record without it:
    # every context the routing was re-keyed for has to have a table here
    missing = sorted(set(rec["contexts"]) - {f"c{c}" for c in docs.values() if c})
    if missing:
        bad.append(f"the routing was re-keyed at {', '.join(missing)} and the model "
                   f"printed no table there; those rows would be missing and the rest "
                   f"recorded as if they were all of them")
    uni = {r["key"]: r["entry"]["value"] for r in uniform["projected"]}
    rows = []
    for name, ctx in sorted(docs.items(), key=lambda kv: kv[1] or 0):
        if ctx is None:
            continue
        res = loaded[name]["result"]
        # a routing measured on one model prices ONE row: every other shape's row
        # is the uniform table's row, to the digit, and the gate holds it to that
        for r in res["projected"]:
            k = r["key"]
            if f".{row_slug}." in k:
                continue
            if k not in uni:
                bad.append(f"{name}: {k} is not a row of the uniform table")
            elif uni[k] != r["entry"]["value"]:
                bad.append(f"{name}: {k} moved with the routing, and it is not the "
                           f"{row_slug} row: a routing measured on one model prices "
                           f"one row")
        m = rec["contexts"][f"c{ctx}"]
        keys = sorted(k for k in held
                      if k.startswith(f"moe.routing.{rec['measured_key_slug']}.c{ctx}.s{rec['seq']}."))
        if not keys:
            bad.append(f"{name}: this file holds no moe.routing."
                       f"{rec['measured_key_slug']}.c{ctx}.s{rec['seq']} key, and a row "
                       f"priced at that routing has nothing to name")
        b = m["block"]
        head = (f"Priced at the routing MEASURED on {rec['measured']} and re-keyed to "
                f"this row, runs/{rec['run']}: a block of {rec['seq']} positions "
                f"touches {m['experts']} of the {m['experts_uniform']} experts and the "
                f"busiest of them takes {m['busiest']} of the {rec['seq']} positions, "
                f"where the uniform assumption the row of this name without "
                f"`{suffix}` is priced at touches all {m['experts_uniform']} and lays "
                f"{m['token_slots'] // m['experts_uniform']} tokens on each. It is ONE "
                f"block's routing -- layer {b['layer']}, prompt {b['prompt']}, block "
                f"{b['block']}, {b['which']} -- and two models route alike and are not "
                f"the same weights: that is the assumption this row makes in place of "
                f"`assumption.cost_model.moe_routing`, which it removes. ")
        for r in res["projected"]:
            k = r["key"]
            if f".{row_slug}." not in k or f".c{ctx}." not in k:
                continue
            if not (k.endswith(".cards_for_20") or k.endswith(".usd_per_mposition")):
                continue
            e = dict(r["entry"])
            e["inputs"] = sorted(set(e["inputs"]) | set(keys) | {k})
            e["note"] = head + e["note"]
            rows.append(dict(r, key=k + suffix, entry=e, artifact=name))
        # one derived row a context: the move against the uniform row, which is a
        # ratio of two cell counts, so no card and no timing scope enters it and
        # every dollar and cards column above moves by exactly this per cent
        base = next((r for r in res["projected"]
                     if r["key"] == f"frontier.{row_slug}.c{ctx}.kv_shared_saving_pct"), None)
        beside = sorted(k for k in held if k.startswith(f"frontier.{row_slug}.")
                        and f".c{ctx}." in k
                        and (k.endswith(".cards_for_20") or k.endswith(".usd_per_mposition")))
        mine = value_of(res, row_slug, ctx, "cells_per_position")
        theirs = value_of(uniform, row_slug, ctx, "cells_per_position")
        rows.append(dict(
            key=f"frontier.{row_slug}.c{ctx}.{suffix.lstrip('_')}_pct",
            recordable=bool(base and base["recordable"]), from_constants=True,
            artifact=name,
            entry=dict(value=(mine / theirs - 1) * 100, unit="per cent", card="none",
                       context=ctx, timing_scope="n/a", grade="projected",
                       inputs=sorted(set((base["entry"]["inputs"] if base else []))
                                     | set(keys) | set(beside)),
                       note=head + f"What that takes off a proved position, or puts on "
                            f"it: {mine:,.0f} modelled cells a proved position against "
                            f"{theirs:,.0f} at the uniform routing. Every dollar and "
                            f"cards row of this shape at this context moves by exactly "
                            f"this per cent, and the preprocessed weight trace, which "
                            f"no measured rate counts, moves the other way: the segment "
                            f"holds {m['experts']} experts' weights and not "
                            f"{m['experts_uniform']}.")))
    # the mixture ratio is stated at C=4,096 and reads one routing, so it is the
    # row of the table priced at the routing that context's own prompts produced
    for name, ctx in docs.items():
        if ctx != 4096:
            continue
        keys = sorted(k for k in held
                      if k.startswith(f"moe.routing.{rec['measured_key_slug']}.c{ctx}.s{rec['seq']}."))
        m = rec["contexts"][f"c{ctx}"]
        for r in loaded[name]["result"]["projected"]:
            if r["key"] != f"moe.{row_slug}.fresh_over_dense":
                continue
            e = dict(r["entry"])
            e["inputs"] = sorted(set(e["inputs"]) | set(keys) | {r["key"]})
            e["note"] = (f"Priced at the routing MEASURED on {rec['measured']} and "
                         f"re-keyed to this row, runs/{rec['run']}: {m['experts']} of "
                         f"the {m['experts_uniform']} experts a block of {rec['seq']} "
                         f"positions, the busiest taking {m['busiest']} of them, and it "
                         f"is one block's routing, {m['block']['which']}. ") + e["note"]
            rows.append(dict(r, key=r["key"] + suffix, entry=e, artifact=name))

print(f"\n{len(rows)} rows, {sum(1 for r in rows if r['recordable'])} of them recordable")
print(f"  {'key':<70} {'value':>14}  unit")
for r in rows:
    v = r["entry"]["value"]
    print(f"  {r['key']:<70} "
          + (f"{v:>14,.4f}" if isinstance(v, float) else f"{str(v):>14}")
          + f"  {r['entry']['unit']}"
          + ("" if r["recordable"] else "   [not recordable]"))
cal = {r["key"]: r["entry"]["value"] for r in rows if "calibration" in r["key"]}
if cal:
    print("  calibration: " + ", ".join(f"{k.split('.')[-2]} {v:+.2f} per cent"
                                        for k, v in sorted(cal.items())))
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
    e["run"], e["artifact"] = run_id, r["artifact"]
    entries[r["key"]] = e
(out / "constants.json").write_text(json.dumps(
    {"provenance": loaded["frontier.json"]["provenance"], "result": entries}, indent=1) + "\n")
print(f"\ncost-model: {len(entries)} entries in out/constants.json")
PY

[ "$DRY" = no ] || exit 0

# ---- the manifest, from the model's own provenance block --------------------
# `--derived` where a measured routing was applied: what this run took from an
# earlier run goes in the manifest, and `--run-name` puts the configuration that
# ran in the run id, because one driver records two of them.
python3 "$HERE/lib/manifest.py" --driver "tools/drivers/$NAME.sh" --fetched "$OUT" \
    --runs "$ROOT/runs" --prover-commit "$PROVER" --harness-commit "$HARNESS" \
    --run-name "$RUN_NAME" ${ROUTING:+--derived "$TMP/derived.json"} \
    --date "$DATE"
rmdir "$OUT" 2>/dev/null || true
( cd "$ROOT" && python3 tools/constants/check.py )
echo "cost-model: the entries are in runs/$RUN_ID/constants.json, in the shape"
echo "  constants.json takes them and naming this run. The recording merges them"
echo "  under \`constants\` and regenerates the index:"
echo "    python3 tools/constants/index.py"
echo "    python3 tools/constants/check.py"
