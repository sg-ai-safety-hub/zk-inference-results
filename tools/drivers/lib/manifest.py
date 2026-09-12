#!/usr/bin/env python3
"""Write `runs/<run-id>/manifest.json` from a fetched output directory.

    manifest.py --driver tools/drivers/<name>.sh --fetched DIR --runs runs/ \
                --prover-commit HASH --harness-commit HASH [--date YYYY-MM-DD]

Every field but `imported`, `driver`, `harness_commit`, `date` and `derived` is
copied from the `provenance` block written into each output; nothing is typed
in.  The run id is `<date>-<driver>-<gpu>` with the GPU as the machine reported
it.  A fetched directory whose outputs carry no provenance block is refused:
such a run is not admissible.

`derived` is the one field no prover wrote and no host saw: the record a driver
gives with `--derived FILE` for an output of the run that was derived from runs
this repository already holds rather than measured.  It names what was derived,
and out of which run, which output and which segment, so the derivation can be
made again and checked.  A run that derives nothing has it null.

Three kinds of run, and the manifest says which in `kind`.  A **prover** run
makes proofs, and its outputs carry a binding table saying what each proof
binds; one that carries none is refused, which is the whole point of the check.
A **harness** run makes no proof: it measures the arithmetic the prover
constrains -- a perplexity, a task score -- so it has no binding table and no
proof digest, and it says so by declaring `kind` `harness` in every one of its
provenance blocks.  Only a directory that declares itself that way, and that
carries no proof digest anywhere, takes the second path; a prover run that lost
its binding table still cannot.

A **verifier** run runs the prover binary and makes no proof either: it reads
proofs another run made and checks them, or derives from the model the public
input those checks compare against.  The prover writes a binding table for each
proof it produces and there are none here, so such a run cannot say what it is
in its own outputs; the driver says it on the command line with `--kind
verifier`, and the same two checks the harness path makes are made here -- no
proof digest anywhere, no binding table -- so a prover run that lost its table
still cannot take this path either.
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
    a digest list, so an output whose every entry is empty carries none.

    A run directory may also hold a JSON file that is not an output document at
    all: `headline-c16384` writes `groups.json`, which is a list of the token
    block groups the job divided the plan into, and `model-roots --out` writes a
    bare list of rows.  A document that is not an object carries no digest, the
    same answer the `provenance` scan already gives it."""
    if not isinstance(doc, dict):
        return None
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
    # A run whose outputs report no GPU touched no card, and `none` is the word
    # this repository already uses for that: it is what such a run's entries
    # carry under `card` and what `register-13b` and `register-14b` are named
    # after.  A run id that said `gpu` instead would name a card that was never
    # there.
    if not name:
        return "none"
    m = re.search(r"\b([A-Z]\d{3,4})\b", name)
    return (m.group(1) if m else re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")).lower()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--driver", required=True)
    ap.add_argument("--fetched", required=True)
    ap.add_argument("--runs", required=True)
    ap.add_argument("--prover-commit", required=True)
    ap.add_argument("--harness-commit", required=True)
    ap.add_argument("--date", default=datetime.date.today().isoformat())
    ap.add_argument("--kind", choices=("prover", "harness", "verifier"), default=None,
                    help="the kind of run, where the outputs cannot say it themselves: "
                         "`verifier` for a run that makes no proof and checks proofs another "
                         "run made")
    ap.add_argument("--derived", metavar="FILE", default=None,
                    help="a JSON record of the outputs this run derived from runs already in "
                         "this repository, written into the manifest as `derived`")
    a = ap.parse_args()

    files = list(outputs_of(a.fetched))
    docs = {f: load_json(os.path.join(a.fetched, f)) for f in files if f.endswith(".json")}
    prov = [(f, d["provenance"]) for f, d in sorted(docs.items()) if isinstance(d, dict) and "provenance" in d]
    if not prov:
        sys.exit("manifest.py: no output carries a `provenance` block; a run without one "
                 "is not admissible")
    kinds = {str(q.get("kind", "prover")) for _, q in prov}
    if len(kinds) != 1:
        sys.exit(f"manifest.py: the outputs declare more than one kind of run, {sorted(kinds)}; "
                 "a run is one or the other")
    declared = kinds.pop()
    if declared not in ("prover", "harness"):
        sys.exit(f"manifest.py: an output declares kind {declared!r}, which is neither "
                 "`prover` nor `harness`")
    # The prover writes no `kind`, so `prover` is what an output that says
    # nothing says.  A driver may name `verifier` over that, and over nothing
    # else: a run whose outputs declare themselves a harness run is one.
    if a.kind and declared != "prover" and a.kind != declared:
        sys.exit(f"manifest.py: the outputs declare kind {declared!r} and the driver says "
                 f"{a.kind!r}; a run is one or the other")
    kind = a.kind or declared
    # The document the manifest takes the run's own fields from: the first that
    # carries a digest, so `argv` names the command that made the proofs rather
    # than whichever output sorts first.  A run that made none falls back to the
    # first, which is what a check-only run has.
    first, p = next((q for q in prov if digests_of(docs[q[0]])), prov[0])
    # A prover output's commit is the prover's; a harness output's is the
    # harness's, because that is the tree that made it and no prover ran.
    pinned = a.harness_commit if kind == "harness" else a.prover_commit
    commits = {str(q.get("commit") or "") for _, q in prov}
    if any(not c or not (pinned.startswith(c) or c.startswith(pinned)) for c in commits):
        sys.exit(f"manifest.py: the outputs were made at {sorted(commits)}, not at the pinned {pinned}")
    name = os.path.basename(a.driver).removesuffix(".sh")
    run_id = f"{a.date}-{name}-{gpu_slug(p.get('gpu'))}"
    digests = {f: digests_of(d) for f, d in docs.items() if digests_of(d) is not None}
    skips = sorted({s for _, q in prov for s in q.get("unsound_skips", [])})
    binding = fold_binding([q.get("binding") for _, q in prov])
    # a run that proves on both backends names both, sorted; one backend stays a string
    backends = sorted({str(q.get("backend")) for _, q in prov})
    backend = backends[0] if len(backends) == 1 else backends
    if binding is None and kind not in ("harness", "verifier"):
        sys.exit("manifest.py: no output carries a binding table, and neither the outputs "
                 "nor the driver declare the run a harness or a verifier run; a prover run "
                 "without one is not admissible")
    if kind == "verifier":
        # The same two checks the harness path makes, from the other side: a run
        # that says it makes no proof must make none.
        if digests:
            sys.exit(f"manifest.py: a verifier run carries proof digests {sorted(digests)}; "
                     "a run that declares it makes no proof must make none")
        if binding is not None:
            sys.exit("manifest.py: a verifier run carries a binding table; a run that makes "
                     "no proof binds nothing")
    if kind == "harness":
        # A run that says it proves nothing must prove nothing, and every file
        # that carries a measurement must say where it came from.  `config.json`
        # is the driver's own record of what it asked for and no program made
        # it, so it is the one output that carries no provenance block.
        if digests:
            sys.exit(f"manifest.py: a harness run carries proof digests {sorted(digests)}; "
                     "a run that declares it makes no proof must make none")
        if binding is not None:
            sys.exit("manifest.py: a harness run carries a binding table; a run that makes "
                     "no proof binds nothing")
        silent = sorted(set(docs) - {f for f, _ in prov} - {"config.json"})
        if silent:
            sys.exit(f"manifest.py: {silent} carry no `provenance` block; in a harness run "
                     "every output but config.json says where it came from")
    manifest = {
        "run_id": run_id,
        "derived": load_json(a.derived) if a.derived else None,
        "driver": a.driver,
        "kind": kind,
        "date": a.date,
        # A harness run ran no prover, so it names none: the commit that made it
        # is the harness commit below.
        "prover_commit": None if kind == "harness" else a.prover_commit,
        "prover_dirty": None if kind == "harness" else any(q.get("dirty") for _, q in prov),
        "harness_dirty": any(q.get("dirty") for _, q in prov) if kind == "harness" else None,
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
