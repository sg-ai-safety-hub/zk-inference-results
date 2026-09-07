# The measured card is the H100

Date: 2026-09-07. Status: decided by the owner (2026-09-07).

## Decision

Every campaign in the issue list runs on an H100 80 GB, and every constant
it produces names that card. The campaign issues were written for an H200;
they are run on the H100 as written, and the numbers the paper cites are the
H100's. An H200 number, if one is ever measured, is a second row labelled with
its card, never a replacement.

## Why

An H100 can be rented on demand; an H200 cannot. A measured number on the card
at hand outweighs a projected number for the card the issues named. The card
is recorded in every manifest as the machine reports it and in every constant,
so nothing in the record is ambiguous.

## Consequence

The `headline-c4096-second-card` campaign, which measured the H100 as the
second card against the H200, loses its object: the H100 is the card. It stays
open only for a memory probe of the pipelined loop at context 16,384, which the
archive estimated at 85 GB, until that loop has been tried on this card. The
cost model's cross-card ratios wait for a second card.
