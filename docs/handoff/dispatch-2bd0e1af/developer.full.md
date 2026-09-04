verdict: APPROVE
next_action: review_round_3_or_close

# FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01 — round 2 developer full report

Committed on branch `worktree-FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01` at `8c5db82`.
Full write-up (evidence, control logs, bakeoff transcripts, per-item detail): see
`docs/handoff/FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01/report.md` and the `bakeoff/round2/` and
`red/` subdirectories next to it, on the lane worktree.

## What round 2 found

Round 1 fixed the arbiter/gate mechanics correctly, but its premise ("the ranked models are
dead upstream") was imprecise. Every ranked route answers HTTP 200 — never 401/403/429. This
is NOT a credentials problem. Probed live 2026-08-30 against the real proxy
(`http://127.0.0.1:8317`, reachable this session): `deepseek-v4-pro`, `kimi-k3`, and
`gemini-3.7-flash` all return `{"content":[{"type":"text","text":" "}]}` — HTTP 200 with
whitespace-only text — at the old probe's `max_tokens:1`. Even `groq/gpt-oss-120b` did the
same at `max_tokens:10/16/32`, only clearing at `max_tokens:64`.

Root cause, confirmed against the proxy's own source
(`~/tools/free-claude-code/src/free_claude_code/core/reasoning.py`,
`ReasoningPolicy.provider_default()`): the proxy leaves reasoning computation to each
provider's own default, so a reasoning-capable model spends its whole tiny token budget on
invisible reasoning before any visible text — the response is well-formed, 200, and blank. A
status-code-only probe cannot see this.

`deepseek-v4-pro` did NOT resolve with more budget: at `max_tokens:500` it hung with no
response after 90s, and again after 125s on retry. That is excluded (not merely demoted) from
every rank as a reliability finding, separate from the budget-starvation root cause.

## What changed

1. **`leadv2-freepool-model-select.sh` `_probe()`** — max_tokens 1→64 (env-overridable via
   `FREEPOOL_MODEL_PROBE_MAX_TOKENS`), captures the response body, and requires the joined
   `content[].text` (stripped) to be non-empty, not just a 2xx status.
2. **New `test-freepool-model-liveness.sh`** (5/5 green). Mutation-proven: a scratch copy of
   the production file has `_probe` reverted to the exact old status-code-only body (anchored
   on a specific line — zero-match anchor is a hard failure, not a skip); against the same
   fixture it wrongly picks the blank-body route, reproducing the incident. Restoring the
   production file passes again. Log: `docs/handoff/FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01/red/model-liveness-green.log`.
3. **`freepool-arm.yaml` re-ranked from a real bakeoff** (small bash-3.2 shell-editing task,
   `max_tokens:500`, graded by `bash -n` + actual execution against expected stdout;
   transcripts in `bakeoff/round2/`): `groq/gpt-oss-120b` (1s, PASS) → `mistral-code-latest`
   (1s, PASS) → `nemotron-3-super` (35s, PASS, newly added — was not in any prior rank list) →
   `kimi-k3` (67s, PASS) → `gemini-3.7-flash` (33s, PASS but flaky under repeated probing in
   the same session). `deepseek-v4-pro` excluded — `HTTP_FAIL` both bakeoff attempts.
   `role_rank.implement` updated the same way (kimi-k3 kept primary — still the
   best-benchmarked agentic coder and it passed the bakeoff — nemotron-3-super added as
   secondary).
4. **Fixed a pre-existing fixture break, in scope not drive-by**: `test-freepool-model-selector.sh`'s
   fake-curl never wrote a `/v1/messages` response body (only a status code) — correct under
   the old probe, silently wrong under the new content-checked one; all 9 cases touching
   `_probe` broke. Fixed the fixture to write a real body (`"OK"` default, `" "` for routes in
   a new `FAKE_CURL_BLANK_ROUTES` var) and updated one hardcoded expectation (`FP-02 flat
   fallback`) from the old primary (`deepseek-v4-pro`) to the new one (`groq/gpt-oss-120b`).
   Back to 25/25 green.
5. **Re-verified round 1's suites still green, unchanged**: `test-worker-output-gate.sh` 8/8
   (mutation control intact), `test-arm-capability-honoured.sh` 4/4.
6. **`tests/run-all.sh`**: wired `test-freepool-model-liveness.sh` into `EXTRA_SUITE_MAP`
   (stems `leadv2-freepool-model-select` and `freepool-coder`). Verified live from a dirty
   tree (temporary print-and-exit patch, ran, restored byte-identical via `diff`) that
   `--scope changed` selects it for this lane's actual changed files.

## Honest gaps (not fixed this round, flagged not silently dropped)

- **`freepool-arm.yaml` changes are invisible to `--scope changed`.** The scope loop
  (`tests/run-all.sh:150`) only matches changed files under `plugins/leadv2/scripts/*.sh` — a
  yaml-only rank reorder never triggers any suite via the changed-file path. Pre-existing gap,
  not introduced this round, but worth calling out since this round's PRIMARY fix is exactly
  that kind of change. Not fixed — broadening the runner's changed-file matching is a larger,
  separate change outside this round's `LANE_WRITES`.
- **`role_rank.bulk`/`review`/`read` not re-verified.** The bakeoff and probe evidence are
  scoped to `implement` (the path this incident hit) and the flat `model_rank` default.
- **Full `--scope changed` run could not complete this session**: it hung on
  `/tmp/leadv2-core-offline.lock` held by a concurrent lane/session (expected in a shared
  worktree environment, not a fault in this change). Verified the specific affected suites
  individually instead (all listed above, all green) plus `bash -n` on every changed `.sh` and
  `python3 -c 'import yaml'` on the changed `.yaml`.
- **Round-1 gap carried forward unchanged**: `leadv2-dispatch-code.sh`'s generic worker-accept
  path for paid arms (codex/glm/sonnet) still lacks the equivalent output-gate wiring
  (freepool's `deadhand_check` has it). Not in this round's `LANE_WRITES` either.

## Self-checks run before this deliverable

```
$ bash -n plugins/leadv2/scripts/lib/leadv2-freepool-model-select.sh \
         plugins/leadv2/scripts/tests/test-freepool-model-selector.sh \
         plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh \
         tests/run-all.sh
(all silent / exit 0)

$ python3 -c "import yaml; yaml.safe_load(open('plugins/leadv2/config/freepool-arm.yaml'))"
YAML OK

$ bash plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh
=== 5 passed, 0 failed ===

$ bash plugins/leadv2/scripts/tests/test-freepool-model-selector.sh
=== 25 passed, 0 failed ===

$ bash plugins/leadv2/scripts/tests/test-worker-output-gate.sh
PASS=8 FAIL=0

$ bash plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh
PASS=4 FAIL=0
```

`test-freepool-capability-floor.sh` (20 passed, 11 failed) and `test-freepool-pin-drift.sh`
(10 passed, 1 failed) both fail identically against the ORIGINAL (pre-round-2) `freepool-arm.yaml`
— confirmed by temporarily restoring the original file via `git show HEAD:...` and re-running;
these are pre-existing baseline reds, not caused by this round's changes.

DELIVERABLE_COMPLETE
