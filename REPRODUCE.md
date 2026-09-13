# Reproduce

One entry per driver, written when the driver's first run lands: the command
with its three arguments, the run ids it produced, the prover commit, the
digests, the binding table from the manifest, and the constants keys it backs.

Written, not yet run:

- `tools/drivers/predict-14b.sh`: Qwen2.5-14B's 48 layer segments at context
  4,096 on the reference backend, one proof per layer, measured against a
  registered prediction. Written and started twice, and the second attempt is
  the one this repository can act on. The prediction is registered now:
  `runs/2026-09-11-register-14b-none` holds it, made from this repository's
  constants file alone and recorded before anything measured, which is the one
  rule the experiment has. The driver then ran at zk-prover b39b806 on a host
  with 20 cores: the weights came down in 23 seconds, all 48 layer witnesses
  were extracted in nine minutes and take 27 GB, and layer 0's proof was made
  and then rejected by the prover's own verification. Not the proof: the
  document says `prove_error` null, `off_table` 0, `ref_mismatch` 0, every
  binding edge bound and every other check true, with one binding equality
  false -- `nn_out_ok`, which asks whether each quantize component published
  the values the key tiles attended over, on all three of q, k and v. Four
  diagnostics on the same witnesses say it is the shape and not this run: layer
  0 and layer 1 fail the same way, `--head-groups 8,8,8,8,8` fails the same way
  as 16,16,8, and so does the segment with the five reductions off, while the
  8B shape proves and accepts at the same commit under the same flags. Forty
  attention heads make `s * nh` 20,480, which is not a power of two, so the
  rotation and the quantize pad their rows to 32,768 and the two sides of that
  equality look like they count different rows; zk-prover #172 has the verdict,
  the parameters and the diagnostics. The job exits before it fetches anything,
  so there is no run directory and no measured constant here yet.
  The rejection is not a run that needs re-trying: zk-prover #173 traced it to
  this model's q, k and v projection biases, which the statement has no site
  for, so **Qwen2.5-14B is not provable as the statement stands** and the
  successor work is zk-prover #174. The measurement is blocked on those two and
  not on a host.

  The prediction is registered all the same, and re-registered on the counted
  path: the witnesses exist, the fields the count needs are properties of them,
  and what the registration then records is what a proof of this shape would
  cost and how far the priced model is from it. What the driver carries now: the
  shared pins of every campaign at this context, `--tight-table` included,
  because this model's witnesses ask for a master exponent table of 2^26 and
  2^27 rows before the flag narrows them to their own keys; layer 0's dump
  written to the same base as every other layer's, which is what the pinned
  harness names it; and the comparison itself, made on the fetched outputs
  before they become a run, so the run carries it. Its comparison is pinned at
  zk-prover #175, which reads a counted registration layer by layer and carries
  the one-line fix for the statement key the prover renamed (zk-prover #171),
  without which the comparison stops on the first chunk it opens.

- `tools/drivers/predict-70b.sh`: one synthetic layer segment at the
  Llama-3.1-70B width per context, 4,096 and 16,384, on a card and at a block
  length the driver is told and has no default for. The shape and not the
  model: 64 attention heads of 128 with 8 key/value heads, hidden 8,192, inner
  28,672, and no weight of that model is read, downloaded or held anywhere.
  The prediction is registered now, at a 128-token block and at context 4,096:
  `runs/2026-09-13-register-70b-none` holds it, counted from the trace layout
  at a stated block of witness fields and recorded before anything was built,
  which is the one rule the experiment has. The driver refuses to start until
  that run is there and refuses a block length it was not counted at.

  It has been run once on an H100 and made no proof, so there is no run
  directory and no measured constant here yet. The reference backend built in
  ten and a half minutes and the job stopped in its first kernel emit: the
  synthetic layer's attention output needs a remainder of 35 bits, the
  statement's widest form holds 31 against a quantize width of 7, and the
  prover refuses it by name. The registration states 21, which is what the same
  generator produces at the 8B attention width.

  The 35 bits are the generator's own weight scale and not the 70B width.
  `AttnOut::rem_bits` is the bit length of the denominator shifted by the gap
  between the attention output's per-token scale and its per-channel V scale,
  and that per-channel scale is the `v` matmul's. On the power-of-two
  dequantize gadget it is drawn over five binades; on the chain gadget it is a
  bf16 weight scale drawn over twenty. `--layout b10`, which is what the
  registration prices, puts every matmul on the chain, `v` included, and no
  recorded synthetic segment had ever done that -- every recorded run with `v`
  on the chain is a real model's dump, whose per-channel V scales span two to
  five binades and whose remainder reads 15 to 19 bits. The prover found the
  same failure one layout over and narrows that draw there, for the matmul it
  delays, and says the line is seen nowhere else. zk-prover #192 has the
  verdict and the options; the width itself is not implicated, because hidden
  8,192 widens the matmul accumulators and those are the normalisation
  window's business, pinned at 20 and inside the sound cap of 21.

  A shorter block does not fix it and neither does a shorter context: the
  eleven bits are a scale spread, and the block reaches the remainder only
  through the key count. Nor does any flag: the attention output's pins may
  only widen what the witness needs. So the four `ao_*` rows of the
  registration's stated block are refuted together, they have to be re-stated
  once the generator's scale is settled, and the registration has to be made
  again -- which means removing that run directory deliberately, as the driver
  says. The count moves by about 1% for each bit of the remainder and by under
  a thousand cells for the other three rows, so the segment figure itself
  stands to within that one row, and the block length and the memory answer do
  not move at all.


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
  `usd_per_1k_positions.headline.c4096.whole_wall`,
  `proof.headline.c4096.bytes_per_position`,
  `proof.headline.c4096.bytes_per_segment_mean_last_block`,
  `proof.headline.c4096.bytes_per_segment_median`,
  `proof.headline.c4096.in_memory_bytes_per_segment_median`,
  `proof.headline.c4096.total_bytes`,
  `proof.headline.c4096.total_in_memory_bytes`,
  `secs_per_layer.headline.c4096.loop`,
  `secs_per_segment.headline.c4096.loop`,
  `secs_per_segment.headline.c4096.whole_wall`,
  `verify.headline.c4096.secs_per_segment_median`,
  `verify.headline.c4096.secs_total`
also backed, the extraction, the cold rows and the cell counts per proved
  position:
  `cells_per_position.headline.c4096.base`,
  `cells_per_position.headline.c4096.boundary`,
  `cells_per_position.headline.c4096.interaction`,
  `cells_per_position.headline.c4096.interaction_argmax`,
  `cells_per_position.headline.c4096.interaction_attnout`,
  `cells_per_position.headline.c4096.interaction_dequant`,
  `cells_per_position.headline.c4096.interaction_embed`,
  `cells_per_position.headline.c4096.interaction_freivalds`,
  `cells_per_position.headline.c4096.interaction_gkrlink`,
  `cells_per_position.headline.c4096.interaction_key_tiles`,
  `cells_per_position.headline.c4096.interaction_quant`,
  `cells_per_position.headline.c4096.interaction_requant`,
  `cells_per_position.headline.c4096.interaction_residual_stream`,
  `cells_per_position.headline.c4096.interaction_table`,
  `cells_per_position.headline.c4096.model`,
  `cells_per_position.headline.c4096.shape`, `secs.headline.c4096.cold_loop`,
  `secs.headline.c4096.cold_whole_wall`, `secs.headline.c4096.extract`,
  `usd_per_1k_positions.headline.c4096.cold_loop`,
  `usd_per_1k_positions.headline.c4096.cold_whole_wall`

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

The size of the proof, and what verifying it cost. Every proof of this run was
kept whole to the end, so `grid.json` carries the true serialized size of all
290 and the total is read off one artifact, where the run at context 16,384 has
to assemble it from two. The 290 serialized proofs are 19,826,058,033 bytes,
18.46 GiB, a median segment 64.97 MiB and the largest 120.0 MiB, which is 4.10
MiB per proved position. Each slice output carries that size beside the size of
the proof as the prover held it before serialization -- `proof_ser_bytes` and
`proof_bytes` -- and the audit requires the two artifacts to agree segment for
segment; before serialization the sequence's proofs are 7.19 GiB, 38.9 per cent
of what was written, so the difference is the JSON encoding and not more proof.
Verification is in the same grid pass: the verifier's own time over the 290
proofs is 119.079 s, a median segment 0.415 s, on the host's own cores and not
on the card. That pass also checked the 537 links and every published id, and
the run recorded no time of its own for it, so there is no link-check row at
this context; the 170 s under host time below is the whole pass.

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

The driver takes one optional input beside its three arguments, `MODEL_ROOTS`,
and it is empty here. It is a path to a model commitment this repository
recorded; given one, the driver puts that file beside the job and the run's own
grid compares every segment's model root against it, so the run fails on a
segment whose root is not the commitment's and the third unchecked end above is
closed inside the run. Nothing is derived for it: the table is
`model-commitment`'s, derived once at the price that entry records, and a run
that reuses it records the path and the file's sha256 in its `config.json`. This
run was made before there was a commitment to give, so its `config.json` names
none and its grid was told nothing. The shape roots are not compared this way:
those rows are keyed by the layer and the prefix width, so they hold for the one
plan they were derived over, where a model root is keyed by the layer alone.

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

Cold and warm. `secs.headline.c4096.extract` is the 771 s above, and
`secs.headline.c4096.cold_loop` and `secs.headline.c4096.cold_whole_wall` add it
to the two proving scopes: what this sequence costs on a host that holds no
witness dump yet, priced as `usd_per_1k_positions.headline.c4096.cold_loop` and
`usd_per_1k_positions.headline.c4096.cold_whole_wall`. The four proving scopes
are the prover's own and begin once the dumps are on disk, so a price built from
them alone is a price for a warm host. Three things the cold rows leave out. The
head extraction pass, which the job runs and does not time, so no artifact
carries its seconds. Emitting the device kernels for the plan's 48 distinct
shapes, installing them and rebuilding, which this job does and does not time
either: the `lib/sequence-job.sh` this run shipped wrote `extract.json` and no
other phase file, so the extraction is the only phase this run can price. That
job now also times the final grid and writes `timing.json`, so the next run of
this driver prices the link check as well. And the link check, 170 s, which is a
verifier cost and not the prover's.

What a proved position commits. A segment commits six trees, and the run's five
slice outputs count them. `cells.headline.c4096.fresh` is three of them added
up -- the base trace, the interaction columns of the LogUp arguments and the
boundary trees, which carry the residual stream and the keys and values a
segment hands on -- and `cells_per_position.headline.c4096.base`, `.interaction`
and `.boundary` are those three over the 4,608 proved positions. The other two
are preprocessed and a segment does not pay for them again:
`cells_per_position.headline.c4096.model` is the weights it reads and `.shape`
the lookup tables and the constants its shape fixes. The chunk output names four
of the six; the boundary trees it does not name, so they are read as the cells
`fresh` has above base and interaction. The interaction tree is the one the
outputs split by component, and the eleven
`cells_per_position.headline.c4096.interaction_*` rows are that split per
position: the requantization seams are the largest of the eleven, the lookup
tables next and the Freivalds checks third. One reader in
`tools/constants/audit.py` re-derives every one of these rows from the slice
outputs and refuses unless the eleven components add up to the interaction tree,
the two preprocessed trees add up to the preprocessed cells the chunks report,
the chunks add up to the run's own `fresh` row, and the recorded rows close the
same two sums.

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
heads of 128, which could not be proved synthetically at this commit for the
same table reason; `prefill-sweep-8b` measures that width.

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

## prefill-sweep-8b

    tools/drivers/prefill-sweep-8b.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-09-prefill-sweep-8b-h200
prover commit: 8cd54f9   harness commit: 8cd54f9
digests: one per point, in `dd_s64_c64.json` and its two siblings; the first 16
  hex are `0b01534132a59626`, `46a42397972056b1` and `dcf40e5a2e30a9c2`
binding (from the manifest, folded over the three proofs): 1 to 14 bound; 15 and
  16 absent; a synthetic segment has neither an embedding row nor an output head
unsound skips: none
constants backed: `cells.b9_prefill_8b.s*.key_tiles`, `.key_tiles_fresh` and
  `.fresh` at three points, and `attention_grid.base_cell_coeffs`

What the run measures. What the attention key tiles of one layer segment cost in
committed cells at the 8B model's own attention width, as the block length and
the prefix it reads move. Three points: a 64-token block and a 128-token block
whose context is the block itself, and a 256-token block with a prefix of 4,096.
The segment is synthetic: without a witness the prover draws the queries, keys,
values, weights and the residual-stream columns from a pseudorandom generator
with a fixed seed, so nothing in it comes from a model and no extraction runs.

What was rejected before this commit. The first run of this driver proved
neither of its two points. At the exponential table width the layer asks for,
the honest proof was rejected, because the synthetic gate matmul's dequantized
output reached far enough below zero that a SwiGLU product had no bf16 exponent
to land on: 31 of 262,144 products at a 64-token block, and the 127,028
off-table values and 78,288 reference mismatches the record reported were those
31 magnified by a second defect in `bf16::from_f64` (zk-prover #143, still
open). zk-prover #144 sizes the gate weight scale off the data the layer draws
and shifts it down by the fewest binades that leave every product inside the
range, and no recorded digest moves with it. At that commit all three points
here prove, each accepted, with every edge bound, no skip in effect and no cell
disagreeing with the reference arithmetic.

What the shape is. 32 attention heads of 128 channels in three key tile groups
of 16, 8 and 8, with every matmul 4,096 by 4,096, which is the heads times the
head dimension and is what lets every edge bind. The softmax variant is
`intexp`, the arithmetic the paper reports, and the five GKR reductions are on.
`prefill-sweep` measures the same kind of cost at four heads of 32 and under
`intsplit6`, because at that commit the paper's own variant could not be proved
at any block length.

| block | prefix | table | key tiles, committed | with interaction | whole segment | proved in |
|---|---|---|---|---|---|---|
| 64 | 64 | 2^24 | 2,105,344 | 2,360,320 | 229,399,968 | 32 s |
| 128 | 128 | 2^24 | 5,259,264 | 5,834,752 | 331,973,792 | 38 s |
| 256 | 4,096 | 2^24 | 124,813,312 | 140,578,816 | 717,607,824 | 75 s |

Why one point whose prefix is longer than its block. The cost model's key tile
term has three coefficients, one on the product of the block length and the
context, one on the context and one on the block length. With the context set
equal to the block length the second and third multiply the same quantity, so
two coefficients come out and three do not, and that is the limit both this
driver's first two points and the four-point sweep at the smaller width record.
One point at a context that is not the block length separates them. This is that
point, and 256 over 4,096 is the one the campaign named.

What the three points give. The sound defaults tile the prefix in blocks of the
block length -- 16 key tiles per head group at 256 over 4,096 -- and add one
square diagonal block, so a segment's key tiles are C/S + 1 tiles of S by S. The
three points fix

    key tiles, committed = 64 (S*C + S^2) + 12,288 C + 12,416 S

and every coefficient of it is an identity of the layout at 32 heads of 128: 64
is two per head, 12,288 is three per head and channel, 12,416 is that plus four
per head. Under the composition the cost model itself uses -- a prefix key tile
at (S, C) plus the same tile at (S, S) with the per-token component dropped --
that is the prefix key tile's own triple, `attention_grid.base_cell_coeffs`:

    64 S*C + 12,288 C + 128 S

What the residual is not. Three points and three coefficients is an exact solve.
The residual is zero by construction and says nothing about the form; a fourth
point is what would make it a fit. What the form assumes is that the prefix's
C/S sub-key-tiles and the diagonal block are the same S by S tile, and the run
records the per-key-tile interaction split so that assumption can be read
rather than taken.

Where this disagrees with the cost model, and by how much. `key_tile_cells` in
`harness/costmodel/cost_model.py` reproduces the two points whose context is
their block length exactly, to the cell. At 256 over 4,096 it gives 109,084,672
against the measured 124,813,312, which is 12.6 per cent below it, and the shortfall
is 15,728,640 cells exactly. That is the queries: the model commits them once
per segment, `nh * hd * S`, and the prover commits them once per key tile, which
at this point is sixteen times, `nh * hd * C`. The difference is
`nh * hd * (C - S)`, which is 4,096 times 3,840. So the model's C and S
coefficients are 8,192 and 4,224 where the measurement gives 12,288 and 128,
their sum agrees, and the two forms can only be told apart at a context that is
not the block length. Every frontier projection the cost model makes is at a
context far above the block length.

Why the interaction side is not recorded. `attention_grid.fresh_cell_coeffs`
stays unbacked. With the five GKR reductions on, most of the key tiles'
interaction is in the reduction rather than in their own columns, so the
quantity is not the model's `fresh` to begin with; and what is left does not
take the three-coefficient form. Solving it over these three points returns a
context coefficient of 13,568/5 and a per-token component of -1,955.2, and a
negative per-token component is not a cost. The run's own per-key-tile split
says why: at 256 over 4,096 the 48 prefix sub-key-tiles do not all cost the same
-- 30 of them 229,376 cells over 40 columns, 15 of them 458,752 over 40, and
three carry 8 more columns each -- and none of them costs what a diagonal block
of the same shape costs. Measuring that coefficient needs the reductions off,
which is a different configuration from the one the paper reports.

The card. The proofs are made on the host's cores under the reference backend
and the card is idle throughout. The machine reports an H200, which is what the
run id and every constant name, and no timing figure from this run is recorded:
the card the paper times is the H100 by decision, and what this run records is
cell counts, which do not depend on the card.

How the run is made. Every pin is named in the driver. The exponential table
width is not derived from the layer: auto-sizing clamps it at 2^22 and the data
needs more, so the two points whose context is their block length carry the
width the layer named in the refusal it raised the first time, and the point
with the longer prefix carries the widths to try in order, of which the first,
2^24, proved. The attention output's remainder is pinned at 22 bits at those two
points and is the witness's own, 21, at the third, which the flag may only
widen; that is why the three whole-segment counts are not one series while the
key tile counts are. The reference backend proves all three: this is a cell
count and a shape, and the two backends prove the same statement to the same
digest. The whole sweep is 145 seconds of proving after a 4-minute build, and
the largest point peaks at 44.1 GiB of host memory.

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
  `positions.headline.c16384`, `proof.headline.c16384.bytes_per_position`,
  `proof.headline.c16384.bytes_per_segment_median`,
  `proof.headline.c16384.in_memory_bytes_per_segment_median`,
  `proof.headline.c16384.total_bytes`,
  `proof.headline.c16384.total_in_memory_bytes`,
  `rate.headline.c16384.commit`,
  `rate.headline.c16384.loop`, `rate.headline.c16384.stwo_total`,
  `rate.headline.c16384.whole_wall`, `secs.headline.c16384.commit`,
  `secs.headline.c16384.loop`, `secs.headline.c16384.stwo_total`,
  `secs.headline.c16384.whole_wall`,
  `secs_per_layer.headline.c16384.loop`,
  `secs_per_position.headline.c16384.loop`,
  `secs_per_position.headline.c16384.whole_wall`,
  `secs_per_segment.headline.c16384.loop`,
  `secs_per_segment.headline.c16384.whole_wall`,
  `segments.headline.c16384`,
  `usd_per_1k_positions.headline.c16384.loop`,
  `usd_per_1k_positions.headline.c16384.whole_wall`,
  `verify.headline.c16384.link_check_secs`,
  `verify.headline.c16384.secs_per_segment_median`,
  `verify.headline.c16384.secs_total`
also backed, the extraction, the cold rows and the cell counts per proved
  position:
  `cells_per_position.headline.c16384.base`,
  `cells_per_position.headline.c16384.boundary`,
  `cells_per_position.headline.c16384.interaction`,
  `cells_per_position.headline.c16384.interaction_argmax`,
  `cells_per_position.headline.c16384.interaction_attnout`,
  `cells_per_position.headline.c16384.interaction_dequant`,
  `cells_per_position.headline.c16384.interaction_embed`,
  `cells_per_position.headline.c16384.interaction_freivalds`,
  `cells_per_position.headline.c16384.interaction_gkrlink`,
  `cells_per_position.headline.c16384.interaction_key_tiles`,
  `cells_per_position.headline.c16384.interaction_quant`,
  `cells_per_position.headline.c16384.interaction_requant`,
  `cells_per_position.headline.c16384.interaction_residual_stream`,
  `cells_per_position.headline.c16384.interaction_table`,
  `cells_per_position.headline.c16384.model`,
  `cells_per_position.headline.c16384.shape`,
  `secs.headline.c16384.cold_loop`, `secs.headline.c16384.cold_whole_wall`,
  `secs.headline.c16384.extract_prove`, `secs.headline.c16384.extract_survey`,
  `usd_per_1k_positions.headline.c16384.cold_loop`,
  `usd_per_1k_positions.headline.c16384.cold_whole_wall`

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

The driver takes one optional input beside its three arguments, `MODEL_ROOTS`,
and it is empty here. It is a path to a model commitment this repository
recorded; given one, the driver puts that file beside the job and the final grid
compares every segment's model root against it, so the run fails on a segment
whose root is not the commitment's and the second unchecked end above is closed
inside the run. The commitment recorded so far was derived over the context
4,096 plan and it serves this one, because a commitment's rows are keyed by the
layer and it is the same model at the same quantization variant: all 33 layer
coordinates of this run, the head's at 32 among them, have a row in it, and
every one of them names the model hash this run's statements name. The
comparison reads the statements, which are never shrunk, so the proof shrinking
this host needs does not touch it. Nothing is derived for it, and this run was
made before there was a commitment to give.

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

How the size of the proof is put together. No one artifact of this run holds the
true size of all 1,058 proofs, because a proof was shrunk as soon as the
verifier had accepted it and the run would not otherwise have fitted the host's
volume, so `proof.headline.c16384.total_bytes` is assembled from two.
`proofs-g<blocks>.json` carries the size of each of the 1,057 proofs the first
pass wrote, taken before that proof was rewritten as its commitments alone;
`verify-fixup.json` carries the true `proof_bytes` of the 34 the fix-up
re-proved, which were never shrunk. 33 of those 34 supersede a first-pass record
and the 34th is `B31head`, the plan line the fix-up added, so 1,024 segments
take the first pass's size, 34 take the fix-up's, and each of the 1,058 takes
exactly one. The audit reads the group records in plan order against this plan
without `B31head`, which is the plan the first pass ran: that is what identifies
the first pass's bare `head` tag as the head over the generated block, and a
record landing anywhere else stops the audit, as does a segment left with no
size or with two. The total is 116,961,203,137 bytes, 108.9 GiB, which is 6.60
MiB per proved position. It is the proof the prover wrote and nothing here
compresses or aggregates it; the number is not read off `grid.json`, whose
`proof_bytes` is the shrunk size for the 1,024.

What the proof weighs before serialization, and what verifying it cost. A slice
output's chunk row carries both sizes: `proof_bytes` is the proof structure's
own and `proof_ser_bytes` is the document the prover wrote. Those rows were
written as each segment was proved, before any proof was shrunk, so the 1,058 of
them reproduce the assembled serialized total segment for segment. The audit
requires that, and it is what lets a median be read off them: 105.8 MiB for the
median segment against 49.6 and 163.9 MiB at the ends, and 42.01 GiB for the
whole sequence before serialization against the 108.9 GiB written, 38.6 per
cent. The verifier's own time over the 1,058 proofs is 832.080 s, a median
segment 0.757 s, on the host's own cores and not on the card; it is summed over
the same two passes the sizes come from, 1,024 segments from the group records
and 34 from the fix-up. The link check over all 1,058 segments replayed no proof
and is the 12 s `timing.json` records for the final grid.

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

Which extraction the record keeps. This run extracted the witness set twice and
the two are separate rows. `secs.headline.c16384.extract_prove`, 9,735 s, is the
prove sweep's, added up over its seven groups: the extraction whose dumps the
1,058 kept proofs read. `secs.headline.c16384.extract_survey`, 9,330 s, is the
survey sweep's, the pass that wrote each block's shape table and emitted its
device kernels; an emitter reads a segment's dump to lower its shape, so those
dumps had to exist, and no proof reads them. Adding the seven prove rows of the
first pass in `groups.jsonl` gives 9,683 s, which is not this number: group
28-32 was extracted again by the fix-up pass, in 2,075 s, and that is the
extraction the kept proofs of that group read. `extract.json` holds one row per
pass and a re-run pass overwrites its own row, so its `by_sweep` totals are the
last extraction of each group, which is what `timing.json` reports and what the
audit adds up again from the rows.

Cold and warm. `secs.headline.c16384.cold_loop` and
`secs.headline.c16384.cold_whole_wall` add the prove sweep alone to the two
proving scopes, priced as `usd_per_1k_positions.headline.c16384.cold_loop` and
`usd_per_1k_positions.headline.c16384.cold_whole_wall`: what this sequence costs
on a host that holds no witness dump yet. The survey sweep is out of them for
the same reason the kernels are -- it exists so that the emitters have dumps to
read, and emitting is a build step -- and `timing.json` keeps the phases apart
so the choice is visible: `kernel_seconds` 1,204 s for the install and the
compile, `grid_seconds` 12 s for the link check, and `extract_seconds` split
into the two sweeps. The head extraction pass is not timed here either. Anyone
who wants the arrangement's whole price rather than the statement's adds
`secs.headline.c16384.extract_survey` and the 1,204 s to the cold row.

What a proved position commits. The same six trees as one context down, over
this run's 20 slice outputs and 16,896 proved positions:
`cells_per_position.headline.c16384.base`, `.interaction` and `.boundary` add up
to `cells.headline.c16384.fresh`, and `.model` and `.shape` are the two
preprocessed trees. The eleven
`cells_per_position.headline.c16384.interaction_*` rows split the interaction
tree by component. The requantization seams are the largest of the eleven here
too, but the key tiles are second where at context 4,096 they are sixth: their
cells grow with the prefix a block reads and nothing else in the split does,
which is the cost the attention grid's coefficients model. The same reader in
`tools/constants/audit.py` re-derives every row and refuses on the same four
conditions.

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

runs: 2026-09-13-reference-digest-plain-h100, and
  2026-09-08-reference-digest-plain-h100 and
  2026-09-09-reference-digest-plain-h200 before it
prover commit: a8586d205b87d7019af5b5005d0a46680a74242e, a commit on zk-prover's
  main, in the 2026-09-13 run; a603db1ddf1e2372d1f9761d684df8f2294199a9
  (zk-prover pull request 107) on the H100 and
  2c8fa991c0f5425be48bf7f8b95334cbd4f716ed on the H200 in the two before it
harness commit: the same commit as the prover, in each run
digests: first 16 hex, and the same on both backends wherever both proved a
  shape. The 2026-09-13 run:
  `full-simd.json`, `full-cuda.json`: `c5c75572ca078b6c`
  `short-simd.json`, `short-cuda.json`: `6267ed8dee200582`
  `plain-simd.json`: `9a062833a4088f05`; an 80 GB card does not attempt that
  shape, so it has no CUDA side here (see below)
  The two runs before it:
  `full-simd.json`, `full-cuda.json`: `05580c4a4b766666`
  `short-simd.json`, `short-cuda.json`: `65d588904d613bff`
  `plain-simd.json`: `d2f2afd860a491d9`, and `plain-cuda.json` on the H200 the
  same; on the H100 that shape had no CUDA side either
dump: `1fb845bc19955bd8`, the 2026-09-13 run's `provenance.dump_sha256`, under
  the attention calibration `b136a8d01ae59a58`; the two runs before it recorded
  neither
binding (from the manifests, folded over the 2026-09-13 run's five proofs, the
  2026-09-08 run's five and the 2026-09-09 run's six): 1 to 14 bound; 15 and 16
  absent; unbound none
unsound skips: none
constants backed: none from the 2026-09-13 run; this run freezes digests, not
  numbers
constants backed, from the 2026-09-08 run, which the newer one does not
  re-point: `secs.reference.c16384.simd_trace`,
  `secs.reference.c16384.simd_interaction`,
  `secs.reference.c16384.cuda_trace`,
  `secs.reference.c16384.cuda_interaction`

What the run proves. Two statements about the same Llama-3.1-8B layer 16, under
the fixed quantization configuration `b10-final`, each with its own diagonal
block and the residual-stream columns and no skip flag: the reference segment,
512 output positions against a 16,384-key prefix with the five GKR reductions
on, which is the paper's configuration; and the short segment, 128 output
positions against a 4,096-key prefix with none of them on. Each is proved on
the SIMD backend and then on the CUDA backend of the same commit, and equal
digests are the gate. The reference segment without the reductions is proved
beside them, on the reference backend always and on a card that reports the
memory for it.

What the short segment is for. Without the reductions the segment's key tiles
each publish their own interaction columns, and the vendored library's
out-of-domain sampling evaluates the polynomials of one size in a single launch
with the polynomial index in a thread block grid's y dimension, which a device
caps at 65,535. zk-prover pull request 107 launches that axis in slices of at
most that many; the evidence a card has to give it is a proof whose sampling
axis is wider than the cap and whose digest is the reference backend's. The
short segment's interaction tree is 102,608 columns wide, 80,424 of them key
tiles, against the reference segment's 93,184 and 70,920.

The reference segment without the reductions proves on a 143 GB card. On the
H200 it proved to `d2f2afd860a491d9`, the digest the reference backend gave it
that day, with no skip in effect, every edge bound and no kernel fallback line.
That is the shape zk-prover #29 opened on: at C = 16,384 with the five reductions
off the sampling axis is wider than a grid dimension holds, and before pull
request 107 the proof stopped in `eval_at_point.cu` with an invalid
configuration argument on a card of this size. It no longer does. Nothing about
the shape got smaller -- it still commits 4,131,033,024 cells -- so what #29
asked can now be answered from a measurement rather than from the cap: the
sliced launch is what the shape needed, and the memory below is what it costs.

What it costs, from the proof's own marks. The two cards agree mark for mark up
to the point where the smaller one stopped, and the next mark is where it would
have had to go:

| mark | card memory in use |
|---|---|
| after the base tree, 66,215 columns | 40.5 GB |
| after the interaction tree, 93,184 columns | 70.9 GB |
| after the boundary tree | 74.2 GB |
| after the composition commitment | 82.2 GB |
| after the opened values | 92.9 GB |

The first four are the same on both cards to the tenth of a gigabyte. The
H100 run reached the fourth with 82.2 GB of the 85.0 GB the driver reports it,
and the quotient stage's next allocation was refused; the H200 run reaches the
fifth, 92.9 GB of the 150.1 GB it reports. So the shape needs about 93 GB and
the 80 GB card was about 11 GB short, which is more than any configuration of
this segment saves.

What the driver does with that. The job reads the memory the device reports and
attempts the shape on a card at or above 120 GiB, which is half again the card
the shape ran out of memory on; it emits that shape's kernels only on such a
card, since without them every lookup would take the host route. A card below
the threshold does what the first run did: proves the shape on the reference
backend, writes what it did not attempt and why into
`out/plain-cuda-refused.json`, and carries the same evidence for the sliced
launch through the short segment. A card above it writes the outcome, the
committed cells and the memory marks into `out/plain-cuda-attempted.json`. A
card that attempts the shape and stops is a result and not a broken run; a
proof that comes out is held to the same gate as the others.

What the 2026-09-13 run moved. All three digests moved from the two runs before
it: the reference segment from `05580c4a4b766666` to `c5c75572ca078b6c`, the
short segment from `65d588904d613bff` to `6267ed8dee200582`, and the reference
segment without the reductions from `d2f2afd860a491d9` to `9a062833a4088f05`.
Each of the three is proved with no skip in effect, so each carries the
residual-stream components and with them a requantize seam scaled by a bf16
value, and the scale table preprocessed under their shape root stopped wrapping
on 2026-09-11 (zk-prover #143). Nothing about the shapes moved with the numbers:
the reference segment commits 2,583,414,208 cells over an interaction tree 5,600
columns wide in both measurements, the short segment 1,227,190,880 over 102,608
and the third 4,131,033,024 over 93,184, each the same to the cell. The
serialized proofs moved by less than one per cent, the reference segment's from
170,620,431 bytes to 169,277,485.

What the driver compared the reference segment against. `full-digest.json`
compares that digest with one written into the driver, and the driver held
`25741d12f315aae7` through all three runs: the value `prover/README.md` recorded
until 2026-09-12, when zk-prover pull request 184 replaced it with
`05580c4a4b766666`. So all three runs report `moved` against a number no page
records, and the comparison worth reading is the one above. The driver now holds
`c5c75572ca078b6c`, which is what the page records from 2026-09-13.

The reference segment's proof, kept for zk-results #112. The driver serializes
no proof: each shape's digest is printed and the proof bytes go with the
process, which is why nothing here shrinks or deletes one. zk-results #112 needs
a proof that a machine without a card can verify, so after the 2026-09-13 run
finished the reference segment was proved once more on the same host, from the
same dump and with the binary that run's `full-simd.json` came out of, with
`--ser-dir` added. That proof's digest is the run's, `c5c75572ca078b6c`, which
is what says the kept bytes are the run's proof and not another one. The
statement, the claims, the proof of 161.4 MiB, the calibration the verifier
derives the shape root from and the prompt ids are kept outside both
repositories, in an `artifacts/2026-09-13-reference-segment/` directory beside
them, with a `SHA256SUMS` file. Nothing of it is in git.

Why the block length moves rather than the context. The key tile count follows
the key blocks -- the prefix and the segment's own block, in blocks of S keys
-- times the head groups, not the context on its own. Both segments here have
33 key blocks and three head groups, so the short segment stays past the cap
while committing 1,227,190,880 cells against the reference segment's
4,131,033,024. Lowering the context alone does the opposite: at 512 output
positions a shorter prefix has fewer key blocks and the axis falls back under
the cap, which is what zk-prover #29 saw from the other side when it put the
threshold at a 15,872-key prefix.

How the run is made. The extractions read the card; each dump is kept under the
remote home and reused, so a second run at another prover commit rebuilds,
re-emits and re-proves and does not extract again. A host that holds neither
extracts both, which is what the 2026-09-13 run did: 118 s for the reference
segment's dump and 22 s for the short segment's, after the model download. The
CUDA backend proves through device kernels generated per segment shape, so the
job emits the kernels for every shape that runs on the card, installs them into
the vendored library and rebuilds; the built tree then differs from the pushed
commit, which is why the manifest records that build as dirty while the
reference backend's stays clean. The two installer scripts were renamed between
the first two runs, and the job takes whichever name the pinned commit has.

## unproved-baseline

    tools/drivers/unproved-baseline.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-09-unproved-baseline-h100
prover commit: none; this run proves nothing   harness commit: 2c8fa991c0f5425be48bf7f8b95334cbd4f716ed
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
it. Both ran here. The serving engine decodes 2.7 times as fast at a single
request and 2.2 times as fast at 16, and it holds a batch of 16 at the longer
context where the other backend cannot: at a 4,096-token prompt it decodes
153.0 positions per second per request against 56.9, and at 16,384 it decodes
140.1 against 57.1. A reader who takes one of these as "what the model runs at"
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
spread recorded here is 3.3 per cent at its widest -- the serving engine's
prefill at one request -- and under 1 per cent at 55 of the 57 rows.

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
its last, and the card read 0 MiB at both ends. It takes 19 minutes, eleven of them
the first backend.

The run of 2026-09-08 is superseded and no constant points at it any more. Its
harness commit is the head of a pull request that was rebase-merged, so that
commit is on no branch of the prover repository and a reader cannot check out
what the record names; its content is on the default branch under another
commit. Nothing else about it was wrong, and its directory stays under `runs/`.
The rates moved with the re-run: the serving engine's are within a per cent of
the earlier ones, and the model library's decode is about 8 per cent slower at
every point, which is more than either run's own spread and is not explained by
anything this repository records.

## model-commitment

    tools/drivers/model-commitment.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-09-model-commitment-h100
prover commit: 32e8fae   harness commit: 32e8fae
digests: none; this run makes no proof
binding: none; a run that proves nothing binds nothing. The manifest records
  the run's kind as `verifier`, which the driver states on the command line
  because no output of such a run can state it, and `lib/manifest.py` then
  checks that the run carries no proof digest and no binding table
unsound skips: none
constants backed: `commitment.c4096.cells`, `commitment.c4096.layers`,
  `commitment.c4096.sha256`

What the run checks. A segment's statement names a model root, and the
verifier's own replay only says that the proof's second commitment is the one
the statement names; which model that root is, is the statement's own assertion
until a published commitment is compared with it. This run derives that
commitment from the model over the plan `headline-c4096` proved, and
`boundary-grid --expect-model-roots --expect-pre-roots` compares every one of
that run's 290 segments against it. All 290 model roots and all 290 shape roots
are the commitment's. Both comparisons also check the model hash the row was
derived under against the one the statement names, so a commitment published for
another model is a named failure and not an accident.

The grid is given the sequence run's published prompt as well, and verifies
every proof, exactly as that run's own grid did: 537 of 537 implied links passed,
290 of 290 proofs accepted, and the 4,096 prompt ids and 512 generated ids all
chained. With the manifest in hand the grid names no unchecked end at all, where
the sequence run's grid named three.

Two derivations, and why both. The published table is the prover's: every row
from the whole dump, which is what a manifest built before any segment has been
proved has to do. The second is the verifier's, from the model half of the dump
and from the statement the sequence run serialized, over the first token block,
which is one chunk at each of the 32 layers. The two must agree on every layer's
model root, or the commitment is not a function of the model alone. They agree
on all 32. The verifier's form is derived without `--tight-table`: that flag
sizes the exponential table off the witness's own shifts and the model-only load
has no witness to read them from. The exponential table is a shape column and no
part of the model tree, which the derivation says itself where a layer's blocks
carry two widths, so dropping it moves no model root.

What the table is reused for. `model-roots.json` in this run directory is the
published commitment and the file a sequence driver's `MODEL_ROOTS` reads:
`headline-c4096`, `control-flags-off-c4096` and `headline-c16384` each take an
optional path to it, and a run given one has its own grid compare every
segment's model root against the table rather than leaving that end for this
campaign to close afterwards. Only the model roots travel that way. The
`--expect-pre-roots` rows are keyed by the layer and the prefix width, and a
shape root is a function of the chunk's own shape and arguments, so they hold
for the plan they were derived over, which is the plan this campaign checks; a
model root is keyed by the layer alone and is a function of the model.
`model-roots-verifier.json` beside it is the cross-check and not the
publication: it covers one token block, so it has no row for the layer
coordinate a head segment sits at, and the drivers refuse it.

What it does not check. The commitment is a function of the weights as this
harness loads and quantizes them. Nothing here compares those weights against a
published checkpoint; the model hash in each row is the harness's own hash of
what it loaded.

How the run is made. It reads the serialized statements and proofs the sequence
run kept on the host -- 870 files -- and makes no proof of its own, so none of
the four proving timing scopes applies to it. The three steps took 6,425 s to
derive the commitment, 503 s for the verifier's form and 171 s for the grid; the
run records them as wall-clock seconds in `timing.json` and backs no constant
with them, because a wall-clock step time of a run that proves nothing is not
one of this repository's timing scopes.

Host time. Just under two hours, almost all of it the first derivation: it runs
the prover's `expect-root` once per plan line, in a process of its own, 290
times.

## microbench-cells

    tools/drivers/microbench-cells.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-11-microbench-cells-h100, and 2026-09-09-microbench-cells-h100
  before it
prover commit: b39b806   harness commit: b39b806
digests: one, the composed segment's, in the manifest's `digests` map
binding (from the manifest, over that one proof): 1 to 14 bound; 15 and 16
  absent, because a synthetic segment has neither an embedding row nor an
  output head
unsound skips: none
constants backed, from the 2026-09-11 run:
  `model_constants.weight_freivalds_cells_per_weight`,
  `model_constants.weight_freivalds_preprocessed_cells_per_weight`,
  `model_constants.logup_marginal_cells_per_lookup`,
  `model_constants.dequant_chain_away_cells_per_acc`,
  `model_constants.dequant_pow2_away_cells_per_acc`,
  `model_constants.dequant_chain_away_base_cells_per_acc`,
  `model_constants.dequant_pow2_away_base_cells_per_acc`,
  `model_constants.argmax_marginal_cells_per_comparison`
constants backed, from the 2026-09-09 run, which the newer one does not
  re-point: `model_constants.dequant_chain_cells_per_acc`,
  `model_constants.dequant_pow2_cells_per_acc`,
  `model_constants.attnout_int8_cells_per_acc`,
  `model_constants.dequant_pow2_cells_per_acc_intercept`,
  `model_constants.dequant_pow2_cells_per_row`,
  `model_constants.requant_cells_per_value`,
  `model_constants.residual_stream_add_cells_per_op`,
  `model_constants.residual_stream_mul_cells_per_op`,
  `model_constants.argmax_cells_per_comparison`,
  `model_constants.attention_cells_per_head_key_token`

What the run measures. What one operation of each kind costs in committed
cells: a dequantized accumulator under each of the five quantization variants
and again at the rounding the cost model charges, a requantized value, a
residual-stream operation under each of its five gadgets, an argmax comparison
at each of three vocabularies, a packed attention instance at five instance
counts, a dequantized accumulator at six accumulator widths and the same at six
values of `kmax`, one weight of the Freivalds check at its design point and at
four row widths, and one lookup at each of the two LogUp batch sizes this
prover uses. Thirteen subcommands, all thirteen answered, none refused. A cell
count is the same on both backends, so they are read on the reference backend
and no card is used; the driver logs the card where the host has one and goes
on where it has none.

Why it is its own run. `microbench` measures the rates the cost model reads --
the vendored library's benchmarks of the primitives, and one composed segment's
commitment and FRI parts -- and those were measured at another prover commit.
A run that re-derived them here would either re-point the constants that name
that run or leave two runs claiming one number. The subcommands could not run
at that commit at all (zk-prover #88); zk-prover #98 then bounded the packed
attention benchmark's shared exponent table by `--table-bits`, which is why the
instance counts above 4 can be asked for and why this driver passes
`--table-bits 23`. The counts at 1, 2 and 4 do not move under the flag.

Why it was run a second time. The 2026-09-09 run answered seven subcommands and
left two of the cost model's inputs measured by nothing: the Freivalds check's
cells per weight and the marginal cells of one lookup. zk-prover #139 and #140
built the two subcommands, and three more lines were asked for beside them --
the dequantization at the rounding away from zero and two more argmax
vocabularies -- so the newer run answers thirteen. The ten constants the
2026-09-09 run backs are unchanged and still name it: nothing is re-pointed,
and every subcommand the older run answered returns the same figures here.

The composed segment is here for one reason: `compose` is the only subcommand
that makes a proof and therefore the only one that writes a binding table,
which is what makes the run admissible. Its numbers back no constant here.

What the run measured and what is recorded. Every figure is a marginal, with
the shared tables left out, because a table is a fixed cost of the segment and
is not multiplied by a count, and with the cells the producer already commits
left out too. Eight new entries come off the 2026-09-11 outputs.

The Freivalds check measures a law and not a number: its three accumulator
columns cost 12 cells a trace row and a row carries `p` weights, so it is
`12/p` fresh cells per weight and `1 + 4/p` preprocessed, and `p` is a layout
knob. The design point is the prover's own default row width, `p = 136`, which
gives 0.0882353 and 1.0294118; the sweep beside it returns both closed forms to
the cell at 8, 16, 32 and 64 weights a row, which is what says the law holds
rather than assuming it. Two things the record has to say beside the number:
the private archive's 0.0902 is `12/133`, the same law at a shape whose grid
padded 32,256 rows up to 2^15, and this subcommand refuses a ragged tiling and
so reports the unpadded form; and a group of `n` matmuls shares one accumulator,
so it costs `(4 + 8n)/(n p)` per weight and not `12/p`, which the cost model
does not know.

The LogUp subcommand gives 4 marginal cells a lookup at batch 1, which every
shared table's own side finalizes with, and 2 at batch 2, which every use side
does -- `4/batch` at both sizes this prover uses. The range check and the pair
table agree at each batch, because an interaction column is one QM31 whatever
the relation's arity. The entry is an object keyed by the batch size, because
the cost model indexes it by the batch it charges and refuses a scalar.

The dequantization at the rounding away from zero gives four: 25.125 cells an
accumulator for the bf16 chain and 14.0625 for a power-of-two scale, and,
with the LogUp running sums left to the batched reduction, 14.375 and 9.25 from
the same points' committed columns over the sixteen accumulators a row carries.
That is the rounding the quantization configuration specifies and what every
recorded proof builds, and the committed-columns figures are what a proof with
`--gkr-dequant` builds. Each of the four is exactly one cell an accumulator
below the round-half-to-even figure beside it, at both variants and on both the
marginal and the committed side.

The argmax at three vocabularies gives the marginal a single vocabulary cannot:
8 tokens over 8,192, 16,384 and 32,768 entries at the same 64 comparisons a
row are exactly collinear at 4.046875 fresh cells a comparison, over a fixed
side of 327,680 cells -- 65,536 committed and 262,144 interaction -- that does
not move with the vocabulary. The cost model charges the marginal; until this
run it reached one by subtracting an assumed fixed side of ten interaction
columns over the trace rows, which at this prover's row counts gives 8.421875
and is wrong by the whole of the real fixed side.

Two more of the cost model's cell inputs get no subcommand and are recorded as
`derived` over the LogUp figure: the per-activation int8 range check, one
arity-2 lookup into the 2^16 byte-pair table covering two activations, and the
bf16 unary operation, one committed bf16 value and one lookup. Neither is a
measurement and neither is a run.

The `kmax` sweep backs nothing and is a gate: the marginal figure is 15.0625 at
all six table sizes while the figure with the tables in goes from 15.475 to
143.756, so the constant the cost model reads does not depend on the table
knob.

What the run does not check. Nothing here is a rate: every number is a cell
count, and the seconds each subcommand reports are on the host's cores with
twenty threads and are not comparable with a card's. The reference check each
subcommand makes is against its own model of the arithmetic, and every point
reported zero mismatches. The `manifest.json` field `cuda_version` reads 13.0
because the prover scrapes it from the `nvidia-smi` banner, which reports the
version the installed display driver supports and not the toolkit the build
used; the 2026-09-09 manifest reads the same 13.0 for the same reason.

Host time. The thirteen subcommands report 26.7 s of proving between them, of
which the packed attention at five instance counts is 25.6, and the composed
segment took 4.6 s of end-to-end wall-clock time. The build in front of them is
not in any output and its time stays in the host's log.

## `control-flags-off-c4096`

```
tools/drivers/control-flags-off-c4096.sh <host> <prover-commit> <harness-commit>
```

runs: `2026-09-11-control-flags-off-c4096-h100`
prover commit: b39b806   harness commit: b39b806
digests: 290, one per segment, in the manifest's `digests` map under the slice
  output that proved it; the first is `fd796456ac60513b` and the last
  `2a7cc72b8131f05f`
binding (from the manifest, folded over the 290 proofs): 1 to 16 bound, none
  absent and none unbound
unsound skips: none
links: 537 of 537 the grid implies ran and passed, 281 on the layer axis and
  256 on the token axis
verified: 290 of 290 segment proofs accepted; 290 of 290 shape roots derived
  from the statement's own parameters and the published calibration are the
  root the statement declares; 4,096 prompt ids and 512 generated ids chained,
  none wrong and none with no proved argmax behind it
kernel fallback lines: 0 on each of the five processes
constants backed: `cells.control.c4096.fresh`, `mem.control.c4096.peak_mib`,
  `secs.control.c4096.serial_loop`, `segments.control.c4096`, and the derived
  `gkr.control.c4096.leave_frac_cells`

What the run checks. `headline-c4096`'s plan, its witnesses, its shared pins and
its binding gadgets, with the five `--gkr-*` reductions off: 290 segments, nine
token blocks of 32 layer segments and the two output head segments, proved on
the CUDA backend in processes of 64. The reductions choose the LogUp backend for
a component and change nothing about what is proved, so the pair of runs prices
what they remove. Every edge inside a segment is bound, the driver passes no
skip flag, and the grid checks every link, verifies every segment's proof and
chains every published id as the headline row's grid does. This is a control and
never a headline row
(docs/decisions/2026-09-03-paper-configuration-all-five-gkr-flags.md).

Why one segment is in flight. The same plan with a second segment generated
while the first is proved ran out of the card's memory in token block 3 on
2026-09-09, after a first process that peaked at 80,497 MiB of the 81,559 MiB
the card reports (#74). With the pipeline off that same first process peaks at
71,601 MiB, so the second segment in flight was costing 8,896 MiB, and the whole
sequence now fits with 4,592 MiB to spare.

What is comparable and what is not. The cells are. A cell is committed by the
segment it belongs to and a second segment in flight adds none, and this run
says so of itself: its first process committed 112,089,779,216 cells over blocks
0 and 1, which is what the pipelined attempt reported over those same 64
segments, to the cell. The seconds are not. This loop proves one segment at a
time and the headline row's overlaps two, and over one sample the memory probe
measured 228.738 s serial against 175.797 s pipelined
(`secs.probe.c16384.serial_loop`, `secs.probe.c16384.pipelined_loop`). So
`secs.control.c4096.serial_loop` says serial in its name, nothing here is
compared with `secs.headline.c4096.loop`, and no figure in this entry is a
throughput.

What the run says. The five reductions remove 36.8 per cent of the committed
cells over a whole sequence: 363,878,357,152 with them
(`cells.headline.c4096.fresh`) against 575,760,898,208 without.
`gkr-ablation-c4096` prices the same five on 32 segments of the block with the
longest prefix, where they weigh most, and gets 37.8 per cent; this row is the
whole sequence, blocks with short prefixes included, and it is the smaller
figure for that reason.

The peak follows the prefix. The five processes peaked at 71,601, 73,105,
74,609, 76,145 and 76,967 MiB as the plan moved from the shortest prefix to the
longest, against 73,723 MiB for the whole of the headline run. So with one
segment in flight the reductions are worth about 3.2 GB of peak card memory at
this context, and the pipelined attempt was asking for about 9 GB more than
that, which is what it did not have.

How the run is made. The witnesses, the prover build and the kernel store are
the ones the campaigns at this context share; this run extracted the witnesses
in 907 seconds over five passes, added its own shapes to the store and rebuilt
the CUDA backend with them. The grid verifies, so it is given the calibration
the model manifest publishes: since zk-prover #95 the verifier derives each
segment's shape root from the statement's own parameters and that calibration
instead of reading the root off the statement, and it refuses to verify without
one. The file is
`runs/2026-09-09-model-commitment-h100/model-roots.json`, whose rows cover this
plan's 290 layer and context coordinates. It was derived at prover commit
32e8fae and this run proves at b39b806, which is sound because a calibration is
a property of the weights and the quantization variant and not of the prover --
and checked, not assumed: every one of the 288 layer dumps this run extracted
carries the `frac_per_head` the manifest's row for its coordinate publishes, and
all 290 derived roots came out equal to the ones the statements carry. One end the headline
row leaves unchecked is therefore checked here, the shape tree behind each
statement; the model each segment proves against is still one, because this run
was given no `MODEL_ROOTS`. The serialized statements and proofs are deleted
after the link check: no campaign re-reads a control's proofs.

Host time. Four hours and thirteen minutes end to end, over two calls of the
driver: 5 minutes the build, 15 the token ids, 907 seconds the extraction, 28
minutes the kernel work and the CUDA rebuild, 5,970.803 seconds the five proving
processes, and 4,210 seconds the verifying grid, of which 3,801 were the 290
shape-tree derivations.

## negative-controls

    tools/drivers/negative-controls.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-11-negative-controls-h100
prover commit: b39b806   harness commit: b39b806
digests: none in the manifest's `digests` map. `compose-probes` reports its
  proofs under `probes` rather than as a point or a chunk list, so what the
  manifest carries from this run is its binding table and no digest
binding (from the manifest, folded over the five honest proofs, one per
  target): 3 and 5 unbound; 1, 2, 4 and 6 to 14 bound; 15 and 16 absent. The
  fold is the weakest answer any target gave: both real targets bind every edge
  their shape has, and so does `syn_aligned`; 3 and 5 are unbound on `syn_sound`
  and `syn_gkrfive`, which is the table `synthetic-digests` records for those
  same two shapes. 15 and 16 are absent everywhere, because a layer segment
  carries neither an embedding row nor an output head. The run is labelled a
  control in its own `config.json`
unsound skips: none
constants backed: `controls.suite.designed_rejections`,
  `controls.suite.accepted`, `controls.suite.crashes`,
  `controls.real.c4096.designed_rejections`,
  `controls.real.c4096.skipped_by_name`

What the run checks. `zk-prover compose-probes` proves the honest statement once
and then, for each control, rebuilds the segment with one value bent and asks
the verifier to check the result against the honest statement. A control passes
only as a designed rejection: the JSON says `accepts: false`, and `falsified`
names the verdict fields the bend turned off, which is what says the control hit
the binding it was written for and not something else. A crash is never a pass.
The gate fails the run on a crash, on any control the verifier accepted, and on
the absence of a control over the model tree. A control the shape cannot state
is not a failure: the prover skips it by name with its reason, and both the name
and the reason are in the record.

What the run says. 236 controls refused for the reasons they were written for
over the five targets, none accepted, no crash, and the model tree covered on
the real segment and on each of the three synthetic shapes. Every honest proof
accepts.

| target | exit | designed rejections | skipped by name | not selected |
|---|---|---|---|---|
| `real` | 0 | 64 | 2 | 0 |
| `real_o_seam` | 0 | 1 | 1 | 64 |
| `syn_sound` | 0 | 50 | 3 | 0 |
| `syn_gkrfive` | 0 | 50 | 3 | 0 |
| `syn_aligned` | 0 | 71 | 0 | 0 |

The real segment is the campaign's point and it had never finished before. At
`32e8fae` the suite died on it at the control after `requant gateup: up
dequantized by another scale`, which was the 42nd, and took the 41 refusals
before it with the process (zk-prover #134). Here that same `requant gateup`
control is refused with three values off the master table, counted and recorded;
the table is the statement's own, narrowed by `--tight-table` from 2^25 to 2^23
with no slack; and the control after it, the one that used to abort, is skipped
by name. zk-prover #146 is what turned the abort into a counted refusal and made
the record outlive the process.

The one rejection on `real_o_seam` is not the seam's control. `--probe` selects
the controls whose name carries the string, and the tampered claim in the
statement is recorded outside that filter, so it fires on every target; the
seam's own control is the target's one skip. The 64 the filter left out are in
the record by name, which is what a filtered run can be read for.

Two controls are skipped on the real segment and three on two of the synthetic
shapes, and the reasons are different. On a dump the seam's control and the
model swap rebuild the segment around a second draw of the residual stream,
which is the synthetic construction's: a dump's activations are the dump's, and
a second draw lands outside the windows the statement pins from the honest
witness, so what would refuse such a witness is the draw and not the binding
under test (zk-prover #24). On `syn_sound` and `syn_gkrfive` the seam's control
is skipped because the shape cannot state it, and the two `jo` controls because
those statements' windows admit one `jo` for every row, and for every token, of
the witness and no other, so a one-step move leaves the window and is refused by
that lookup before the pin it tests can see it. `syn_aligned` states all 71.

The control that covers the model tree is the one that says the norm weight is
the model's and not the prover's. It rejects through the model root, and
`compose-probes` pins both of the honest run's roots, so what identifies it in
the gate is the refusal it was written for and the root that moved, never its
name, which says `norm_scale`.

How the run is made. On the SIMD backend, on the host's cores: a control is
about the statement, which is the same on both backends, and `synthetic-digests`
and `reference-digest` have already recorded that the CUDA backend reproduces
the SIMD proof byte for byte on these shapes. The real segment's line is taken
from a plan written over the witnesses `control-flags-off-c4096` extracted, with
the headline row's own layer flags, so the statement under test is the one the
headline run proved; the line goes last on the command line, so its own pins
win. The seam's control also runs in a process of its own through `--probe`,
which since zk-prover #151 costs the honest proof and nothing more, because the
filter is now read before a control rebuilds anything.

Host time. Three hours: the real segment 2 h 51 m of it at about 110 seconds a
control, its honest proof 100.3 s; the seam's process 4 minutes; the three
synthetic shapes 5 minutes between them. The build was already on the host.

## register-14b

```
tools/drivers/register-14b.sh <witness fields file>
```

runs: `2026-09-11-register-14b-none`
prover commit: none, the run proves nothing   harness commit: 64318ab
digests: none. The document's own identity is `prediction_sha256`
  `406cf7e43961547cec58957ecd2042bc0085ae4d84efc6508810248ce4de3c37` and
  `prediction_block_sha256`
  `2119d291f96cd0c1ee150cec3c00aa29c6d1fd8db547693f9bec044f1e0826f1`, both
  digests of the content and not of the file
binding: none; a run that commits nothing binds nothing, and the manifest says
  `kind` `harness`
unsound skips: none
constants file frozen: `constants.json` at
  `b7c3280bcb027b4cdb4c9ed4bbe530f29f29b7473c35e9ca448fc8471d670809`,
  `zk_results_commit` 485e69f
constants backed: the derived `e4.qwen2p5_14b.c4096.predicted_cells_per_token_layers`

What the run is. The prediction `predict-14b` is measured against, written down
before the measurement exists. It takes no host and no card: the registration is
a computation over this repository's `constants.json`, two layer segments two
recorded runs already proved, and the witness fields of the 48 dumps, so the
driver runs where the repository is and opens no ssh connection. A prediction
registered after the measurement would not be a prediction, which is the one
rule this experiment has, so the order is register, measure, compare and the
driver refuses to run once either a `register-14b` or a `predict-14b` run is in
`runs/`.

This registration REPLACES the one this run directory held before, and the old
one is in this repository's history at cb69914. Replacing it is allowed because
nothing has been measured against either: a registration is the document that
must not move after the measurement, and there is none. **Why it was replaced is
the table term.** The cost model priced the whole shape from per-unit constants
read off one measured 8B segment, and one of those inputs is the master exponent
table's size: it charged 2^23 rows on all 48 layers, because 2^23 is what the 8B
segments carry. This model's layers are not that. After `--tight-table` narrows
each one to the largest key its own key tiles look up, they are

| rows | 2^21 | 2^22 | 2^23 | 2^24 | 2^25 |
|---|---:|---:|---:|---:|---:|
| layers | 1 | 32 | 8 | 5 | 2 |

and five cells a table row makes the two layers at 2^25 short by 125.8 M cells
each. The owner's ruling on 2026-09-11 was to use the size the model is known to
need, so the registration now counts every segment from the prover's trace
layout at the fields that segment's own dump carries.

What the fields are, and why reading them keeps this a prediction. They are the
calibration a run takes off its own witness -- the master table's size, the
normalisation width, the attention output's five exponent and accumulator widths
and the fold's pins -- and every one of them is a property of the forward pass,
fixed before any proof is built: the prover derives them all inside its own
witness load, before it first touches a card. `harness/eval/predict/witness_fields.py`
reads them the same way on the host that holds the dumps, without proving,
and the file it writes is `witness-fields.json` in the run directory, one row
per layer with that dump's digest beside it. The registration names the file by
digest and carries every row inside its own hashed content, so the count can be
checked without the dumps.

What is registered. Qwen2.5-14B-Instruct, 48 layers, `d` 5,120, 40 heads of 128,
`dff` 13,824, at the statement `predict-14b.sh` proves -- the diagonal block and
the five reductions, which the driver and the registration compare flag by flag.
**Context 4,096 only**: a witness field is a property of one forward pass over
one prefix, and these dumps are that context's, so the other context is refused
rather than counted at fields it was not read at.

| C | cells/token, layers only | key tile half | the rest | one layer segment, mean |
|---|---:|---:|---:|---:|
| 4,096 | 158,802,703 | 28,002,240 | 130,800,463 | 1,693,895,499 |

Against the priced registration this replaces, at the same context and the same
statement: 151,193,309 against 158,802,703, +5.03 per cent, all of it in the
rest. The key tile half is the same integer on both, to the cell -- 259,604,480
base and 39,086,080 interaction cells a segment -- because it is a closed form of
the layout either way and the three grids tile exactly at 40 heads grouped 16,
16, 8. The 48 segments are 1,666,319,008 to 1,824,875,168 cells and no longer one
number, which is the other thing the priced model could not say. With every
witness field at the dearest value the recorded 8B runs carry, the same count is
171,554,425 a token, +8.03 per cent: that is what this shape would have to be
registered at if its witnesses did not exist.

Two of the 48 layers were not blind. The first proof attempt was rejected by the
prover's own verification (zk-prover #172), and those two rejected documents
reported `cells.fresh` for layers 0 and 1 before this registration was made. The
counted numbers are 1,793,630,880 and 1,824,875,168, which is what those two
documents reported, to the cell. Nothing here is fitted to them and neither is an
input to anything: the same code reproduces all 84 recorded 8B segments to the
cell without having seen this shape, and the registration's own provenance says
which two layers were visible and that the other 46 were not.

The 8B anchors, which are measured. The registration reads one layer 16 segment
per context out of the two headline runs, derived by `lib/seq5-reference.py` the
same way `predict-14b.sh` derives them, and the manifest's `derived` block names
the run, the slice output, the segment tag and the proof digest of each. On the
counted path the anchor is the same function at the same fields as the runs
recorded, and it reproduces both recorded whole-block rows
(`cells_per_position.headline.c*.fresh_layers_block`) exactly, to the cell, at
both contexts. That is not what the 14B is graded against: the acceptance range
was fixed in advance and is not rebased on any anchor.

Where every input came from. No cell cost is charged on the committed side at
all: every cell of every layer segment is counted. The 29 inputs the cost model
would charge are still recorded, with the source of each, so a reader can see the
two paths beside each other, and none of them is a number from outside these two
repositories. The driver refuses a registration that charged anything read from a
micro-benchmark inputs directory, and none was: the run passes no `--inputs` and
the gate reads the prediction's own record rather than the command line. It also
refuses a registration whose fields are not the file this run fetched, or whose
fields were read under knobs the measuring driver does not pass -- the head
grouping, the table rule and the quantize width are three of those, and a segment
counted at another grouping is another segment.

Why the pin moved, again. The driver pinned b39b806 and now pins 64318ab, which
is zk-prover #175 and is NOT merged: that is the commit that added the counted
path and the module that reads the fields. A registration is recorded against the
commit that made it whatever branch that commit is on, and the digest says so --
`frozen_inputs.code_sha256` holds the digest of every file the count is a
function of, `predict.py`, `exact_cells.py` and `witness_fields.py` among them,
so an edit to any of them re-registers the prediction under a new identity. That
is why the registration is made once, from one commit, and recorded before
anything measures.

## `register-13b`

```
tools/drivers/register-13b.sh <witness fields file>
```

runs: `2026-09-11-register-13b-none`
prover commit: none   harness commit: 5638f0f
digests: none; the run's own outputs are the registration and its configuration
binding: none; this run proves nothing
unsound skips: none
constants backed: none by the index's reckoning, which attributes a constant to
  the run named on it, and a projection names its inputs instead. The number
  this run produced is
  `e4.codellama_13b.c4096.registered_cells_per_token_layers`, whose note names
  this run id and the prediction digest below.

What the run is. The prediction `predict-13b` is measured against, written
before any proof of that model existed. It takes no host and no card: it is a
computation over this repository's `constants.json`, the two measured 8B layer
chunks the two headline runs already proved, and the witness fields file the
extraction wrote.

    prediction_sha256        1f72abda113efc9d21a2645173a0164b9155ceb6fcb4113ae8f0c9fb712f1d68
    prediction_block_sha256  e18f9d8483ab804c47badd889a56bd05ac5808f32024de12fe9e388624efc391
    constants.json frozen    841dcd6ebda5bbb0a082f28c1bcba5df474e78c0d9be21d7f5569d0353e59f5b
    zk_results_commit        b455227
    counted                  39 segments; layer 0 absent

Counted and not priced. On this path the model charges no per-unit cell cost on
the committed side. Every cell of every layer segment is counted from the
prover's trace layout at the witness fields that segment's own dump carries --
the master exponent table, the accumulator widths, the fold's pins -- and those
are properties of the forward pass, fixed the moment the witness is written and
before any proof of it exists. At a new model they are not the 8B's modal
values: over these 39 dumps the table runs 2^22 to 2^26 where the 8B's modal
value is 2^23, and a single assumed table would be wrong on most of them.

Why 39 and not 40. Layer 0 of this model is in no dump. The harness refuses to
write it, because the attention output's quotient term at that layer is
7 + 26 = 33 bits against the field's 31 in the widest form there is: the first
number is the int8 fold's target width minus one and the second is the layer's
own divisor range, which a driver may only widen. So the registration counts the
39 segments that exist and states in its own provenance which layer it does not
carry and that every per-token figure it holds is over the segments it counts.
Nothing at this quantization recovers that layer.

Why the frozen constants digest is not this repository's current one. A
registration freezes the constants file as it stood when the prediction was
made, which was before the measurement and therefore before the measured
constants below were added. That is the point of freezing it, and re-running
this driver now is refused for the same reason: a registration is made once, and
replacing one means removing the run that holds it, deliberately.

The registration this one replaced. An earlier registration was recorded on the
same day and removed before any proof existed. It counted a master exponent
table nobody proves at: the driver had inherited `predict-14b.sh`'s missing
`--tight-table` flag, which at this shape is not a small difference -- layer 1
asks for 2^29 rows without it and the prover's own circle domain is at most
2^31, so the column is refused outright, where with the flag that layer proves
at 2^26. Nothing was measured against either document (zk-results #111).

## `predict-13b`

```
tools/drivers/predict-13b.sh <host> <prover-commit> <harness-commit>
```

runs: `2026-09-11-predict-13b-h100`
prover commit: b08870a   harness commit: 1a6ed26
digests: 39, one per layer segment, in the manifest's `digests` map under the
  output that proved it; the first is `0f1cd29432390b50` and the last
  `a7c43e98e8c931d0`
binding (from the manifest, folded over the 39 proofs): 1 to 14 bound; 15 and 16
  absent, which is a segment that is neither the first nor the head, on every
  one of them
unsound skips: none
constants backed: `e4.codellama_13b.c4096.layers`,
  `e4.codellama_13b.c4096.cells_fresh_by_layer`,
  `e4.codellama_13b.c4096.cells_fresh`,
  `e4.codellama_13b.c4096.cells_per_token_layers`,
  `e4.codellama_13b.c4096.key_tiles_cells`,
  `e4.codellama_13b.c4096.peak_rss_bytes`, `positions.predict13b.c4096`,
  `proof.predict13b.c4096.bytes_per_segment_median`,
  `proof.predict13b.c4096.total_bytes`, and the derived
  `e4.codellama_13b.c4096.rho`, `e4.codellama_13b.c4096.residual_pct`,
  `proof.predict13b.c4096.bytes_per_position`,
  `proof.predict13b.c4096.bytes_per_segment_mean` and
  `proof.predict13b.c4096.bytes_per_segment_over_8b`

What the run measures. E4's third scale: a model shape the cost model was never
fitted on, proved one layer segment per process, at S=512 against a 4,096-token
prefix on the reference backend, spec `b10-final`, head groups 16,16,8, every
binding gadget on and no skip flag anywhere. 39 segments of CodeLlama-13b-hf --
40 attention heads of 128, hidden 5,120, inner 13,824, one key/value head per
attention head -- against the 8B the model was fitted at, which is 32 heads,
hidden 4,096, inner 14,336 and one key/value head per four.

Why this model. Qwen2.5-14B, the shape E4 registered, cannot be proved at all:
it biases the q, k and v projections, the statement has no site for a projection
bias, and the honest segment is rejected on the one equality that compares the
derived integer with the key tile's (zk-prover #172, and #174 for the component
that would be needed). The extractor refuses a biased matmul by name now, so
those witnesses cannot be rebuilt either. What E4 predicts is a shape and not a
checkpoint, so the measurement moved to the nearest bias-free model of that
class. Whether this becomes E4's third-scale row rather than the 14B is the
owner's decision (zk-prover PR 173, decision 3) and is not taken here.

Why 39 layers and not 40. Layer 0 is in no dump and in no proof: the harness
refuses to write it, because its attention output's quotient term is
7 + 26 = 33 bits against the field's 31 in the widest form there is, and the
divisor range is the layer's own, which a driver may only widen. The prover
would not have said so -- it takes the wider form and proves on, and there is no
cap check on that side -- so the harness's refusal is what catches it, and the
run records the refusal and proves the other 39. No other layer is near that limit:
their divisor ranges run 15 to 19 bits. Every figure in this
entry and every constant it backs is a 39-segment figure and not the stack's.

What the run says. 78,094,735,408 fresh committed cells over the 39 segments of
one 512-token block, which is 152,528,780 cells per decoded token in the layers
this run proves. The key tiles committed 259,604,480 base cells and 39,086,080
interaction cells on every one of the 39, the same integers on all of them. The master exponent table is the one thing that moves: 2^22 on nineteen
segments, 2^23 on thirteen, 2^24 on five, 2^25 on one and 2^26 on one, and the
spread between the cheapest and dearest segment is 16 per cent for that reason
alone. `kmax` is 19 on every segment and the attention output's remainder width
runs 15 to 19 bits.

What the comparison says. The registered prediction and the measurement agree on
every one of the 39 segments, to the cell, and therefore on the total:

    predicted cells/token (layers)  152,528,780.09375
    measured  cells/token (layers)  152,528,780.09375
    rho                             1.00000   (+0.000 per cent)

The comparison is protocol A with no widening, because the run proved every
segment the registration counts and nothing is extrapolated from a sample. The
key tiles' two integers are the registered ones on every chunk; the
boundary trees are 94,371,840 on every chunk, which is the closed form at this
shape; and the fields the registration counted each segment at are the fields
the prover derived for it, checked one segment at a time. The ratio is inside the
narrowest of E4's three pre-registered thresholds, and that range is E4's,
applied to a shape E4 did not register: whether this run is graded that way is the owner's
decision and not settled here.

Read the residual for what it is. It is not a fit within three per cent; it is
zero. The count is of a layout, and a layout counted correctly reproduces the
number a proof of it reports exactly, which is what the 84 recorded 8B segments
already showed and what this shape shows again without the counting code having
ever seen it. What the run tests is whether the layout is the one the prover
builds at a shape nothing was fitted at, and the answer is that it is.

One of the 39 layers was not blind. Layer 16 of this model was extracted and
proved once before the registration was made, as a probe of whether a bias-free
model of this class proves at all, and that proof reported `cells.fresh`
2,290,115,312 at these flags. The registration's own provenance says so. It made
no run record, the dump it proved is not one of the dumps this run proves, and
the other 38 were blind.

How the run is made. Two phases with the registration between them, because a
counted registration is read off the dumps and a prediction written after a
proof is not a prediction. The first call extracts, writes the witness fields
file and stops before the first proof; the fields file is fetched, the
registration recorded, the status file cleared, and the same call made again
proves. The weights are 26,034,525,679 bytes of safetensors -- this checkpoint
publishes a second complete copy of itself in the older pickle format and the
driver does not fetch it -- and the 39 dumps are 24,292,170,179 bytes.

Host time. 5,331 seconds of proving over 39 processes, one per segment, 20 rayon
threads each: 190 seconds the dearest segment and 128 the cheapest. The largest
process held 231,041,085,440 bytes, which is layer 1, the one segment whose
master exponent table is 2^26, against 235 GB on the machine; every other
segment stayed under 128 GB. The serialized statements and proofs are
1,350,216,784 bytes of proof over the 39 chunks and 3,520,037,495 serialized.

## `cost-model`

```
tools/drivers/cost-model.sh <prover-commit> <harness-commit>
tools/drivers/cost-model.sh --dry-run <prover-commit> <harness-commit>
tools/drivers/cost-model.sh --routing <run-id>:<row> <prover-commit> <harness-commit>
```

runs: `2026-09-13-cost-model-none`, which supersedes
  `2026-09-12-cost-model-none`, and `2026-09-13-cost-model-routing-none`
prover commit: none   harness commit: 6589471, and `7ef4122` for the routing run
digests: none; the run makes no proof and commits nothing
binding: none; this run proves nothing
unsound skips: none
constants backed: the 247 rows the index lists against the first run --
  `frontier.<model>.h100.c<ctx>.<scope>.cards_for_20` and its
  `usd_per_mposition` twin for all nine shapes at two contexts and four scopes,
  the same dollars under the two layouts nobody has built
  (`usd_per_mposition_kv_shared` on the six grouped-query shapes and
  `usd_per_mposition_mla_absorbed` on the three latent ones), the eighteen
  ratios that say what each of those two is worth
  (`frontier.<model>.c<ctx>.kv_shared_saving_pct` and
  `frontier.<model>.c<ctx>.mla_absorbed_pct`), the ten `moe.<model>.*` ratios
  and the three `frontier.calibration.*` residuals, all grade `projected`. The
  twenty-one `assumption.cost_model.*` keys each of them names in its `inputs`
  are not this run's: eleven are `measured` off the two headline runs and ten
  are `asserted`. The routing run backs the 19 the index lists against it:
  `frontier.qwen3-235b-a22b.h100.c<ctx>.<scope>.cards_for_20_routing_measured`
  and its `usd_per_mposition` twin at both contexts and all four scopes,
  `moe.qwen3-235b-a22b.fresh_over_dense_routing_measured`, and the two
  `frontier.qwen3-235b-a22b.c<ctx>.routing_measured_pct` rows, all `projected`.
  Each of them names in its `inputs` the uniform row it sits beside and the
  three `moe.routing.qwen3_30b_a3b.c<ctx>.s512.*` rows of
  `2026-09-13-moe-routing-h100`.

What the run is. The frontier price table, projected from this repository's own
constants and from nothing else, and the first driver that needs no host. It
archives the pinned harness commit, synchronizes its environment, runs
`harness.costmodel.frontier` against `constants.json` with the two
micro-benchmark directory variables unset, and reads the model's own provenance
block to decide whether it may record anything. `ZK_PROVER_DIR` names a local
`zk-prover` clone where the driver's default is not one. `--dry-run` prints the
same rows, lets the model fall back to the micro-benchmark directory and writes
nothing. The sources are unpacked under `$TMPDIR`, which needs about 2 GB for
the unpacked tree and the harness's pinned environment; both runs of this entry
were made with `TMPDIR=/var/tmp`.

The pin, and this time it is on main. `6589471` is the head of zk-prover's main
and carries all three of the pull requests the superseded entry was waiting on.
zk-prover #181 named the one per-unit cell cost a counted row charges by its
constants key, so every `preprocessed_over_fresh` row names
`model_constants.weight_freivalds_preprocessed_cells_per_weight` and no recorded
`inputs` list is short. #182 counts the keys and values per key/value head
beside the per-head count the prover builds, and adds the key `kv_per_head`.
#186 counts the three multi-head latent attention shapes from the five widths
their own configs publish, both ways, and adds `mla_form`,
`mla_cache_per_tile`, `mla_latent_norm` and `mla_seams`. The 2026-09-12 run was
pinned at `d9f891d`, the head of the then unmerged #181.

Why this run replaces the older one rather than sitting beside it. A projected
row is not a measurement, so two runs of the same model at two commits are not
two observations of anything: the newer commit is simply what the model says
now, and the older rows would only be a second answer to the same question. The
run directory stays under `runs/` and its manifest with it; it backs no entry.
Nothing it priced moved: all 103 rows of 2026-09-12 come back here to the digit,
card, context, timing scope, unit and note included, and the only change on them
is that their `inputs` name the five new assumption keys.

What it printed. 247 rows, all of them recordable, over all nine shapes. The
three multi-head latent attention shapes -- DeepSeek-V3, Kimi K2, Kimi K3 --
are priced for the first time. They are counted both ways: the rows record the
materialised layout, which expands the keys and the values per head before the
attention, and the absorbed layout, which folds the low-rank pair into the query
side and caches the latent itself, is recorded beside them under
`usd_per_mposition_mla_absorbed`. The absorbed one is the dearer of the two at
every shape and both contexts, by 5.4 to 18.9 per cent, so the recorded number
is also the cheaper one. The six grouped-query shapes carry a second column of
the same kind, for a prover that shared its keys and values across a group: 2.2
to 5.3 per cent of a proved position at C=4,096 and 6.4 to 13.4 per cent at
C=16,384. No AIR in this project builds either layout, and the sharing figure is
a floor, because the interaction columns those same key and value columns carry
are not in it. No H200 row is printed at all: the H200 rate this repository
holds is the private archive's decode-only sequence, and the driver runs with
the archive variables unset. The calibration is the run's own check and has not
moved: `frontier.calibration.c4096.residual_pct` at one context and
`frontier.calibration.c16384.residual_pct` at the other, and the worse of the
two is what the whole table stands on.

What the gate refuses. A projection is only worth recording when every number
behind it is in this repository. The driver reads the model's own provenance
block input by input and refuses on a charged cell cost that came from anywhere
but the constants file, on a statement whose layout is not read from the
constants file, on a measured rate that is not a key here, on a model that ran
at another commit or in a dirty tree, and on an `assumption.cost_model.<field>`
that is not an entry of `constants.json`. It also refuses when the model marks
its own table not recordable and the gate found no reason of its own, so the two
verdicts can never disagree silently. The run that made this entry passed all of
them. The same commit run against this file before the five new assumption keys
were recorded refuses on exactly those five and records nothing, which is the
contract working, and it is the same refusal `80dd8ee` met on all sixteen a day
before the superseded run.

Where the twenty-one come from. Eleven are the mode of one field over the 64
layer and first segments of the two recorded headline runs, `slice_0256.json` of
`2026-09-09-headline-c4096-h100` and `slice_1024.json` of
`2026-09-08-headline-c16384-h100`, which are the same two artifacts the composed
prices are read off. `audit.py`'s `witness_assumptions` section re-derives each
mode from those two artifacts and fails if one has moved, and it breaks a draw
the way the cost model's own `modal_witness` does: the most common value, and
the smallest of them where two are as common. The other ten are in no run -- the
head grouping, the head a key and a value are committed once for, the softmax
and the rounding a run of another shape would be proved at, the two a mixture
row assumes about routing, and the four a latent attention row assumes about its
layout -- so they are `asserted` with the reason in the note.
`assumption.cost_model.moe_router` is an upper bound and not a point estimate;
this file has no `bound` grade, so it is `asserted` and its note carries the
bound.

The measured routing, and it is an argument because it is a decision.
`--routing <run-id>:<row>` prices one mixture row a second time at the per-expert
token counts a `moe-routing` run recorded, and records those rows BESIDE the
uniform ones under names ending `_routing_measured`, never instead of them. The
argument states the whole of the decision: whose routing, and which row it is
applied to. `2026-09-13-moe-routing-h100` measured Qwen3-30B-A3B and keys its
table by that model, which the frontier holds no row for, so `--routing` refuses
the table until someone re-keys it. This driver is where that happens, once, in
the open: it reads the table out of the recorded run's own artifact, re-keys it
to the row the argument names, refuses a table whose token slots are not the
block's `S k`, and writes the re-keyed table itself -- with whose routing it is
and which row it went onto -- into the manifest's `derived` block, which is where
a run says what it took from an earlier run. So the exact input every recorded
row was priced at is in this repository twice over: as the measuring run's
artifact, and as the table in the pricing run's own manifest.

What the table is, and it is one block. The measuring run writes the
representative block -- the median by distinct experts over every mixture layer
and every prompt -- and not a mean, because a mean of histograms is not a routing
any block had. So a row priced this way is priced at that one block's routing for
every block of every layer: at C=4,096 it is layer 10, prompt 4, block 3, which
touches 73 experts and whose busiest matmul covers 510 of the 512 positions
against the 462.6 the mean busiest of every block is. Both figures are in the
measuring run and the row's note says which one it stands on.

The three tables a routing run prints. The uniform table first -- it is what a
measured row is recorded beside and what every other shape's row is held to --
and then one table per context the routing was measured at, because the model
holds one routing at a time and a context's rows are priced at the table that
context's own prompts produced. The gate refuses on a row of any other shape that
moved between them: a routing measured on one model prices one row.

The routing run's pin, and it is not on main either. It is zk-prover `7ef4122`,
the head of `routing-measured`, which is zk-prover PR 191 against main and is
unmerged, as `2026-09-12-cost-model-none` is pinned at the head of the unmerged
#181. Two things were missing and the table refused the shape without them: how a
measured block tiles, and how many experts the preprocessed trace holds. A routed
expert's `down` matmul has 4,096 outputs and its only divisors are powers of two,
so its rows are the token count shifted and `MatLayout::choose_padded` refuses
every count whose leading bits are under 1.5. 463 tokens tile -- 512 rows with 49
of lead, under the quarter the chooser allows -- so that expert is ONE matmul, and
that is what the prover builds. 268 tokens tile at no width, and the count falls
back to the rule the uniform share is laid out by: the largest power of two at or
below the count, then the remainder the same way, so 268 is 256 + 8 + 4. The
token count is conserved in a split and rounded up in a padded matmul, and
neither changes how many experts the segment reads: that is what the preprocessed
trace holds the weights of, and before #191 it was the uniform `E (1 - (1 -
k/E)^S)` whatever the routing, so a row counted at 73 experts' matmuls still
charged 128 experts' weights.

What the measurement moved, at S=512 and the five reductions on:

```
                                     uniform    measured    move
  C=4,096   cells a proved position  384,360,142  391,372,542   +1.82%
            loop, USD a Mposition       3,555.59     3,620.46   +1.82%
            loop, cards for 20                78           80
            stwo total, USD a Mposition   275.28       280.30   +1.82%
            preprocessed a token     471,320,245  275,127,868  -41.63%
  C=16,384  cells a proved position  537,461,481  548,698,617   +2.09%
            loop, USD a Mposition       5,971.95     6,096.81   +2.09%
            loop, cards for 20               131          134
            stwo total, USD a Mposition   413.73       422.38   +2.09%
            preprocessed a token     471,320,245  271,560,734  -42.38%
```

The two halves of the assumption move the price in opposite directions and the
committed side nets out close to nothing. The segment reads 73 of the 128 experts
instead of all of them, so its preprocessed weight trace -- which no measured rate
counts -- holds 42 per cent fewer weights; the same comparison counting that
trace is 1.9147 at the measured routing against the 2.4171 this file records at
the uniform one, and this run does not record it. But
the tokens are nowhere near level on the experts they do touch, and 73 lopsided
matmuls cost more in committed cells than 128 level ones: one of 510 tokens pays
2 rows of padding, one of 3 pays the fixed side of a matmul for three tokens. The
net is 1.8 per cent dearer a proved position at C=4,096 and 2.1 at C=16,384. It is
the first mixture row in this repository priced at a routing that was measured
rather than assumed, and the assumption it replaces is stated in every one of its
notes: the routing is Qwen3-30B-A3B's, applied to Qwen3-235B-A22B because the two
route alike -- 128 experts, top-8, no shared expert, every layer a mixture layer
-- and they are not the same weights.

How the layout is chosen is a judgement and the number depends on it. One matmul
an expert wherever the chooser has a layout is what #191 counts and is the +1.8
per cent above; the strict rule, every block a power of two and no padding at all,
turns 73 experts into 206 matmuls, 139 of them under sixteen tokens, and comes out
10.3 per cent dearer instead. The first is what the prover builds.

## moe-routing

```
tools/drivers/moe-routing.sh download <host> <model> <ctx>[,<ctx>...]
tools/drivers/moe-routing.sh run      <host> <model> <ctx>[,<ctx>...]
```

runs: `2026-09-13-moe-routing-h100`
prover commit: none   harness commit: `6589471`
digests: none; the run makes no proof and commits nothing
binding: none; this run proves nothing
unsound skips: none
constants backed: the 18 rows the index lists against this run --
`moe.routing.qwen3_30b_a3b.c<ctx>.s<S>.distinct_experts_mean` at both contexts and
all four block sizes, grade `measured`; the same rows' `distinct_experts_uniform`,
grade `derived`; and `...c<ctx>.s512.tokens_per_expert_max_mean`, grade `measured`.

What the run is. `assumption.cost_model.moe_routing` says every token's top-k is
uniform over the experts, and one number is what a counted mixture row reads off
it: how many distinct experts a block of S positions touches, which is how many
routed matmuls the segment builds and whose weights its preprocessed trace holds.
`harness/costmodel/exact_cells.py` at zk-prover `6589471` is where it is used --
`expected_distinct_experts` returns `E (1 - (1 - k/E)^S)`, `segment_params` builds
that many routed matmuls out of it, and `routed_blocks` spreads the block's `S k`
token slots over them. It is per block of S positions and not per key tile: the
routed side of a mixture layer's `params` block is a function of S and the routing
alone, and the context enters a mixture layer only through the attention side,
which no expert sees. This run measures that same quantity on a real forward pass,
per mixture layer and per block of S in 128, 256, 512 and 1,024, with the
assumption's own answer computed beside every figure out of the same E, k and S.
No proof is involved and none is possible: no run of any mixture model has been
proved.

The model. `Qwen/Qwen3-30B-A3B` at revision
`ad44e777bcd18fa416d9da3bd8f70d33ebb85d39`: `num_experts` 128,
`num_experts_per_tok` 8, `moe_intermediate_size` 768, `decoder_sparse_step` 1,
`mlp_only_layers` empty and no shared-expert key, so all 48 of its layers are
mixture layers and the run hooked all 48 routers. That is the routing shape of the
priced Qwen3-235B-A22B row -- 128 experts, top-8, no shared expert, every layer a
mixture layer -- at 61,084,157,680 bytes of bf16 weights instead of about 470 GB.
Whether one model's routing may price the other's row is a decision and the run
does not take it: `routing_table` in the artifact is keyed by the measured model's
own slug, which the frontier holds no row for.

The corpus. The harness's own eval slice, `harness/witness/text.txt` through
`harness.witness.common.tokens` at the pinned commit, tokenized by this model:
20,480 token ids, five disjoint prompts at 4,096 and one at 16,384, which is the
longest the corpus gives there.

What it measured, meaned over the 48 mixture layers and every block of every
prompt:

```
   ctx     S   distinct  assumed   ratio   busiest expert   the model builds
  4096   128     58.581  127.967  0.4578    116.80 / 128      8 tokens x 128
  4096   256     65.999  128.000  0.5156    232.21 / 256     16 tokens x 128
  4096   512     73.163  128.000  0.5716    462.57 / 512     32 tokens x 128
  4096  1024     80.598  128.000  0.6297    922.52 / 1024    64 tokens x 128
 16384   128     58.316  127.967  0.4557    116.02 / 128      8 tokens x 128
 16384   256     65.552  128.000  0.5121    230.59 / 256     16 tokens x 128
 16384   512     72.717  128.000  0.5681    459.18 / 512     32 tokens x 128
 16384  1024     79.940  128.000  0.6245    915.46 / 1024    64 tokens x 128
```

The assumption is wrong in both halves, and in the same direction. A block of 512
positions touches **73.2 of the 128 experts**, not 128: the segment builds 57 per
cent of the routed matmuls the count charges it for, and its preprocessed trace
holds 57 per cent of the routed weights. And the tokens are nowhere near level on
the experts they do touch. The busiest expert of a 512-position block takes 462.6
of those positions on average against the 32 the count lays out, the quietest
takes 1, and in the median block -- layer 10, prompt 4, block 3, 73 experts --
one matmul covers 510 of the 512 positions, the next 420, and half the token slots
sit on matmuls of 186 tokens or more while eight experts take a single token each.
Both contexts agree to within one per cent of each other, so this is the model's
routing and not one prompt's. Per layer the count runs from 49.0 at layer 19 to
112.4 at layer 0, and no block of any layer reached 128: over all 1,920 blocks at
c4096, S=512 the count ran 39 to 118.

Which way it moves a price is not recorded here and is not this run's to say: the
entry's own note prices the assumption by putting the same token slots on 8
experts of 512 tokens each, so a measured distribution has to be put through
`harness.costmodel.frontier --routing FILE` -- a `cost-model` run -- before any row
moves. The artifact carries the distribution in the shape that reads, per context,
at S=512.

The host, and what it cost. Two subcommands, because the two halves need different
things: `download` needs the network and the disk and not the card, so it takes no
`~/.zk-run.lock`, ran beside another campaign, and refused before writing a byte
unless the free space would leave 40 GB behind for the jobs already queued -- it
fetched 61,084,157,680 bytes in 149.4 seconds and left 50.6 GB free. `run` needs
the card to itself: it goes through `tools/remote/run.sh`, holds the lock, and read
the snapshot the download left with `HF_HUB_OFFLINE` set. It held the card for
**72 seconds**, of which 62 were the weight load; the six forward passes took about
ten seconds in all, 0.8 seconds for the one at 16,384.

Two things the host made necessary, both recorded in the run's `config.json`. The
weights are read straight onto the card through a device map, never into host
memory and moved afterwards, because the host is a container with a memory cap of
its own; the script refuses a load that left a parameter behind, and this one
reported `cuda:0` for every parameter at 8.6 GiB of host memory. transformers reads
a device map only when `accelerate` is importable and the pinned lock holds none,
so the job puts `accelerate` and `psutil` on top of the pinned environment with
`--no-deps`, which resolves nothing and cannot move the pinned torch; the next
campaign's own `uv sync --frozen` takes them away again. The run was made at
`accelerate` 1.15.0, torch 2.13.0+cu129, transformers 5.15.0, numpy 2.5.2.


## `verify-consumer`

```
tools/drivers/verify-consumer.sh <host> <artifact-dir> <verifier-binary> <cores>
```

runs: `2026-09-13-verify-consumer-h100`
prover commit: 6589471   harness commit: 6589471, and no harness ran: the run's
  only program is that binary, and the manifest names a commit either way
digests: none; the run makes no proof. The proof it checks is
  `c5c75572ca078b6c551edd62d72ed96d7f0357958e1bbc805f803328ee270054`, which is
  the digest `2026-09-13-reference-digest-plain-h100` recorded for this segment
binding: none; this run proves nothing
unsound skips: none
constants backed: `verify.consumer.c16384.secs_per_segment_median` and
  `verify.consumer.c16384.peak_rss_bytes`, both `measured`, and
  `verify.consumer.c16384.secs_total_sequence`, which is the first times
  `segments.headline.c16384`

What the run is. The first verification this repository records on a machine of
the size a reader means by a consumer machine: four cores and no card. Every
other verify row here is the run host's sixteen cores beside the card. It builds
nothing, proves nothing, takes no host lock and touches no card; it is given a
binary and a directory of bytes and runs the replay the artifact's README gives,
three times, each repetition a process of its own under `/usr/bin/time -v`. The
cores are the first four of the cpuset the run is confined to, and the binary
reports four threads in its own `env` block, which the run checks.

What it replays. One Llama-3.1-8B layer-16 segment, `S = 512` output positions
against a `C = 16,384` key prefix, the five reductions on and no skip in effect:
the proof `2026-09-13-reference-digest-plain-h100` made, kept beside that run
with its statement, its published claims, the calibration and the prompt ids.
The driver pins all seven digests, so a directory that hashes to anything else
is refused before a second of work is spent on it, and it leaves a `SHA256SUMS`
behind where the host holds none. The proof is 169,277,485 bytes. It is not in
this repository: whether it goes into git is the owner's to decide.

What it measured. The verifier accepted all three times, at 42.91, 43.17 and
44.76 seconds of its own; the three processes took 43.89, 44.09 and 45.69
seconds of wall-clock time and peaked at 30,652,805,120, 30,588,841,984 and
30,541,778,944 bytes. 42.25 s of the median is the one shape root the verifier
derives from the published calibration and compares with the one the statement
carries; what is left is the proof's own check, 0.92 s, against 0.757 s for the
median segment of the sequence on sixteen cores. Four cores and 32 GB of memory
are therefore enough to check a segment of the widest sequence this repository
has proved, in three quarters of a minute.

Which check ran where. `verify.headline.c16384.secs_total` and its median are
the same sequence on the run host's sixteen cores, and that pass was given no
calibration: its `shape_roots` field is null, so it derived no shape root and is
the proof checks alone. This run derives one, which is most of its seconds. The
two rows are in the same timing scope and are not the same measurement, and
`verify.consumer.c16384.secs_total_sequence` says which of the two it multiplies.

The negative control. A copy of the three serialized documents under a scratch
directory on the host, with one byte of the proof body changed: byte 84,699,131
of 169,277,485, the last digit of the number `129`, which became `120`. The file
keeps its length and every other byte, and the copy hashes to
`4172cbea24c3d99e7b4d43fe720ae30affc995c5e9f866a7754d7505fa901a74`. The verifier
refused it, exit 1, in 42.53 s: `grid verify llama31-8b-l16-s512-c16384:
REJECTED`, with `stark` false and `error` `Merkle(RootMismatch)` and every other
field of the verdict true -- the shape root still derives and matches, the sums
still cancel, and what fails is the proof. A control the verifier accepts fails
the run and records nothing.

What is not measured. A segment at context 4,096, which is smaller in every
term: no proof of one is kept anywhere, so the smaller case has not been
replayed on a machine of this size. The run also says nothing about a machine
with fewer than four cores or less memory, and nothing about how long the whole
sequence takes in one process: every number here is one segment at a time.

## memory-probe-context

    tools/drivers/memory-probe-context.sh <host> <prover-commit> <harness-commit> <context>

runs: `2026-09-13-memory-probe-c24576-h100`
prover commit: 6589471   harness commit: 6589471
digests: layer 16 of the last token block, `dc56b8482e172eeb`, the same from the
  card (`decode.json`) and from the reference backend (`reference-simd.json`)
binding: 1 to 15 bound; 16 absent   (from the manifest)
unsound skips: none
constants backed: `mem.probe.c24576.decode_peak_mib`,
  `mem.probe.c24576.layer0_oom_peak_mib`, `secs.probe.c24576.decode_loop`,
  `bits.probe.c24576.layer0_ao_acc`,
  `bits.probe.c24576.layer0_ao_no_wrap_margin`

What the run measures. Where one 80 GB card gives out as the context grows.
Issue #115 records three memory rows off a straight line through two measured
peaks, and the row that decides the most says one card is full at a context of
about 23,065. Two points cannot show that a line is straight, so this driver
proves segments at a context it is told and records what the card holds. The
context is an argument and the run name carries it, so each context is its own
status file, its own directory on the host and its own run id.

What it proved, and what it did not. Two segments of the last token block, one
process each, the pipeline off, the card sampled once a second. Layer 16, the
reference layer, whose shape 12 of that block's 32 segments have, peaked at
79,643 MiB of the card's 81,559 and proved. Layer 0, which carries the embedding
gadget and is the largest segment of the plan, did not: it ran the card out of
memory, and the most the card reported holding before the allocation it could
not serve was 81,073 MiB, 486 short of the card. Layer 0 is the segment the
headline loops' peaks are -- 78,843 MiB on its own at context 16,384 against
that loop's 78,799 -- so it is the segment the projected rows are a line
through, and its failure is the measurement those rows wanted. Between them the
two contexts put the card's limit in the open range from 16,384 to 24,576, with
the projected 23,065 inside it.

Layer 16 is proved first and layer 0 last, and that order is the measurement.
The projection puts layer 0 above the card at this context, so measured first a
failure there would have cost the other segment; measured last it cost nothing,
and the reference backend then proved layer 16 again in host memory. That proof
is the run's provenance anchor: a segment the card cannot hold writes no output
at all, and without an anchor the answer most worth recording could not have
been recorded. It hashes to the digest the card's proof of the same segment
hashed to.

The shapes this host could not emit. `plan.py` writes one emit line per distinct
shape of the block, keyed by the master exponent table's width, and at this
context the block's widest is 2^28 rows -- one bit past anything the recorded
campaigns have emitted, and layer 1's alone. Emitting it needs more memory than
the host had: the job was killed twice by the container's out-of-memory killer
at exactly that shape, after the extraction and before a segment was proved.
`--tight-table` narrows the table to the keys the witness has, but only after
the width the shape asks for is built, so it does not bound what emitting
costs. So the
driver emits the shapes its proved segments carry and no others -- 2^25 and
2^27 here -- and `emit.json` records which shapes the block had and which were
emitted. That narrowing is open to a probe and not to a loop that proves all 32
layers: at this context such a loop could not be built on this host at all,
whatever the card would have held. zk-prover #190 has that and the build
script's hardcoded sixteen-way kernel compile.

What 32,768 did, and why it has no run directory. The same driver was run at
32,768 on 2026-09-14 and got as far as the first extraction pass, where it
refused, by name and in three minutes of card time:

    block 64 layer 0: the attention output's no-wrap window does not fit:
    1 + 16 + 9 + 6 = 32 > 31 (over by 1, magnitude form). The two limbs must
    together cover |acc| (25 bits) and the exponent window must cover
    e = jv - jo, so no wider decomposition of either recovers a bit, and the one
    bit the magnitude form is worth is already taken. What is left is a narrower
    context or a quantization whose accumulator is narrower.

That is the answer at 32,768 and not a fault of the run. The accumulator sums
over the prefix, so it gains a bit as the context doubles: 24 bits at 24,576, 25
at 32,768. The 24,576 table above records the width and the two exponents, and
what they come to there is exactly the field's 31 with nothing left, which is the
constant beside them. One context further the same window is 32 and the
extraction will not write the dump. So above 24,576 the memory question does not
arise under this quantization variant: the segment cannot be written, let alone
proved, on a card of any size.

It leaves no run directory, and that is a real gap rather than a choice. A
manifest is copied from a prover's provenance block and refuses a fetched
directory that has none; here nothing was proved, because the refusal is in the
extraction and comes before any prover runs. The 16,384-token probe's reference
segment exists to keep an out-of-memory answer recordable, and it cannot help
with this one: the plan a reference proof would be sliced from is built from a
shape table over all 32 layers, and layer 0 has no dump. What the repository
holds instead is the 24,576 row above, whose margin of nothing predicts this
refusal, and the log line quoted here.

How the run is made. The prompt is the corpus's first 24,576 tokens and the
model's own greedy continuation under the variant the paper reports, generated
the way the 16,384-token campaign generates it; the pinned harness cuts its eval
corpus at 20,480 tokens and refuses a prompt length that is not a power of two,
so the job carries a shim that lifts both and checks that the wider slice begins
with the tokens the recorded campaigns read (zk-prover #187). The forward pass
runs the whole sequence, because a block reads the keys and values of every
block before it, and only the last block's dumps are written: 32 layers, 15.2
GiB in 1,434 seconds over five passes, beside 7.5 GiB of block-invariant files
-- the same 7.5 GiB the 16,384-token probe measured, which is where the block
dumps grow with the context and these do not. The pins the segments are proved
at are that whole block's worst case and not the proved layers' own rows, so
what is proved is the shape a headline loop at this context would prove; at
24,576 those pins are the 16,384-token campaign's exactly.


## block-length-c4096

    tools/drivers/block-length-c4096.sh <host> <prover-commit> <harness-commit> <S>

runs: 2026-09-13-block-length-c4096-s256-h100 (S = 256, the last block's 32
  layer segments); 2026-09-14-block-length-c4096-s1024-h100 (S = 1,024, layer 16
  of the last block alone)
prover commit: 6589471   harness commit: 6589471
digests: at S = 256 the block's 32 layer segments, in `card.json`, of which
  layer 16's first 16 hex are `9fae85fa8d67d93b`; at S = 1,024 the one segment's
  are `6f0be75ebf8749ea`. At both block lengths the reference backend proved
  that same layer 16 segment to the same bytes, in `reference-simd.json`
binding: S = 256, 1 to 15 bound and 16 absent; S = 1,024, 1 to 14 bound and 15
  and 16 absent   (from the manifests)
unsound skips: none
constants backed, at each of `s256` and `s1024`:
  `segments.block.c4096.s<S>`, `cells.block.c4096.s<S>.fresh`,
  `secs.block.c4096.s<S>.{commit,stwo_total,whole_wall,loop}`,
  `mem.block.c4096.s<S>.peak_mib`,
  `proof.block.c4096.s<S>.bytes_per_segment_median`,
  `secs_per_segment.block.c4096.s<S>.{commit,stwo_total,whole_wall,loop}`,
  `cells.block.c4096.s<S>.exact_predicted`, `cells.block.c4096.s<S>.rho`

What the runs measure. Every other number in this repository is at S = 512
positions a segment. S is in the statement twice over: the prefix is tiled into
key blocks of S, so the key tile term of a segment's cells moves with it, and
the weights are committed once a segment whatever S is, so the per-position
share of them is the model's weights over S. These two runs prove the last token
block of the context 4,096 plan at S = 256 and at S = 1,024 -- block 16 of 17
and block 4 of 5, both over the same 4,096-position prefix and under the same
flags as `headline-c4096`'s block 8, which is the S = 512 point they are read
against. At S = 256 the whole block is proved, 32 layer segments. At S = 1,024
one segment is: layer 16, which `lib/seq5-reference.py` reads as this
repository's reference segment at a context, because a block that long was
expected not to fit an 80 GB card and one segment answers that most cheaply.

The one row every block length has in common is therefore that layer, and this
is it. The S = 512 column is `runs/2026-09-09-headline-c4096-h100`'s B8L16, off
its slice output, and `loop` in this table is each chunk's own share of its
process at all three, so that the column compares like with like; the process
figure at S = 1,024, which also reads the witness and builds the layer, is
`secs.block.c4096.s1024.loop`, 43.844 s.

| layer 16 of the last block | S = 256 | S = 512 | S = 1,024 |
|---|---|---|---|
| fresh cells | 803,041,312 | 1,393,069,168 | 2,631,844,976 |
| ... a proved position | 3,136,880 | 2,720,838 | 2,570,161 |
| commit, s | 0.927 | 0.652 | 0.823 |
| stwo total, s | 1.468 | 1.090 | 1.274 |
| whole wall-clock, s | 12.780 | 21.176 | 39.584 |
| loop, s | 8.704 | 12.937 | 22.603 |
| whole wall-clock, s a proved position | 0.0499 | 0.0414 | 0.0387 |
| loop, s a proved position | 0.0340 | 0.0253 | 0.0221 |
| serialized proof, bytes | 110,821,768 | 82,827,883 | 69,864,042 |
| ... bytes a proved position | 432,898 | 161,773 | 68,227 |

And the whole block at the two block lengths that proved one, which is what a
sequence would pay:

| the last block's 32 layer segments | S = 256 | S = 512 |
|---|---|---|
| fresh cells | 25,608,247,152 | 44,557,347,792 |
| ... a proved position | 100,032,215 | 87,026,070 |
| commit, s a segment | 0.797 | 0.664 |
| stwo total, s a segment | 1.303 | 1.103 |
| whole wall-clock, s a segment | 12.944 | 22.011 |
| loop, s a segment | 10.275 | 13.333 |
| serialized proof, median bytes a segment | 112,113,493 | 81,802,018 |
| the card's peak, MiB of 81,559 | 58,267 | 73,723 |

What they say. Every per-position cost falls as the block grows, monotonically
over the three: cells, both timing scopes and, by a wide margin, the size of the
proof, which is 6.3 times smaller a position at S = 1,024 than at S = 256. There
is no crossover in the range measured and no sign of one. The two ends are the
two prices: a short block buys a smaller working set and pays for it in every
per-position figure, and a long block is the other way round.

**S = 1,024 fits, which it was not expected to.** One segment at that block
length peaked 71,739 MiB of the card's 81,559, 88.0%, with 9,820 MiB left. The
expectation came from the count -- the segment is 1.889 times the S = 512 one --
and from the recorded S = 512 sequence peaking 73,723 MiB. It is one segment
against a loop, so it is not proof that a whole S = 1,024 plan fits; what makes
it worth more than a guess is that the recorded probe at context 16,384 found
the same peak with the pipeline off and on. A block of 1,024 positions over all
five blocks, with the output head in the plan, is the run that would settle it.

What the counted side says, and what it costs the count. `predicted.json` is the
prover's trace layout counted at that block length over the very segments the
run proves, each at the witness-calibrated fields its own dump carries, written
before the loop ran. It is low at both block lengths -- `rho` 1.0063 at S = 256
and 1.0020 at S = 1,024 -- and the block length is not why. A count charges five
cells a row for a range table of `2^ao_rem_bits` rows; the fields file states
each dump's OWN width; and a chunk loop proves every segment at one shared pin,
which the plan takes over every row of every block and which is 20 at both. So
the count charges the narrower table wherever a dump's own width is below the
pin: at S = 256 layer 0's own width already is the pin and counts exactly while
each of the other 31 is short by five cells times the rows it misses --
5,242,880 cells on 15 layers, 5,160,960 on 14, 4,587,520 and 4,505,600 on one
each -- and at S = 1,024 the one segment's own width is 15, so it is short one
2^20-row table, 5,242,880 cells, and that is the whole of the 0.20%. Recounted
at the pin and nothing else changed, the same function gives the S = 1,024
measurement **exactly** and lands within 0.0022% at S = 256. It is a zk-prover
matter, zk-prover #194, and the `rho` rows are the size of it. The S = 512 block
these are read against is counted exactly by the same function, because the
fields there are read out of the proved chunks' own parameters, which carry the
pin.

How the runs are made. The extraction runs the whole forward pass over the
sequence either way, because a block reads the keys and values of every block
before it, and only the last block's dumps are written: five passes, 175 s and
4.6 GiB at S = 256, 331 s and 13.8 GiB at S = 1,024, beside 7.5 GiB of files
shared between the blocks. Every layer of the block is extracted even where one
segment is proved, because the loop's pins are taken over the whole block's
shape table and a pin read off one layer is not the pin a plan at that block
length would be proved at. Layer 0 is a pass of its own because the embedding
table is written into every dump of the pass it is given. The plan is that one
block, no output head segment and no verifier pass, so each run's label is
`probe` and no number here is a throughput row for a sequence. At S = 256 every
shape was already in the host's kernel store and nothing was emitted or rebuilt;
the loop proved all 32 segments in one pipelined process in 353 s of wall-clock
time, and the whole job took 35 minutes. At S = 1,024 the one segment took 45 s
of wall-clock time around the process.

The reference backend then proved layer 16 of the same block in host memory --
78.6 s at S = 256, 223.0 s at S = 1,024 -- which is the runs' provenance anchor,
because a loop the card cannot hold writes no output at all and `manifest.py`
refuses a fetched directory that carries no provenance block. It is also a
digest gate, and at both block lengths its proof bytes hash to what the card's
proof of that same segment hashed to: a STARK's determinism checked across the
two backends at two block lengths neither had been run at.

## phase-split-c4096

    tools/drivers/phase-split-c4096.sh <host> <prover-commit> <harness-commit>

runs: 2026-09-13-phase-split-c4096-h100
prover commit: 6589471   harness commit: 6589471
digests: the sample's 32 segment proofs, the same in both loops; the first and
  the last, 16 hex: `59fff6b1f0232615`, `b3956211cbac08e9`
binding (from the manifest, folded over the 64 proofs): 1 to 15 bound; 16 absent
unsound skips: none
constants backed: `segments.phase.c4096`, and for each of the two loops
  `secs.phase.c4096.<loop>.loop` with the twelve
  `secs.phase.c4096.<loop>.<phase>` rows under it.
  `share.phase.c4096.<loop>.<phase>` and `secs.phase.c4096.kernels_bought` are
  derived from those.

What this measures. The segment loop's own seconds, split into phases that
partition it, over the 32 layer segments of the last token block of
`headline-c4096`'s plan: the paper's configuration, the five reductions on and
the shared pins every campaign at this context carries. The sample is proved
twice with one segment in flight, once with the generated constraint kernels in
place and once with every one of them declining to the host, and the two loops
proved the same 32 statements to the same 32 digests.

Why one segment in flight. `assumption.loop_split.c4096.interaction_frac` and
the three beside it are asserted because the headline row's loop overlaps one
segment's generation with another's proving: `trace_secs`, `interaction_secs`,
`stwo_total` and `read_secs` add to 144 per cent of that loop's own seconds and
are not a split of it. With one segment in flight they stop overlapping. They
are still not a split even then -- `read_secs` is one of the four kinds of work
inside `build_secs` rather than a peer of the other three, and the four leave a
sixth of this loop unnamed -- so the run records twelve terms that do partition
it, and the job refuses to publish a loop whose twelve do not add to its own
seconds.

The witnesses. This host held no witness at this context, so the driver
extracted the sample block's own: the same ids at the same corpus offset, the
same five layer passes at the same quantization variant, with layer 0 its own
pass so that its dump carries the embedding table. The forward pass covers all
4,608 positions whichever blocks are written, so the sample block's dumps are
the ones `headline-c4096` writes, and the 211 seconds this cost bought 20 GB
where the whole nine-block set is about 122 GB. Two checks say the sample is
that campaign's and not a narrower one: the shared pins the shape table gives,
`--kmax 19 --ao-rem-bits 20 --fold-rem-bits 15 --fold-alpha 6`, are the pins
`runs/2026-09-09-headline-c4096-h100` was proved at, and all 32 plan lines are
that run's block-8 lines to the byte once the witness path is set aside.

The split. Seconds over the 32 segments, and each phase's share of the loop it
was measured in.

                        kernels             nokernels
                              s        %            s        %
    `read`                  4.0     0.54          5.6     0.12
    `decode`                4.6     0.62          5.0     0.11
    `check`                13.2     1.77         13.1     0.28
    `construct`            58.4     7.81         67.9     1.43
    `alloc`                 6.6     0.88         13.6     0.29
    `build_rest`            1.3     0.17          1.3     0.03
    `trace`               264.9    35.40        278.8     5.89
    `interaction`         313.1    41.84        313.8     6.62
    `stwo`                 34.1     4.56      3,983.7    84.10
    `serialize`             3.7     0.50          4.4     0.09
    `prove_rest`           41.8     5.58         46.4     0.98
    `loop_rest`             2.4     0.32          3.5     0.07
    loop                  748.2   100.00      4,737.0   100.00

Against the split the projection assumes. The four shares zk-prover #12 quotes
off an old H200 serial loop are interaction 49, base trace 30, the proof system
9 and the dump read 5 per cent, naming 93 per cent of the loop. Measured here
on the paper's configuration: interaction 41.84, base trace 35.40, the proof
system 4.56 and the dump read 0.54, naming 82.35 per cent. Interaction is 7.2
points below the assumed share and base trace 5.4 above it, which are the two
the projection divides by a measured factor; the proof system is half its
assumed share and the dump read is a tenth of it, at 4.0 seconds over 32
segments. None of this is carried into `secs.projected.c4096.loop_ported_rates`
here. The shares above are a serial loop's over one token block and the
projection is about a pipelined loop over nine, so whether they transfer is a
measurement decision and not an arithmetic one; the projected row keeps the
split it assumes and the note that says so.

What the generated constraint kernels buy. The same 32 segments, the same
statements, the same 32 digests: 748.2 seconds with the kernels in place and
4,737.0 without, 3,988.8 seconds more, a factor of 6.33. Per segment that is
23.4 seconds against 148.0. The whole of it is one phase: `stwo` goes from 34.1
seconds to 3,983.7 and from 4.56 to 84.10 per cent of its loop, while the
eleven others move by seconds. The prover's own phase detail says the same
thing from the other side: the same 3,872 constraint evaluations cost 0.138
seconds on the card and 3,950.1 on the host. What that does not price is the
generated witness-generation and LogUp builders, which the switch does not
reach: `ZK_GENERATED_LOGUP` chooses those and has a host builder to decline to
only where the component's columns are on the host, so switching them off would
price the device residency as well.

Where the loop's generation goes, by component. The run records the prover's
own host phases summed over the sample beside the split, because a phase share
says how much of the loop is host-side generation and this says which components
it is -- what zk-prover #12 moves onto the card one group at a time. The six
largest of the kernels loop: the key tiles' generation 120.4 s, then the
residual stream's at 63.6 s, the GKR reductions 56.8 s, the dequant interaction
49.2 s, the requantize interaction 45.6 s and the requantize generation 45.0 s.

Host time. 110 minutes end to end: 197 s for the ids, 211 s for the extraction
over five passes, 695 s for the emits and the rebuild of the CUDA backend, 768 s
for the kernels loop and 4,755 s for the nokernels loop. The extraction and the
rebuild are paid once per host; a second run of the pair costs the two loops.
The store gained nothing -- 47 kernels, none new -- because a kernel is keyed by
the fingerprint of its lowered form and the shapes this sample needs were
already in it from another context.

## `register-70b`

```
tools/drivers/register-70b.sh
```

runs: `2026-09-13-register-70b-none`
prover commit: none   harness commit: 111347e (zk-prover `shape-70b-synthetic`,
  not merged: re-pin the driver when it is)
digests: none; the run's own outputs are the registration and its configuration
binding: none; this run proves nothing
unsound skips: none
constants backed: none. The number this run produced is the registered
  prediction below; nothing in `constants.json` reads it until `predict-70b`
  has measured against it.

What the run is. The prediction `predict-70b` is measured against, written
before anything at this width was built, proved or counted. It takes no host and
no card: it is a computation over this repository's `constants.json`, the two
measured 8B layer chunks the two headline runs already proved, and a stated
block of witness fields this driver holds.

    prediction_sha256        80394b3d9476c825bd7301eec7398dca240f96ced8d795062c3d6762c799d33b
    prediction_block_sha256  e2af2a7bf3b17b7f49c4d504fe8219a9f94b2c060ba473b1aca046f617619ee6
    constants.json frozen    77b7d01843e3e363108a37237f73038516a49fbae205df438918dbd3d63c2c9b
    fields file              f429fd094c7e3bf10e4492b90a356cc0244f1748a080fde6282347544cd8982f
    zk_results_commit        9ecef91
    counted                  80 segments, none absent, at C = 4,096 and a
                             128-token block

What it registers. 676,250,394 fresh committed cells a decoded token over the
80 layer segments of Llama-3.1-70B at context 4,096, of which 119,032,320 are
the attention key tiles and 557,218,074 the rest. One layer segment of that
stack is 1,081,685,392 cells and the segment that carries the embedding lookup
is 1,106,904,464; the stack's average is 1,082,000,630. That layer segment is
what `predict-70b` proves and what the comparison is against. The key tiles
committed 173,047,808 base cells and 17,403,904 interaction cells a segment,
the same integers the closed form gives, so the three grids tile exactly at
this shape. One layer segment here is 0.777 times the measured 8B layer chunk,
which is a segment over a quarter as many positions at the same context.

Counted and not priced, and counted at a STATED block of fields. On this path
the model charges no per-unit cell cost on the committed side: every cell is
counted from the prover's trace layout. What the layout needs and a model and a
context do not give it is the block of fields a run calibrates off its own
witness. `register-13b` reads that block off dumps. There are no dumps here and
there will be none: what `predict-70b` proves is a synthetic layer segment at
this width, built by the prover's own fixed-seed generator, so the block is
stated in the driver with where each field comes from, and it travels into the
registration under `frozen_inputs.witness_fields.stated_from`. Three kinds:

- the master exponent table at 2^24 and the normalisation window at 20 are
  flags. `predict-70b.sh` passes `--table-bits` and `--kmax` and the prover
  takes both verbatim, so neither is assumed. The window is also the prover's
  own blind bound at this shape, so the flag and the derivation agree;
- the attention output's quantize width of 7 and the two fold pins at 0 are
  the generator's own: a synthetic layer sets that width to 8, and `--layout
  b10` puts all seven matmuls on the chain dequantize gadget and delays none;
- the attention output's measured windows -- the divisor range at 21 bits, the
  accumulator's 16 and 6, and the two exponent extremes -- are the assumption.
  No flag pins them and they exist only once the generator has drawn the
  layer. They are stated at the values the same generator produced at the 8B
  attention width in `2026-09-09-prefill-sweep-8b-h200`, output
  `dd_s256_c4096.json`: the same generator flags, the same head dimension of
  128, the same quantize widths and the same context. They are properties of
  the attention's own arithmetic and not of the head count, which is the one
  thing the two shapes do not share.

The witness bound beside the count says what the assumption is worth from the
other side: the same 80 segments with every witness-calibrated field at the
dearest value the recorded 8B runs carry come out 6.78% above this count.

Why the block is 128 and not 512. One 70B layer segment at a 512-token block
does not fit an 80 GB card at either context, and that is the memory question
issue 93 asks to answer before a host is booked. The 8B's own measured pairs
put the card at 47.9 MiB per million cells of the largest segment at C = 4,096
(`mem.headline.c4096.peak_mib` against that loop's embedding segment) and 33.2
at C = 16,384 (`mem.probe.c16384.layer0_peak_mib` against the same segment
there). This shape's layer segment counts 2,851,597,200 cells at C = 4,096 and
4,525,124,496 at C = 16,384 over a 512-token block, which those two ratios put
at 167% and 184% of the 81,559 MiB the card reports. At 256 the larger context
is still over. At 128 the counts are 1,081,685,392 and 2,037,986,704, which the
same ratios put at 63.5% and 82.9%. The assumption is that peak card memory at
one context goes with the largest segment's fresh committed cells, at the same
statement and the same reductions on the same card; the line through both
measured pairs, which makes no such assumption, puts the same two points at 87%
and 94%, so the choice survives either reading and the margin the run has in
hand is the smaller of the two.

Why C = 4,096 alone. A witness field is a property of one forward pass over one
prefix: the attention output's divisor range and the master exponent table both
grow with it, so a segment at one context is not counted at another's fields and
the harness refuses to. There is a recorded synthetic segment at C = 4,096 to
state the assumed four from and none at C = 16,384. So the registration covers
C = 4,096, says in its own `contexts_not_registered` that it does not cover
C = 16,384, and `predict-70b` prints which contexts it is measured against and
which it is not. Pinning the attention output's windows in that driver, the way
`prefill-sweep-8b` pins its divisor range, is what would make every field of a
synthetic segment a flag and let both contexts be registered in advance; that is
a measurement decision and is not taken here.

Why the driver pins an unmerged zk-prover commit. The counted path needs three
things main does not carry: the counted-registration record for this shape, a
block length the document can be counted at -- every registration before this
one is at 512, which is what `predict.py` assumed -- and a writer for a fields
file of a segment that has no dump. Re-pin the driver at the merge commit; the
registration then has to be made again, because the code it read is part of what
it froze.

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
