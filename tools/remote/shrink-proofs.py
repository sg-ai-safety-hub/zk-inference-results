#!/usr/bin/env python3
"""Verify each finished group's proofs, then shrink them to the roots the link
check reads, so that a sequence run at context 16,384 fits the host's volume.

    tools/remote/shrink-proofs.py <run dir> <simd prover> <prompt ids json>

Runs on the host, beside a `headline-c16384.sh` job and not inside it: it is a
mitigation for one host's disk and not part of what the run measures.  It takes
no lock, writes only under the run's own `out/`, `ser/`, `ser-hold/` and
`ser-shrunk/`, and stops on its own once the job is done and every group is
shrunk.  Start it detached:

    setsid nohup nice -n 19 python3 shrink-proofs.py \
        ~/runs/<name> ~/build/<commit>/t-simd/release/zk-prover ~/prompt.json &

Why.  A serialized proof at this context is 112 to 159 MiB and the plan has
1,057 of them: about 108 GiB of proofs against a 216 GiB volume that also holds
26 GiB of weights, 9 GiB of build trees, 10 GiB of other runs' outputs and up to
60 GiB of one group's layer dumps.  The run reaches its sixth group with about
6 GiB to spare, which is not a margin.

What it does, once per group, after the job has written the group's line into
`groups.jsonl` and while the proofs are still whole:

  1. `boundary-grid --verify --prompt` over the group's tags.  This runs the
     verifier on every one of the group's proofs -- which the job's own final
     grid does not do, and the context 4,096 run never did -- and records the
     chunk rows with the true `proof_bytes`.
  2. the sha256 and the size of every proof, recorded before anything is
     touched.
  3. each proof rewritten as its `commitments` field alone.  `boundary-grid`
     without `--verify` deserializes a proof as `RootsOnly` and keeps nothing
     else (prover/src/boundary.rs:1078), so the job's final grid over the whole
     plan reads exactly what it would have read.  The statements and the
     verifier's `claims.json` are not touched.
  4. `boundary-grid` over the same tags again, and the chunk rows and link
     counts compared with step 1's.  Anything but `proof_bytes` differing stops
     the watcher.

A group whose proofs do not all verify stops the watcher with nothing deleted.
"""
import hashlib
import json
import os
import subprocess
import sys
import time

STUB_MIN = 4096          # a proof this small is one this has already shrunk
KEY = b'"commitments"'


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def plan_tags(plan, lo, hi):
    tags = []
    for line in open(plan):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        tags.append(s.split("--ser-tag ")[1].split()[0])
    return tags[lo:hi]


def grid(prover, ser, tags, out, extra=()):
    cmd = [prover, "boundary-grid", "--dir", ser, "--tags", ",".join(tags),
           "--allow-gaps", *extra]
    env = dict(os.environ, RAYON_NUM_THREADS="4")
    with open(out, "w") as f, open(out + ".err", "w") as e:
        rc = subprocess.call(cmd, stdout=f, stderr=e, env=env,
                             preexec_fn=lambda: os.nice(19))
    return rc, json.load(open(out))["result"]


def roots_of(path):
    with open(path, "rb") as f:
        raw = f.read()
    h = hashlib.sha256(raw).hexdigest()
    i = raw.find(KEY)
    if i < 0 or raw.find(KEY, i + 1) >= 0:
        raise SystemExit(f"{path}: not one commitments field; refusing to touch it")
    j = raw.index(b":", i + len(KEY)) + 1
    value, _ = json.JSONDecoder().raw_decode(raw.decode("utf-8", "strict"), j)
    return h, len(raw), value


def comparable(result):
    """The part of a grid result that the proof's bytes cannot change."""
    return ({k: result[k] for k in ("links_expected", "links_run", "links_passed",
                                    "all_chain") if k in result},
            [{k: v for k, v in c.items() if k != "proof_bytes"}
             for c in result.get("chunks", [])])


def hold(run, ser, tags):
    """A second name for each of the group's three documents, so that the job's
    own `rm -rf $SER` at the end of the run cannot take the proofs out from
    under a verification that is still reading them.  A hard link costs no
    space and the bytes go when the last name does."""
    d = os.path.join(run, "ser-hold")
    if os.path.isdir(d):
        for f in os.listdir(d):
            os.remove(os.path.join(d, f))
    else:
        os.makedirs(d)
    for t in tags:
        for kind in ("proof", "fixed", "claims"):
            src = os.path.join(ser, f"{t}.{kind}.json")
            if os.path.exists(src):
                os.link(src, os.path.join(d, f"{t}.{kind}.json"))
    return d


