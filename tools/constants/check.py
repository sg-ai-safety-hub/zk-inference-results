#!/usr/bin/env python3
"""Consistency check on `constants.json`, then the artifact audit.

    python3 tools/constants/check.py [--strict]

Structure: every entry carries the nine fields; its grade is one of the five;
a `measured` entry names a run directory that exists, with a manifest, and an
artifact in it; an `external` entry's note carries a URL; an `asserted` entry's
note gives the reason; a `derived` entry is recomputed below from the entries
it names.  Then `audit.py` re-derives every `measured` entry from its artifact.
`--strict` also fails on a non-empty `discrepancies` list, which a release tag
requires.  A `projected` entry is recomputed where PROJECTED holds a line for it,
which is where the projection's whole arithmetic is entries of this file; the
cost model's own rows are priced in its run and only their `inputs` are checked.  A `derived` entry whose two sides are counts in a run artifact rather
than entries of this file is recomputed through `audit.py`'s reader for it.
This file reads no prose.
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from constants import load, value as v  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIELDS = ("value", "unit", "card", "context", "timing_scope", "grade", "note")
GRADES = ("measured", "derived", "projected", "external", "asserted")
fails = []


def composed():
    """The composed statement's rows, recomputed from the two headline runs.

    Their two sides are counts one slice output holds and not entries of this
    file, so the reader lives in `audit.py` beside the other artifact readers and
    is called here as well; it reads the outputs once.
    """
    import audit  # noqa: E402
    return audit.composed_figures()[0]


def registered_14b():
    """The 14B prediction's own figure, out of the registration run.

    The same reader the audit uses, for the same reason `composed` is one: the
    figure is in a run artifact and not in an entry of this file.
    """
    import audit  # noqa: E402
    return audit.registered_14b()


def moe_uniform(key):
    """The routing assumption's own answer for one `moe.routing.*` key.

    The same reason `composed` and `registered_14b` are readers: its two sides
    are the experts and the top-k the run recorded in its artifact, not entries
    of this file.
    """
    import audit  # noqa: E402
    return audit.moe_routing_uniform(key)


def block_counted(s):
    """One block length's counted cells, out of the run that counted them.

    A fourth reader in `audit.py` for the same reason the three above are
    there: the figure is the prover's trace layout counted at that block
    length, and it is in a run artifact rather than in an entry of this file.
    """
    import audit  # noqa: E402
    return audit.block_length_counted(s)


# The block lengths `tools/drivers/block-length-c4096.sh` measures one token
# block at.  A line below exists for each of them and does nothing until that
# run's rows are in this file.
BLOCK_LENGTHS = (256, 512, 1024)
BLOCK_SCOPES = ("commit", "stwo_total", "whole_wall", "loop")


def chk(name, got, key, tol=0.005):
    """A `derived` entry recomputed: relative tolerance, absolute when the stored value is 0."""
    exp = v(key)
    ok = abs(got - exp) <= tol if exp == 0 else abs(got - exp) / abs(exp) <= tol
    print(f"{'OK  ' if ok else 'FAIL'}  {name:44s} stored={exp}  computed={got:,.6g}")
    if not ok:
        fails.append(f"derived: {key}")


# The models `tools/drivers/moe-routing.sh` has measured the routing of. One
# name per model, because the derived lines below are keys and a key names one.
MOE_ROUTING_MODELS = ("qwen3_30b_a3b",)

# The twelve phases `phase-split-c4096` measures, in the order its record writes
# them; `audit.py` holds the same list and reads the seconds, this file divides.
PHASE_SPLIT = ("read", "decode", "check", "construct", "alloc", "build_rest",
               "trace", "interaction", "stwo", "serialize", "prove_rest", "loop_rest")

# -- every `derived` entry this file knows how to recompute --------------------
# One line per derived constant; a derived entry with no line here fails below.
DERIVED = {
    # E4's comparison at the third scale: what the run measured over what the
    # registration counted, and that ratio as a percentage.  Both sides are
    # entries of this file -- one measured over the run's 39 layer proofs, one
    # the registration's own counted figure -- and both are over the same 39
    # segments, because layer 0 of that model is in no dump and neither side
    # counts it.
    "e4.codellama_13b.c4096.rho": lambda: chk(
        "E4 13B measured over registered cells/token",
        v("e4.codellama_13b.c4096.cells_per_token_layers")
        / v("e4.codellama_13b.c4096.registered_cells_per_token_layers"),
        "e4.codellama_13b.c4096.rho", 1e-9),
    "e4.codellama_13b.c4096.residual_pct": lambda: chk(
        "E4 13B residual",
        (v("e4.codellama_13b.c4096.rho") - 1.0) * 100.0,
        "e4.codellama_13b.c4096.residual_pct", 1e-9),
    "verinf.maverick.tok_s": lambda: chk(
        "VerInf Maverick positions/s", v("verinf.maverick.positions") / (v("verinf.maverick.prover_hours") * 3600),
        "verinf.maverick.tok_s", 0.001),
    # E4: the 14B measurement against the prediction registered before it.  The
    # predicted row is the registration's own figure, read off the run that
    # recorded it; rho divides the measured entry by it, so both sides of the
    # comparison are rows of this file and neither is a second measurement.
    "e4.qwen2p5_14b.c4096.predicted_cells_per_token_layers": lambda: chk(
        "14B registered prediction, cells/token (layers)", registered_14b(),
        "e4.qwen2p5_14b.c4096.predicted_cells_per_token_layers", 0.0),
    "e4.qwen2p5_14b.c4096.rho": lambda: chk(
        "14B measured / registered prediction",
        v("e4.qwen2p5_14b.c4096.cells_per_token_layers")
        / v("e4.qwen2p5_14b.c4096.predicted_cells_per_token_layers"),
        "e4.qwen2p5_14b.c4096.rho", 0.001),
    # The mixture routing campaign: beside every measured distinct-expert count,
    # what `assumption.cost_model.moe_routing` gives for the same block. A model
    # this repository holds no run for has no entry and no line of this runs.
    **{f"moe.routing.{m}.c{c}.s{s}.distinct_experts_uniform": (lambda m=m, c=c, s=s: chk(
        f"{m} c{c:,} S={s} distinct experts, under the routing assumption",
        moe_uniform(f"moe.routing.{m}.c{c}.s{s}.distinct_experts_uniform"),
        f"moe.routing.{m}.c{c}.s{s}.distinct_experts_uniform", 1e-9))
       for m in MOE_ROUTING_MODELS for c in (4096, 16384) for s in (128, 256, 512, 1024)},
    "verinf.gb10_vs_h200_bandwidth_ratio": lambda: chk(
        "GB10 measured / H200 spec bandwidth",
        v("verinf.gb10_measured_bandwidth_gbps") / v("hardware.h200.hbm_gbps_spec"),
        "verinf.gb10_vs_h200_bandwidth_ratio", 0.001),
    # The sequence at context 4,096.  A rate is cells over the seconds at one
    # timing scope, and a positions-per-second row is the sequence's positions
    # over the same seconds; both sides of every division are `measured` rows
    # of the same run, so nothing here is a second measurement.
    **{f"rate.headline.c4096.{s}": (lambda s=s: chk(
        f"c4096 headline {s.replace('_', ' ')} rate",
        v("cells.headline.c4096.fresh") / v(f"secs.headline.c4096.{s}") / 1e6,
        f"rate.headline.c4096.{s}", 0.001))
       for s in ("commit", "stwo_total", "whole_wall", "loop")},
    # The sequence at context 16,384: the same two divisions over the same
    # kind of rows, one campaign up.
    **{f"rate.headline.c16384.{s}": (lambda s=s: chk(
        f"c16384 headline {s.replace('_', ' ')} rate",
        v("cells.headline.c16384.fresh") / v(f"secs.headline.c16384.{s}") / 1e6,
        f"rate.headline.c16384.{s}", 0.001))
       for s in ("commit", "stwo_total", "whole_wall", "loop")},
    **{f"pos_s.headline.c16384.{s}": (lambda s=s: chk(
        f"c16384 headline positions/s, {s.replace('_', ' ')}",
        v("positions.headline.c16384") / v(f"secs.headline.c16384.{s}"),
        f"pos_s.headline.c16384.{s}", 0.001))
       for s in ("whole_wall", "loop")},
    # What one proved position costs in proof bytes: the sequence's whole proof
    # over the positions it proves.  Both sides are `measured` rows of the same
    # run, so this is not a second measurement.  The serialized total is the one
    # divided at both contexts, because that is what a verifier is given.
    **{f"proof.headline.c{c}.bytes_per_position": (lambda c=c: chk(
        f"c{c} headline proof bytes per proved position",
        v(f"proof.headline.c{c}.total_bytes") / v(f"positions.headline.c{c}"),
        f"proof.headline.c{c}.bytes_per_position", 0.001))
       for c in (4096, 16384)},
    # The same proof measured the other three ways the sequence can be divided.
    # The in-memory total over the positions, beside the serialized row above.
    # And, per segment, the mean beside the median the file already carries: the
    # median is a segment the run proved and the mean is the only per-segment
    # figure that multiplies back to the total, so a reader is given both and
    # the notes say which is which.
    **{f"proof.headline.c{c}.in_memory_bytes_per_position": (lambda c=c: chk(
        f"c{c} headline in-memory proof bytes per proved position",
        v(f"proof.headline.c{c}.total_in_memory_bytes") / v(f"positions.headline.c{c}"),
        f"proof.headline.c{c}.in_memory_bytes_per_position", 0.001))
       for c in (4096, 16384)},
    **{f"proof.headline.c{c}.{p}bytes_per_segment_mean": (lambda c=c, p=p, t=t: chk(
        f"c{c} headline {'in-memory ' if p else ''}proof bytes per segment, mean",
        v(f"proof.headline.c{c}.{t}") / v(f"segments.headline.c{c}"),
        f"proof.headline.c{c}.{p}bytes_per_segment_mean", 0.001))
       for c in (4096, 16384)
       for p, t in (("", "total_bytes"), ("in_memory_", "total_in_memory_bytes"))},
    # The same two divisions on the 13B run, whose plan is one token block of
    # layer segments and no output head: the block's positions and the segments
    # the run proved, which is 39 of the model's 40 and is a row of this file.
    "proof.predict13b.c4096.bytes_per_position": lambda: chk(
        "13B proof bytes per proved position",
        v("proof.predict13b.c4096.total_bytes") / v("positions.predict13b.c4096"),
        "proof.predict13b.c4096.bytes_per_position", 0.001),
    "proof.predict13b.c4096.bytes_per_segment_mean": lambda: chk(
        "13B proof bytes per layer segment, mean",
        v("proof.predict13b.c4096.total_bytes") / v("e4.codellama_13b.c4096.layers"),
        "proof.predict13b.c4096.bytes_per_segment_mean", 0.001),
    # What the two measured shapes say about proof size against model width.
    # Both sides are one layer segment's serialized proof at S=512 against a
    # 4,096-token prefix, at the same five reductions and the same quantization;
    # the 8B side is the last token block's mean, because that is the block
    # whose prefix is the whole context and the only like-for-like one.
    "proof.predict13b.c4096.bytes_per_segment_over_8b": lambda: chk(
        "13B over 8B, serialized bytes per layer segment",
        v("proof.predict13b.c4096.bytes_per_segment_mean")
        / v("proof.headline.c4096.bytes_per_segment_mean_last_block"),
        "proof.predict13b.c4096.bytes_per_segment_over_8b", 0.001),
    # The three shares of the sequence's seconds, each of a scope that contains
    # the one above it: the commitment path inside the proof system's own call,
    # that call inside the summed per-segment wall-clock time, and the
    # commitment path inside the segment loop.  Every side is a `measured` row
    # of the same run, so none of these is a second measurement.  The fourth
    # ratio the item proposed, whole wall over loop, is not one of these: it is
    # above 1 because the loop pipelines, so it is no scope's share of another
    # and this file carries no row for it.
    **{f"share.headline.c{c}.{name}": (lambda c=c, name=name, a=a, b=b: chk(
        f"c{c} headline {name.replace('_', ' ')}",
        v(f"secs.headline.c{c}.{a}") / v(f"secs.headline.c{c}.{b}"),
        f"share.headline.c{c}.{name}", 0.001))
       for c in (4096, 16384)
       for name, a, b in (("commit_of_stwo_total", "commit", "stwo_total"),
                          ("stwo_total_of_whole_wall", "stwo_total", "whole_wall"),
                          ("commit_of_loop", "commit", "loop"))},
    # The verifier's side over the same two divisors.  Its seconds are the
    # host's cores and the proving seconds beside them are the card's, which is
    # why no row here is a ratio of the two.
    **{f"verify.headline.c{c}.secs_per_segment_mean": (lambda c=c: chk(
        f"c{c} headline verifier seconds per segment, mean",
        v(f"verify.headline.c{c}.secs_total") / v(f"segments.headline.c{c}"),
        f"verify.headline.c{c}.secs_per_segment_mean", 0.001))
       for c in (4096, 16384)},
    **{f"verify.headline.c{c}.secs_per_position": (lambda c=c: chk(
        f"c{c} headline verifier seconds per proved position",
        v(f"verify.headline.c{c}.secs_total") / v(f"positions.headline.c{c}"),
        f"verify.headline.c{c}.secs_per_position", 0.001))
       for c in (4096, 16384)},
    # The same sequence checked on four cores of a machine with no card, one
    # segment at a time: the measured median times the segment count, and not a
    # second measurement of anything.
    "verify.consumer.c16384.secs_total_sequence": lambda: chk(
        "c16384 sequence checked on four cores, median times segments",
        v("verify.consumer.c16384.secs_per_segment_median")
        * v("segments.headline.c16384"),
        "verify.consumer.c16384.secs_total_sequence", 1e-6),
    # The ablation: what one reduction removes, as a fraction of the figure
    # without it.  The key tiles' reduction is measured against no reduction at
    # all; the other four extend it, so each is measured against it.
    **{f"gkr.ablation.{name}.leave_frac_{what}": (lambda name=name, what=what, base=base: chk(
        f"{name} removes, {what}",
        1 - v(f"{'cells' if what == 'cells' else 'secs'}.ablation.c4096.{name}"
              f"{'' if what == 'cells' else '.loop'}")
          / v(f"{'cells' if what == 'cells' else 'secs'}.ablation.c4096.{base}"
              f"{'' if what == 'cells' else '.loop'}"),
        f"gkr.ablation.{name}.leave_frac_{what}", 0.002))
       for what in ("cells", "loop")
       for name, base in (("bands", "none"), ("bands_dequant", "bands"),
                          ("bands_residual_stream", "bands"), ("bands_freivalds", "bands"),
                          ("bands_attnout", "bands"), ("all_five", "none"))},
    # The whole-sequence control against the headline row: what the five
    # reductions remove over a sequence, as a fraction of the count without
    # them.  Only the cells are a pair -- this control's loop proves one segment
    # at a time and the headline row's overlaps two -- so there is no
    # leave_frac_loop here, which the ablation has because its seven
    # configurations were all proved the same way.
    "gkr.control.c4096.leave_frac_cells": lambda: chk(
        "the five reductions remove, whole sequence, cells",
        1 - v("cells.headline.c4096.fresh") / v("cells.control.c4096.fresh"),
        "gkr.control.c4096.leave_frac_cells", 0.002),
    **{f"pos_s.headline.c4096.{s}": (lambda s=s: chk(
        f"c4096 headline positions/s, {s.replace('_', ' ')}",
        v("positions.headline.c4096") / v(f"secs.headline.c4096.{s}"),
        f"pos_s.headline.c4096.{s}", 0.001))
       for s in ("whole_wall", "loop")},
    # What one proved position costs (docs/decisions): the seconds it took and
    # the dollars those seconds are worth at the card's reference rate.  Both
    # sides of every division are entries of this file, so nothing here is a
    # second measurement; the rate is `external` and names its source.
    **{f"secs_per_position.headline.c{c}.{s}": (lambda c=c, s=s: chk(
        f"c{c} headline seconds per proved position, {s.replace('_', ' ')}",
        v(f"secs.headline.c{c}.{s}") / v(f"positions.headline.c{c}"),
        f"secs_per_position.headline.c{c}.{s}", 0.001))
       for c in (4096, 16384) for s in ("whole_wall", "loop")},
    **{f"usd_per_1k_positions.headline.c{c}.{s}": (lambda c=c, s=s: chk(
        f"c{c} headline USD per 1,000 proved positions, {s.replace('_', ' ')}",
        v(f"secs.headline.c{c}.{s}") / v(f"positions.headline.c{c}")
        * v("cost.h100_reference_usd_per_hour") / 3600 * 1000,
        f"usd_per_1k_positions.headline.c{c}.{s}", 0.001))
       for c in (4096, 16384) for s in ("whole_wall", "loop")},
    # The same seconds over the plan instead of over the positions: what one
    # segment of the sequence cost on average, and what one of the model's 32
    # layers cost over the whole sequence.  A segment's own cost grows with the
    # prefix its token block reads, so neither row is any one segment's time.
    # The layer row divides by the layer count and not by a constant of this
    # file: 32 is the model's, the audit reads it off each run's own config and
    # refuses a run that reports another, and the two output head segments are
    # in the seconds and are not a layer.
    **{f"secs_per_segment.headline.c{c}.{s}": (lambda c=c, s=s: chk(
        f"c{c} headline seconds per segment, {s.replace('_', ' ')}",
        v(f"secs.headline.c{c}.{s}") / v(f"segments.headline.c{c}"),
        f"secs_per_segment.headline.c{c}.{s}", 0.001))
       for c in (4096, 16384) for s in ("whole_wall", "loop")},
    **{f"secs_per_layer.headline.c{c}.loop": (lambda c=c: chk(
        f"c{c} headline seconds per layer, loop",
        v(f"secs.headline.c{c}.loop") / 32,
        f"secs_per_layer.headline.c{c}.loop", 0.001))
       for c in (4096, 16384)},
    # The same seconds over the layer segments alone, which is the plan's
    # segments less its two output head segments.  A head segment sits at the
    # layer coordinate past the last layer, proves no attention and commits no
    # boundary tree for the keys and values, so a claim priced on a fraction of
    # the layers divides by this and a claim priced on a fraction of the proofs
    # divides by secs_per_segment.  Both recorded plans have two heads, one over
    # the last prompt block and one over the generated block, and the audit
    # counts them off each run's own plan.
    **{f"secs_per_layer_segment.headline.c{c}.{s}": (lambda c=c, s=s: chk(
        f"c{c} headline seconds per layer segment, {s.replace('_', ' ')}",
        v(f"secs.headline.c{c}.{s}") / (v(f"segments.headline.c{c}") - 2),
        f"secs_per_layer_segment.headline.c{c}.{s}", 0.001))
       for c in (4096, 16384) for s in ("whole_wall", "loop")},
    # The two cell inputs that are exact counts on top of one LogUp lookup, not
    # measurements of their own: the range check on a committed int8 activation,
    # which is half an arity-2 lookup into the byte-pair table, and one bf16
    # unary operation, which commits its output as one bf16 value and pays one
    # lookup.  Both index the recorded marginal at the batch every use side
    # finalizes with, which is the batch the cost model charges.
    "model_constants.int8_range_cells_per_activation": lambda: chk(
        "int8 range check per activation",
        v("model_constants.logup_marginal_cells_per_lookup")["2"] / 2,
        "model_constants.int8_range_cells_per_activation", 0.001),
    "model_constants.residual_stream_unary_cells_per_op": lambda: chk(
        "bf16 unary operation",
        2 + v("model_constants.logup_marginal_cells_per_lookup")["2"],
        "model_constants.residual_stream_unary_cells_per_op", 0.001),
    # The cost model's commitment-rate input: committed cells over the seconds
    # the commitment path took, both measured on the same proof.
    "rate.microbench.commit": lambda: chk(
        "microbench commitment rate",
        v("cells.microbench.compose_fresh") / v("secs.microbench.compose_commit") / 1e6,
        "rate.microbench.commit", 0.001),
    # Cold: the extraction the proofs read plus the proving scope, which is what
    # the sequence costs on a host that holds no witness dump yet.  At context
    # 16,384 the run extracted twice and the cold row counts the prove sweep
    # alone: the survey sweep's dumps are read by the kernel emitters and by no
    # proof, and emitting kernels is not in the cold figure either.
    **{f"secs.headline.c{ctx}.cold_{s}": (lambda ctx=ctx, s=s, ex=ex: chk(
        f"c{ctx} headline cold {s.replace('_', ' ')} seconds",
        v(ex) + v(f"secs.headline.c{ctx}.{s}"),
        f"secs.headline.c{ctx}.cold_{s}", 0.001))
       for ctx, ex in ((4096, "secs.headline.c4096.extract"),
                       (16384, "secs.headline.c16384.extract_prove"))
       for s in ("whole_wall", "loop")},
    **{f"secs_per_position.headline.c{ctx}.cold_{s}": (lambda ctx=ctx, s=s: chk(
        f"c{ctx} headline seconds per proved position, cold {s.replace('_', ' ')}",
        v(f"secs.headline.c{ctx}.cold_{s}") / v(f"positions.headline.c{ctx}"),
        f"secs_per_position.headline.c{ctx}.cold_{s}", 0.001))
       for ctx in (4096, 16384) for s in ("whole_wall", "loop")},
    **{f"usd_per_1k_positions.headline.c{ctx}.cold_{s}": (lambda ctx=ctx, s=s: chk(
        f"c{ctx} headline USD per 1,000 proved positions, cold {s.replace('_', ' ')}",
        v(f"secs.headline.c{ctx}.cold_{s}") / v(f"positions.headline.c{ctx}")
        * v("cost.h100_reference_usd_per_hour") / 3600 * 1000,
        f"usd_per_1k_positions.headline.c{ctx}.cold_{s}", 0.001))
       for ctx in (4096, 16384) for s in ("whole_wall", "loop")},
    # What the composed prover builds each gadget at, and what one token block's
    # 32 layer segments cost per decoded token: cells over a count the same
    # segment reports, on the two headline runs.  Nothing is rounded, here or in
    # the recorded value: the reader divides.
    **{k: (lambda k=k, w=what: chk(w, composed()[k], k, 1e-9))
       for k, what in (
           ("model_constants.dequant_chain_composed_cells_per_acc",
            "composed dequantization, per accumulator"),
           ("model_constants.requant_composed_cells_per_value",
            "composed requantization, per value"),
           ("model_constants.quant_composed_cells_per_value",
            "composed q and k quantization, per value"),
           ("model_constants.weight_freivalds_composed_cells_per_weight",
            "composed Freivalds check, per weight"),
           ("model_constants.attnout_composed_cells_per_acc",
            "composed attention-output fold, per accumulator"),
           ("model_constants.residual_stream_composed_mul_cells_per_op",
            "composed bf16 multiply, per operation"),
           ("model_constants.residual_stream_composed_add_cells_per_op",
            "composed bf16 add, per operation"),
           ("model_constants.residual_stream_composed_swiglu_cells_per_op",
            "composed SwiGLU channel, per operation"),
           ("cells_per_position.headline.c4096.fresh_layers_block",
            "c4096 one block's layer segments, per position"),
           ("cells_per_position.headline.c16384.fresh_layers_block",
            "c16384 one block's layer segments, per position"))},
    # One token block at a block length that is not the recorded 512: the
    # counted side, the measured side over it, and the four per-segment rows.
    # The counted row is read out of the run that counted it, the way the 14B's
    # registered figure is; the other two divide entries of this file.
    **{f"cells.block.c4096.s{s}.exact_predicted": (lambda s=s: chk(
        f"S = {s} one block, the trace layout counted at that block length",
        block_counted(s), f"cells.block.c4096.s{s}.exact_predicted", 1e-9))
       for s in BLOCK_LENGTHS},
    **{f"cells.block.c4096.s{s}.rho": (lambda s=s: chk(
        f"S = {s} measured cells over counted",
        v(f"cells.block.c4096.s{s}.fresh") / v(f"cells.block.c4096.s{s}.exact_predicted"),
        f"cells.block.c4096.s{s}.rho", 1e-9))
       for s in BLOCK_LENGTHS},
    **{f"secs_per_segment.block.c4096.s{s}.{sc}": (lambda s=s, sc=sc: chk(
        f"S = {s} seconds a segment, {sc.replace('_', ' ')}",
        v(f"secs.block.c4096.s{s}.{sc}") / v(f"segments.block.c4096.s{s}"),
        f"secs_per_segment.block.c4096.s{s}.{sc}", 0.001))
       for s in BLOCK_LENGTHS for sc in BLOCK_SCOPES},
    # What the port is worth on one segment, per phase: the host backend's
    # seconds over the device backend's, on the one proof both backends made.
    # Both sides of each division are `measured` rows of the same run.
    "port.reference.c16384.trace_speedup": lambda: chk(
        "reference segment, trace generation, host over device",
        _speedups()[0], "port.reference.c16384.trace_speedup", 1e-6),
    "port.reference.c16384.interaction_speedup": lambda: chk(
        "reference segment, interaction generation, host over device",
        _speedups()[1], "port.reference.c16384.interaction_speedup", 1e-6),
    # Each phase's share of the loop it was measured in, for the loop with the
    # generated constraint kernels in place and for the loop with every one of
    # them declining to the host.  Both sides are `measured` rows of the same
    # run, and the twelve shares of one loop add to 1 because the twelve seconds
    # add to its own -- which the run refuses to publish otherwise.
    **{f"share.phase.c4096.{lp}.{ph}": (lambda lp=lp, ph=ph: chk(
        f"{ph} share of the c4096 {lp} loop",
        v(f"secs.phase.c4096.{lp}.{ph}") / v(f"secs.phase.c4096.{lp}.loop"),
        f"share.phase.c4096.{lp}.{ph}", 1e-6))
       for lp in ("kernels", "nokernels") for ph in PHASE_SPLIT},
    # What the generated constraint kernels are worth on that sample, in seconds
    # of the loop.  Both sides are `measured` loops of the same run over the same
    # 32 segments, proved to the same digests, so their difference is the kernels.
    "secs.phase.c4096.kernels_bought": lambda: chk(
        "c4096 sample loop without the generated kernels less with them",
        v("secs.phase.c4096.nokernels.loop") - v("secs.phase.c4096.kernels.loop"),
        "secs.phase.c4096.kernels_bought", 1e-6),
}

# -- the two projections' own arithmetic ---------------------------------------
# A `projected` row is not recomputed here in general: the cost model's rows are
# priced inside its own run and this file holds only their inputs.  The rows
# below are projections whose whole arithmetic is entries of this file -- an
# assumption is one of the entries -- so they are recomputed exactly as a
# `derived` row is, and PROJECTED holds one line each.  A projected row with no
# line there is left alone; only its `inputs` are checked.
def _speedups():
    """What the port already did to one segment, per phase: the host backend's
    seconds over the device backend's, on the same proof."""
    return (v("secs.reference.c16384.simd_trace") / v("secs.reference.c16384.cuda_trace"),
            v("secs.reference.c16384.simd_interaction")
            / v("secs.reference.c16384.cuda_interaction"))


