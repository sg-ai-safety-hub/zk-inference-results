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
  `constants.json`: the `model_constants.*` keys below, all of them from
  `microbench-cells`, all of them marginal figures with the shared tables left
  out because a table is a fixed cost of the segment and is not multiplied by a
  count.
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
  choice and not a constant of the gadget. No subcommand in this repository
  measures it; the model reads it from a file a retired benchmark tree wrote,
  and zk-prover #139 asks for the subcommand. No key here backs it.
- Dequantization after each matmul: cells per accumulator, for the bf16 chain
  and for power-of-two scales (`model_constants.dequant_chain_cells_per_acc`,
  `model_constants.dequant_pow2_cells_per_acc`), times the accumulators of
  every layer matmul and of the output head. The attention output has a
  dequantization of its own, folded straight to int8 because its consumer
  requantizes it anyway (`model_constants.attnout_int8_cells_per_acc`), times
  the outputs of every layer and head. All three are measured with the round
  half to even; the model charges rounding away from zero on the layer
  matmuls, which is one cell an accumulator less.
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
  key and per token, and the diagonal block's own share
  (`attention_grid.fresh_cell_coeffs`). The per-entry half of that is measured
  on its own (`model_constants.attention_cells_per_head_key_token`) and is what
  the superseded single-slope form charged for the whole term; the coefficients
  are not measured here, and until they are the single slope is valid only at
  the block length it was solved at.
- Lookups: the exponential table and the range checks on every committed
  activation are inside the per-operation figures above, each of which counts
  the gadget's own lookups. What is not measured anywhere here is the marginal
  cost of a lookup on its own -- the cells one lookup adds beyond the two trace
  cells a witness commits anyway, which depends on how many lookups share one
  interaction column. The model reads it per batch size from the retired file,
  and the residual-stream subcommand assumes the same two cells at the default
  batch of two, in the figure it reports and again inside every marginal it
  computes. zk-prover #140 asks for the subcommand. No key here backs it.
- The residual stream: one correctly rounded bf16 add
  (`model_constants.residual_stream_add_cells_per_op`) times the two residual
  adds of every layer and the adds of each normalisation's reduction, and one
  bf16 multiply (`model_constants.residual_stream_mul_cells_per_op`) times the
  two multiplies of every normalisation and the SwiGLU's product. The unary
  table application the model charges beside them is a constant of the
  subcommand and not one of its measurements, so no key here backs it.
- The output head as its own segment: its Freivalds check once per segment, its
  accumulators dequantized, and one comparison per vocabulary entry per token
  to prove the emitted token is the argmax
  (`model_constants.argmax_cells_per_comparison`).

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

The interaction tree is the one the slice outputs split by component, and the
split is what the list above prices. Each key is that component's cells over
the run's proved positions; `interaction_` names the tree they come from.

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

One reader in `tools/constants/audit.py` re-derives all of it from the slice
outputs and refuses unless the shape and model trees add up to the preprocessed
cells the chunk reports, the eleven components add up to the interaction tree,
the chunks add up to the run's `fresh` row, and the recorded rows close the same
two sums themselves.

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
`model_constants.*` key above is re-derived from its run's own JSON by
`audit.py`'s `microbench-cells` section, which also gates the three statements
this page makes about a sweep rather than a point: that the width sweep
reproduces to the cell at all six widths, that the marginal figure is the same
at all six table sizes, and that the per-entry attention figure is the same at
all five instance counts.
