#!/usr/bin/env python3
"""What a mixture model's router actually does, per layer and per block of S positions.

    uv run --project <zk-prover>/harness --frozen --no-group cpu --group cuda \
        python tools/moe/routing_stats.py --model Qwen/Qwen3-30B-A3B \
        --ctx 4096,16384 --blocks 128,256,512,1024 --out DIR --work DIR

THE QUANTITY.  `assumption.cost_model.moe_routing` is one sentence -- every
token's top-k is uniform over the experts -- and what the counted mixture row
reads off it is one number per mixture layer per token block: how many DISTINCT
experts a block of S positions touches.  `harness/costmodel/exact_cells.py` at
zk-prover 6589471 is where that number is used:

  * `expected_distinct_experts(E, k, S)` returns `E (1 - (1 - k/E)^S)`, and
    `frontier.moe_of` rounds it to `touched`;
  * `segment_params` builds `touched` routed matmuls out of it -- their weights
    are what the segment's preprocessed trace holds, and the preprocessed trace
    is the term that does not amortise;
  * `routed_blocks(S, k, touched)` then spreads the `S k` token slots over those
    matmuls, and `distribution` -- `[(tokens, matmuls), ...]` -- overrides it
    with what a real run of the model did.

It is per block of S positions and NOT per key tile.  The routed side of a
segment is a function of `s` and the routing alone; the context C enters a
mixture layer's `params` block only through the attention side, which no expert
sees.  S on the recorded statement is 512.

So this script measures those two things and nothing else: per layer and per
block size, how many distinct experts a block of S consecutive positions
touched, and how the block's `S k` token slots were spread over them.  The
uniform-draw expectation is computed beside every measured figure, out of the
same E, k and S, so the file says what the assumption claimed as well as what
happened.  No proof is involved and no prover runs: this is a forward pass with
hooks on the routers.

THE CORPUS is the harness's own, at the pinned commit: `harness/witness/text.txt`
through `harness.witness.common.tokens()`, which is the eval slice every quality
campaign in this repository scores over, tokenized by the measured model's own
tokenizer.  `ZK_MODEL` and `ZK_OUT` are set below before that module is
imported, because it reads both at import time and caches the token ids under
`ZK_OUT`: a cache written by another model's tokenizer would be another corpus.
The slice is 40 blocks of 512 = 20,480 token ids, so a context of 4,096 gives
five disjoint prompts and 16,384 gives one, and the JSON says which.

THE ENVIRONMENT is the harness's uv project at the pinned commit, the same one
every other measurement here runs in: it pins torch, transformers and numpy
through `harness/uv.lock`, and it is the only environment that has
`harness.witness.common` and `harness.provenance`, both of which this reads
rather than restates.  There is no second set of pins to keep in step.

WHAT IT WRITES.  `routing.json`, a run JSON of this repository's usual shape:
the harness's own provenance block, and a `result` holding one entry per
context, per block size and per layer.  `result.routing_table` is the same
measurement in the shape `harness.costmodel.frontier`'s `--routing FILE`
reads, so the row can be counted at the measurement instead of at the
assumption; it is keyed by the MEASURED model's slug, and re-keying it to the
row a reader wants priced is a decision and not a transcription.
"""
import argparse
import collections
import importlib.util
import json
import os
import pathlib
import re
import sys
import time


def ints(text, what):
    """A comma-separated list of positive counts."""
    out = []
    for part in text.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            n = int(part)
        except ValueError:
            raise SystemExit(f"routing_stats: {what} {part!r} is not a number")
        if n < 1:
            raise SystemExit(f"routing_stats: {what} {n} is not a positive count")
        out.append(n)
    if not out:
        raise SystemExit(f"routing_stats: no {what} given")
    return out


def slug(name):
    """A model name as the cost model slugs it (`harness/costmodel/frontier.py`,
    slug), which is what its `--routing FILE` keys a row by."""
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def key_slug(name):
    """A model name as one segment of a constants key here: the repository
    dropped `e4.codellama_13b` and `e4.qwen2p5_14b` out of the same rule -- the
    model's own name without the vendor, lower case, underscores for everything
    else."""
    return re.sub(r"[^a-z0-9]+", "_", name.rsplit("/", 1)[-1].lower()).strip("_")


