#!/usr/bin/env python3
"""Write the chunk loop's plan file for `b65 compose-chunks --plan`.

One line per chunk, in the order the sequence proves them: the 32 layers and
then the head. A line carries only what that chunk decides for itself -- its
witness, its master table, and for the head the argmax and its row count.
Everything the whole sequence shares (the round, the band sizes, the pins, the
tight table) stays on the command line, because that is where the loop's
shared arguments live and repeating them per line is how a driver drifts.

The lines are the same arguments `n_seq.sh`'s `seq` step passes to 33 separate
`compose` processes, which is what makes the loop's digests comparable to
theirs chunk by chunk.

**Stream DD (E11): the block axis.**  A full prompt+output proof is `B` token
blocks of 32 layer chunks, plus one `lm_head` chunk, and the writer learns that with
one extra loop and no new argument *kind*:

    plan.py --dir D --blocks 9 --head D/witness_B8_head --out plan.txt

reads `D/shapes_B<b>.json` and writes `--witness D/witness_B<b>_L<k>
--ser-tag B<b>L<k>`.  What a prompt block's line carries that a decode line
does not is **nothing new** -- the prefix length is `Params.c`, which
`params_of` reads off the witness's own manifest (`main.rs:567`,
`c: b0.shape.c`), so a block is a directory and a table size and that is all.
No `Params` field is added, which matters because `bounds.rs:253-257`'s
`shape_ok` compares `params.s`, `params.glue`, the blowup and the two boundary
trees' sizes and would reject every cross-block link if a block index entered
the statement.

Two block-axis facts the writer enforces rather than leaves to the runner:

* **Block 0 has no prefix.**  `c = 0` makes `Grid::new(groups = c * insts, ..)`
  divide by zero (`layout.rs:117`), so a corner-only chunk does not compose
  today -- that configuration is stream CC's.  Block 0 is therefore skipped
  unless `--with-block-0` is passed, and the plan says so in a comment.
* **The head goes on the last block only.**  A prompt block emits no token.
  `--head-every-block` is there for the variant that proves one per block, and
  it is off, because nothing downstream asks for it yet.

`--emit-out` writes the *emit* set: one representative line per distinct
constraint-kernel shape rather than one per chunk.  `emitset` runs one
`cudaemit` per plan line and the store dedups by fingerprint afterwards, so at
257 lines it launches 257 processes to install ~40 shapes.  Within one model
and one set of shared pins the only shape-bearing things that vary down a plan
are the prefix length and the master table size, so `(c, table_bits)` -- plus
the head's two extra arguments -- is the whole distinct set.

**Stream EE (E11): the flags a line carries.**  `--layer-flags` goes on every
layer line, `--l0-flags` on the layer-0 lines after it, `--head-flags` on the
head line, and `--l0-dir` points the layer-0 lines at another dump set (a
layer-0 re-extract with `--embed`).  The E11 plan at C=4096 is

    plan.py --dir D --blocks 9 --with-block-0 --head H \
        --layer-flags='--round even --corner --kv-bind' --head-flags='--ao-rem-bits 23'

(the `=` form, because the value starts with a dash), and a line's flags are
part of its emit key, so the emit set grows by the lines whose flags make a
new kernel shape and by nothing else.
"""

import argparse
import json
import os


def read_rows(path):
    return {r["layer"]: r for r in json.load(open(path))["rows"]}


def want_layers(spec, rows):
    if not spec:
        return sorted(rows)
    want = []
    for part in spec.split(","):
        if "-" in part:
            lo, hi = part.split("-")
            want.extend(range(int(lo), int(hi) + 1))
        else:
            want.append(int(part))
    return want


def layer_line(tb, wdir, tag, extra=""):
    return f"--table-bits {tb} --bounds{extra} --witness {wdir} --ser-tag {tag}"


def head_line(hdir, htb, tag="head", extra=""):
    return (f"--table-bits {htb} --head-argmax --deq-per-row 501{extra} "
            f"--witness {hdir} --ser-tag {tag}")


