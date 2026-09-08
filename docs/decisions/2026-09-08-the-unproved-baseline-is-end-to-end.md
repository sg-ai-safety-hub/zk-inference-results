# The unproved baseline is measured end to end

Date: 2026-09-08. Status: decided by the owner (2026-09-08).

## Decision

The unproved baseline that every "times slower" and every dollar-per-position
figure is stated against is measured over the same positions the proved rate
counts: the prompt's prefill and the 512 decoded tokens, as one wall-clock
time, in positions per second. A baseline rate that subtracts the prompt's time
is not recorded.

## Why

The decision of 2026-09-03 made every proved statement end to end: the measured
rows are 4,608 positions at context 4,096 and 16,896 at context 16,384, the
prompt included. The harness's like-for-like comparison was written when the
proved rate was decode-only and subtracts a one-token call from the baseline to
remove the prompt. Dividing an end-to-end proved rate by a decode-only baseline
rate compares two different quantities; the ratio would be wrong in the
paper's favour.

## Consequence

`unproved-baseline` measures prefill plus decode per point and records
positions per second; the prefill-subtraction path in the harness's comparison
is retired (zk-prover #74 and its follow-up issue), and the two constants that
described it (`scope.prefill_status`, `scope.sampling_status`) are not defined.
