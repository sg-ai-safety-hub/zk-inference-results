# The cost model

`harness/costmodel/` in `zk-prover` prices a proof from measured rates and a
cell count. Nothing in it is a measurement; every number it prints is
`projected` and names the constants it read. This page says which key backs
each of the model's inputs, and where a key is named here and measured by
nothing it says that too. Where a key is measured, this page names it and
quotes no number of its own.

## Inputs

- Micro-benchmarks of the proof system on one card (`--inputs DIR`): the
  commitment rate in cells per second, field operation rates, the time one
  lookup takes and the end-to-end proving rate.
- What one operation of each kind costs in committed cells, through
  `constants.json`: the `model_constants.*` keys below. The ones from
  `microbench-cells` are marginal figures with the shared tables left out,
  because a table is a fixed cost of the segment and is not multiplied by a
  count. They come off two runs of that driver: the eight the newer one records
  are `runs/2026-09-11-microbench-cells-h100`, which answers thirteen
  subcommands, and the ten beside them are `runs/2026-09-09-microbench-cells-h100`,
  which answered seven and which the newer run does not re-point. The
  `*_composed_*` ones are what the composed prover builds the same gadget at,
  read off the two headline runs; the section below tabulates them.
- The measured sequence runs, through `constants.json`: cells committed per
  token and the rate at each timing scope (`cells.headline.c16384.fresh`,
  `rate.headline.c16384.commit`, `rate.headline.c16384.whole_wall`,
  `rate.headline.c16384.loop`), and what a proved position commits per
  component, which the section below tabulates.
- The reference rental rates (`cost.h100_reference_usd_per_hour`,
  `cost.h200_reference_usd_per_hour`).

## What it counts, per decoded token

- The weight matmuls, checked by Freivalds' method: a fixed number of cells per
  weight, times the model's parameters, divided by the tokens one proof covers.
  The check's three accumulator columns cost twelve cells a trace row and a row
  carries as many weights as the layout gives it, so the figure is a layout
  choice and not a constant of the gadget. The key that backs it is
  `model_constants.weight_freivalds_cells_per_weight`, measured at the prover's
  own default row width, and the preprocessed side of the same layout choice is
  `model_constants.weight_freivalds_preprocessed_cells_per_weight`, which is
  `1 + 4/p` on the same points. Both are marginals over the weights two output
  widths differ by, so neither carries the row padding a real grid has. The
  model charges one figure for every matmul group, and the measurement says a
  group of `n` matmuls shares one accumulator and costs `(4 + 8n)/(n p)`: on a
  layer that over-charges the two-matmul group by 20 per cent and the
  three-matmul one by 29. What the composed prover builds the check at is a
  different figure and has a key of its own, below.
- Dequantization after each matmul: cells per accumulator, for the bf16 chain
  and for power-of-two scales (`model_constants.dequant_chain_cells_per_acc`,
  `model_constants.dequant_pow2_cells_per_acc`), times the accumulators of
  every layer matmul and of the output head. The attention output has a
  dequantization of its own, folded straight to int8 because its consumer
  requantizes it anyway (`model_constants.attnout_int8_cells_per_acc`), times
  the outputs of every layer and head. Those three are the round half to even;
  the model charges rounding away from zero, which is one cell an accumulator
  less and has keys of its own -- `model_constants.dequant_chain_away_cells_per_acc`
  on the layer matmuls and `model_constants.dequant_pow2_away_cells_per_acc` on
  the output head. With `--gkr-dequant` on, the batched reduction proves the
  LogUp running sums and the gadget commits its base columns alone, which is
  `model_constants.dequant_chain_away_base_cells_per_acc` and
  `model_constants.dequant_pow2_away_base_cells_per_acc`: one cell an
  accumulator below the round-half-to-even split, as the marginal figures are.
- What a wider trace row buys. The power-of-two dequantization is exactly
  `model_constants.dequant_pow2_cells_per_acc_intercept` cells per accumulator
  plus `model_constants.dequant_pow2_cells_per_row` cells per trace row, at all
  six widths measured, so the figure the model multiplies by an accumulator
  count is the intercept plus the row term over the accumulators a row carries.
  At the sixteen-per-row layout the two give
  `model_constants.dequant_pow2_cells_per_acc`. The table size buys table and
  not slope: over six values of `kmax` the marginal figure does not move and the
  figure with the tables in goes from 15.5 to 143.8 cells per accumulator.
