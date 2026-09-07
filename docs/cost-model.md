# The cost model

`harness/costmodel/` in `zk-prover` prices a proof from measured rates and a
cell count. Nothing in it is a measurement; every number it prints is
`projected` and names the constants it read. No measured constant exists yet
in this repository, so this page names the keys the drivers will back.

## Inputs

- Micro-benchmarks of the proof system on one card (`--inputs DIR`): the
  commitment rate in cells per second, field operation rates, the cost of one
  lookup and the end-to-end proving rate.
- The measured sequence runs, through `constants.json`: cells committed per
  token and the rate at each timing scope (`cells.headline.c16384.fresh`,
  `rate.headline.c16384.commit`, `rate.headline.c16384.whole_wall`,
  `rate.headline.c16384.loop`).
- The reference rental rates (`cost.h100_reference_usd_per_hour`,
  `cost.h200_reference_usd_per_hour`).

## What it counts, per decoded token

- The weight matmuls, checked by Freivalds' method: a fixed number of cells
  per weight (`model_constants.weight_freivalds_cells_per_weight`).
- Dequantization after each matmul: cells per accumulator, for the bf16 chain
  and for power-of-two scales (`model_constants.dequant_chain_cells_per_acc`,
  `model_constants.dequant_pow2_cells_per_acc`).
- Attention: cells per (head, key, token) over the key tiles, a fixed cost per
  key and per token, and the diagonal block's own share
  (`attention_grid.band_model_fresh_coeffs`).
- Lookups: the exponential table, the range checks on every committed
  activation, and the marginal cost of a lookup
  (`model_constants.logup_marginal_cells_per_lookup`).
- The residual stream: the two normalisations and the residual adds.
- The output head as its own segment.

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
this repository like any other, made by a driver, with a manifest.
