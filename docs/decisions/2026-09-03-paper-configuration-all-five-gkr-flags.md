# The paper's configuration has all five GKR flags on

Date: 2026-09-03. Status: decided by the owner (first recorded 2026-08-31).

## Decision

Every prover-side number the paper cites is measured with all five GKR
reductions enabled: on the attention key tiles, the dequantization gadgets,
the residual stream, the Freivalds checks of the weight matmuls, and the
attention output. The default build enables them; a run without them is a
control, reported as such, and never a headline.

## Why

The reductions remove committed cells without changing what is proved, and
the paper's throughput claim is about the prover as built. Reporting the
slower configuration would understate the system; reporting a mix would make
the numbers incomparable.

## Consequence

Drivers set the five flags in one place and write them into the manifest.
A run the paper cites with any of them off is a defect in the driver.