def _loop_host_8x():
    """The figure's own number: the proof system as measured, the rest of the
    loop divided by the one factor the figure assumes."""
    stwo = v("secs.headline.c4096.stwo_total")
    return stwo + (v("secs.headline.c4096.loop") - stwo) / v("assumption.loop_port.host_speedup")


def _loop_ported_rates():
    """The same loop with each phase divided by the factor the reference segment
    measured for that phase.  The proof system and the dump read have no factor
    and are carried at their own seconds, and so is the share of the loop the
    assumed split does not name."""
    trace = v("port.reference.c16384.trace_speedup")
    interaction = v("port.reference.c16384.interaction_speedup")
    f = {p: v(f"assumption.loop_split.c4096.{p}_frac")
         for p in ("interaction", "trace", "stwo", "read")}
    return v("secs.headline.c4096.loop") * (
        f["interaction"] / interaction + f["trace"] / trace
        + f["stwo"] + f["read"] + (1 - sum(f.values())))


def _mem_line():
    """The two headline peaks as a line in the context: MiB a position of prefix,
    and the peak the line puts at context 0.  The contexts are the two entries'
    own `context` fields."""
    c = load()["constants"]
    lo, hi = c["mem.headline.c4096.peak_mib"], c["mem.headline.c16384.peak_mib"]
    slope = (hi["value"] - lo["value"]) / (hi["context"] - lo["context"])
    return slope, lo["value"] - slope * lo["context"]


