# Reproduce

One entry per driver, written when the driver's first run lands: the command
with its three arguments, the run ids it produced, the prover commit, the
digests, the binding table from the manifest, and the constants keys it backs.

Written, not yet run:

- `tools/drivers/predict-14b.sh`: Qwen2.5-14B's 48 layer segments at context
  4,096 on the reference backend, one proof per layer, measured against a
  registered prediction. Written and started; the extraction ran and the first
  layer did not prove. The rotation gadget requires the product of the block
  length and the attention head count to be a power of two, this model has 40
  heads, and 40 carries a factor of five that no block length divides out
  (zk-prover #73). The same is true of the campaign's fallback-large shape,
  which also has 40 heads. Separately, the prediction cannot be registered:
  the script that writes it cannot be imported (zk-prover #67), and a prediction
  written after the measurement is not a prediction.

- `tools/drivers/control-flags-off-c4096.sh`: `headline-c4096`'s plan with the
  five GKR reductions off, which is what prices them. Written and started; the
  first segment of the first token block does not prove in that configuration,
  and the prover stops on it (zk-prover #59). The plan begins with that block,
  so the control cannot be made on the same segments as the headline row until
  the prover is fixed. Nothing in the driver gets past it: the flags are what
  the control is. Meanwhile `gkr-ablation-c4096` prices the same five on a
  sample of segments that does not include that block.
- `tools/drivers/negative-controls.sh`: the control suite on one real segment of
  `headline-c4096`'s plan and on the three synthetic shapes. Written and run;
  the suite stops on its own assertion at its 22nd control, which is accepted
  where it has to be refused (zk-prover #60), and it writes its record only when
  it finishes, so the run produced no output to keep. The 21 controls before it
  were refused as designed, on the real segment and on each of the three
  synthetic shapes alike.

## synthetic-digests

    tools/drivers/synthetic-digests.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-07-synthetic-digests-h100
prover commit: e378539   harness commit: e378539
digests: first 16 hex, the same on both backends for each shape:
  `sound-simd.json`, `sound-cuda.json`: `82085896a8408f36`
  `sound_gkrfive-simd.json`, `sound_gkrfive-cuda.json`: `6bee5972d6f616aa`
  `sound_aligned-simd.json`, `sound_aligned-cuda.json`: `9c3cdebd97a7d57b`
binding (from the manifest, folded over the six proofs): unbound 3 and 5;
  1, 2, 4 and 6 to 14 bound; 15 and 16 absent
unsound skips: none
constants backed: none; a digest is a gate, not a number

What the run checks. A synthetic segment is a layer segment the prover makes
up: without a witness it draws the queries, keys, values, weights and the
residual-stream columns from a pseudorandom generator with a fixed seed, so
every machine builds the same segment, and nothing in it comes from a model or
from the harness. The proof over it is a real STARK with the same constraints,
the same binding gadgets and the same statement layout as a segment of that
shape taken from a model, and the verifier re-checks it from the serialized
bytes before the run reports `accepts`. The digest is SHA-256 over those proof
bytes and nothing else. A STARK proof is deterministic once the trace and the
parameters are fixed, so the SIMD backend and the CUDA backend must produce
byte-identical proofs: equal digests mean every committed column, every
constraint evaluation and every Merkle layer agreed on the device and on the
host. What a synthetic run leaves untested is only what a segment from a model
adds: the paper's shape (larger key tiles and tables, context 16,384), the
model commitment against the published root, and the extraction; that is what
the full-size reference run is for.

How the run is made. The harness commit is pinned and its source pushed, but
no harness step runs. The CUDA backend proves through device kernels generated
per segment shape, so the job emits the kernels for the three shapes into one
store, installs them into the vendored library and rebuilds; the built tree
then differs from the pushed commit, which is why the manifest records the
build as dirty. A `kernel fallback:` line on stderr would mean a lookup was
evaluated on the host instead of by its generated kernel; none appeared on any
of the three CUDA proofs, and the counts (0, 0 and 0) are in the `.fallbacks`
files beside the outputs.
## reference-digest

    tools/drivers/reference-digest.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-07-reference-digest-h100
prover commit: 5ca1070cc12c479adbbb236bd579e558c13ca8a3
harness commit: 5ca1070cc12c479adbbb236bd579e558c13ca8a3
digests: first 16 hex, the same on both backends:
  `reference-simd.json`, `reference-cuda.json`: `25741d12f315aae7`
binding (from the manifest, folded over the two proofs): 1 to 14 bound;
  15 and 16 absent; unbound none
unsound skips: none
constants backed: none; this run freezes a digest, not a number

What the run proves. One Llama-3.1-8B layer-16 segment, 512 output positions
against a 16,384-key prefix, under the fixed quantization configuration
`b10-final`: the full-size reference `zk-prover`'s digest gate names, and what
a synthetic run cannot reach. The dump is extracted with its own diagonal
block and with the residual-stream columns, so every binding gadget the sound
defaults switch on can be stated on it and the driver passes no skip flag;
edges 15 and 16 are absent because a layer-16 segment has neither the
embedding nor the output head. The segment is proved on the SIMD backend and
then on the CUDA backend of the same commit, and equal digests are the gate.
No `kernel fallback:` line appeared on the CUDA proof, and the count (0) is in
`reference-cuda.fallbacks` beside the outputs.

Three flags in the driver's command line differ from the reference command
`zk-prover` recorded before the sound defaults, and each is forced:

- `--diagonal-block` in place of `--unsound-skip-kv-boundary`, on both the
  extraction and the proof, which is what this run is for.
- `--round even` in place of `--round away`. `b10-final` rounds a half to
  even, and the dump's own `dequant_round` says so; an away-rounding prover
  builds tables whose keys this witness's values miss, 797 of them, the LogUp
  sums do not cancel and the honest proof is rejected. The prover does not
  read the dump's field, so the driver names the mode.
- the five GKR reductions, which are the paper's configuration and the layer
  flags of `tools/drivers/headline-c16384.sh`. Without them this segment's
  interaction tree is 93,184 columns wide; the vendored library's
  out-of-domain sampling puts the polynomial count in a thread block grid's y
  dimension, a device caps that at 65,535, and the CUDA backend stops with an
  invalid configuration argument. With the five flags the interaction tree is
  5,600 columns and both backends prove the segment.

How the run is made. The extraction reads the card, so every `uv` call selects
the harness's cuda group; it took 73 s and wrote 4.2 GB, and the driver keeps
the dump under the remote home and reuses it, so a second run at another
prover commit rebuilds, re-emits and re-proves without extracting again. A
dump is only reusable while the harness writes the same manifest keys. The
CUDA backend proves through device kernels generated per segment shape, so the
job emits the kernels for this one shape, installs them into the vendored
library and rebuilds; the built tree then differs from the pushed commit,
which is why the manifest records the build as dirty.

The same digest came out of an earlier run of this driver at another prover
commit, from a dump extracted on the host's CPU instead of the card, so
neither the extractor's device nor the renames between the two commits move
this proof.

## headline-c4096

    tools/drivers/headline-c4096.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-09-headline-c4096-h100
prover commit: 32e8fae   harness commit: 32e8fae
digests: 290, one per segment, in the manifest's `digests` map under the slice
  output that proved it; the first is `c6715532ede992fe` and the last
  `d965f874f9184f9d`
binding (from the manifest, folded over the 290 proofs): 1 to 16 bound, none
  absent and none unbound
unsound skips: none
links: 537 of 537 the grid implies ran and passed, 281 on the layer axis and
  256 on the token axis
verified: 290 of 290 segment proofs accepted; 4,096 prompt ids and 512
  generated ids chained, none wrong and none with no proved argmax behind it
kernel fallback lines: 0 on each of the five processes
constants backed: `cells.headline.c4096.fresh`, `mem.headline.c4096.peak_mib`,
  `positions.headline.c4096`, `rate.headline.c4096.commit`,
  `rate.headline.c4096.loop`, `rate.headline.c4096.stwo_total`,
  `rate.headline.c4096.whole_wall`, `secs.headline.c4096.commit`,
  `secs.headline.c4096.loop`, `secs.headline.c4096.stwo_total`,
  `secs.headline.c4096.whole_wall`, `segments.headline.c4096`,
  `pos_s.headline.c4096.loop`, `pos_s.headline.c4096.whole_wall`,
  `secs_per_position.headline.c4096.loop`,
  `secs_per_position.headline.c4096.whole_wall`,
  `usd_per_1k_positions.headline.c4096.loop`,
  `usd_per_1k_positions.headline.c4096.whole_wall`

What the run checks. A 4,096-token prompt and the 512 tokens the model goes on
to write are proved as one statement: nine token blocks of 32 layer segments and
two output head segments, 290 proofs. A layer segment's proof binds the
residual stream it consumed to the previous layer's output and the keys and
values it wrote to the next block's input, so the 290 proofs are not 290
separate claims;
`boundary-grid` compares each root a segment committed with the root the segment
that reads it committed, over the serialized statements and proofs and nothing
else. The first layer of every block binds the residual stream it starts from to
the rows of the embedding matrix that the block's published ids select. Every
proof's own binding table names each of the fourteen edges inside a segment as
bound, the embedding edge with them, and the edge from the logits to the emitted
token; the driver passes no skip flag and the manifest's list of them is empty.
The five GKR reductions are on, which is the paper's configuration.

The output head is proved over the last prompt block as well as over the
generated block, so the token every position emits is bound to the logits
computed for it. Two head segments and not one: a generated position's id has to
equal the argmax proved for the position before it, and the position before the
first generated one is the last position of the last prompt block, so a plan
with a head on the generated block alone leaves that one id backed by nothing
(docs/decisions/2026-09-08-the-head-is-proved-over-the-last-prompt-block.md).
The grid was run with `--verify --prompt`, which verifies every segment's proof
and chains every published id: each prompt position against the ids the
statement publishes, each generated position against the argmax a head segment
proved for the position before it. All 290 proofs accepted and all 4,608
positions chained.

What it does not check. Three ends are unchecked and the grid output names them:
each segment's shape root is compared only against its own statement, each
segment's model root only against its own proof rather than against a published
model commitment, and the tree-0 root of each chunk is the verifier's own
assertion that the root is this layer's and this shape's. `model-commitment`
publishes that commitment and makes both comparisons over this run's proofs.

How the run is made. The prompt is the evaluation corpus's tokens 12,288 to
16,383 -- the last 4,096 of the 16,384-token prompt the larger context reads, so
the two contexts read the same prose -- and the output is the model's own greedy
continuation under the reported quantization configuration, decoded once with
513 new tokens and once with 512 so that the two can be compared. The witnesses
are extracted on the card in five passes over the sequence, one per group of
layers, with the block-invariant files written once and shared; the head dumps
are one further pass, over the two blocks that carry a head segment, at the
layers' own quantization variant so that the head proves the argmax of the
residual stream the layers proved. That pass carries `--diagonal-block`: under
this variant the extractor checks the v fold's identity before it writes a chunk
and reads the diagonal block's `vvc` to do it, so it refuses a head dump made
without the flag. The head line in the plan carries no such flag, because the
head chunk performs no attention. The witnesses are kept on the host under a
directory named by the harness commit, and the campaigns that follow prove the
same ones. The CUDA backend proves through device kernels generated per segment
shape, so the job emits the kernels for every distinct shape in the plan into one
store, installs them into the vendored library and rebuilds; the built tree then
differs from the pushed commit, which is why the manifest records the build as
dirty. The link check runs on the SIMD backend of the same commit, which is why
the manifest names both backends. The serialized statements and proofs are kept
after the link check -- 870 files, 19.0 GiB, on the host -- because the model
commitment campaign checks each of them and cannot make them again for less than
this run's price.

Host time. The extraction took 771 s on the card over the five layer passes; the
head pass and the kernels for the plan's 48 distinct shapes were made in the same
job. The five proving processes' own loops took 742, 781, 815, 865 and 479
seconds, and the link check with verification took 170 s. The run was made over
three calls of the driver: the first stopped at the kernel install, because the
pinned prover commit renames those two scripts (zk-prover #108) and this
repository's drivers had not yet been rebased onto the rename; the second proved
the first four slices and stopped on the last, because the plan's emit list holds
one head line for two head blocks and the second head's feed kernels were never
generated (zk-prover #131). Neither attempt produced a proof that is kept: a
slice whose output is written is not proved again, so the four slices the second
attempt proved are this run's, and the third attempt emitted the missing shapes,
rebuilt and proved the last slice.

The run of 2026-09-07 is superseded and no constant points at it any more. That
run proved 288 segments and no output head, so nothing bound the token a position
emits to the logits computed for it, and its published ids were compared against
no prompt. The two are not a run-to-run pair: they prove different statements,
over a different number of segments, at a different prover commit. Its directory
stays under `runs/` because the record of what was measured is not rewritten.

## gkr-ablation-c4096

    tools/drivers/gkr-ablation-c4096.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-07-gkr-ablation-c4096-h100
prover commit: aed0f37   harness commit: aed0f37
digests: 224, one per proof, in the manifest's `digests` map under the
  configuration that proved it: 32 for each of the seven
binding (from the manifest, folded over the 224 proofs): 1 to 15 bound; 16
  absent, because the sample is layer segments and no output head
unsound skips: none
kernel fallback lines: 0 on each of the seven processes
constants backed: `segments.ablation.c4096`, `cells.ablation.c4096.<name>` and
  `secs.ablation.c4096.<name>.loop` for each of the seven configurations, and
  `gkr.ablation.<name>.leave_frac_cells` for the six that remove anything

What the run checks. One sample of segments proved seven times: the 32 layer
segments of the last token block of `headline-c4096`'s plan, which is the block
with the longest prefix and therefore the one where the reductions weigh most.
The seven configurations are no reduction at all, the key tiles' reduction
alone, each of the other four on top of it, and all five together. Every one of
them proves the same witnesses under the same shared pins with every binding
gadget on and no skip flag, so the seven differ in their proofs and not in what
they claim, and what one reduction removes is read off the pair that differ in
it alone.

Four of the five are not configurations on their own. The dequantization
gadgets, the residual stream, the Freivalds checks and the attention output all
join the key tiles' own reduction rather than standing up one of their own, and
the prover refuses each of them without it: "it composes with `--gkr-bands`; it
does not replace it". So the sample prices each of the four against the key
tiles, and the key tiles against no reduction at all.

What the run says. The five together remove 37.8 per cent of the committed
cells. They remove no time: the seven loop times lie between 450.6 and 456.7
seconds, a spread of six seconds on runs of seven and a half minutes, so at this
shape and on this card the reductions buy committed cells and not wall-clock
time. The commitment path alone does move with them, from 34.1 seconds with none
to 21.4 with all five, but the commitment path is 5 per cent of the loop here and
the rest does not follow it. The peak the card reported holding follows the cells
closely, from 75.4 GiB with none to 65.9 GiB with all five.

The labels this run gave its seven configurations -- `bands`, `bands_dequant`
and the rest -- were written before the key tiles were renamed, and the run's own
outputs are named by them, so the constants keyed on them keep the older noun.
The driver's flags are the current ones.

How the run is made. The witnesses are the ones `headline-c4096` extracted, and
the driver refuses to run without them rather than extracting a second set: a
comparison across configurations is only a comparison if the witnesses are the
same. Each configuration's plan is written over the whole sequence, so a line is
the line the headline plan carries, and then the sample block's lines are taken
out of it; the distinct kernel shapes among them are emitted into the one store,
the store is installed once and the CUDA backend is rebuilt once, and the seven
are proved one process each, pipelined. No statement is serialized: the sample
is one token block, and what this run measures is the price of a reduction
rather than the chain, which the headline run checks over the whole sequence.
## memory-probe-c16384

    tools/drivers/memory-probe-c16384.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-07-memory-probe-c16384-h100
prover commit: 81a5ec9   harness commit: 81a5ec9
digests: the four segments of the compared loops, first 16 hex, the same
  whether the loop was pipelined or not:
  `cd28d8a02717a76d`, `21b745e99128a861`, `7185c76c704a8f87`, `169e3b2ae3a397c8`
  and the first of them again from the reference backend, in `reference-simd.json`
binding: 1 to 15 bound; 16 absent   (from the manifest)
unsound skips: none
constants backed: `segments.probe.c16384`, `cells.probe.c16384.fresh`,
  `mem.probe.c16384.{serial,pipelined,layer0,pipelined_l0}_peak_mib`,
  `secs.probe.c16384.{serial,pipelined,layer0,pipelined_l0}_loop`

What the run measures. Whether the headline sequence at context 16,384 fits an
80 GB card, and what it would cost. The sequence is 33 token blocks of 32 layer
segments; a block's segments grow with the prefix it reads, so the last block's
are the largest in the whole plan and they are what sets the peak. The probe
extracts that block alone and proves four of its segments twice, once with the
pipeline off and once with it on, the same four segments in the same order both
times, sampling the card once a second while each loop runs. Layer 0 is measured
twice more, on its own and paired with layer 1 under the pipeline, because its
statement carries the embedding gadget and it is the largest segment in the
plan: the pair that decides whether the campaign can be pipelined is the one
containing it.

Four segments are not a sequence and no number here is a throughput row. They
prove no statement about a prompt and its output, the plan they are sliced from
has no output head in it, and the run's label is `probe`, so a reader of the run
directory cannot mistake it for a headline. What they do carry is every binding
gadget the sound defaults switch on, and the driver passes no skip flag, so a
segment that could not state one would have been refused rather than proved.

The same segment is proved again on the reference backend, which proves in host
memory and so cannot run the card out of it. That proof is the run's provenance
anchor: a loop the card cannot hold writes no output at all, and without an
anchor the answer most worth recording could not be recorded. It is also a
digest gate. Its proof bytes hash to what the card's proof of the same segment
hashed to, which is the first time the two backends have been compared on a
segment of the headline plan at this context under the variant the paper
reports; the digest frozen before it was a single layer under the output head's
variant.

How the run is made. The extraction runs the whole forward pass over all 33
blocks either way, because a block reads the keys and values of every block
before it; only the last block's dumps are written, which is what makes the
probe affordable on disk where the whole plan's extraction is not. Layer 0 is a
pass of its own because the embedding table is written into every dump of the
pass it is given. The CUDA backend proves through device kernels generated per
segment shape, so the job emits the kernels for this block's six shapes,
installs them into the vendored library and rebuilds; the built tree then
differs from the pushed commit, which is why the manifest records the build as
dirty.
## microbench

    tools/drivers/microbench.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-07-microbench-h100
prover commit: 81a5ec9   harness commit: 81a5ec9
digests: `compose-simd.json`: `917645a0e83a04aa`
binding: 1 to 14 bound; 15 and 16 absent   (from the manifest); a synthetic
  segment has neither an embedding row nor an output head
unsound skips: none
constants backed: `cells.microbench.compose_fresh`,
  `secs.microbench.compose_commit`, `rate.microbench.commit`,
  `hash.merkle_simd_secs`, `hash.merkle_cpu_secs`, `field.m31_mul_secs`,
  `field.m31_add_secs`, `field.qm31_mul_secs`, `field.m31_mul_simd_secs`,
  `lookup.simd_generic_logup_secs`, `lookup.cpu_generic_logup_secs`,
  `fri.fold_line_secs`

What the run measures. What the proof system charges, in the two units the cost
model prices a proof in: seconds per committed cell, and seconds per operation
of the primitives underneath. Nothing here touches a card and nothing here is a
throughput row.

One composed segment on the reference backend, of the shape the prover records
as its aligned sound synthetic one, with the five reductions on. It is the only
thing in this run that proves anything and therefore the only thing that writes
a binding table, so it is what makes the run admissible; its own committed cell
count over the seconds its commitment path took is the commitment rate the cost
model reads. The segment is drawn from a pseudorandom generator with a fixed
seed, so nothing in it comes from a model and no extraction runs.

Then the vendored library's own benchmarks of the primitives: multiplication and
addition in the base field and in the extension field the challenges live in,
one logarithmic-derivative lookup argument, one Merkle commitment, and one
folding step of the low-degree test. Each is frozen as the time the benchmark
reports, not as a rate, so the audit re-derives it from the estimate file
without carrying any number of its own; each constant's note says what one
iteration of that benchmark does and the benchmark source says the same.

What the run could not measure. Seven subcommands of the prover -- the ones that
price one dequantized accumulator, one requantized value, one residual-stream
operation, one argmax comparison, one packed attention instance, the width sweep
and the table sweep -- refuse to run at this prover commit. Each panics the same
way inside the vendored library, on its own default arguments, on the reference
backend; the run records each refusal in `out/refused.txt` and goes on.
`compose` on the same binary and the same tree is unaffected. Those seven are
where the cost model's cells-per-operation inputs come from, so this run backs
none of them and the campaign is part of its issue rather than the end of it.
The eighth refusal is the polynomial-commitment benchmark, which does not
compile against the library it benchmarks.

How the run is made. The prover is built once at the pinned commit and the
benchmarks are built from the same tree, so the primitives timed are the
primitives the segment was proved with. The benchmarks are given ten samples and
five seconds of measurement each, which is enough for a rate and keeps the run
inside its half hour; the estimate files the audit reads carry the mean and its
standard error, and every mean here is within a per cent of its own error.

## quality-0p5b

    tools/drivers/quality-0p5b.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-07-quality-0p5b-h100
prover commit: none -- this run builds and runs no prover
harness commit: 5c0dbfe
digests: none; this run makes no proof
binding: none; this run makes no proof
unsound skips: none
constants backed: `quality.0p5b.ppl_*` for each of the sixteen variants, and
  `quality.0p5b.ppl_*_delta_pct` with `_se_nats` for the reported variant, the
  fixed configuration and the three baselines

What the run measures. The perplexity of Qwen2.5-0.5B-Instruct under every
quantization variant `docs/quantization.md` names, on the host's cores, over
forty chunks of 512 tokens of the fixed corpus: 20,440 scored positions, the
same positions for every variant. The small model is where a variant's cost
shows up largest and cheapest to measure, and where the sequence of
configurations that led to the reported one can be priced in full without a
card.

It is a harness run and not a prover run. Nothing in it proves anything: it
measures the arithmetic the prover constrains, which is what makes
`docs/quantization.md`'s claim -- that the quality numbers describe exactly the
arithmetic that is proved -- a claim about measured things on both sides. So its
outputs carry no binding table and no proof digest, its manifest says `kind`
`harness` and names no prover commit, and `lib/manifest.py` has a second path
for exactly that shape of run. The prover commit argument is unused.

Every variant is scored on the same chunks of the same corpus, and the corpus is
named by its digest in every output, so two variants' perplexities are
comparable and the difference between them is paired over positions. The harness
computes each difference and its standard error from the per-token losses, and
writes them beside the rows; this repository reads them back rather than
recomputing them, because the error of a difference measured on the same
positions is not the error of either perplexity on its own and there should be
one place it is worked out.

How the run is made. One process per variant, so peak memory stays at one model,
and a variant already in the file is not measured again -- a job that was
interrupted is restarted for the price of what it did not finish. The harness
writes its calibration files and its token cache into a working directory beside
the run's outputs and not into them: those are inputs, they are specific to the
model, and a run directory holds outputs. What is fetched is the rows, the
per-token losses they were computed from, COSINE and nothing else.

## quality-gemma270m

    tools/drivers/quality-gemma270m.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-07-quality-gemma270m-h100
prover commit: none -- this run builds and runs no prover
harness commit: 5c0dbfe
digests: none; this run makes no proof
binding: none; this run makes no proof
unsound skips: none
constants backed: `quality.gemma270m.ppl_*` for the four variants,
  `quality.gemma270m.ppl_*_delta_pct` with `_se_nats` for the three that are
  compared against the float reference, and `quality.gemma270m.cosine_*`

What the run measures. Whether the quantization configuration the paper
reports costs the same on a model it was not designed against. Gemma-3-270M
interleaves sliding-window attention layers with full-attention ones, so its
keys and values are not the shape the configuration was tuned on, and a
variant that only works on the model it was fitted to would show here.

Two statistics, because a perplexity alone does not answer it. The perplexity
says what the configuration costs; the cosine similarity of the whole logit
vector against the float reference says how far the distribution moved, which
is what a published comparison of quantized models reports and which a
perplexity can hide. Both are measured on the same forty chunks of 512 tokens
of the same corpus the other quality campaigns use, so the two models' rows
are read against each other and not against different text.

It is a harness run and not a prover run. Nothing in it proves anything: it
measures the arithmetic the prover constrains, which is what makes
`docs/quantization.md`'s claim -- that the quality numbers describe exactly the
arithmetic that is proved -- a claim about measured things on both sides. So its
outputs carry no binding table and no proof digest, its manifest says `kind`
`harness` and names no prover commit, and `lib/manifest.py` has a second path
for exactly that shape of run. The prover commit argument is unused.

Every variant is scored on the same chunks of the same corpus, and the corpus is
named by its digest in every output, so two variants' perplexities are
comparable and the difference between them is paired over positions. The harness
computes each difference and its standard error from the per-token losses, and
writes them beside the rows; this repository reads them back rather than
recomputing them, because the error of a difference measured on the same
positions is not the error of either perplexity on its own and there should be
one place it is worked out.

How the run is made. One process per variant, so peak memory stays at one model,
and a variant already in the file is not measured again -- a job that was
interrupted is restarted for the price of what it did not finish. The harness
writes its calibration files and its token cache into a working directory beside
the run's outputs and not into them: those are inputs, they are specific to the
model, and a run directory holds outputs. What is fetched is the rows, the
per-token losses they were computed from, COSINE and nothing else.

## quality-suite

    tools/drivers/quality-suite.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-08-quality-suite-h100
prover commit: none -- this run builds and runs no prover
harness commit: 5c0dbfe
digests: none; this run makes no proof
binding: none; this run makes no proof
unsound skips: none
constants backed: `quality.8b.ppl_*` for each of the sixteen variants and the
  paired difference of five of them, `quality.8b.{gpqa_d, mmlu_pro,
  ifeval_prompt_strict}_*` for both configurations and their paired difference,
  and `suite.decode_positions` with `suite.e11_positions`

What the run measures. What the quantization configuration the paper reports
costs on the model the paper reports, in the two ways a reader will ask. First
perplexity, under every variant `docs/quantization.md` names, on forty chunks of
512 tokens of the fixed corpus: 20,440 scored positions, the same positions for
every variant. Then three task suites -- a graduate-level science set, a subset
of a professional knowledge set, and an instruction-following set -- under the
reported variant and under a float control that answers the same items in the
same order.

The control is what makes the task numbers mean anything. Two accuracies
measured on the same items are not two independent samples: the items both
configurations get right carry no information about the difference between them,
so the error on that difference is built from the items they disagree on and is
far smaller than the error on either accuracy. The harness computes it item by
item and writes it beside the scores, and the difference is what the paper
claims something about.

It is a harness run and not a prover run. Nothing in it proves anything: it
measures the arithmetic the prover constrains, which is what makes
`docs/quantization.md`'s claim -- that the quality numbers describe exactly the
arithmetic that is proved -- a claim about measured things on both sides. So its
outputs carry no binding table and no proof digest, its manifest says `kind`
`harness` and names no prover commit, and `lib/manifest.py` has a second path
for that shape of run. The prover commit argument is unused.

How the run is made. The three task sets are not carried in either repository
and are fetched from their published locations, each timed and sized into the
run's own configuration record and named afterwards by digest in every output
that read it. Four packages the harness's lockfile does not carry are brought in
for the commands that need them and never written into the pinned environment:
two to read a parquet file, and two the instruction checkers need. A task lane
whose items are all answered is not run again and a variant already measured is
not measured again, so the scoring can be redone without regenerating anything
-- which is what happened here, because the first attempt reached the scoring
step and stopped on a package the instruction checkers import and do not name.

What is fetched is the perplexity rows, the per-token losses they were computed
from, the task scores, and the per-item answers those were computed over.

The per-item rows kept under `tasks/` carry each item's id and its prompt and
generated token counts, which is what the audit reads; the generated text
itself stays on the host, since it is the model's output and not a measurement.

## prefill-sweep

    tools/drivers/prefill-sweep.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-08-prefill-sweep-h100
prover commit: 81a5ec9   harness commit: 81a5ec9
digests: one per point, in `dd_s256.json` and its three siblings
binding: 1 to 14 bound; 15 and 16 absent   (from the manifest); a synthetic
  segment has neither an embedding row nor an output head
unsound skips: none
constants backed: `cells.b9_prefill.c*.key_tiles` and `.fresh` at four block
  lengths, `design.prefill_key_tile_s_squared`, `design.prefill_key_tile_s`

What the run measures. What one layer segment costs in committed cells as the
block it proves grows, with the context equal to the block length, at 256, 512,
1,024 and 2,048. The segment is synthetic: without a witness the prover draws
the queries, keys, values, weights and the residual-stream columns from a
pseudorandom generator with a fixed seed, so nothing in it comes from a model
and no extraction runs. What moves between the four points is the block length
and nothing else.

The number the cost model wants is the price of the attention key tiles, which
is the part of a segment that grows with the square of the block length while
everything else grows with the length itself. That part is counted on its own,
so the rest of the segment does not dilute it, and the four points give it
exactly: 24 cells per squared block length and 784 per block length, reproducing
all four measured counts with a residual of zero over an eightfold range. That
is a closed form read off a measurement rather than a fit with an error.

Which arithmetic, and why not the paper's. A synthetic layer under the softmax
variant the paper reports cannot be proved at any of these block lengths. Its
master table is sized from its own data and clamped to 2^22 rows, the data needs
23 bits of key, and neither pinning the width nor asking for a tight table
raises the clamp; the honest proof is rejected on values that fall off the table
(zk-prover #72). The run proves one small block under both variants to compare
their key-tile counts, finds that the paper's does not prove even there, records
that, and sweeps under the variant that has no exponential table. Every constant
the run backs says which variant it is, and none of them is the paper's
attention grid.

What the shape is, and what it is not. Four attention heads of 32 channels in
two key tiles, with the matmul widths equal to their product, which is what lets
every edge bind: at a head count and head dimension whose product the matmuls do
not match, the attention output and the o matmul run over different sequences
and two edges of the statement have no counterparty. It is not the 8B model's 32
heads of 128, which cannot be proved synthetically for the same table reason.

What the sweep cannot separate. The cost model's key-tile term has three
coefficients, one on the product of the block length and the context, one on the
context and one on the block length. With the context set equal to the block
length the first two multiply the same quantity, so two coefficients come out
and three do not. Separating all three needs points where the context and the
block length differ, which this campaign's issue puts out of scope.

How the run is made. Every pin is named in the driver and none is left to the
layer, so the points differ in the block length alone. The reference backend
proves all of them: this is a cell count and a shape, the two backends prove the
same statement to the same digest, and the largest point is bounded by host
memory rather than by the card. The whole sweep is 73 seconds of proving.

## headline-c16384

    tools/drivers/headline-c16384.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-08-headline-c16384-h100
prover commit: 355c19d   harness commit: 355c19d
digests: 1,058, one per segment, in the manifest's `digests` map under the slice
  output that proved it; the first is `8ad70411f2ee0016` and the last
  `be4e9f38c17a36ac`
binding (from the manifest, folded over the 1,058 proofs): 1 to 16 bound, the
  embedding edge and the head's logits-to-token edge among them; none unbound,
  none absent
unsound skips: none
links: 2,049 of 2,049 the grid implies ran and passed, 1,025 on the layer axis
  and 1,024 on the token axis
ids: 16,384 prompt positions checked against the run's own published prompt and
  512 generated positions against the token a head proved for the position
  before, 0 wrong and 0 unbacked
kernel fallback lines: 0 on each of the 20 processes
constants backed: `cells.headline.c16384.fresh`, `mem.headline.c16384.peak_mib`,
  `pos_s.headline.c16384.loop`, `pos_s.headline.c16384.whole_wall`,
  `positions.headline.c16384`, `rate.headline.c16384.commit`,
  `rate.headline.c16384.loop`, `rate.headline.c16384.stwo_total`,
  `rate.headline.c16384.whole_wall`, `secs.headline.c16384.commit`,
  `secs.headline.c16384.loop`, `secs.headline.c16384.stwo_total`,
  `secs.headline.c16384.whole_wall`, `segments.headline.c16384`

What the run checks. A 16,384-token prompt and the 512 tokens the model goes on
to write are proved as one statement: 33 token blocks of 32 layer segments and
two output head segments, 1,058 proofs. A layer segment's proof binds the residual stream it consumed to
the previous layer's output and the keys and values it wrote to the next
block's input, so the 1,058 proofs are not 1,058 separate claims; a head
segment binds the residual its final norm consumed to the last layer's output
and proves which token the logits at each of its positions make the largest.
`boundary-grid` compares each root a segment committed with the root the
segment that reads it committed, over the serialized statements and proofs and
nothing else, and it is given the run's own prompt: every prompt position's
published id is compared against that file and every generated position's
against the token a head proved for the position before it. The first layer of
every block binds the residual stream it starts from to the rows of the
embedding matrix that the block's published ids select. Every proof's own
binding table names each of the fourteen edges inside a segment as bound, the
embedding edge with them and the head's edge as well; the driver passes no skip
flag and the manifest's list of them is empty. The five GKR reductions are on,
which is the paper's configuration.

Why the head sits over two blocks. The first generated token's id is the
argmax of the logits at the last prompt position, so a plan with a head over the
generated block alone leaves that one id compared against nothing and the grid
reports it unbacked
(docs/decisions/2026-09-08-the-head-is-proved-over-the-last-prompt-block.md).
The head over block 31 closes it, and it is why this plan is 1,058 segments and
2,049 links where issue #1 asked for 1,057 and 2,047. Both head chunks sit at
layer coordinate 32, one past the last layer, and each emits 512 tokens.

What it does not check. Two ends, and the grid output names them: each segment's
shape root is compared only against its own statement, and each layer's model
root -- the grid reads 33 distinct ones and none is missing -- only against the
proofs that carry it, not against a published model commitment. The head chunk
commits no tree 4, so it is the last chunk of the layer axis and its norm's
output is nobody's residual.

How the run is made. The prompt is the evaluation corpus's first 16,384 tokens
and the output is the model's own greedy continuation under the reported
quantization configuration, decoded once with 513 new tokens and once with 512
so that the two can be compared. The whole witness set at this context is 302
GiB against about 76 GiB free, so the job never holds it: it extracts a few
token blocks, writes each block's shape table and emits its device kernels while
the dumps are still there, deletes the dumps and goes on to the next few; then
it installs the kernels once, rebuilds the CUDA backend, and extracts each group
a second time to prove it. How many blocks a group holds is measured and not
written down -- the job divides the free space it sees by the block size it
measured, up to five -- and it came out five blocks for six groups and three for
the last. One block of this context is 13,060,046,978 bytes at block 32 falling
to 7,020,248,456 at block 0, and the block-invariant files another
8,047,558,656; `disk.json` and `groups.json` carry what the job measured. The
groups run highest block first, because `ao_rem_bits` and the master table width
grow with the prefix a block reads and the pins the emitters are given have to
be the pins the proving processes are given. The link check runs on the SIMD
backend of the same commit, which is why the manifest names both backends.

The head. The first pass of this run extracted the output head under
`b10-final`, a driver default inherited from `headline-c4096.sh` where it never
mattered because that plan carried no head segment. The two specs give the
`lm_head` matmul the same arithmetic but not the same residual stream, so the head proved the argmax of a
model the 1,056 layer segments do not prove; the head dump's own manifest said
so at extraction time, `emits_next_token` 477 of 511. The per-group
verification caught it: every proof of the group holding the head verified, and
34 of the 511 generated positions failed the check that a position's published
id is the token the head proved for the position before it. The layer proofs
were kept, both heads were re-extracted under `y-delay-vw12` and proved, and the
final grid covers 1,058 segments -- 1,025 links on the layer axis and 1,024 on
the token axis. The head line's `--ao-rem-bits` is read off the head dumps' own
shape rows, which came out as 15, where the driver used to pin 23. A head dump
under the layers' variant is extracted with `--diagonal-block`: `y-delay-vw12`
delays the v matmul, so the extractor checks the v fold's identity against the
diagonal block's `vvc` before it writes the chunk and refuses a dump made
without the flag. The head line itself carries no `--diagonal-block`, because
the head chunk performs no attention.

Which check ran where. Every one of the 1,058 chunk proofs was replayed by the
verifier on its whole serialized bytes -- 1,024 of them group by group as the
run went, recorded in `verify-g<blocks>.json`, and the 34 the fix-up re-proved
in `verify-fixup.json`. Every implied link was checked once over all 1,058
segments at the end, and so was every published id, against `prompt.json` for
the 16,384 prompt positions and against a head's proved argmax for the 512
generated ones. The final grid did not re-run the verifier: 1,058 whole proofs
are about 108 GiB against a 216 GiB volume, so each group's proofs were shrunk
to the roots the grid reads once the verifier had accepted them, and
`proofs-g<blocks>.json` carries the sha256 and the size of every proof as the
prover wrote it. `proof_bytes` in `grid.json` is therefore the shrunk size and
not the proof's for the 1,024 that were shrunk, 1,447 to 1,931 bytes; the 34 the
fix-up re-proved were never shrunk and theirs is the true size, 118.0 to 163.9
MiB.

Host time. The extraction took 19,065 s on the card over 70 passes, 9,330 s in
the survey sweep and 9,735 s in the prove sweep. The kernels for the plan's
distinct shapes were installed and compiled in 1,204 s. The seven groups of the
first pass took 7,285, 6,567, 5,464, 4,420, 3,647, 3,041 and 1,762 seconds of
wall-clock time, highest block first, each including its own extraction of
2,023, 1,938, 1,693, 1,374, 1,162, 897 and 596 s; the fix-up pass took 4,525 s
end to end, of which 2,075 s re-extracted group 28-32 and 1,089.7 s of segment
loop proved the 34 segments. The link check over all 1,058 segments took 12 s.
The 1,057 proofs the first pass wrote were 49.6 to 163.9 MiB each and 108.8 GiB
in all, and a segment's statement as the grid reads it is 99,710 to 319,425
bytes. The card held at most 78,799 MiB of the 81,559 MiB it reports.

The run directory's `groups.json` is the fix-up pass's and reads zero for the
six groups it did not touch, because the job writes it from the last row per
group; `groups.jsonl` beside it carries every row of every pass, which is where
the seven group times above come from.

Three workarounds are in the driver and each names its issue. The token
generator is run through a shim, because it imports a module under a name that
does not resolve (zk-prover #51); the layer-0 dumps are moved into the name the
shape table and the plan read, because a one-layer extraction writes another
(zk-prover #55); and the two kernel install scripts are called by whichever name
the prover commit has, because zk-prover #108 renamed them after this run was
pinned. A fourth defect is recorded rather than worked around: the kernel
emitter refuses the shape of the block with no prefix, so that one shape's
generation kernels are not in the store (zk-prover #57), and
`genemit-refused.txt` in the run directory says which line it was. It cost
nothing measurable: no lookup took the host route on any of the 20 processes.

## reference-digest-plain

    tools/drivers/reference-digest-plain.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-08-reference-digest-plain-h100
prover commit: a603db1ddf1e2372d1f9761d684df8f2294199a9 (zk-prover pull request 107)
harness commit: a603db1ddf1e2372d1f9761d684df8f2294199a9
digests: first 16 hex:
  `full-simd.json`, `full-cuda.json`: `05580c4a4b766666`
  `short-simd.json`, `short-cuda.json`: `65d588904d613bff`
  `plain-simd.json`: `d2f2afd860a491d9` (the reference backend only; see below)
binding (from the manifest, folded over the five proofs): 1 to 14 bound;
  15 and 16 absent; unbound none
unsound skips: none
constants backed: none; this run freezes digests, not numbers

What the run proves. Two statements about the same Llama-3.1-8B layer 16, under
the fixed quantization configuration `b10-final`, each with its own diagonal
block and the residual-stream columns and no skip flag: the reference segment,
512 output positions against a 16,384-key prefix with the five GKR reductions
on, which is the paper's configuration; and the short segment, 128 output
positions against a 4,096-key prefix with none of them on. Each is proved on
the SIMD backend and then on the CUDA backend of the same commit, and equal
digests are the gate.

What the short segment is for. Without the reductions the segment's key tiles
each publish their own interaction columns, and the vendored library's
out-of-domain sampling evaluates the polynomials of one size in a single launch
with the polynomial index in a thread block grid's y dimension, which a device
caps at 65,535. zk-prover pull request 107 launches that axis in slices of at
most that many; the evidence a card has to give it is a proof whose sampling
axis is wider than the cap and whose digest is the reference backend's. The
short segment's interaction tree is 102,608 columns wide, 80,424 of them key
tiles, against the reference segment's 93,184 and 70,920.

The reference segment's digest is not the one `prover/README.md` records.
The page records `25741d12f315aae7`, taken on 2026-09-07 at another prover
commit and from a dump another harness commit wrote; at the commit this run
pins, the same command on the same statement proves 05580c4a4b766666 on both backends.
Thirty-seven prover commits and a changed extractor lie between the two, so
which of them moved it is not this run's to say; the comparison is recorded in
`full-digest.json` and the digest that stands at this commit is the one above.

Why the block length moves rather than the context. The key tile count follows
the key blocks -- the prefix and the segment's own block, in blocks of S keys
-- times the head groups, not the context on its own. Both segments here have
33 key blocks and three head groups, so the short segment stays past the cap
while committing 1,227,190,880 cells against the reference segment's
4,131,033,024. Lowering the context alone does the opposite: at 512 output
positions a shorter prefix has fewer key blocks and the axis falls back under
the cap, which is what zk-prover #29 saw from the other side when it put the
threshold at a 15,872-key prefix.

The reference segment without the reductions is proved here on the reference
backend only: it does not fit this card. Its CUDA proof was attempted once, at
this prover commit on 2026-09-08, and stopped in the quotient stage
(`quotients.cu:370`, out of memory) with 82.2 GB of the 85.0 GB the driver
reports in use at the composition commitment and a 256 MB allocation refused;
the card was otherwise empty. The driver does not attempt it again, and
`out/plain-cuda-refused.json` records that, the shape's committed cells and the
memory the card reports.

How the run is made. The extractions read the card; the reference segment's
dump is the one `reference-digest.sh` leaves under the remote home and is
reused, and the short segment's is extracted in seconds. The CUDA backend
proves through device kernels generated per segment shape, so the job emits the
kernels for both shapes that run on the card, installs them into the vendored
library and rebuilds; the built tree then differs from the pushed commit, which
is why the manifest records the build as dirty.

## unproved-baseline

    tools/drivers/unproved-baseline.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-08-unproved-baseline-h100
prover commit: none; this run proves nothing   harness commit: 3c876f55fb5ece2565355aa1e4dc59b36fbd855d
digests: none; a harness run carries no proof
binding: none; a harness run binds nothing
unsound skips: none
constants backed: `pos_s.unproved.<backend>.c<context>.b<batch>.{prefill,decode,end_to_end}`,
  57 of them: three rates at each of 19 points

What the run measures. Llama-3.1-8B-Instruct on the card, in bf16, prefilling a
prompt and decoding 512 tokens after it, at the two contexts the proved rows are
measured at and over a range of batch sizes, with nothing proved about any of
it. These are the rows a proved cost per position is read against.

What a rate is. Every recorded rate is positions per second for one request:
the prompt's positions over the prefill's wall-clock time, the generated
positions over the decode's, and every position over the whole pass's. A host
serving B requests at once produces B times the recorded rate; the entries are
per request so that the single-request row and the batched rows are the same
kind of number. The two parts fall one position short of the end-to-end count,
because the first generated position is produced inside the prefill call and is
charged to neither part.

Why three and not one. The paper quotes a cost per proved position and the
reader applies their own mix of prompt and generated positions, so no row here
is an overhead denominator and none of them subtracts the prompt out (the
decisions of 2026-09-08 in `docs/decisions/`). A reader who wants a prefill-only
comparison takes the prefill rate; one who wants decode takes the decode rate;
one who wants a whole request takes the end-to-end rate.

The two backends answer different questions. `hf` is what a reader gets by
loading the model and calling it, and `vllm` is what a reader gets by deploying
it. Both ran here. The serving engine decodes 2.5 times as fast at a single
request and 2.2 times as fast at 16, and it holds a batch of 16 at the longer
context where the other backend cannot: at a 4,096-token prompt it decodes
153.3 positions per second per request against 62.3, and at 16,384 it decodes
140.3 against 62.6. A reader who takes one of these as "what the model runs at"
picks a number that differs by more than a factor of two depending on which
backend they had in mind, which is the reason both are here.

Where the sweep stops. The backend that ships with the model library runs out
of card memory at a 16,384-token prompt and 16 requests at a time: it asks for
another 7.00 GiB with 4.76 GiB free of the 79.18 GiB the card reports it, having
74.41 GiB in use. Every other point of the sweep fits, and the serving engine
fits all twenty. That is a measurement of the card and not
a gap in the run: the harness records such a point with its reason, and the
gate reads that record rather than demanding a number the card cannot
produce.

What the spread means. Each point is three timed repetitions after one untimed
warmup, and the recorded value is the median over them of that repetition's own
rate. The warmup makes the same two calls a timed repetition makes and generates
the same 512 tokens, which is what tells a reader this record apart from one
made before it: the warmup used to generate 8 tokens, so the first timed
repetition of every point was the first long decode its process had run, and the
recorded spread was tens of times the run's own variation (zk-prover #106). The
spread recorded here is 3 per cent at its widest, and under 1 per cent at
most points.

What the run does not check. Nothing here is proved, so there is no binding
table, no digest and no statement: the manifest says `kind` `harness` and names
no prover commit. The generated text is not compared between the two backends,
and the harness's own digest of it is not stable across repetitions of the same
greedy point (noted in zk-prover #106). Nothing here says the two backends
compute the same tokens; they are timed, not compared.

How the run is made. The driver pushes the harness at its pinned commit, syncs
the environment the model library needs and builds a second one for the serving
engine, which is never committed; the weights come from the machine's cache. A
timing that shares a card is not a timing, so the run is started only with the
card empty and with the machine's other work held off it, and afterwards the
machine's own logs are read to see whether anything else ran while it did.
Nothing did here: no other job wrote a line between this run's first stamp and
its last, and the card read 0 MiB at both ends. It takes 18 minutes, ten of them
the first backend.

## Entry template

```
## <driver>

    tools/drivers/<driver>.sh <host> <prover-commit> <harness-commit>

runs: <run-id>, ...
prover commit: <hash>   harness commit: <hash>
digests: <artifact>: <digest>, ...
binding: bound <edges>; unbound <edges>   (from the manifest)
unsound skips: none
constants backed: <keys>
```
