# GLM-EFFICIENCY-01 — effort wiring, flash routing data, capability refresh

Lane branch `worktree-GLM-EFFICIENCY-01`. Founder order 2026-09-02 ("we under-use
GLM"), on top of `docs/handoff/GLM-EFFICIENCY-AUDIT-01/report.md` (the measured basis;
this report extends it, does not re-derive it).

## 1. Probe results (EVIDENCE CONTRACT)

### 1a. Mechanism: how effort reaches Z.AI through Claude Code

- CC `--effort` exists and is wired to the provider:
  `claude --version` → `2.1.258 (Claude Code)`; `claude -p --help | grep effort` →
  `--effort <level>    Effort level for the current session`.
- Z.AI's Anthropic-compat endpoint reads it. Live fetch
  `curl -sL https://docs.z.ai/devpack/latest-model.md` (2026-09-02) — "Switch Effort
  (Thinking Intensity)" table: Claude Code uses `thinking.type` and
  `output_config.effort`; `reasoning_effort` minimal/light/low → low,
  medium/high → high, xhigh/max/ultra → max; unknown string → max + hint.
  Priority: explicit effort > thinking toggle > default `max`. Default level: max.
- GLM-5.3 / 5.3-flash force thinking ON (no disable). Live fetch
  `curl -sL https://docs.z.ai/guides/llm/glm-5.3.md`: "`reasoning_effort` `low`,
  `high`, `max`, default `max`". Same ladder on the flash page
  (`https://docs.z.ai/guides/vlm/glm-5.3-flash.md`).

### 1b. The setting measurably changes the response (decisive probe)

Raw endpoint, Anthropic-compat shape, `output_config.effort`, same prompt, glm-5.3
(`/tmp/glm-curl-probe.sh`, run 2026-09-02):

```
=== output_config.effort=low ===
usage: {"input_tokens": 40, "output_tokens": 130, ...}
=== output_config.effort=max ===
usage: {"input_tokens": 40, "output_tokens": 369, ...}
```

2.8× output tokens at `max` on identical input. CC-level A/B
(`/tmp/glm-effort-probe.sh`, `claude -p --effort low|max --model glm-5.3`): output
tokens 3 (low) vs 29 (max), wall 34s vs 41s — same direction, weaker signal (tiny
prompt). The stream now surfaces real usage with
`output_tokens_details.thinking_tokens` on this endpoint.

Conclusion: the knob is real — NOT a no-op control, so it ships.

### 1c. Quota weights — the audit's premise was INVERTED

Live fetch `curl -sL https://docs.z.ai/devpack/teamplan.md` (2026-09-02), credit
formula `(in*mult + cached_in*cached_mult + out*mult)/10,000`:

| Model | Input mult | Cached mult | Output mult |
|---|---|---|---|
| GLM-5.3 | 6.9 | 1.7 | 24 |
| GLM-5.3-Flash | 2.3 | 0.56 | 8 |

**Flash weighs exactly ⅓ of glm-5.3** (2.3/6.9 = 8/24 = ⅓). The flash page's "3× the
quota" means 3× the ALLOWANCE (Team Standard ~965–1,930 M tokens/week at 95% cache
hit vs glm-5.3's 319–638), not 3× the cost. GLM-EFFICIENCY-AUDIT-01 read the
direction backwards; the brief's item-3 premise ("flash has 3× the quota weight …
Standard stays on glm-5.3") does not survive its own evidence contract.

Escalated via `leadv2-ask.sh` (qid `q-bba84179`). **Founder ruling (architect,
option b, 2026-09-02T00:16:28Z):** flash-preferred policy confirmed correct; fix is
the data-only cost correction `0.4 → 0.33` in `plugins/leadv2/config/leadv2-routing.yaml`
(LANE_WRITES extended to that file for this lane); no arbiter rewrite
(SIZE_MAP folds trivial/light into the same 'standard' cell as standard, so
"flash only trivial/light" is not reachable by sizes-list edits alone).

### 1d. UNVERIFIED (out of scope / not probeable this lane)

