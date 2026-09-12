# The gap between the statement proved and a request as served

The prover proves one end-to-end statement about one request: every position of
a prompt and of a 512-token greedy continuation, from the embedding up through
every layer and through the output head, under one fixed quantization
configuration, with the residual stream bound between layers and the keys and
values bound between token blocks
(`docs/decisions/2026-09-03-end-to-end-statements-only.md`; the prover's
`prover/README.md` in `zk-prover` says which gadget binds which edge and which
switch gives one up).

A request a provider serves is not that. This page states the difference row by
row: what is proved today, what a provider does instead, and what closing the
row would take. It closes nothing, and where a row names a design it names it in
one sentence. A number appears only where `constants.json` holds one, with the
key beside it.

| row | tracked by |
|---|---|
| Arithmetic | no issue |
| Decoding | none open; `zk-prover` #179 closed by the owner |
| Determinism | `zk-prover` #126 |
| Tokenization and the chat template | no issue |
| Batching and the serving stack | `zk-prover` #12 for the prover's ceiling; nothing for a batch dimension |
| Binding to the traffic record | no issue |
| The architecture | `zk-prover` #174 for the bias site; nothing for the rest |
| Tool calls, system prompts, multi-turn | no issue |

## Arithmetic

**Proved today.** The fixed quantization configuration `y-delay-vw12`, which
`docs/quantization.md` states in full: int8 activations per token with a dynamic
scale, int8 weights per output channel, accumulation exact in the field,
dequantization as correctly-rounded bf16 steps, the nonlinear operations in
bf16, and an integer softmax with queries at 12 bits and keys at 11. The
statement is about that arithmetic and about no other.

**A provider instead.** Serves bf16, or fp8, on whichever kernels its stack
picks. The measured stand-in for a published system is the `dynamic-int8`
variant (`quality.8b.ppl_dynamic_int8_delta_pct`).

**What the difference costs.** Against a byte-identical fp32 control on the same
items: perplexity `quality.8b.ppl_y_delay_vw12_delta_pct`, +6.96 per cent, with
the paired standard error in `quality.8b.ppl_y_delay_vw12_se_nats`; the paired
task differences `quality.8b.mmlu_pro_paired_delta_y_delay_vw12` and
`quality.8b.gpqa_d_paired_delta_y_delay_vw12` are both 0.0, and
`quality.8b.ifeval_prompt_strict_paired_delta_y_delay_vw12` is -0.006. On a
second, smaller architecture the same configuration costs
`quality.gemma270m.ppl_y_delay_vw12_delta_pct`, +14.6 per cent.

**To close it.** A statement over bf16 matmuls and a bf16 softmax, in place of
the int8 product and the integer softmax. What that would cost in committed
cells is in no constant and in no count: it has not been counted, and no figure
in this repository stands in for it.

**Tracked by.** No issue.

## Decoding

**Proved today.** Greedy decoding. The head segment proves that the emitted
token is the lowest-indexed maximum of the logits computed for the position
before it, which is the rule the model decodes by; `--unsound-argmax-lax`
weakens that to any maximum and marks the run a control. The decode a witness is
extracted from does not stop at an end-of-text: `harness/witness/gen_ids.py`
records a stop and passes it through, so the statement is 512 decoded tokens
whatever the model would have done.

**A provider instead.** Samples from the softmax under a temperature and a
top-p, and stops at the end-of-sequence token.

**To close it.** Either a statement over the softmax of the whole vocabulary
with a seed committed before decoding, or VerInf's bound on the information the
committed model does not explain (`verinf.maverick.bound_bits_per_token`, 0.88
bits per token), which bounds information and does not prove which token was
drawn.

**Tracked by.** `zk-prover` #179 asked for both designs, costed; the owner
closed it, because the post names the two ways and leaves them open. No open
issue.

## Determinism

**Proved today.** One decode. The ids of that decode are an input to every
segment of the sequence, and the proof binds the tokens to the logits computed
for them.

**A provider instead.** Reruns the same prompt. `zk-prover` #126 records three
repetitions of one greedy point on the `hf` backend at context 4,096 -- same
process, same weights, same prompt, sampling off, no early stop -- whose
generated-token digests do not all agree: the first and third do, the second
does not.

So the proof is honest about the decode it was made from and says nothing about
whether the model would produce that decode again: a verifier who checked it by
re-running the model would be comparing against an output the serving path does
not reproduce.

**To close it.** A serving path whose reductions are pinned, so that a rerun is
a check. #126 is neither diagnosed nor fixed, and it lists what to rule out
first.

**Tracked by.** `zk-prover` #126, open, labelled `defect`.

## Tokenization and the chat template