def expected_distinct(experts, topk, s):
    """`E (1 - (1 - k/E)^S)`: the assumption's own answer, the same arithmetic
    `exact_cells.expected_distinct_experts` does."""
    if experts <= 1 or topk <= 0:
        return 0.0
    return experts * (1.0 - (1.0 - topk / experts) ** s)


def uniform_split(s, topk, touched):
    """What `exact_cells.routed_blocks` lays out under the assumption: the
    largest power of two at or below the uniform share, and as many of them as
    the token slots take.  Returns None where the slots do not tile, which is
    the case that function refuses."""
    slots = s * topk
    share = int(slots / max(1.0, touched))
    te = 1 << max(0, share.bit_length() - 1)
    if te < 1 or slots % te:
        return None
    return [te, slots // te]


def routers_of(model, torch):
    """Every mixture layer's router, in layer order: (layer index, module path,
    the module whose output names the experts each token was routed to).

    A mixture block is a module that has both a `gate` and an `experts`
    attribute -- the shape Qwen3-MoE, DeepSeek and Mixtral all take in
    transformers -- and the router is its `gate`, whether that is a bare linear
    layer over the logits or a module that does the top-k itself.
    """
    found = []
    for name, mod in model.named_modules():
        gate, experts = getattr(mod, "gate", None), getattr(mod, "experts", None)
        if experts is None or not isinstance(gate, torch.nn.Module):
            continue
        m = re.search(r"layers\.(\d+)", name)
        found.append((int(m.group(1)) if m else len(found), f"{name}.gate", gate))
    found.sort(key=lambda r: r[0])
    return found


def selected(out, topk, experts, torch):
    """The experts a router chose, as `(positions, k)` indices.

    Two shapes, because two kinds of router module exist: one returns the top-k
    indices itself (transformers 5's `Qwen3MoeTopKRouter` returns logits, scores
    and indices) and one is a bare linear layer whose output is the `E` logits
    per position.  The top-k of the logits is the top-k of their softmax, so the
    indices are the same either way.
    """
    parts = list(out) if isinstance(out, (tuple, list)) else [out]
    for t in reversed(parts):
        if torch.is_tensor(t) and not t.is_floating_point() and t.shape[-1] == topk:
            return t.reshape(-1, topk)
    for t in parts:
        if torch.is_tensor(t) and t.is_floating_point() and t.shape[-1] == experts:
            return t.reshape(-1, experts).topk(topk, dim=-1).indices
    raise SystemExit(
        "routing_stats: a router returned nothing this reads: no integer tensor of "
        f"{topk} columns and no float tensor of {experts}. The routed experts have to "
        "be read off the router itself; add the shape here rather than inferring them.")


def block_rows(idx, experts, torch):
    """One block of positions: how many distinct experts it touched, and the
    histogram of tokens per touched expert, `{tokens: experts}`."""
    counts = torch.bincount(idx.reshape(-1).to(torch.int64), minlength=experts)
    nonzero = counts[counts > 0]
    hist = collections.Counter(int(n) for n in nonzero.tolist())
    return int(nonzero.numel()), hist, int(nonzero.max()), int(nonzero.min())


def histogram_table(hist):
    """A `{tokens: experts}` histogram as the cost model's `[[tokens, matmuls],
    ...]`, widest matmul first."""
    return [[t, n] for t, n in sorted(hist.items(), reverse=True)]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", required=True, help="the model id, as the hub names it")
    ap.add_argument("--revision", default="main", help="the model repository revision")
    ap.add_argument("--ctx", required=True,
                    help="prompt lengths, comma separated; each is measured on as many "
                         "disjoint prompts as the corpus gives")
    ap.add_argument("--blocks", default="128,256,512,1024",
                    help="the token block sizes S the count is made at")
    ap.add_argument("--table-block", type=int, default=512,
                    help="the block size `result.routing_table` is written at; 512 is "
                         "the statement the recorded runs proved")
    ap.add_argument("--device", default="cuda")
    ap.add_argument("--attn", default="sdpa", help="the attention implementation")
    ap.add_argument("--out", required=True, help="directory for routing.json")
    ap.add_argument("--work", required=True,
                    help="the harness's own output directory: the token cache is an "
                         "input of this run and does not belong in its outputs")
    args = ap.parse_args(argv)

    ctxs = ints(args.ctx, "context")
    blocks = ints(args.blocks, "block size")
    out = pathlib.Path(args.out)
    work = pathlib.Path(args.work)
    out.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)
    # Before `harness.witness.common` is imported: it reads both at import time,
    # and the token cache under ZK_OUT is written by one model's tokenizer.
    os.environ["ZK_MODEL"] = args.model
    os.environ["ZK_OUT"] = str(work)
    os.environ.setdefault("ZK_DEVICE", args.device)

    if args.device != "cpu" and importlib.util.find_spec("accelerate") is None:
        raise SystemExit(
            "routing_stats: transformers reads `device_map` only when accelerate is "
            "importable, and without it the weights are read into host memory and moved "
            "to the card afterwards -- which is what a container's memory cap refuses. "
            "Put it beside the pinned environment (uv pip install --no-deps accelerate "
            "psutil), or measure on --device cpu.")

    import torch
    from transformers import AutoConfig, AutoModelForCausalLM

    from harness import provenance
    from harness.witness import common

    cfg = AutoConfig.from_pretrained(args.model, revision=args.revision)
    cfg = getattr(cfg, "text_config", None) or cfg
    experts = int(getattr(cfg, "num_experts", 0) or getattr(cfg, "n_routed_experts", 0) or 0)
    topk = int(getattr(cfg, "num_experts_per_tok", 0) or 0)
    if experts < 2 or topk < 1:
        raise SystemExit(f"routing_stats: {args.model} has {experts} routed experts and "
                         f"top-{topk}; it is not a mixture model and there is no routing "
                         f"to measure")
    routing_fields = {k: getattr(cfg, k, None) for k in (
        "model_type", "num_hidden_layers", "hidden_size", "num_experts",
        "n_routed_experts", "num_experts_per_tok", "moe_intermediate_size",
        "decoder_sparse_step", "mlp_only_layers", "norm_topk_prob",
        "n_shared_experts", "shared_expert_intermediate_size")}

    ev, _ = common.tokens()
    corpus_tokens = int(ev.numel())
    print(f"corpus: {corpus_tokens:,} eval token ids from {common.TEXT}, "
          f"tokenized by {args.model}")
    plan = {}
    for c in ctxs:
        n = corpus_tokens // c
        if n < 1:
            raise SystemExit(
                f"routing_stats: the corpus gives {corpus_tokens:,} token ids and a "
                f"prompt of {c:,} does not fit in it. The eval slice is 40 blocks of "
                f"512 (harness/witness/common.py, tokens); measure at a context it "
                f"holds, or say in the record that the longest is {corpus_tokens:,}.")
        plan[c] = n
        print(f"  context {c:,}: {n} disjoint prompt(s), {n * c:,} positions")

    t0 = time.time()
    # Straight to the card, shard by shard, and never through host memory: the
    # host is a container with a memory cap of its own and 61 GB of bf16 weights
    # read into RAM and moved afterwards is what an out-of-memory kill is made
    # of. transformers reads `device_map` without accelerate on this version;
    # a device of `cpu` is the dry check's path and maps nothing.
    load_kw = dict(revision=args.revision, dtype=torch.bfloat16,
                   attn_implementation=args.attn)
    if args.device != "cpu":
        load_kw["device_map"] = {"": args.device}
    print(f"loading {args.model} at {args.revision}, bfloat16, attn {args.attn}, "
          f"device_map {load_kw.get('device_map')}")
    model = AutoModelForCausalLM.from_pretrained(args.model, **load_kw).eval()
    if args.device != "cpu":
        where = {str(p.device) for p in model.parameters()}
        if any(d.startswith("cpu") for d in where):
            raise SystemExit(f"routing_stats: the weights landed on {sorted(where)} and "
                             f"not on {args.device} alone; a load that goes through host "
                             f"memory is what this host's cap refuses")
        print(f"loaded in {time.time() - t0:.0f}s onto {sorted(where)}")
    else:
        print(f"loaded in {time.time() - t0:.0f}s")
    # The output head is not run: the vocabulary projection of 16,384 positions
    # is gigabytes of logits and no router reads it.
    base = getattr(model, "model", model)

    found = routers_of(model, torch)
    if not found:
        raise SystemExit(f"routing_stats: no mixture block in {args.model}: no module "
                         f"carries both a gate and an experts attribute")
    print(f"routers: {len(found)} of {getattr(cfg, 'num_hidden_layers', '?')} layers, "
          f"{experts} experts, top-{topk}")

    store = {}
    handles = []
    contexts, table, refused = {}, {}, []

    def hook_for(layer):
        def hook(_mod, _inputs, output):
            store[layer] = selected(output, topk, experts, torch).to("cpu", torch.int16)
        return hook

    for layer, _path, mod in found:
        handles.append(mod.register_forward_hook(hook_for(layer)))
    layers = [layer for layer, _p, _m in found]

    def measure(c, per_layer, samples):
        """One context's forward passes, prompt by prompt, into the two
        accumulators: `per_layer[(S, layer)]` and `samples[S]`, the blocks the
        representative is taken out of."""
        for p in range(plan[c]):
            ids = ev[p * c:(p + 1) * c].to(args.device).unsqueeze(0)
            store.clear()
            t1 = time.time()
            with torch.no_grad():
                base(input_ids=ids, use_cache=False)
            missing = [layer for layer in layers if layer not in store]
            if missing:
                raise SystemExit(f"routing_stats: layers {missing} routed nothing in the "
                                 f"forward pass; every mixture layer has to be hooked")
            print(f"context {c:,} prompt {p + 1}/{plan[c]}: {time.time() - t1:.1f}s")
            for layer in layers:
                idx = store[layer]
                if idx.shape[0] != c:
                    raise SystemExit(
                        f"routing_stats: layer {layer} routed {idx.shape[0]} positions "
                        f"and the prompt is {c}; the router's output is not one row a "
                        f"position and the blocks below would not be blocks of positions")
                for s in blocks:
                    if c % s:
                        raise SystemExit(f"routing_stats: a context of {c} does not "
                                         f"divide into blocks of {s}")
                    for b in range(c // s):
                        d, hist, hi, lo = block_rows(idx[b * s:(b + 1) * s], experts, torch)
                        row = per_layer[(s, layer)]
                        row["distinct"].append(d)
                        row["hist"].update(hist)
                        row["tokens_max"].append(hi)
                        row["tokens_min"].append(lo)
                        samples[s].append((d, layer, p, b, hist))
            store.clear()

    def aggregate(c, per_layer, samples):
        """One context's figures, out of what `measure` accumulated for it."""
        by_block = {}
        for s in blocks:
            rows = []
            for layer in layers:
                row = per_layer[(s, layer)]
                n = len(row["distinct"])
                rows.append(dict(
                    layer=layer, blocks=n,
                    distinct_experts_mean=sum(row["distinct"]) / n,
                    distinct_experts_min=min(row["distinct"]),
                    distinct_experts_max=max(row["distinct"]),
                    tokens_per_expert_max_mean=sum(row["tokens_max"]) / n,
                    tokens_per_expert_min_mean=sum(row["tokens_min"]) / n,
                    # summed over this layer's blocks; a reader divides by `blocks`
                    tokens_per_expert_histogram={str(k): v
                                                 for k, v in sorted(row["hist"].items())}))
            allb = samples[s]
            allb.sort(key=lambda r: (r[0], r[1], r[2], r[3]))
            med = allb[len(allb) // 2]
            uniform = expected_distinct(experts, topk, s)
            mean = sum(r["distinct_experts_mean"] for r in rows) / len(rows)
            dist = histogram_table(med[4])
            if sum(t * n for t, n in dist) != s * topk:
                raise SystemExit(f"routing_stats: the representative block at S={s} holds "
                                 f"{sum(t * n for t, n in dist)} token slots and a block of "
                                 f"{s} positions at top-{topk} has {s * topk}")
            by_block[str(s)] = dict(
                block_size=s, samples=len(allb), blocks_per_prompt=c // s,
                # the mean over every mixture layer and every block of every
                # prompt; each layer contributes the same number of blocks, so
                # this is the mean of the per-layer means
                distinct_experts_mean=mean,
                distinct_experts_min=min(r["distinct_experts_min"] for r in rows),
                distinct_experts_max=max(r["distinct_experts_max"] for r in rows),
                distinct_experts_uniform=uniform,
                measured_over_uniform=mean / uniform if uniform else None,
                tokens_per_expert_mean=s * topk / mean if mean else None,
                tokens_per_expert_max_mean=sum(r["tokens_per_expert_max_mean"]
                                               for r in rows) / len(rows),
                tokens_per_expert_min_mean=sum(r["tokens_per_expert_min_mean"]
                                               for r in rows) / len(rows),
                uniform_split=uniform_split(s, topk, round(uniform)),
                representative=dict(layer=med[1], prompt=med[2], block=med[3],
                                    distinct_experts=med[0], distribution=dist),
                layers=rows)
            ratio = f"{mean / uniform:.4f}" if uniform else "n/a"
            print(f"context {c:,} S={s:<5} distinct experts: {mean:8.3f} measured, "
                  f"{uniform:8.3f} under the assumption, ratio {ratio}")
        contexts[str(c)] = dict(context=c, prompts=plan[c], positions=plan[c] * c,
                                blocks=by_block)
        t = by_block.get(str(args.table_block))
        if t:
            table[f"c{c}"] = t["representative"]["distribution"]

    try:
        for c in ctxs:
            # The two accumulators are per context and are merged into the record
            # only once the context has measured: a context the card cannot take
            # is recorded as refused and does not cost the contexts that did
            # measure, which is the rule the quality campaigns already follow for
            # a variant a model will not take. A refusal this file makes itself
            # is a SystemExit and still ends the run.
            per_layer = collections.defaultdict(lambda: dict(
                distinct=[], hist=collections.Counter(), tokens_max=[], tokens_min=[]))
            samples = collections.defaultdict(list)
            try:
                measure(c, per_layer, samples)
            except RuntimeError as e:
                why = str(e).strip().split("\n")[0][:300]
                print(f"context {c:,}: NOT MEASURED -- {why}")
                refused.append(dict(context=c, why=why))
                cuda = getattr(torch, "cuda", None)
                if cuda is not None:
                    cuda.empty_cache()
                continue
            aggregate(c, per_layer, samples)
    finally:
        for h in handles:
            h.remove()

    if not contexts:
        raise SystemExit("routing_stats: no context measured. " + json.dumps(refused))

    prov = provenance.block(
        model=args.model, device=args.device, threads=torch.get_num_threads(),
        module="tools.moe.routing_stats", argv=sys.argv[1:],
        corpus=provenance.digest(common.TEXT), corpus_tokens=corpus_tokens,
        contexts=ctxs, block_sizes=blocks, revision=args.revision,
        load="device_map" if args.device != "cpu" else "direct")
    # `provenance.block` names a module of the harness, and this is a file of
    # this repository run inside the harness's environment. It says so.
    prov["binary"] = "python tools/moe/routing_stats.py"
    doc = dict(provenance=prov, result=dict(
        model=args.model, slug=slug(args.model), key_slug=key_slug(args.model),
        revision=args.revision,
        experts=experts, topk=topk, mixture_layers=len(layers),
        routers=[p for _l, p, _m in found], config=routing_fields,
        corpus=dict(file=str(common.TEXT), tokens=corpus_tokens,
                    source="harness.witness.common.tokens, the eval slice"),
        block_sizes=blocks, contexts=contexts, refused=refused,
        routing_table={slug(args.model): table},
        routing_table_note=(
            "the measured distribution in the shape harness.costmodel.frontier's "
            f"--routing FILE reads, at S={args.table_block}, one entry per context "
            "measured. It is keyed by this model's own slug, which the frontier has "
            "no row for: pricing another row at it is a decision about whether the "
            "two shapes route alike, not a transcription.")))
    path = out / "routing.json"
    with open(path, "w") as f:
        json.dump(doc, f, indent=1, sort_keys=True)
        f.write("\n")
    print(f"routing_stats: wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
