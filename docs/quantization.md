# The quantization configuration

The harness runs the model in a fixed integer and bf16 arithmetic and writes
the witness the prover constrains, so the quality numbers describe exactly
the arithmetic that is proved. The configurations are named presets in
`harness/witness/common.py` of `zk-prover`; the numbers that will back this
page are the constants named in parentheses, none of which exists yet in
this repository.

## What the paper reports: `y-delay-vw12`

- Linear layers: activations quantized to int8 per token with a dynamic
  scale, weights to int8 per output channel; the accumulation is exact in
  the field.
- Dequantization after the seven layer matmuls: a chain of three
  correctly-rounded bf16 steps, rounding half to even, so a general bf16
  scale can be proved; the output head uses power-of-two scales instead,
  which collapse the chain to one rounding.
- Nonlinear operations in bf16, with the normalisation's reduction as a
  balanced tree in bf16.
- Attention scores as an integer softmax: queries at 12 bits, keys at 11,
  power-of-two attention scales with one query scale per head, a 9-bit
  softmax numerator; the exponential is a lookup table keyed by the bf16
  input.
- The attention output rounded straight to an integer with a power-of-two
  output scale, at 12 bits rather than 8, so the output projection consumes
  a wider value and one rounding is saved.
- The value projection's requantization delayed to its consumer, which
  removes the chain's roundings on that path; only the key/value cache sits
  between the two.

Its perplexity against the fp32 model (`quality.8b.ppl_y_delay_vw12_delta_pct`)
and its scores on the three tasks (`quality.8b.gpqa_d_y_delay_vw12`,
`quality.8b.mmlu_pro_y_delay_vw12`, `quality.8b.ifeval_prompt_strict_y_delay_vw12`)
are measured against a byte-identical fp32 control on the same items; each
task carries its own paired standard error, since the item counts differ
(`quality.8b.gpqa_d_paired_se_vs_fp32_y_delay_vw12`,
`quality.8b.mmlu_pro_paired_se_vs_fp32_y_delay_vw12`,
`quality.8b.ifeval_prompt_strict_paired_se_vs_fp32_y_delay_vw12`).

## Variants measured beside it

- `fp32`: the reference forward pass.
- `dynamic-int8`: dynamic int8 linear layers, bf16 nonlinear operations, no
  integer softmax; the published system's configuration as far as it is known.
- `static`: static per-tensor W8A8 with a calibrated activation scale, the
  weakest int8 there is (`quality.8b.ppl_static_w8a8`).
- `w8a16`: weight-only per-channel int8 with float activations, the int8
  variant a reader would actually deploy (`quality.8b.ppl_w8a16`).
- `b6-design-p2o`, `b10-design`, `b10-residual-stream`, `b10-final`: the sequence of
  configurations that led to the reported one, each adding one choice; the
  perplexity of each is a measured row (`quality.8b.ppl_b10_final`).
- `y-attnout-w10`, `-w11`, `-w12`, `-w16` and `y-delay-v`, `y-delay-up`,
  `y-delay-all`: one change each on `b10-final`, the probes from which the
  reported variant was composed.

A second, smaller model (`quality.gemma270m.*`) checks that the configuration
transfers across architectures, including a sliding-window attention.
