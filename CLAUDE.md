# Rules

## Read
- This file, your issue, REPRODUCE.md's entry for the driver you touch, and
  the files you own. Nothing else unless the issue names it.

## Runs
- A run is made only through tools/drivers/. The driver pins the prover and
  harness commits, writes the manifest from the prover's provenance block,
  and runs check.py. Nothing is transcribed by hand.
- Hosts are ssh aliases passed on the command line. Nothing about a host is
  written into this repository: not an address, not a card, not a socket,
  not which alias is which machine. The manifest records the GPU the
  machine reports.
- One run per host at a time, enforced by tools/remote/lock.sh. Run
  detached, poll the status file, never wait in a foreground ssh.
- Logs stay on the host. If a log line is evidence, the manifest quotes it.

## Numbers
- Every number the paper cites lives once, in constants.json, with a run
  id and an artifact, and the audit re-derives it. A number that cannot be
  re-derived is graded asserted with the reason, or does not exist.
- Every recorded number names card, context and timing scope.
- Old numbers from the private archive are a sanity check, never a source.

## Write
- Never append to a document. Your record is your pull request: state
  block (done, remaining, headline), the binding table of the configuration
  measured, a numbers table, the constants added.
- Standard words. tools/constants/words.py checks README.md, REPRODUCE.md
  and docs/ and CI runs it. Issues and pull requests are not checked; write
  them plainly anyway.
- Measurement and paper decisions the owner makes go in docs/decisions/,
  one dated file, never edited after merge.
- Commit only when asked. Commits split tools / runs / docs.

## Reporting to the user
- Same four rules as zk-prover: numbered decisions with stakes and a
  recommendation; the thing before the pointer; consequence, mechanism,
  identifiers, in that order; plain words for what is off, unchecked or
  not built.