**Proved today.** The statement's public input is a sequence of token ids. The
verifier is given them -- `boundary-grid --verify` demands `--prompt` as it
demands the calibration manifest -- and the layer-0 embedding gadget (edge 15)
proves that the residual stream the first layer reads is the committed embedding
matrix's row for the committed id. The ids the measured runs prove are a slice
of a corpus token array, cut by `harness/witness/gen_ids.py --prefix/--offset`;
no chat template is applied to them.

**A provider instead.** Receives text: a system prompt, a user turn, sometimes
tool definitions. It applies a tokenizer and a chat template to get ids, and
detokenizes ids to get the text it returns.

**To close it.** The tokenizer and the template inside the statement, or a
commitment to both with the check left outside the proof. Neither exists. Both
ends of a request -- the text in and the text out -- are outside every proof
this repository records.

**Tracked by.** No issue.

## Batching and the serving stack

**Proved today.** One request, one segment at a time: 512 output positions
against a committed key prefix, 32 layer segments to a token block, and an
output head segment over the last prompt block and the generated one
(`segments.headline.c16384` over `positions.headline.c16384`). There is no batch
index in the statement.

**A provider instead.** Batches requests and paginates the key/value cache
across them. The baseline campaign records what that is worth, per request, at
batch 1 through 16 on both backends: `pos_s.unproved.vllm.c4096.b1.end_to_end`
against `pos_s.unproved.vllm.c4096.b16.end_to_end`, where the host's own figure
is sixteen times the second.

**To close it.** A batch index in the statement, or a per-request proof taken
while the server batches, under which the other requests' rows of a batched
matmul are in the witness and not in the statement.

**Tracked by.** `zk-prover` #12 tracks the prover's own ceiling, which is
host-side witness generation. No issue for a batch index or for the paginated
cache.

## Binding to the traffic record

**Proved today.** Nothing. A proof names its prompt ids, the model root it was
made against and the shape root the verifier derives; no proof here names a
request, a client, a time or a served response. What a verifier learns is that
these ids produce these tokens under this model commitment, not that this is
what anybody was served.

**A provider instead.** Serves over an API, records the request and the
response, and can hand a client a transcript of both.

**To close it.** An anchor that commits the served transcript and a proof that
the ids it proves are that transcript's ids. Issue #117 names VerInf's
transcript anchor as the precedent; nothing in this repository records what that
anchor commits to, and the `verinf.*` constants are that work's measurements and
not its anchor.

**Tracked by.** No issue. `zk-prover` #179 put this row out of its scope by
name.

## The architecture

**Proved today.** Dense Llama-shaped decoder blocks: seven matmuls to a layer,
RMS norms, SwiGLU, a rotation, grouped-query attention, and a causal mask on the
diagonal block over a prefix whose key tiles carry no mask columns at all. The
shape is public, by construction: the verifier rebuilds the shape tree from the
statement's own `params` and the per-layer calibration the model manifest
publishes, so layer count, head counts, widths and context are things the
verifier knows rather than things the proof hides.

**A provider instead.** Serves models the statement cannot state. A projection
bias is the measured case: Qwen2.5 gives `q_proj`, `k_proj` and `v_proj` one,
the dequant component states the product and nothing else, and the extractor
refuses such a dump by name (`zk-prover` #174, with #172 the rejection it
measured on layer 0 of the 14B witness). Beside it: sliding-window and
alternating local-global attention, QK-norm, a logit softcap, and mixtures of
experts. Providers also do not publish the architecture at all, which the
statement's public shape does not allow for.

**To close it.** A component for each site: a per-channel add between the
dequantization and the rotation, which is #174's list of four sites; mask
columns on the prefix key tiles, so that a key outside a window can be excluded;
a norm between the projection and the rotation. The quantization configuration
was checked on a sliding-window model in the harness
(`quality.gemma270m.ppl_y_delay_vw12_delta_pct`), and the cost model prices a
mixture-of-experts shape, so both exist as arithmetic and as a projection; what
neither has is a statement.

**Tracked by.** `zk-prover` #174 for the bias site. No issue for the window, for
QK-norm, for the softcap, for mixtures of experts, or for hiding the
architecture.

## Tool calls, system prompts, multi-turn

**Proved today.** One prompt and one continuation. Within a sequence, a
generated position's id is bound to the argmax proved for the position before
it, which is why a headline run proves an output head segment over the last
prompt block as well as over the generated one. Across turns there is no such
binding: each turn is a new prompt, proved by itself.

**A provider instead.** Runs a conversation. A system prompt the user never
sees, several turns, a key/value cache reused between them, and tool calls whose
results the server writes into the context -- content that the model did not
produce and that the next turn is conditioned on.

**To close it.** A binding from one proof's emitted ids into the next proof's
prompt ids, and a statement for the content the server inserts between the two.
Neither exists; a multi-turn session is as many unrelated proofs as it has
turns.

**Tracked by.** No issue.