- Requantization before each matmul, with the scale argument that goes with it
  (`model_constants.requant_cells_per_value`), times each distinct matmul input,
  less the committed quantized value the model already counts.
- Attention: cells per (head, key, token) over the key tiles, a fixed cost per
  key and per token, and the diagonal block's own share. The committed side of
  those coefficients is measured (`attention_grid.base_cell_coeffs`) and the
  per-entry half is measured on its own
  (`model_constants.attention_cells_per_head_key_token`), which is what the
  superseded single-slope form charged for the whole term; the single slope is
  valid only at the block length it was solved at. The interaction side,
  `attention_grid.fresh_cell_coeffs`, is not in the file: with the five
  reductions on most of the key tiles' interaction is in the reduction rather
  than in their own columns, and what is left does not take that form.
  REPRODUCE.md's `prefill-sweep-8b` section says what measuring it would need.
- Lookups: the exponential table and the lookups a gadget makes on its own
  values are inside the per-operation figures above, each of which counts them.
  What none of those figures holds is the marginal cost of a lookup on its own
  -- the cells one lookup adds beyond the two trace cells a witness commits
  anyway, which depends on how many lookups share one interaction column. The
  key that backs it is
  `model_constants.logup_marginal_cells_per_lookup`, one figure per lookup batch
  size: 4 at batch 1, which every shared table's own side finalizes with, and 2
  at batch 2, which every use side does. It is recorded as an object keyed by
  the batch size, because the model indexes it by the batch it charges and
  refuses a scalar. Two of the model's inputs are exact counts on top of it and
  are `derived` from it rather than measured: the range check on every committed
  int8 activation, half of one arity-2 lookup into the byte-pair table
  (`model_constants.int8_range_cells_per_activation`), and the bf16 unary
  operation below.
- The residual stream: one correctly rounded bf16 add
  (`model_constants.residual_stream_add_cells_per_op`) times the two residual
  adds of every layer and the adds of each normalisation's reduction, and one
  bf16 multiply (`model_constants.residual_stream_mul_cells_per_op`) times the
  two multiplies of every normalisation and the SwiGLU's product. The unary
  table application the model charges beside them is not a measurement of the
  subcommand but an exact count -- one committed bf16 value and one lookup --
  and the key that backs it, `model_constants.residual_stream_unary_cells_per_op`,
  is `derived` from the LogUp figure above.
- The output head as its own segment: its Freivalds check once per segment, its
  accumulators dequantized, and one comparison per vocabulary entry per token
  to prove the emitted token is the argmax. What the model charges is the
  marginal, `model_constants.argmax_marginal_cells_per_comparison`, read as the
  slope of fresh cells against comparisons over three vocabularies at one token
  count; `model_constants.argmax_cells_per_comparison` is the whole gadget over
  its comparisons at one vocabulary, the gadget's fixed side included, and is
  not what the model reads.

Time at a timing scope is cells divided by the measured rate at that scope;
cost is time times the reference rate. The model is calibrated against the
measured sequence and reports its residual (`frontier.calibration.residual_pct`).

The witness extraction is in none of those scopes: it happens before the prover
is called, and the four scopes are the prover's own. A price that assumes the
dumps are already on the host is therefore a price for a warm host. The record
carries the other one beside it, extraction and proving added up:
`secs.headline.c4096.cold_loop`, `secs.headline.c4096.cold_whole_wall` and the
two keys beside them one context up, priced as
`usd_per_1k_positions.headline.c4096.cold_loop` and its three counterparts.
Neither figure includes emitting the device kernels, installing them or
rebuilding.

## What the composed prover builds them at

Every figure above was measured on a standalone gadget chain: one gadget per
proof, with its own tables and its own LogUp running sums. The prover composes
the seven matmuls, the attention grid and the residual stream into one AIR,
where a value one gadget commits is the next one's input and the batched
reductions prove the running sums, and the same gadget does not cost the same
there. The eight keys below are what it costs there, at the statement both
headline runs prove: Llama-3.1-8B, a block of 512 decoded tokens, spec
`b10-final`, all five reductions on. Each one is cells over a count the same
segment reports, and each is the same pair of integers on all 62 non-embedding
layer segments of one token block at each context.

