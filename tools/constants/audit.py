#!/usr/bin/env python3
"""Re-derive every `measured` constant from its run artifact.

One section per driver, registered in SECTIONS when the driver's first run
lands.  A section receives the audit and the constants it is responsible for,
opens `runs/<run>/<artifact>`, recomputes each value, and calls `claim`.  A
`measured` constant no section claims is a failure: the audit never accepts a
constant without an artifact it has read.  Run through `check.py`.
"""
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from constants import load  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]


class Audit:
    def __init__(self, fails):
        self.fails = fails
        self.claimed = set()
        self.npass = 0

    def claim(self, key, computed, tol=0.001):
        """`computed`, from the artifact, against the stored value."""
        e = load()["constants"][key]
        published = e["value"]
        agree = abs(computed) <= tol if published == 0 else abs(computed / published - 1) <= tol
        print(f"{'PASS' if agree else 'FAIL'}  {key:52s} stored={published}  artifact={computed:,.6g}  "
              f"[runs/{e['run']}/{e['artifact']}]")
        self.claimed.add(key)
        if agree:
            self.npass += 1
        else:
            self.fails.append(f"audit: {key}: stored {published}, artifact {computed}")

    def exact(self, key, computed):
        e = load()["constants"][key]
        agree = computed == e["value"]
        print(f"{'PASS' if agree else 'FAIL'}  {key:52s} stored={e['value']}  artifact={computed}")
        self.claimed.add(key)
        if agree:
            self.npass += 1
        else:
            self.fails.append(f"audit: {key}: stored {e['value']!r}, artifact {computed!r}")


def artifact(run, name):
    """One committed artifact of one run, as JSON."""
    return json.loads((ROOT / "runs" / run / name).read_text())


def manifest(run):
    return artifact(run, "manifest.json")


# -- sections: (driver name, function(audit, keys)) ----------------------------
# Added when a driver's first run lands; each function re-derives the constants
# whose `run` was made by that driver.
SECTIONS = []


def run(fails):
    a = Audit(fails)
    c = load()["constants"]
    measured = {k: e for k, e in c.items() if e["grade"] == "measured"}
    print("\n" + "=" * 100)
    print(f"ARTIFACT AUDIT: {len(measured)} measured constants, {len(SECTIONS)} sections")
    print("=" * 100)
    for driver, fn in SECTIONS:
        mine = {k: e for k, e in measured.items()
                if (ROOT / "runs" / e["run"] / "manifest.json").exists()
                and manifest(e["run"]).get("driver", "").endswith(f"/{driver}.sh")}
        fn(a, mine)
    for k in sorted(set(measured) - a.claimed):
        fails.append(f"audit: {k} is measured but no section re-derives it")
    print(f"{a.npass} re-derived and agreeing; {len(set(measured) - a.claimed)} unclaimed")
    return a


if __name__ == "__main__":
    f = []
    run(f)
    sys.exit(1 if f else 0)
