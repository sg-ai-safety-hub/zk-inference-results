# The paper's quantization configuration is the delayed-requantization variant

Date: 2026-09-03. Status: decided by the owner (2026-09-02).

## Decision

The paper reports the variant `y-delay-vw12`: the fixed configuration
`b10-final` with the value projection's requantization delayed to its
consumer and a 12-bit attention output. Every quality number, every witness
and every prover-side number the paper cites is on this variant; other
variants appear only as measured alternatives, labelled.

## Why

Both changes are improvements on the measured evidence: fewer committed
cells and a small quality gain against `b10-final`, at no cost to what the
proof binds. The owner's rule is that every optimisation that is one goes in.

## Consequence

The witness extraction and the task suite run on this variant. Rows measured
on `b10-final` before this decision are carried only where the variant does
not matter and say so.
