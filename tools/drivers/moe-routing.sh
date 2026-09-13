#!/bin/sh
# moe-routing: what a mixture model's router actually does, measured, against
# what the counted mixture rows assume it does.
#
#   tools/drivers/moe-routing.sh download <host> <model> <ctx>[,<ctx>...]
#   tools/drivers/moe-routing.sh run      <host> <model> <ctx>[,<ctx>...]
#
# The assumption. `assumption.cost_model.moe_routing` says every token's top-k
# is uniform over the experts. What a counted mixture row reads off that is one
# number per mixture layer per token block -- how many DISTINCT experts a block
# of S positions touches -- and the file prices it at 13.63 per cent of one
# Qwen3-235B-A22B mixture segment at C=4,096, S=512. The number is the count of
# routed matmuls the segment builds, whose weights its preprocessed trace holds;
# the spread of the tokens over those matmuls is the other half of it. Both are
# per block of S positions and neither is per key tile: the routed side of a
# mixture layer's `params` block is a function of `s` and the routing alone
# (harness/costmodel/exact_cells.py at the pinned commit, expected_distinct_experts,
# routed_blocks and segment_params). This run measures exactly those two things
# on a real forward pass and writes them beside the assumption's own answer.
#
# The model. Qwen3-30B-A3B: 128 experts, 8 active per token, decoder_sparse_step
# 1 and mlp_only_layers empty, so all 48 of its layers are mixture layers and no
# expert is shared. That is the routing shape of the priced Qwen3-235B-A22B row
# -- 128 experts, top-8, no shared expert, every layer a mixture layer -- at
# about 61 GB of bf16 weights instead of 470. Whether one model's routing stands
# in for the other's is the owner's call and the run does not assume it: the
# measurement is recorded under the model that made it.
#
# This is a harness run. Nothing in it proves anything: no prover is built,
# pushed or run, no witness is extracted and no proof is made. Its outputs carry
# no binding table and no proof digest, `lib/manifest.py` records it with `kind`
# `harness` and no prover commit, and `register-13b` is the precedent for a run
# of this repository that measures without proving.
#
# TWO SUBCOMMANDS, because the two halves need different things from the host.
#
#   download   61 GB of weights into the host's hub cache. It needs the network
#              and the disk and it does NOT need the card, so it takes no
#              `~/.zk-run.lock` and may run beside another job's. It refuses
#              before it writes a byte when the free space would not leave
#              RESERVE_GB behind for the jobs already queued, and it is started
#              detached like every other job here, with its own status file.
#   run        the forward passes. This one needs the card, so it goes through
#              tools/remote/run.sh and takes the lock, and it refuses a host
#              whose lock is held. It reads the weights the download left and
#              fetches nothing: HF_HUB_OFFLINE is set, so a snapshot that is not
#              there is an error and never a silent second download.
#
# One run covers every context given, and the contexts are a list for that
# reason: a run id is `<date>-<driver>-<card>`, so two runs of this driver on one
# day on one card would collide, and one load of 61 GB of weights serves every
# prompt length anyway. The corpus is the harness's eval slice, 20,480 token
# ids, so 4,096 gives five disjoint prompts and 16,384 gives one.
#
# What it writes. `runs/<run-id>/routing.json` -- the measurement, per context,
# per block size and per layer, with the uniform expectation beside every figure
# -- `config.json`, `constants.json` in the shape constants.json takes its
# entries, and `manifest.json`. Nothing is transcribed: the recording merges the
# entries the run itself wrote.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SUB=${1:?download or run}
shift
HOST=${1:?host alias}; MODEL=${2:?model id, as the hub names it}
CTX=${3:?context length(s), comma separated}
ZK_PROVER=${ZK_PROVER_DIR:-$ROOT/../zk-prover}     # a local clone to archive the commit from
NAME=moe-routing
. "$HERE/lib/driver.sh"

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=measurement          # a forward pass with hooks on the routers; no proof
# The pinned harness commit. Nothing here runs the prover, so this is the tree
# that produces every number: the cost model whose assumption is under test lives
# in it, and so do `harness.witness.common`, whose eval slice is the corpus, and
# `harness.provenance`, whose block every output carries. It is the commit the
# frontier rows this measurement is about were counted at.
HARNESS=a8586d205b87d7019af5b5005d0a46680a74242e
PROVER=$HARNESS            # unused: no prover runs and the manifest records none
BLOCKS=128,256,512,1024    # the token block sizes S the count is made at
TABLE_BLOCK=512            # the block size the routing table is written at
DEVICE=cuda
ATTN=sdpa
REVISION=${ZK_REVISION:-main}
# What the jobs already on this host need after the weights are down. The
# download refuses rather than filling the disk under a running campaign.
RESERVE_GB=40
DL=$NAME-download
BUILD="build/$(printf '%.12s' "$HARNESS")"
HSRC=$BUILD/harness-src

