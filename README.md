# zk-results

The measurements behind the paper: one directory per run, the constants the
paper cites, the audit that links each constant to a run, and the drivers that
make runs. The software is in the companion repository `zk-prover`; every run
here pins the commit of it that produced the run, and that hash is the only
link between the two.

## How a run is made

```sh
tools/drivers/<name>.sh <host> <prover-commit> <harness-commit>
```

`<host>` is an ssh alias the caller owns; nothing about any host is written
here. The driver pushes `zk-prover` at the two commits to the host, starts the
job detached through `tools/remote/run.sh` (one run per host at a time, a lock
in the remote home, a status file to poll) and exits. Run again with the same
arguments to see the status, and once the status says done the driver fetches
the outputs into `runs/<run-id>/`, writes `manifest.json` from the prover's
own provenance block, and runs `tools/constants/check.py`. Logs, witnesses and
serialized proofs stay on the host.

The run id is `<date>-<driver>-<gpu>`, the GPU as the machine reported it.
The manifest carries the prover and harness commits, the command line, the
driver and CUDA versions, every output's proof digest, the list of unsound
skips in effect (empty in any run the paper cites), and the binding table:
which of the fourteen edges between one layer segment's sub-computations the
proof binds. `REPRODUCE.md` has one entry per driver once it has run.

## How a constant is read

`constants.json` holds every number the paper cites, once:

```json
"tok_s.headline.c16384.commit": {
  "value": 20.9, "unit": "tok/s", "card": "H200", "context": 16384,
  "timing_scope": "commit", "grade": "measured",
  "run": "2026-09-10-headline-c16384-h200", "artifact": "slice_0000.json",
  "note": "33 segments including the output head"
}
```

Every entry names its card, its context and its timing scope (`commit`,
`stwo total`, `whole wall`, `loop`, or `primitive` for one primitive of the
proof system timed on its own, defined at the top of the file). The
grade says how the value is checked: `measured` is re-derived from the named
artifact by `tools/constants/audit.py`; `derived` is recomputed by `check.py`
from the entries it names; `projected` comes from the cost model with its
inputs named; `external` carries the URL it was read from; `asserted` is an
assumption of the owner's, with the reason. A number that fits none of these
does not exist here. The `discrepancies` list is empty at every tag.

The paper reads `export/constants.tex`, written by `tools/constants/export.py`
at a tag, and types no number itself.

## Layout

| path | what |
|---|---|
| `runs/<run-id>/` | `manifest.json` and the run's JSON outputs; no logs |
| `constants.json` | the numbers |
| `INDEX.md` | generated: run id, driver, constants backed |
| `REPRODUCE.md` | one entry per driver that has run |
| `tools/drivers/` | one script per measured configuration, named as `REPRODUCE.md` names it |
| `tools/remote/` | `push.sh`, `lock.sh`, `run.sh`, `fetch.sh`; host-agnostic |
| `tools/constants/` | `check.py`, `audit.py`, `constants.py`, `export.py`, `index.py`, `words.py` |
| `docs/` | the cost model, the quantization configuration, and dated decisions |

## Checks

CI runs `check.py` (which runs the audit), `words.py` over the durable prose,
the `docs/` line budget, the immutability of `docs/decisions/`, and a scan of
the diff for addresses and tokens. `CLAUDE.md` holds the rules for agents.

## Acknowledgements
This work used compute resources provided by Side Channel Cloud (https://sidechannel.cloud), operated by Amodo Design.