def _mem_at(ctx):
    slope, at_zero = _mem_line()
    return at_zero + slope * ctx


def _context_at(mib):
    slope, at_zero = _mem_line()
    return (mib - at_zero) / slope


PROJECTED = {
    "secs.projected.c4096.loop_host_8x": lambda: chk(
        "c4096 loop, every host second 8x faster", _loop_host_8x(),
        "secs.projected.c4096.loop_host_8x", 1e-5),
    "secs.projected.c4096.loop_ported_rates": lambda: chk(
        "c4096 loop at the ported phases' measured factors", _loop_ported_rates(),
        "secs.projected.c4096.loop_ported_rates", 1e-5),
    **{f"mem.projected.c{ctx}.peak_mib": (lambda ctx=ctx: chk(
        f"peak MiB at context {ctx:,}, on the two headline peaks' line",
        _mem_at(load()["constants"][f"mem.projected.c{ctx}.peak_mib"]["context"]),
        f"mem.projected.c{ctx}.peak_mib", 1e-6))
       for ctx in (32768, 131072)},
    "mem.projected.context_at_card_limit": lambda: chk(
        "context where the line reaches the card's memory",
        _context_at(v("hardware.h100.memory_total_mib")),
        "mem.projected.context_at_card_limit", 1e-6),
}


