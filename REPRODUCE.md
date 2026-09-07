# Reproduce

One entry per driver, written when the driver's first run lands: the command
with its three arguments, the run ids it produced, the prover commit, the
digests, the binding table from the manifest, and the constants keys it backs.

Written, not yet run:

- `tools/drivers/headline-c16384.sh`: the paper's headline configuration, one
  16,384-token prompt and its 512 output tokens proved from the embedding up,
  on the CUDA backend, pipelined. Written on `lib/sequence-job.sh`, which is the
  job body the context 4,096 campaign ran. It waits on disk, not on the card:
  `memory-probe-c16384` measured the loop at 78,843 MiB of an 81,559 MiB card,
  and measured one token block of this context's witness at 12.16 GiB, so the
  33 blocks the plan reads are 310 GiB of extraction. Its `pipeline` is 1
  because that probe measured the pipeline to cost nothing on this card.
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

runs: 2026-09-07-headline-c4096-h100
prover commit: aed0f37   harness commit: aed0f37
digests: 288, one per segment, in the manifest's `digests` map under the slice
  output that proved it; the first is `c6715532ede992fe` and the last
  `49f2772888718f64`
binding (from the manifest, folded over the 288 proofs): 1 to 15 bound; 16
  absent, because the output head's segment is not in this plan
unsound skips: none
links: 535 of 535 the grid implies ran and passed, 279 on the layer axis and
  256 on the token axis
kernel fallback lines: 0 on each of the five processes
constants backed: `cells.headline.c4096.fresh`, `mem.headline.c4096.peak_mib`,
  `positions.headline.c4096`, `rate.headline.c4096.commit`,
  `rate.headline.c4096.loop`, `rate.headline.c4096.stwo_total`,
  `rate.headline.c4096.whole_wall`, `secs.headline.c4096.commit`,
  `secs.headline.c4096.loop`, `secs.headline.c4096.stwo_total`,
  `secs.headline.c4096.whole_wall`, `segments.headline.c4096`,
  `pos_s.headline.c4096.loop`, `pos_s.headline.c4096.whole_wall`

What the run checks. A 4,096-token prompt and the 512 tokens the model goes on
to write are proved as one statement: nine token blocks of 32 layer segments,
288 proofs. A layer segment's proof binds the residual stream it consumed to
the previous layer's output and the keys and values it wrote to the next
block's input, so the 288 proofs are not 288 separate claims; `boundary-grid`
compares each root a segment committed with the root the segment that reads it
committed, over the serialized statements and proofs and nothing else. The
first layer of every block binds the residual stream it starts from to the rows
of the embedding matrix that the block's published ids select. Every proof's
own binding table names each of the fourteen edges inside a segment as bound
and the embedding edge with them; the driver passes no skip flag and the
manifest's list of them is empty. The five GKR reductions are on, which is the
paper's configuration.

What it does not check. The output head's segment is not in this plan, so
nothing binds the token a position emits to the logits computed for it. An
honest head segment is refused at this prover commit: the seam between the
attention output and the o matmul is checked on a segment whose residual-stream
components are the final norm's, where the two sides are folds over unrelated
sequences and cannot be equal (zk-prover #58). One variable in the driver puts the segment back when
that is fixed. Three ends are unchecked besides, and the grid output names them:
the ids are compared against no published prompt, each segment's shape root is
compared only against its own statement, and each segment's model root is
compared only against its own proof rather than against a published model
commitment.

How the run is made. The prompt is the evaluation corpus's tokens 12,288 to
16,383 -- the last 4,096 of the 16,384-token prompt the larger context reads,
so the two contexts read the same prose -- and the output is the model's own
greedy continuation under the reported quantization configuration, decoded once
with 513 new tokens and once with 512 so that the two can be compared. The
witnesses are extracted on the card in five passes over the sequence, one per
group of layers, with the block-invariant files written once and shared; they
are kept on the host under a directory named by the harness commit, and the
campaigns that follow prove the same ones. The CUDA backend proves through
device kernels generated per segment shape, so the job emits the kernels for
every distinct shape in the plan into one store, installs them into the
vendored library and rebuilds; the built tree then differs from the pushed
commit, which is why the manifest records the build as dirty. The link check
runs on the SIMD backend of the same commit, which is why the manifest names
both backends.

Host time. The extraction took 715 s on the card over the five passes and wrote
72 GB; the kernels for the plan's 46 distinct shapes were emitted in 20 minutes
and compiled in 15; the five proving processes took 748, 786, 821, 870 and 467
seconds; the link check took 39 s. The witnesses were extracted by an earlier
attempt of this job, so this run's own `extract.json` records no pass and the
seconds above are read off the log, which stays on the host.

Two workarounds are in the driver and both name their issue. The token
generator is run through a shim, because it imports a module under a name that
does not resolve (zk-prover #51); and the layer-0 dumps are moved into the name
the shape table and the plan read, because a one-layer extraction writes
another (zk-prover #55). A third defect is recorded rather than worked around:
the kernel emitter refuses the shape of the block with no prefix, so that one
shape's generation kernels are not in the store (zk-prover #57), and
`genemit-refused.txt` in the run directory says which line it was. It cost
nothing measurable: no lookup took the host route on any of the five processes.

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