def flags(s):
    """A flag string as written on a line: one leading space, or nothing."""
    s = " ".join(s.split())
    return f" {s}" if s else ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True,
                    help="the layer witness directory, holding shapes.json and witness_L*")
    ap.add_argument("--head", default="", help="the head witness directory, if it is to be proved")
    ap.add_argument("--layers", default="", help="which layers, e.g. 0-31 or 0,1,2 (default all)")
    ap.add_argument("--out", required=True)
    # ---- stream DD (E11): the block axis ------------------------------------
    ap.add_argument("--blocks", default="",
                    help="how many token blocks the sequence has: an integer, or 'auto' to "
                         "count DIR/shapes_B*.json. Empty (the default) is the pre-DD "
                         "single-block plan and its lines are unchanged.")
    ap.add_argument("--with-block-0", action="store_true",
                    help="include block 0's layer chunks. It has c = 0 and does not compose "
                         "today (layout.rs:117 divides by c * insts); stream CC owns the "
                         "corner-only configuration.")
    ap.add_argument("--head-every-block", action="store_true",
                    help="an lm_head chunk after every block, not only the last one")
    ap.add_argument("--emit-out", default="",
                    help="also write the distinct emit shapes, one representative plan line "
                         "each, for `emitset` to walk instead of the plan")
    # ---- stream EE (E11): what every line carries besides its own shape ------
    # The E11 grid wants AA's flags on every layer line (`--round even --corner
    # --kv-bind --bounds`), BB's `--embed` on the layer-0 lines, and the head
    # pinned where seq6 ran it.  They go on the LINE, not the shared command
    # line, because `bounds-grid` reads a chunk's flags back off its statement
    # and the head must not inherit `--kv-bind`.  A line's flags are part of its
    # emit key: an `--embed` layer-0 line is a different kernel shape from a
    # layer-1 line at the same (c, table bits).
    ap.add_argument("--layer-flags", default="",
                    help="appended to every layer line, e.g. "
                         "'--round even --corner --kv-bind' (E11)")
    ap.add_argument("--l0-flags", default="",
                    help="appended to every layer-0 line after --layer-flags, e.g. "
                         "'--embed' (E11, stream BB)")
    ap.add_argument("--l0-dir", default="",
                    help="take the layer-0 witnesses from this directory instead of --dir "
                         "(a layer-0 re-extract with --embed next to the full dump set)")
    ap.add_argument("--head-flags", default="",
                    help="appended to the head line, e.g. '--ao-rem-bits 23' to keep the "
                         "head at its own pin when the shared pins are the layers'")
    a = ap.parse_args()
    lf, l0f, hf = flags(a.layer_flags), flags(a.l0_flags), flags(a.head_flags)

    if not a.blocks:
        blocks = [None]
    elif a.blocks == "auto":
        import glob
        blocks = sorted(int(os.path.basename(q)[len("shapes_B"):-len(".json")])
                        for q in glob.glob(f"{a.dir}/shapes_B*.json"))
        assert blocks, f"--blocks auto: no {a.dir}/shapes_B*.json"
    else:
        blocks = list(range(int(a.blocks)))

    lines, emit = [], {}
    n_rows, n_layer_rows = 0, 0
    for b in blocks:
        if b is None:
            rows = read_rows(f"{a.dir}/shapes.json")
            pre, wpre = "", f"{a.dir}/witness_L"
        else:
            if b == 0 and not a.with_block_0:
                lines.append("# block 0 skipped: c = 0 is the corner-only chunk (stream CC); "
                             "pass --with-block-0 once it composes")
                continue
            rows = read_rows(f"{a.dir}/shapes_B{b}.json")
            pre, wpre = f"B{b}", f"{a.dir}/witness_B{b}_L"
            lines.append(f"# block {b}: prefix c = {rows[sorted(rows)[0]]['c']}")
        want = want_layers(a.layers, rows)
        for k in want:
            tb = rows[k]["table_bits"]
            extra = lf + (l0f if k == 0 else "")
            wdir = f"{wpre}{k}"
            if k == 0 and a.l0_dir:
                wdir = f"{a.l0_dir}/{os.path.basename(wpre)}{k}"
            line = layer_line(tb, wdir, f"{pre}L{k}", extra)
            lines.append(line)
            n_rows += 1
            n_layer_rows += 1
            emit.setdefault((rows[k]["c"], tb, False, extra), line)
        if a.head and (a.head_every_block or b == blocks[-1]):
            htb = json.load(open(f"{a.head}/manifest.json"))["master_table_bits"]
            lines.append("# the head, last, and it is the same compose family with two extra "
                         "arguments")
            hl = head_line(a.head, htb, "head" if not a.head_every_block else f"{pre}head", hf)
            lines.append(hl)
            n_rows += 1
            emit.setdefault((None, htb, True, hf), hl)
    lines.insert(0, f"# stream O: {n_layer_rows} layer chunks from {a.dir}"
                    if blocks == [None] else
                    f"# stream DD: {n_layer_rows} layer chunks over {len(blocks)} token "
                    f"blocks from {a.dir}")

    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{a.out}: {n_rows} chunks")

    if a.emit_out:
        el = [f"# stream DD: {len(emit)} distinct emit shapes for the {n_rows} chunks of "
              f"{a.out}; the key is (prefix c, master table bits, head, the line's flags)"]
        for key in sorted(emit, key=lambda k: (k[2], k[0] or 0, k[1], k[3])):
            el.append(emit[key])
        os.makedirs(os.path.dirname(a.emit_out) or ".", exist_ok=True)
        with open(a.emit_out, "w") as f:
            f.write("\n".join(el) + "\n")
        print(f"{a.emit_out}: {len(emit)} emit shapes (of {n_rows} chunks, "
              f"x{n_rows / max(len(emit), 1):.1f} fewer cudaemit launches)")


if __name__ == "__main__":
    main()
