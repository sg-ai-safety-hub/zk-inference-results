# GPU time is priced at reference market rates, never at what was paid

Date: 2026-09-03. Status: decided by the owner (2026-08-31).

## Decision

Every dollar figure divides a measured time by a published on-demand rental
rate for the card, from one provider, one tier and one date for all cards
compared (`cost.h100_reference_usd_per_hour`, `cost.h200_reference_usd_per_hour`).
What the project actually paid for its hosts is never a divisor and never
printed.

## Why

One host was sponsored and one was rented at a negotiated price; neither is
a rate a reader can obtain. A published list price is reproducible and, at
the higher tier, conservative for a cost claim.

## Consequence

The rates are `external` constants with their URLs. A cost constant names
them in its derivation, and `check.py` recomputes it.