URL = re.compile(r"https?://\S+")


def structure():
    doc = load()
    c = doc["constants"]
    print(f"{len(c)} constants, {len(doc['discrepancies'])} discrepancies\n")
    for k, e in c.items():
        missing = [f for f in FIELDS if f not in e]
        if missing:
            fails.append(f"{k}: missing {missing}")
            continue
        if e["grade"] not in GRADES:
            fails.append(f"{k}: grade {e['grade']!r} is not one of {GRADES}")
        if e["value"] is None and not e["note"]:
            fails.append(f"{k}: null with no note")
        if isinstance(e["value"], dict):
            # An object-valued entry is one number per key -- the LogUp marginal
            # is one figure per lookup batch size -- and its readers index it.  A
            # member that is not a number would fail inside the cost model or in
            # a `derived` line below rather than here.
            bad = [m for m, n in e["value"].items() if not isinstance(n, (int, float))]
            if not e["value"]:
                fails.append(f"{k}: object-valued and empty; an object-valued entry is one "
                             f"number per key")
            elif bad:
                fails.append(f"{k}: object-valued, and {bad} carries no number; an "
                             f"object-valued entry is one number per key")
        if e["grade"] == "measured":
            run, art = e.get("run"), e.get("artifact")
            if not run or not art:
                fails.append(f"{k}: measured without run and artifact")
            else:
                d = ROOT / "runs" / run
                if not (d / "manifest.json").exists():
                    fails.append(f"{k}: run {run} has no manifest")
                if not (d / art).exists():
                    fails.append(f"{k}: artifact runs/{run}/{art} does not exist")
        elif e["grade"] == "external" and not URL.search(e["note"]):
            fails.append(f"{k}: external without a URL in its note")
        elif e["grade"] == "asserted" and len(e["note"]) < 20:
            fails.append(f"{k}: asserted without a reason")
        elif e["grade"] == "derived" and k not in DERIVED:
            fails.append(f"{k}: derived but check.py does not recompute it")
        elif e["grade"] == "projected":
            # A projection is only readable if the entries behind it can be found:
            # `inputs` names them, and a name that is not a key of this file names
            # nothing.  The arithmetic itself is the model's and is in the run's
            # artifact; what is checked here is that its inputs are entries.
            if not e.get("inputs"):
                fails.append(f"{k}: projected without `inputs` naming the model's constants")
            else:
                absent = [i for i in e["inputs"] if i not in c]
                if absent:
                    fails.append(f"{k}: projected, and its `inputs` name {absent}, "
                                 f"which this file does not hold")
        if "source" in e:
            fails.append(f"{k}: free-text `source` field; use run/artifact or the note")


def main(argv):
    structure()
    for k in sorted(DERIVED):
        if k in load()["constants"]:
            DERIVED[k]()
    for k in sorted(PROJECTED):
        if k in load()["constants"]:
            PROJECTED[k]()
    import audit  # noqa: E402
    audit.run(fails)
    if "--strict" in argv and load()["discrepancies"]:
        fails.append(f"{len(load()['discrepancies'])} open discrepancies; a tag needs none")
    print()
    if fails:
        print("FAILURES:", *fails, sep="\n  ")
        return 1
    print("all consistent.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