- Caching over `api/anthropic` (dashboard-only truth) — per brief, out of scope.
- Whether Z.AI's dashboard separates thinking tokens from output tokens for quota
  accounting (the stream's `thinking_tokens` read 0 on both A/B runs; glm-5.3 bills
  reasoning as output per the docs' effort table — credit impact is inside the
  output multiplier).
- Rate/concurrency limits — still dashboard-login-gated (audit §1 row 6 stands).

## 2. What changed

| File | Change |
|---|---|
| `plugins/leadv2/scripts/glm-coder.sh` | New `GLM_EFFORT` env seam (same pattern as `GLM_MODEL`); both `claude -p` spawn sites (v1 `run` + bg `__run_child`) append `--effort <v>` when set and in `low\|medium\|high\|max`; unset/out-of-vocab ⇒ flag omitted (fail-open to provider default `max`, byte-identical pre-lane spawn). |
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | `effort_dropped` (EFFORT-IS-NOT-WIRED-01) replaced by `_glm_effort_for_class` + `effort_applied … mechanism=flag source=class_map resolved=<v>`; `GLM_EFFORT` exported into the glm/glm-flash launcher env. Mapping: trivial/light/bulk → low, standard → high, heavy/strategic → max; review/verify roles → high (contract-complete; glm is review-excluded today). Note: standard/heavy/strategic intake routes `phases`-side by classifier design, so the direct-dispatch spawn sees trivial/light/bulk mostly; the map is contract for every caller. |
| `plugins/leadv2/config/leadv2-routing.yaml` | glm-flash capability_matrix cell `cost: 0.4 → 0.33` (measured credit ratio; founder ruling q-bba84179) + comment rewrite. |
| `plugins/leadv2/config/model-capability.yaml` | `glm` row refreshed from the 5.3 pages (1M ctx / 128K out, thinking forced, effort ladder, credit weights, evidence URLs, `confidence: medium`); new `glm-flash` row (multimodal, 1M/128K, ⅓ credit weight, effort ladder, URLs). Stale GLM-5.2-era UNVERIFIED flag removed. |
| `plugins/leadv2/docs/model-effort-matrix.md` | GLM lane rows now name the `GLM_EFFORT` seam; new "GLM effort wiring" section with the Z.AI URLs, probe numbers, class→effort table, corrected quota-weight fact. |
| `plugins/leadv2/scripts/tests/test-glm-effort-wiring.sh` | New suite (below). |
| `tests/run-all.sh` | Suite registered in `EXTRA_SUITE_MAP` (both `glm-coder.sh` and `leadv2-dispatch-code.sh` stems). |

## 3. Verification

`LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-glm-effort-wiring.sh`:

```
[TEST] PASS: bash -n scripts/glm-coder.sh (incl. 3.2)
[TEST] PASS: bash -n scripts/leadv2-dispatch-code.sh (incl. 3.2)
[TEST] PASS: run path: GLM_EFFORT=low -> spawn argv carries --effort low
[TEST] PASS: run path: GLM_EFFORT unset -> no --effort flag (provider default max, pre-lane spawn shape)
[TEST] PASS: run path: GLM_EFFORT=ultramax rejected by whitelist -> flag omitted (fail-open)
[TEST] PASS: bg path: __run_child spawn argv carries --effort low
[TEST] PASS: dispatch: task-class trivial -> launcher env GLM_EFFORT=low (end-to-end)
[TEST] PASS: dispatch: task-class light -> launcher env GLM_EFFORT=low (end-to-end)
[TEST] PASS: class map: trivial -> low
[TEST] PASS: class map: light -> low
[TEST] PASS: class map: bulk -> low
[TEST] PASS: class map: standard -> high
[TEST] PASS: class map: heavy -> max
[TEST] PASS: class map: strategic -> max
[TEST] PASS: dispatch: journal carries effort_applied mechanism=flag (no effort_dropped remains)
[TEST] PASS: NC(red): dropping the pass-through leaves the launcher env without GLM_EFFORT (part A red)
[TEST] PASS: NC(red): mutant journal reverted to effort_dropped (journal assertion red)
[TEST] PASS: routing yaml: parses; glm-flash cell cost corrected to 0.33
[TEST] PASS: arbiter: light-size code work picks glm-flash / glm-5.3-flash
[TEST] PASS: arbiter: standard-size code work picks glm-flash / glm-5.3-flash
[TEST] passed=20 failed=0
```