case "$SUB" in
  download|run) ;;
  *) echo "$NAME: no such subcommand: $SUB (download or run)" >&2; exit 2 ;;
esac

# ---- the download ------------------------------------------------------------
if [ "$SUB" = download ]; then
    ST=$(ssh -o BatchMode=yes "$HOST" "cat ~/runs/$DL.status 2>/dev/null || true")
    case "$ST" in
      *"done exit=0"*)
        echo "$NAME: the weights are down on $HOST: $ST"
        ssh -o BatchMode=yes "$HOST" "cat ~/runs/$DL/weights.json 2>/dev/null || true"
        echo "next: when the card is free,"
        echo "  tools/drivers/$NAME.sh run $HOST $MODEL $CTX"
        exit 0 ;;
      *"done exit="*)
        echo "$NAME: the download on $HOST failed: $ST"
        echo "log:     ssh $HOST tail -50 '~/runs/$DL.log'"
        echo "restart: ssh $HOST rm -f '~/runs/$DL.status' && $0 download $HOST $MODEL $CTX"
        echo "         (a restart re-uses every file already in the hub cache)"
        exit 1 ;;
      running*)
        echo "$NAME: the download on $HOST is running: $ST"
        echo "poll: ssh $HOST cat '~/runs/$DL.status'"
        echo "tail: ssh $HOST tail -5 '~/runs/$DL.log'"
        exit 0 ;;
    esac

    drv_check_commits
    # The card may be busy and that is allowed here; it is said out loud so that
    # a reader of the log knows this job ran beside another one.
    HELD=$(ssh -o BatchMode=yes "$HOST" "cat ~/.zk-run.lock 2>/dev/null || true")
    [ -z "$HELD" ] || echo "$NAME: $HOST is running $HELD; the download needs no card and takes no lock"
    drv_push "$HSRC" "$HARNESS"

    JOB=$(mktemp)
    RESERVE_BYTES=$((RESERVE_GB * 1000 * 1000 * 1000))
    cat > "$JOB" <<JOBEOF
#!/bin/sh
# generated by $NAME.sh download; runs detached on the host and takes no run lock
set -eu
B=\$HOME/$BUILD
R=\$HOME/runs/$DL
HSRC=\$B/harness-src/harness
mkdir -p \$R
$(drv_job_preamble)

st "host: \$(nproc) cores, model $MODEL at $REVISION"
st "harness: \$(cat \$B/harness-src/.source-commit)"
df -h \$HOME | tail -1

# The environment, and the one thing this job must not do to it. Another
# campaign may be running out of this same project directory right now, and a
# sync that selected other groups would swap its torch build out from under it.
# So: use the environment that is already there when it is there, and build one
# only when it is not.
PY=\$HSRC/.venv/bin/python
if [ -x \$PY ] && \$PY -c 'import huggingface_hub' > /dev/null 2>&1; then
  st "environment: the project venv is already built; not syncing"
else
  st "environment: syncing the harness at the pinned commit"
  ( cd \$HSRC && uv sync --frozen \$UVG )
fi

# The disk, before a byte is written. The size comes from the hub's own file
# metadata and not from a number in a driver, and the reserve is what the jobs
# already on this host need after this one has finished.
\$PY - "$MODEL" "$REVISION" "$RESERVE_BYTES" \$R/weights.json <<'PY'
import fnmatch, json, os, shutil, sys, time

