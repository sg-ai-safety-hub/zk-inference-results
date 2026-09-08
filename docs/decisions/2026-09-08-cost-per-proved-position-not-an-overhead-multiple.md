# The paper quotes cost per proved position, not an overhead multiple

Date: 2026-09-08. Status: decided by the owner (2026-09-08). Refines the
decision of the same day on the unproved baseline.

## Decision

The paper's cost claim is a cost per proved position: seconds per position at
the loop scope and at the whole wall-clock scope, and dollars per thousand positions
at the reference card rate. It does not quote a single "times slower" multiple
against an unproved baseline.

The unproved baseline is still measured, and in three numbers per point: the
prefill of the prompt on its own, the decode of the generated tokens on its
own, and the two end to end, each as positions per second over the positions
it covers. The reader multiplies the cost per proved position by their own mix
of prompt and generated positions and compares with the unproved cost of that
same mix.

## Why

Overhead is a property of the workload, not of the prover. The prover's cost is
the same per position whether the position was prompted or generated (about
78 million committed cells per position at context 4,096), while the unproved
cost differs by two orders of magnitude between a prefilled and a decoded
position. One prover on one card therefore looks a thousand times slower on a
prompt-heavy request and thirty times slower on a decode-heavy one. A single
multiple would be true only for one mix and would invite the argument about
which baseline it was taken against; a cost per position and a baseline in
its parts sidestep both.

## Consequence

The baseline driver records prefill, decode and end-to-end per point, in
positions per second over their own positions; none of the three is the
"overhead" denominator. The constants file carries `secs_per_position.*` and
`usd_per_1k_positions.*` as derived entries from the measured loop and
whole wall-clock rows and the reference card rate, and the export writes those for
the paper. The earlier decision's rule that the end-to-end figure counts the
prompt stands; its consequence that a prefill-only or decode-only baseline rate
is not recorded is replaced by this one.
