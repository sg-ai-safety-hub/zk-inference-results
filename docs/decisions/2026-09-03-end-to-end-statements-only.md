# The paper measures end-to-end statements only

Date: 2026-09-03. Status: decided by the owner.

## Decision

Every prover-side number the paper cites comes from a statement that proves
the prompt and the output from the embedding up: the whole forward pass over
every position, with the residual stream bound between layers and the keys
and values bound between token blocks. Decode-only sequences, which prove
512 output tokens against a key/value cache that is committed but not itself
proved, are not measured and do not appear in `constants.json`.

## Why

A decode-only rate leaves the prompt's computation asserted by the prover
and checked by nothing, so it is not a rate for the claim the paper makes.
Carrying both kinds of row invites the comparison of an end-to-end rate to a
decode-only one, which is the error the private archive's records made.

## Consequence

The campaign list has no decode driver. A comparison between cards, if
wanted, runs the end-to-end configuration on the second card. Positions per
second, not tokens per second, is the unit of every throughput constant.