from huggingface_hub import HfApi, constants, snapshot_download

model, revision, reserve, record = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
want = ("*.json", "*.safetensors", "*.txt", "*.model")
cache = constants.HF_HUB_CACHE
os.makedirs(cache, exist_ok=True)

info = HfApi().model_info(model, revision=revision, files_metadata=True)
sizes = {s.rfilename: (s.size or 0) for s in info.siblings}
need = sum(n for f, n in sizes.items() if any(fnmatch.fnmatch(f, p) for p in want))
free = shutil.disk_usage(cache).free
print(f"repository {model} at {info.sha}: {len(sizes)} files, {need:,} bytes to fetch")
print(f"disk at {cache}: {free:,} bytes free, reserve {reserve:,}")
if free - need < reserve:
    raise SystemExit(
        f"moe-routing: {free:,} bytes free and the weights are {need:,}; that leaves "
        f"{free - need:,} where the jobs already on this host need {reserve:,}. "
        f"Nothing was downloaded.")

t0 = time.time()
path = snapshot_download(model, revision=revision, allow_patterns=list(want))
# every file in a snapshot is a link to the blob that holds it, one to one, and
# getsize follows the link, so this is the size on disk and counts nothing twice
on_disk = sum(os.path.getsize(os.path.join(r, f))
              for r, _, fs in os.walk(path) for f in fs)
doc = {"model": model, "revision": revision, "commit": info.sha,
       "bytes": on_disk, "announced_bytes": need,
       "seconds": round(time.time() - t0, 1),
       "free_after": shutil.disk_usage(cache).free}
with open(record, "w") as f:
    json.dump(doc, f, indent=1, sort_keys=True)
    f.write("\n")
print(json.dumps(doc))
PY

df -h \$HOME | tail -1
st "done"
JOBEOF
    ssh -o BatchMode=yes "$HOST" "mkdir -p ~/runs/$DL && cat > ~/runs/$DL/job.sh" < "$JOB"
    rm -f "$JOB"
    # Detached, and deliberately NOT through tools/remote/run.sh: that wrapper
    # acquires `~/.zk-run.lock` and frees it when the job exits, and this job
    # neither needs the card nor may take a lock another job is queued behind.
    # The wrapper below is otherwise run.sh's, for run.sh's reasons: the script
    # travels on standard input because a command argument does not survive
    # every connection, and the heredoc gives ssh an end of input so it returns
    # instead of waiting on a stdin the detached job no longer holds.
    ssh -o BatchMode=yes "$HOST" sh <<SHEOF
mkdir -p ~/runs && setsid nohup sh -c 'S=\$HOME/runs/$DL.status; echo "running \$(date -u +%Y-%m-%dT%H:%M:%SZ) pid \$\$" > \$S; sh \$HOME/runs/$DL/job.sh; rc=\$?; echo "done exit=\$rc \$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> \$S' > ~/runs/$DL.log 2>&1 < /dev/null &
SHEOF
    echo "$NAME: the download started on $HOST and holds no run lock"
    echo "poll:   ssh $HOST cat '~/runs/$DL.status'"
    echo "tail:   ssh $HOST tail -20 '~/runs/$DL.log'"
    echo "then:   run this command again to see it finish"
    exit 0
fi

# ---- the run -----------------------------------------------------------------
# The finish path is written out here rather than taken from `drv_finish`,
# because this run writes its constants entries out of its own fetched output
# and that has to happen between the fetch and the manifest: `manifest.py` moves
# the fetched directory into `runs/` and a run directory is never opened again.
ST=$(drv_status)
case "$ST" in
  *"done exit=0"*)
    DATE=$(printf '%s\n' "$ST" | awk '/^done/ {print substr($3, 1, 10)}')
    TMP=$(mktemp -d "$ROOT/runs/.fetch-$NAME.XXXXXX")
    "$ROOT/tools/remote/fetch.sh" "$HOST" "$NAME" "$TMP"
    # The gate: what the run has to be before it is recorded, and the entries it
    # backs. Nothing measured is typed in; this reads the output the job wrote.
    python3 - "$TMP" "$DATE" "$NAME" "$HARNESS" "$HERE/lib" "$TABLE_BLOCK" <<'PY'