Mutation negative control (red-first): a scratch mutant of the dispatcher with the
`GLM_EFFORT` pass-through dropped and the journal line reverted makes the launcher-env
and journal assertions RED (`GLM_EFFORT=<unset>` recorded, `effort_dropped` back in the
journal) — asserted inside the suite's NC block, working tree never touched.
Intermediate fixture-bug reds during development (stub `$*` expansion, foreign-root
guard, shared-registry writeset collision on `src/x.py`, mutant SCRIPT_DIR) were
harness defects, fixed; the final NC is a true red-then-green on the wiring itself.

## 4. Routing outcome under the ruling

- Trivial/Light build work → `glm-flash` (arbiter: cheapest capable — flash cost 0.33
  beats glm 1 / codex 3..7 / sonnet 5; verified in-suite for light AND standard).
- Standard → `glm-flash` as well (NOT glm-5.3 as the brief wrote — the founder ruling
  confirmed the flash-preferred policy; glm-5.3 keeps heavy/bulk and all protected/
  safety chains, where flash is stripped by `protected:false` + `untrusted:true`).
- Existing lock_busy / quota fallbacks untouched (glm-flash shares the glm bucket and
  lockout scope; GLM-53-FLASH-ARM-01 refusal attribution unchanged).
- Quota gating thresholds, the lock, Sonnet/Codex routing: untouched (Do-NOT honored).
- No `[1m]` / auto-compact trial in this lane (separate follow-up, per brief).
- GLM-47-BAN-01 respected: only glm-5.3 / glm-5.3-flash referenced; the probe scripts
  under /tmp used glm-5.3 only.

## 5. Residual risks

- `effort_applied` claims `mechanism=flag`; the flag is proven to reach the spawn argv
  by suite, but end-to-end provider acceptance of CC's `--effort` on a REAL dispatched
  lane is UNVERIFIED this lane (the raw-endpoint probe is the evidence the provider
  honors the field; a live heavy lane will journal real usage deltas via the stream).
- Routing yaml cost is a STATIC preference; the arbiter still models provider-level
  utilization only (per-cell comment retained verbatim on that point).

## Falsifiability proof (fix-round 2, 2026-09-02)

R1 review stopped at `review_gate status=blocked reason=suite_falsifiability_undetermined` before any
model review ran. Fix-round 2 re-proved the gate on the lane tip (merge of `main`, 2026-09-02):

Suite baseline (green, 1:49.83 wall, 20/20):

```
[TEST] PASS: NC(red): dropping the pass-through leaves the launcher env without GLM_EFFORT (part A red)
[TEST] PASS: NC(red): mutant journal reverted to effort_dropped (journal assertion red)
[TEST] PASS: routing yaml: parses; glm-flash cell cost corrected to 0.33
[TEST] PASS: arbiter: light-size code work picks glm-flash / glm-5.3-flash
[TEST] PASS: arbiter: standard-size code work picks glm-flash / glm-5.3-flash
[TEST] passed=20 failed=0
bash plugins/leadv2/scripts/tests/test-glm-effort-wiring.sh 2>&1  27.17s user 25.34s system 47% cpu 1:49.83 total
RC=0
```

Falsifiable gate, full output (4 sequential suite runs, 4:47 total, every run inside the 180s watchdog):

```
$ bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-glm-effort-wiring.sh
leadv2-suite-falsifiable: suite=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GLM-EFFICIENCY-01/plugins/leadv2/scripts/tests/test-glm-effort-wiring.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=84
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
GATE_RC=0
```

Verdict line reads FALSIFIABLE: the generic assertion-tool sabotage (84 shimmed `grep` calls) flipped the
suite to rc=1, i.e. the suite's assertions are load-bearing — it cannot stay green under broken
verification tooling. The suite's own declared negative control (the scratch-copy mutant dispatcher with
the `GLM_EFFORT` pass-through removed and `effort_applied` demoted to `effort_dropped`,
test-glm-effort-wiring.sh:254-300) additionally goes red inside the suite under mutation of the function
under claim (`_glm_effort_for_class` / the `--effort` pass-through at leadv2-dispatch-code.sh ~:5100).