def do_group(run, prover, prompt, g):
    ser, out = os.path.join(run, "ser"), os.path.join(run, "out")
    name = g["blocks"]
    tags = plan_tags(os.path.join(out, "plan.txt"), g["plan_lo"], g["plan_hi"])
    proofs = [os.path.join(ser, f"{t}.proof.json") for t in tags]
    absent = [p for p in proofs if not os.path.exists(p)]
    if absent:
        log(f"group {name}: {len(absent)} proofs are not written yet; waiting")
        return False
    whole = [p for p in proofs if os.path.getsize(p) >= STUB_MIN]
    log(f"group {name}: {len(tags)} tags, {len(whole)} whole proofs, "
        f"{sum(os.path.getsize(p) for p in proofs) / 2**30:.1f} GiB")

    held = hold(run, ser, tags)
    log(f"group {name}: held under {held}; verifying every proof")
    rc, before = grid(prover, held, tags, os.path.join(out, f"verify-g{name}.json"),
                      ("--verify", "--prompt", prompt))
    v = before.get("verified") or {}
    if not v.get("all") or v.get("run", 0) != len(tags):
        raise SystemExit(f"group {name}: the verifier did not accept every proof "
                         f"({v.get('accepted')}/{v.get('run')} of {len(tags)}, exit {rc}); "
                         f"nothing deleted, see out/verify-g{name}.json")
    log(f"group {name}: {v['accepted']}/{v['run']} proofs verified, grid exit {rc}")

    rows = []
    for t in tags:
        p = os.path.join(ser, f"{t}.proof.json")
        h, n, value = roots_of(os.path.join(held, f"{t}.proof.json"))
        tag = t
        if not os.path.exists(p):
            rows.append({"tag": tag, "sha256": h, "bytes": n, "roots": len(value),
                         "gone_from_ser": True})
            continue
        if n < STUB_MIN:
            rows.append({"tag": tag, "sha256": h, "bytes": n, "roots": len(value),
                         "already_stub": True})
            continue
        tmp = p + ".stub"
        with open(tmp, "w") as f:
            json.dump({"commitments": value}, f)
        os.replace(tmp, p)
        rows.append({"tag": tag, "sha256": h, "bytes": n, "roots": len(value),
                     "stub_bytes": os.path.getsize(p)})
    freed = sum(r["bytes"] - r.get("stub_bytes", r["bytes"]) for r in rows)
    json.dump({"group": name, "plan_lo": g["plan_lo"], "plan_hi": g["plan_hi"],
               "proofs": rows, "bytes_before": sum(r["bytes"] for r in rows),
               "bytes_freed": freed,
               "note": "sha256 and size of each serialized proof as the prover wrote it, "
                       "taken before the proof was rewritten as its commitments alone. "
                       "The digests are the prover's own proof_sha256s in the slice "
                       "outputs; these are computed over the files."},
              open(os.path.join(out, f"proofs-g{name}.json"), "w"), indent=1)
    log(f"group {name}: {freed / 2**30:.1f} GiB freed")

    rc2, after = grid(prover, ser, tags, os.path.join(out, f"regrid-g{name}.json"))
    for f in os.listdir(held):
        os.remove(os.path.join(held, f))
    if comparable(before) != comparable(after):
        raise SystemExit(f"group {name}: the grid over the shrunk proofs is not the grid "
                         f"over the whole ones; see out/regrid-g{name}.json")
    log(f"group {name}: the grid reads the same, links {after.get('links_passed')}"
        f"/{after.get('links_run')}, chain {after.get('all_chain')}")
    return True


def main(run, prover, prompt):
    done = os.path.join(run, "ser-shrunk")
    os.makedirs(done, exist_ok=True)
    while True:
        gj = os.path.join(run, "groups.jsonl")
        rows = {}
        if os.path.exists(gj):
            for line in open(gj):
                if line.strip():
                    r = json.loads(line)
                    rows[r["blocks"]] = r
        for name, g in rows.items():
            if os.path.exists(os.path.join(done, name)):
                continue
            if do_group(run, prover, prompt, g):
                open(os.path.join(done, name), "w").close()
        st = os.path.join(os.path.dirname(run), os.path.basename(run) + ".status")
        finished = os.path.exists(st) and open(st).read().count("done exit=")
        if finished and all(os.path.exists(os.path.join(done, n)) for n in rows):
            log("the job is finished and every group is shrunk; the watcher stops")
            return
        time.sleep(120)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