import json, pathlib, sys
tmp, date, name, harness, lib = (pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3],
                                 sys.argv[4], sys.argv[5])
statement_block = int(sys.argv[6])
sys.path.insert(0, lib)
import manifest  # noqa: E402

doc = json.loads((tmp / "routing.json").read_text())
prov, res = doc["provenance"], doc["result"]
bad = []
c = prov.get("commit") or ""
if not c or not (c.startswith(harness) or harness.startswith(c)):
    bad.append(f"the measurement ran at {c or 'no commit'}, not at the pinned {harness}")
if prov.get("dirty"):
    bad.append("the pinned tree was dirty")
if prov.get("kind") != "harness":
    bad.append(f"the output declares kind {prov.get('kind')!r}; this run proves nothing")
if res["experts"] < 2 or res["topk"] < 1:
    bad.append(f"{res['model']} routes {res['topk']} of {res['experts']} experts; "
               "there is no routing to measure")
stack = res["config"].get("num_hidden_layers")
if stack and res["mixture_layers"] != stack:
    bad.append(f"{res['mixture_layers']} of {stack} layers are mixture layers, and every "
               "figure here is a mean over the mixture layers alone; record which layers "
               "they are before this is a row about the model")
run_id = f"{date}-{name}-{manifest.gpu_slug(prov.get('gpu'))}"
entries, rows = {}, []
for ctx, cdoc in sorted(res["contexts"].items(), key=lambda kv: int(kv[0])):
    for s, b in sorted(cdoc["blocks"].items(), key=lambda kv: int(kv[0])):
        if not b.get("samples"):
            bad.append(f"context {ctx}, S={s}: no block was measured")
            continue
        stem = f"moe.routing.{res['key_slug']}.c{ctx}.s{s}"
        shared = dict(unit="experts", card="none", context=int(ctx), timing_scope="n/a",
                      run=run_id, artifact="routing.json")
        entries[f"{stem}.distinct_experts_mean"] = dict(
            shared, value=b["distinct_experts_mean"], grade="measured",
            note=f"How many distinct experts a block of {s} consecutive positions touches "
                 f"in one mixture layer of {res['model']}, measured on {cdoc['prompts']} "
                 f"prompt(s) of {ctx} positions from the harness's eval corpus: the mean "
                 f"over the {res['mixture_layers']} mixture layers and the "
                 f"{b['blocks_per_prompt']} block(s) each prompt divides "
                 f"into, {b['samples']} blocks in all, spread {b['distinct_experts_min']} "
                 f"to {b['distinct_experts_max']}. This is the quantity "
                 f"assumption.cost_model.moe_routing assumes: the routed matmuls a segment "
                 f"builds, and so the weights its preprocessed trace holds.")
        entries[f"{stem}.distinct_experts_uniform"] = dict(
            shared, value=b["distinct_experts_uniform"], grade="derived",
            note=f"What the assumption gives for the same block: "
                 f"E (1 - (1 - k/E)^S) at E = {res['experts']}, k = {res['topk']}, "
                 f"S = {s}, which is exact_cells.expected_distinct_experts. It is beside "
                 f"the measured entry so the two are read together and neither is a "
                 f"second measurement of the other.")
        if int(s) == statement_block:
            # The spread, at the block size the recorded statement proves. The
            # distinct count is bounded by the experts a layer has and says
            # little once a block is long enough to touch them all; what the
            # routed matmuls are actually laid out from is how unevenly the
            # block's token slots fall, and this is that in one number.
            entries[f"{stem}.tokens_per_expert_max_mean"] = dict(
                shared, unit="tokens", value=b["tokens_per_expert_max_mean"],
                grade="measured",
                note=f"The busiest routed matmul of a block of {s} positions: the tokens "
                     f"the most-used expert of a mixture layer took, meaned over the "
                     f"{res['mixture_layers']} layers and the {b['samples']} blocks. "
                     f"Under assumption.cost_model.moe_routing every routed matmul of "
                     f"this block covers {(b['uniform_split'] or ['n/a'])[0]} tokens "
                     f"(exact_cells.routed_blocks at E = {res['experts']}, k = "
                     f"{res['topk']}, S = {s}); a measured block is laid out from its "
                     f"own histogram, which runs/<run>/routing.json carries in full. "
                     f"That flat figure is what the model BUILDS and not what a uniform "
                     f"draw's busiest expert takes, which is higher than the share for "
                     f"the same reason any multinomial maximum is: read this against the "
                     f"histogram, not against the share.")
        rows.append((f"c{ctx} S={s}", b["distinct_experts_mean"],
                     b["distinct_experts_uniform"], b["samples"]))
