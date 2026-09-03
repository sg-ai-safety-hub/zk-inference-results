"""Read `constants.json`: `get(key)`, `value(key)`, `keys(prefix)`.  Never writes.

    from constants import get, value
    value("cost.h200_reference_usd_per_hour")
"""
import json
import pathlib

PATH = pathlib.Path(__file__).resolve().parents[2] / "constants.json"
_DOC = None


def load():
    """The whole file: `_schema`, `_grades`, `_timing_scopes`, `constants`, `discrepancies`."""
    global _DOC
    if _DOC is None:
        _DOC = json.loads(PATH.read_text())
    return _DOC


def get(key):
    c = load()["constants"]
    if key not in c:
        near = sorted(k for k in c if k.split(".")[0] == key.split(".")[0])[:8]
        raise KeyError(f"{key!r} is not in constants.json; same group: {near or 'none'}")
    return c[key]


def value(key):
    e = get(key)
    if e["value"] is None:
        raise ValueError(f"{key!r} has no value: {e.get('note', '')}")
    return e["value"]


def keys(prefix=""):
    return sorted(k for k in load()["constants"] if k.startswith(prefix))


def discrepancies():
    return load()["discrepancies"]


if __name__ == "__main__":
    doc = load()
    print(f"{PATH.name}: {len(doc['constants'])} constants, {len(doc['discrepancies'])} discrepancies")
    for k in keys():
        e = doc["constants"][k]
        print(f"  {k:52s} {e['value']!s:>14}  {e['unit']:<14} [{e['grade']}] {e['card']}/{e['context']}/{e['timing_scope']}")
