# JUDGE-GLM-FAILS-ON-PREAMBLE-NOT-ON-THE-MODEL-01

## What was measured (2026-09-14, by the lead, reproducible)

The live comparison lane reported: **GLM produced no real judge envelope in 13/13 requests**, and the
judge default was correctly flipped back to haiku on that evidence. The conclusion "GLM does not
answer" is WRONG, and the reason it looked true is this:

The judge invokes `glm-coder.sh run … --out <file>` and then reads that file. The file does not
start with the envelope. It starts with warning lines the CLI prints into it:

```text
[claude-code:unrecognized_model] {"model":"glm-5.3-flash","query_source":"generate_session_title"}
⚠ claude.ai connectors are disabled because ANTHROPIC_API_KEY or another auth source is set …
[claude-code:unrecognized_model] {"model":"glm-5.3","query_source":"sdk"}
{"duration_api_ms":20055, … }
```

and it ENDS with a completely successful result:

```text
"canonicalModel":"glm-5.3","is_error":false,"subtype":"success","result":"{\"ok\":true}",
"num_turns":1,"ttft_ms":13342,"duration_ms":14797
```

GLM answered the prompt exactly and in ~15s. Independently confirmed against the endpoint itself:
every candidate id — `glm-5.3`, `glm-5.3-flash`, `glm-5.2`, `glm-4.6`, `glm-4.5`, `glm-4.5-air` —
returns HTTP 200 from `https://api.z.ai/api/anthropic/v1/messages`. The token is valid, the model id
is served, the transport works. `[claude-code:unrecognized_model]` is a **cosmetic CLI warning**, not
an API error — note `is_error:false` in the same file.

So the defect is: **the judge's reader assumes the output file begins with its envelope.** Three
noise lines make a strict parse fail, the judge falls back to its code-only estimator, and because
the judge discards transport stderr (`>/dev/null 2>/dev/null`) the failure is silent and looks
identical to "the provider returned nothing".

## What to build

1. **Parse the envelope out of a noisy file.** Read the LAST complete JSON object (or select by a
   field that identifies the envelope), never "the whole file must be JSON". Cover, with a test each:
   warning lines before the JSON; a `⚠`-prefixed non-ASCII line; a warning line that is itself valid
   JSON (the `unrecognized_model` lines ARE JSON objects — a naive "find the first `{`" fix would
   grab one and is not acceptable); an empty file; a file with no JSON at all.
2. **A silent fallback must say why.** When the judge falls back it must record a reason
   (`parse_failed` / `transport_rc=<n>` / `empty_output` / `timeout`), visible in the envelope it
   returns. Today `estimate_source: fallback` is indistinguishable across all four causes, which is
   precisely why 13 identical failures read as a provider verdict.
3. **Stop discarding the transport's stderr unconditionally.** Keep it (a temp file is fine) and
   surface its tail in the fallback reason. Redaction already exists in `glm-coder.sh`
   (`redact_stream` / `ZAI_AUTH_TOKEN`) — use it; never print a token.
4. **Then re-run the comparison.** The harness already exists:
   `plugins/leadv2/scripts/leadv2-judge-arm-live-comparison.sh`, with
   `docs/handoff/JUDGE-ARM-LIVE-COMPARISON/results.jsonl` as the prior (all-fallback) baseline.
   Re-run it and report GLM's real verdicts against haiku's.

   Carry the other half of that lane's finding into the re-run: **haiku is self-inconsistent** —
   same mission, run 1 `standard`, run 2 `complex`; `subsystems_touched` 3 vs 8; complexity
   self-consistency 1/3. Report GLM's own self-consistency the same way. If GLM is MORE consistent
   than haiku, say so plainly — that changes which arm should be default for reasons beyond price.
5. **Set the default to whatever the re-run supports**, and name the number in the report. Do not
   assume the answer is GLM.

## Method — binding

- The negative control for item 1 is the real file: keep a copy of a noisy `--out` capture as a
  fixture and assert the parser extracts the envelope from it. A test that only feeds clean JSON
  proves nothing about the defect being fixed.
- **A silence must be distinguishable from a verdict.** That is the general lesson here and it is
  the acceptance bar for item 2, not a nicety.
- Re-check what looks obviously true: today a confident "13/13 the provider returned nothing" was an
  artefact of the reader, and before that a confident "zero gate disagreements" was an artefact of
  reading the journal instead of the launcher's stderr. Assume your own measurement has a surface
  problem until you have shown it does not.

## Acceptance

1. The judge returns a real GLM envelope on a live call — shown, with `judge_arm: glm` present.
2. Each of the four fallback causes produces a distinct, recorded reason — demonstrated per cause.
3. The re-run comparison report: per-arm self-consistency, cross-arm disagreement count, failure
   rate, and the default that follows from them.
4. Still green: `test-leadv2-task-judge.sh`, `test-arbiter-decision-record-inputs.sh`,
   `test-reset-urgency.sh`, `test-arbiter-prices-by-provider.sh`.
5. New suites registered so `tests/run-all.sh --scope changed` SELECTS them; commit first, then show
   the selection output.

## Off limits

- `glm-coder.sh`'s transport env (`ANTHROPIC_BASE_URL` / `AUTH_TOKEN` / `DISABLE_MODEL_AVAILABILITY_CHECK`)
  — measured working, both its `run` and background paths set it identically. The bug is downstream
  of the transport, in the reader.
- The judge's separation of concerns: it carries ZERO arm/model/provider/quota vocabulary.
- `reset_urgency`, `provider_cost`, decision-record schema v2 — landed, not yours.
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.
