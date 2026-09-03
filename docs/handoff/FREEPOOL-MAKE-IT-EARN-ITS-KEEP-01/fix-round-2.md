# FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01 — round 2: the ranked models are dead upstream

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01`

LANE_WRITES: plugins/leadv2/config/freepool-arm.yaml,plugins/leadv2/scripts/lib/leadv2-freepool-model-select.sh,plugins/leadv2/scripts/freepool-coder.sh,plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh,plugins/leadv2/scripts/tests/test-worker-output-gate.sh,plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh,tests/run-all.sh,docs/handoff/FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01/

Round 1 is committed as `78ae2a5` and it was good work. **You were right not to build a second
model selector** — `lib/leadv2-freepool-model-select.sh` already exists, is data-driven from
`config/freepool-arm.yaml`, and is genuinely wired into `freepool-coder.sh:406` via
`--model "${_model}"`. Refusing to create a drifting duplicate was the correct call. The output
gate and the arbiter-exclusion fix both landed with RED logs.

That means the mission's premise about model choice was wrong, and the lead has now measured what
is actually happening. This is the real defect.

## Measured 2026-08-30 13:30Z — probe every rank directly against the proxy

Running the selector to completion:

```
probe failed for "anthropic/nvidia_nim/moonshotai/kimi-k3", advancing rank
probe failed for "anthropic/nvidia_nim/deepseek-ai/deepseek-v4-pro-0813", advancing rank
probe failed for "anthropic/gemini/models/gemini-3.7-flash", advancing rank
chosen="anthropic/mistral/mistral-code-latest" alternatives=4 probe_ms=255
```

Direct `POST /v1/messages` against each, same proxy, same minute:

| rank | model | result |
|---|---|---|
| 1 | `nvidia_nim/deepseek-ai/deepseek-v4-pro-0813` | probe fails |
| 2 | `nvidia_nim/moonshotai/kimi-k3` | **empty response body** |
| 3 | `gemini/models/gemini-3.7-flash` | **empty response body** |
| 4 | `groq/openai/gpt-oss-120b` | HTTP 200, but `content: [{"text": " "}]` — **answers blank** |
| 5 | `mistral/mistral-code-latest` | HTTP 200, correct answer |
| — | `nvidia_nim/nvidia/nemotron-3-super-120b-a12b` | HTTP 200, answers |

So the arm is **not** pinned to a bad default — the selector works exactly as designed and every
one of its four preferred models is dead or degraded upstream. Every freepool task today ran on
rank 5, `mistral-code-latest`: the entry whose own `why:` calls it "broadest fallback before the
caller drops to paid Claude". That is why the output was unusable, and it is why this matters —
the founder's goal is free-arm throughput, and the arm is running on its last resort.

The proxy returning **HTTP 200 with an empty or blank body** is the trap: the transport looks
perfect (2654 requests, all 200) while three of five routes carry nothing.

## The work

### 1. A liveness probe that rejects an empty answer

The selector's probe currently accepts rank 4 (`gpt-oss-120b`), which returns a single space. A
probe that treats "200 OK" as success cannot distinguish a working model from a dead route. Make
the probe assert on **content**: a short deterministic prompt must come back with non-whitespace
text. Control: feed it a fixture that returns `{"content":[{"text":" "}]}` and confirm the probe
rejects it and advances rank.

### 2. Find out why the good routes are empty, and say so plainly

Are the upstream provider keys missing or expired in the proxy's own `.env`, is the route id wrong,
or is the free tier exhausted? The answer decides everything: if it is credentials, restoring them
is the single highest-value action available for the founder's cost goal, and it belongs in
`report.md` as an explicit recommendation with the evidence. Do not guess — probe and report.

### 3. Re-rank on measured evidence

Whatever survives the content-probe, rank it by a real bakeoff: one small shell-editing task per
surviving candidate, transcripts in `bakeoff/`, `bash -n`-clean output decides. `nemotron-3-super`
answers and is not currently in the rank list at all — include it in the bakeoff rather than
assuming it is bad.

### 4. Keep the output gate honest

The gate from round 1 is the reason a weak model is now survivable: it must reject any non-parsing
file from **any** arm. Re-run its RED control and confirm it still fails on a broken file.

## Out of scope

Do not disable freepool or hardcode it out of routing. The goal is more free-arm throughput.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file, RED,
  revert, GREEN; a zero-match anchor is a hard failure, not a skip. Logs in `red/`.
- No `grep` against script source as an assertion; no negated command as an assertion.
- Bash 3.2.57 only.
- `git add <file> <file>`, never `git add <dir>`.
- Commit before you stop.

## Done means

A content-based liveness probe with a mutation-proven control that rejects a blank-body route; a
named, evidence-backed reason why ranks 1-3 return empty, with a concrete recommendation; the rank
list re-ordered from a real bakeoff including `nemotron`; and a `report.md` whose first line states
which model the free arm will actually run on tomorrow.
