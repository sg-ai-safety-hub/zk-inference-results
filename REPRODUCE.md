# Reproduce

One entry per driver, written when the driver's first run lands: the command
with its three arguments, the run ids it produced, the prover commit, the
digests, the binding table from the manifest, and the constants keys it backs.

No driver has run yet. Written, not yet run:

- `tools/drivers/headline-c16384.sh`: the paper's headline configuration, one
  16,384-token prompt and its 512 output tokens proved from the embedding up,
  on the CUDA backend, pipelined. Waits for the prover's sound defaults and
  provenance block.

## Entry template

```
## <driver>

    tools/drivers/<driver>.sh <host> <prover-commit> <harness-commit>

runs: <run-id>, ...
prover commit: <hash>   harness commit: <hash>
digests: <artifact>: <digest>, ...
binding: bound <edges>; unbound <edges>   (from the manifest)
unsound skips: none
constants backed: <keys>
```
