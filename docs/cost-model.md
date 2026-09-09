# The cost model

`harness/costmodel/` in `zk-prover` prices a proof from measured rates and a
cell count. Nothing in it is a measurement; every number it prints is
`projected` and names the constants it read. This page says which key backs
each of the model's inputs, and where a key is named here and measured by
nothing it says that too.

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
  `rate.headline.c16384.loop`).
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
