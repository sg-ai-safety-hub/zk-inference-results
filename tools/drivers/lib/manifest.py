#!/usr/bin/env python3
"""Write `runs/<run-id>/manifest.json` from a fetched output directory.

    manifest.py --driver tools/drivers/<name>.sh --fetched DIR --runs runs/ \
                --prover-commit HASH --harness-commit HASH [--date YYYY-MM-DD]

Every field but `imported`, `driver`, `harness_commit` and `date` is copied
from the `provenance` block the prover writes into each output; nothing is
typed in.  The run id is `<date>-<driver>-<gpu>` with the GPU as the machine
reported it.  A fetched directory whose outputs carry no provenance block is
refused: such a run is not admissible.
"""
import argparse
import datetime
import json
import os
import re
import shutil
import sys


def outputs_of(fetched):
    for root, _, files in os.walk(fetched):
        for f in sorted(files):
            yield os.path.relpath(os.path.join(root, f), fetched)


def load_json(path):
    with open(path) as f:
        return json.load(f)


def digests_of(doc):
    """The proof digest(s) one output carries: one for `compose`, one per
    segment for `compose-chunks`.

    `boundary-grid` reports a `chunks` list too -- the cells of the grid, read
    back off disk -- and those rows carry no digest.  A list of nothing is not
    a digest list, so an output whose every entry is empty carries none."""
    r = doc.get("result", {})
    if "point" in r and "proof_sha256" in r["point"]:
        return r["point"]["proof_sha256"]
    if "chunks" in r:
        d = [c.get("proof_sha256") for c in r["chunks"]]
        return d if any(d) else None
    return None


def fold_binding(tables):
    """One binding table over every output's: an edge is unbound if any output
    left it unbound, else bound if any output bound it, else absent.  This is
    the prover's own fold (`provenance.binding`) applied once more, because a
    plan split over several processes reports one table per process."""
    tables = [t for t in tables if t]
    if not tables:
        return None
    edges = []
    for i, e0 in enumerate(tables[0]["edges"]):
        states = [t["edges"][i]["state"] for t in tables if i < len(t["edges"])]
        state = "unbound" if "unbound" in states else "bound" if "bound" in states else "absent"
        why = next((t["edges"][i].get("why") for t in tables
                    if i < len(t["edges"]) and t["edges"][i]["state"] == "unbound"), None)
        edges.append({"n": e0["n"], "edge": e0["edge"], "state": state, "why": why})
    unbound = [e["n"] for e in edges if e["state"] == "unbound"]
    return {"proofs": sum(t.get("proofs", 1) for t in tables), "edges": edges,
            "all_bound": not unbound, "unbound": unbound}


def gpu_slug(name):
    m = re.search(r"\b([A-Z]\d{3,4})\b", name or "")
    return (m.group(1) if m else re.sub(r"[^a-z0-9]+", "-", (name or "gpu").lower()).strip("-")).lower()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--driver", required=True)
    ap.add_argument("--fetched", required=True)
    ap.add_argument("--runs", required=True)
    ap.add_argument("--prover-commit", required=True)
    ap.add_argument("--harness-commit", required=True)
    ap.add_argument("--date", default=datetime.date.today().isoformat())
    a = ap.parse_args()

    files = list(outputs_of(a.fetched))
    docs = {f: load_json(os.path.join(a.fetched, f)) for f in files if f.endswith(".json")}
    prov = [(f, d["provenance"]) for f, d in sorted(docs.items()) if isinstance(d, dict) and "provenance" in d]
    if not prov:
        sys.exit("manifest.py: no output carries a `provenance` block; this prover commit "
                 "writes none, and a run without one is not admissible")
    # The document the manifest takes the run's own fields from: the first that
    # carries a digest, so `argv` names the command that made the proofs rather
    # than whichever output sorts first.  A run that made none falls back to the
    # first, which is what a check-only run has.
    first, p = next((q for q in prov if digests_of(docs[q[0]])), prov[0])
    commits = {str(q.get("commit") or "") for _, q in prov}
    if any(not c or not (a.prover_commit.startswith(c) or c.startswith(a.prover_commit)) for c in commits):
        sys.exit(f"manifest.py: the outputs were made at {sorted(commits)}, not at the pinned {a.prover_commit}")
    name = os.path.basename(a.driver).removesuffix(".sh")
    run_id = f"{a.date}-{name}-{gpu_slug(p.get('gpu'))}"
    digests = {f: digests_of(d) for f, d in docs.items() if digests_of(d) is not None}
    skips = sorted({s for _, q in prov for s in q.get("unsound_skips", [])})
    binding = fold_binding([q.get("binding") for _, q in prov])
    # a run that proves on both backends names both, sorted; one backend stays a string
    backends = sorted({str(q.get("backend")) for _, q in prov})
    backend = backends[0] if len(backends) == 1 else backends
    if binding is None:
        sys.exit("manifest.py: no output carries a binding table; a run without one is not admissible")
    manifest = {
        "run_id": run_id,
        "driver": a.driver,
        "date": a.date,
        "prover_commit": a.prover_commit,
        "prover_dirty": any(q.get("dirty") for _, q in prov),
        "harness_commit": a.harness_commit,
        "gpu": p.get("gpu"),
        "driver_version": p.get("driver_version"),
        "cuda_version": p.get("cuda_version"),
        "backend": backend,
        "argv": [p.get("binary"), *p.get("args", [])],
        "outputs": files,
        "digests": digests,
        "unsound_skips": skips,
        "binding": binding,
        "imported": False,
    }
    dest = os.path.join(a.runs, run_id)
    if os.path.exists(dest):
        sys.exit(f"manifest.py: {dest} exists; a run directory is never overwritten")
    shutil.move(a.fetched, dest)
    with open(os.path.join(dest, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
        f.write("\n")
    print(f"manifest.py: {dest}/manifest.json ({len(files)} outputs, {len(digests)} with digests, "
          f"skips {skips or 'none'})")


if __name__ == "__main__":
    main()