| what it counts | at the composed statement | the same gadget on its own |
|---|---|---|
| dequantization after each matmul, per accumulator | `model_constants.dequant_chain_composed_cells_per_acc` | `model_constants.dequant_chain_cells_per_acc` |
| requantization before each matmul, per value | `model_constants.requant_composed_cells_per_value` | `model_constants.requant_cells_per_value` |
| the quantization of the attention q and k, per value | `model_constants.quant_composed_cells_per_value` | nothing measures it |
| the Freivalds check of the weight matmuls, per weight | `model_constants.weight_freivalds_composed_cells_per_weight` | `model_constants.weight_freivalds_cells_per_weight` |
| the attention output's fold, per accumulator | `model_constants.attnout_composed_cells_per_acc` | `model_constants.attnout_int8_cells_per_acc` |
| one bf16 multiply of the residual stream, per operation | `model_constants.residual_stream_composed_mul_cells_per_op` | `model_constants.residual_stream_mul_cells_per_op` |
| one bf16 add of the residual stream, per operation | `model_constants.residual_stream_composed_add_cells_per_op` | `model_constants.residual_stream_add_cells_per_op` |
| one SwiGLU channel, table application and product together | `model_constants.residual_stream_composed_swiglu_cells_per_op` | `model_constants.residual_stream_unary_cells_per_op`, counted, and `model_constants.residual_stream_mul_cells_per_op`, measured |

The two columns are different quantities, and a model pricing the composed
statement reads the left one and not the right. Three things about the left
column. The first five rows are the committed columns plus what the reduction
leaves in the interaction trace, because a reduction moves those cells rather
than removing them; the three residual stream rows are the committed columns of
the rope's own components, the only bf16 operations whose count a segment
reports by itself. Both runs record `params.round: "even"`, so the
dequantization row is the round half to even, where the model charges rounding
away from zero on the layer matmuls, one cell an accumulator less. Layer segment
0 carries the embedding lookup and builds one cell an attention-output
accumulator more than the rest, and is in none of the eight.

Each figure is a re-fit against one shape and one statement, which is what its
note says and what a model reading it has to repeat: it is what the 8B layer
segment builds, not a form in the shape.

## What the sequence measured, per proved position

Every component above has a measured counterpart, so this page quotes no share
of its own. A segment commits six trees. Two of them are preprocessed -- the
shape tree, which holds the lookup tables and the constants its shape fixes,
and the model tree, which holds the weights it reads. The other three are paid
for again by every segment and are what `cells.headline.c4096.fresh` and
`cells.headline.c16384.fresh` add up: the base trace, the interaction columns
of the LogUp arguments, and the boundary trees, which commit the
residual stream and the keys and values a segment hands on.

| tree | context 4,096 | context 16,384 |
|---|---|---|
| base trace | `cells_per_position.headline.c4096.base` | `cells_per_position.headline.c16384.base` |
| interaction | `cells_per_position.headline.c4096.interaction` | `cells_per_position.headline.c16384.interaction` |
| boundary | `cells_per_position.headline.c4096.boundary` | `cells_per_position.headline.c16384.boundary` |
| model, preprocessed | `cells_per_position.headline.c4096.model` | `cells_per_position.headline.c16384.model` |
| shape, preprocessed | `cells_per_position.headline.c4096.shape` | `cells_per_position.headline.c16384.shape` |

The slice outputs split the interaction tree by component themselves. The base
trace they do not: the reader adds it up out of the counters beside the chunk's
own cells, charging one committed column of its rows for each LogUp table, and
both splits are recorded. Each key is that component's cells over the run's
proved positions, and `base_` or `interaction_` names the tree it comes from.
The base tree carries nine of the eleven components below and neither the
reduction link nor the argmax gadget; the argmax gadget's base side is the one
thing no counter names, and it is recorded whole as
`cells_per_position.headline.c<ctx>.unattributed`, which only an output head
segment carries. The table below is the interaction split, which is what the
list above prices.