print(f"\n{res['model']} at {res['revision']}: {res['experts']} experts, top-{res['topk']}, "
      f"{res['mixture_layers']} mixture layers")
print(f"  {'block':<14} {'measured':>10} {'assumed':>10} {'ratio':>8} {'blocks':>8}")
for label, got, want, n in rows:
    print(f"  {label:<14} {got:>10.4f} {want:>10.4f} "
          f"{(got / want if want else 0):>8.4f} {n:>8}")
for r in res.get("refused") or ():
    print(f"  context {r['context']}: NOT MEASURED -- {r['why']}")
if bad:
    print("\nnot recordable:")
    for b in bad:
        print(f"  {b}")
    sys.exit(f"{name}: the run is not what this driver records; nothing is written "
             f"under runs/")
(tmp / "constants.json").write_text(json.dumps(
    {"provenance": prov, "result": entries}, indent=1, sort_keys=True) + "\n")
print(f"\n{name}: run id {run_id}, {len(entries)} entries in out/constants.json")
PY
    python3 "$HERE/lib/manifest.py" --driver "tools/drivers/$NAME.sh" --fetched "$TMP" \
        --runs "$ROOT/runs" --prover-commit "$PROVER" --harness-commit "$HARNESS" \
        --date "$DATE"
    rmdir "$TMP" 2>/dev/null || true
    (cd "$ROOT" && python3 tools/constants/check.py)
    RUN=$(ls -d "$ROOT"/runs/*-"$NAME"-* | tail -1)
    echo
    echo "$NAME: recorded in runs/$(basename "$RUN")"
    echo "next:  merge the entries under \`constants\` and regenerate the index:"
    echo "         python3 tools/constants/index.py"
    echo "         python3 tools/constants/check.py"
    echo "       and, to count a mixture row at the measurement instead of at the"
    echo "       assumption, write the routing table out and pass it to the model:"
    echo "         python3 -c 'import json,sys; json.dump(json.load(open(sys.argv[1]))"
    echo "           [\"result\"][\"routing_table\"], open(sys.argv[2], \"w\"), indent=1)' \\"
    echo "           runs/$(basename "$RUN")/routing.json routing.json"
    echo "       Its key is this model's own slug, and the frontier holds no row under"
    echo "       that name: which row it may price is the owner's decision."
    exit 0 ;;
  *"done exit="*)
    echo "$NAME on $HOST failed: $ST"
    echo "log:     ssh $HOST tail -50 '~/runs/$NAME.log'"
    echo "restart: ssh $HOST rm -f '~/runs/$NAME.status' && $0 run $HOST $MODEL $CTX"
    exit 1 ;;
  running*)
    echo "$NAME on $HOST: $ST"
    echo "poll: ssh $HOST cat '~/runs/$NAME.status'"
    exit 0 ;;
esac

# ---- start: the card, the sources, the script, the job -----------------------
drv_check_commits
HELD=$(ssh -o BatchMode=yes "$HOST" "cat ~/.zk-run.lock 2>/dev/null || true")
if [ -n "$HELD" ]; then
    echo "$NAME: $HOST is busy: $HELD" >&2
    echo "        The forward passes need the card to themselves. Wait for that job," >&2
    echo "        then start this one; the weights are already down and the download" >&2
    echo "        subcommand does not have to be run again." >&2
    exit 1
fi
WEIGHTS=$(ssh -o BatchMode=yes "$HOST" "cat ~/runs/$DL/weights.json 2>/dev/null || true")
if [ -z "$WEIGHTS" ]; then
    echo "$NAME: no weights record on $HOST. The run reads the snapshot the download" >&2
    echo "        left and fetches nothing of its own:" >&2
    echo "          tools/drivers/$NAME.sh download $HOST $MODEL $CTX" >&2
    exit 2
fi
echo "$NAME: weights on $HOST: $WEIGHTS"
drv_push "$HSRC" "$HARNESS"
ssh -o BatchMode=yes "$HOST" "mkdir -p ~/runs/$NAME && cat > ~/runs/$NAME/routing_stats.py" \
    < "$ROOT/tools/moe/routing_stats.py"
echo "$NAME: tools/moe/routing_stats.py -> $HOST:~/runs/$NAME/routing_stats.py"

JOB=$(mktemp)
cat > "$JOB" <<JOBEOF
#!/bin/sh
# generated by $NAME.sh run; runs on the host under tools/remote/run.sh
set -eu
B=\$HOME/$BUILD
R=\$HOME/runs/$NAME
HSRC=\$B/harness-src/harness
OUT=\$R/out
WORK=\$R/work            # the harness's own output directory: the token cache is
mkdir -p \$OUT \$WORK    # an input of this run and does not belong in its outputs
$(drv_job_preamble)
# The snapshot the download left, and no other. A weight file that is not there
# is an error here; it is never a second download in the middle of a measurement.
export HF_HUB_OFFLINE=1

st "cores: \$(nproc), device $DEVICE, attention $ATTN"
st "harness: \$(cat \$B/harness-src/.source-commit)"
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

( cd \$HSRC && uv sync --frozen \$UVG )
# The pinned lock holds no accelerate, and transformers reads a device map only
# when accelerate is importable. Without it the 61 GB of weights are read into
# host memory and moved to the card afterwards, and this host is a container
# with a memory cap of its own: a load like that is what an out-of-memory kill
# is made of. So accelerate is put on top of the pinned set with --no-deps,
# which resolves nothing and cannot move the pinned torch, and the next
# campaign's own uv sync --frozen takes it away again. The version is recorded
# below, because it is part of what produced the numbers.
uv pip install --python \$HSRC/.venv/bin/python --no-deps accelerate psutil
ACCEL=\$(\$HSRC/.venv/bin/python -c 'import accelerate; print(accelerate.__version__)')
st "environment: accelerate \$ACCEL on top of the pinned lock, --no-deps"

cat > \$OUT/config.json <<CFG
{"driver": "$NAME", "label": "$LABEL", "kind": "harness",
 "model": "$MODEL", "revision": "$REVISION", "device": "$DEVICE", "attn": "$ATTN",
 "contexts": "$CTX", "blocks": "$BLOCKS", "table_block": $TABLE_BLOCK,
 "harness_commit": "$HARNESS",
 "accelerate": "\$ACCEL, added to the pinned environment with --no-deps so the weights load straight onto the card",
 "weights": \$(cat \$HOME/runs/$DL/weights.json),
 "corpus": "harness/witness/text.txt through harness.witness.common.tokens, the eval slice every quality campaign here scores over; the output names it by digest",
 "card": "the forward passes run on it; no proof is made and nothing is timed",
 "witness": "none: no dump is written and no proof of this model exists anywhere"}
CFG

st "routing: $MODEL, contexts $CTX, blocks $BLOCKS"
uv run --project \$HSRC \$UVG python \$R/routing_stats.py \\
    --model $MODEL --revision $REVISION --ctx $CTX --blocks $BLOCKS \\
    --table-block $TABLE_BLOCK --device $DEVICE --attn $ATTN \\
    --out \$OUT --work \$WORK

du -sh \$OUT | awk '{print "fetched size: " \$1 "  " \$2}'
st "done"
JOBEOF
drv_start "$JOB"
rm -f "$JOB"
