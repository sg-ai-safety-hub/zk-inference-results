# tools/remote

Hosts are ssh aliases the caller owns; nothing here knows a host. The scripts
assume `nvidia-smi`, `cargo` and `uv` on the host.

A pushed tree carries no `.git`. `push.sh` writes `.source-commit` beside the
sources (the commit the files came from, plus `dirty` when a working tree with
uncommitted changes was pushed) and the prover's build script reads it into the
`provenance.commit` and `provenance.dirty` fields of every output.