| component | what it counts | context 4,096 | context 16,384 |
|---|---|---|---|
| Freivalds | the weight matmuls | `cells_per_position.headline.c4096.interaction_freivalds` | `cells_per_position.headline.c16384.interaction_freivalds` |
| requant | the qkv, gateup and down seams | `cells_per_position.headline.c4096.interaction_requant` | `cells_per_position.headline.c16384.interaction_requant` |
| table | the exponential, the range checks and the residual stream's own tables | `cells_per_position.headline.c4096.interaction_table` | `cells_per_position.headline.c16384.interaction_table` |
| dequant | dequantization after each matmul | `cells_per_position.headline.c4096.interaction_dequant` | `cells_per_position.headline.c16384.interaction_dequant` |
| quant | the quantization of q and k | `cells_per_position.headline.c4096.interaction_quant` | `cells_per_position.headline.c16384.interaction_quant` |
| key tiles | the attention scores, the diagonal block among them | `cells_per_position.headline.c4096.interaction_key_tiles` | `cells_per_position.headline.c16384.interaction_key_tiles` |
| gkrlink | a GKR reduction's claim carried into the AIR that consumes it | `cells_per_position.headline.c4096.interaction_gkrlink` | `cells_per_position.headline.c16384.interaction_gkrlink` |
| attnout | the attention output's quantization | `cells_per_position.headline.c4096.interaction_attnout` | `cells_per_position.headline.c16384.interaction_attnout` |
| residual stream | the two normalisations, the residual adds, the rope reconstructions | `cells_per_position.headline.c4096.interaction_residual_stream` | `cells_per_position.headline.c16384.interaction_residual_stream` |
| embed | the embedding rows a block's published ids select | `cells_per_position.headline.c4096.interaction_embed` | `cells_per_position.headline.c16384.interaction_embed` |
| argmax | the output head's own segment | `cells_per_position.headline.c4096.interaction_argmax` | `cells_per_position.headline.c16384.interaction_argmax` |

The two contexts are not the same shape, and the key tiles are why: their share
of the interaction tree grows with the prefix a block reads, which is the cost
the attention grid's coefficients model. Two other rows move with the context --
the lookup tables, a little, and the argmax row, which is two head segments over
four times as many positions -- and the rest are within a few per cent of each
other per position.

Two rows of the same kind stand outside that table: the fresh cells of the 32
layer segments of one token block over the 512 positions that block proves,
`cells_per_position.headline.c4096.fresh_layers_block` and
`cells_per_position.headline.c16384.fresh_layers_block`. The block is the one
whose prefix is the whole context, the output head segment is not in it, and it
is what the cost model's own registration compares its layers-only prediction
per decoded token against. Every row in the table above divides the whole run,
output heads and shorter prefixes included, by every position the run proves,
and is smaller for that reason.

One reader in `tools/constants/audit.py` re-derives all of it from the slice
outputs. Over the run it refuses unless the shape and model trees add up to the
preprocessed cells the chunk reports, the eleven components add up to the
interaction tree, and the chunks add up to the run's `fresh` row. Per segment it
refuses if a base counter is missing, if the base components add up to more than
that segment's own base tree, if base cells are left over on a segment that
states no argmax gadget, if base and interaction are above fresh, or if one of
the two breakdowns a chunk carries beside a component stops adding up to the
component it splits. The recorded rows then close three sums of their own: the
components to the interaction tree, the base components with the unattributed
cells to the base trace, and the three trees to the run's `fresh` row per proved
position.

## What it projects

- Cards needed for a target throughput per model shape and context
  (`frontier.<model>.c<ctx>.<scope>.cards_for_20`), and dollars per million
  tokens (`frontier.<model>.c<ctx>.<scope>.usd_per_mtok`).
- Mixture-of-experts shapes: committed cells against a dense model of the
  same active size (`moe.<model>.preprocessed_over_fresh`).
- The price of proving a whole evaluation suite, from the suite's token
  counts (`suite.decode_positions`, `suite.e11_positions`) and the measured
  per-position rate: `harness.costmodel.suite_cost`.

## Where the measured quantities come from

Every `projected` constant lists its inputs; `check.py` recomputes the
arithmetic between them. The model's own micro-benchmark inputs are runs in
this repository like any other, made by a driver, with a manifest. Each
`model_constants.*` key measured on a gadget of its own is re-derived from its
run's own JSON by `audit.py`'s `microbench-cells` section, one run at a time, so
that an entry is never re-derived from another run the same driver made. That
section also gates the six statements this page makes about a sweep rather than
a point: that the width sweep reproduces to the cell at all six widths, that the
marginal figure is the same at all six table sizes, that the per-entry attention
figure is the same at all five instance counts, that the Freivalds check is
`12/p` fresh and `1 + 4/p` preprocessed at every width it was asked for, that
the rounding away from zero is one cell an accumulator below the round half to
even at every variant and on both the marginal and the committed side, and that
the three argmax vocabularies are collinear. The eight composed keys and the two
per-block rows are re-derived the same way by the section beside it, off the two
headline runs' slice outputs, and it refuses unless the two contexts give the
same integers.
