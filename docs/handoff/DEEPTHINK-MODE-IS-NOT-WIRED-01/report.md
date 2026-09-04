# DEEPTHINK-MODE-IS-NOT-WIRED-01 — report: deepthink rides the effort vocabulary

Lane commit: `39982836` (code + suite) · resume run 2026-09-04.

## 1. Answer: what turns deep thinking on for glm-5.3 / glm-5.3-flash

**There is no separate "thinking mode" switch at the provider.** Live probing against
`https://api.z.ai/api/anthropic/v1/messages` (the transport `glm-coder.sh` actually uses) shows
that for both `glm-5.3` and `glm-5.3-flash`:

- both models **always reason** (a thinking block appears on a plain request with no extra fields);
- the Anthropic-style `thinking` object **collapses into the effort vocabulary**:
  `thinking.type=disabled` is honoured only as "downshift" (no thinking block, or near-zero), while
  `thinking.type=enabled` behaves like default `max`;
- `thinking.budget_tokens` is **silently dropped** (a budget of 1 token produced 599 chars of
  thinking — an honoured budget is impossible with that output);
- `output_config.effort` — the field Claude Code's `--effort` flag lands in — is the **only**
  thinking-intensity dial the provider honours, and `max` is the provider's documented
  **Deep Reasoning** level.

Doc confirmation (fetched during the probe session,
`probes/doc-glm53.md:33`): `reasoning_effort` accepts `low | high | max` — `low` "Lightweight
Reasoning", `high` "Enhanced Reasoning", `max` "Deep Reasoning". And `probes/doc-devpack-latest-model.md:93-103`
(the provider's own compat table): `thinking.type` not-set/true/enabled/adaptive → `max`;
false/disabled/none/off → `low`; "Disabling the thinking configuration is converted to `low`";
priority: Explicit Effort > thinking toggle > default `max`.

So the founder requirement's second half ("deepthink mode when needed") is satisfied by the SAME
parameter the first half already uses: **effort=max IS deepthink at z.ai.** Wiring a second flag
would be a dead knob the provider does not read.

## 2. Live probe battery (acceptance §1 — the probe, not the doc, is the proof)

Battery script: `probes/probe-provider.sh` (phases `validate` / `behavior` / `effort`; every
request a live `curl` against api.z.ai, 15 s apart). Raw responses: `probes/*.json`. Distilled:

| probe | request differs from baseline by | result |
|---|---|---|
| `53-baseline` | — (plain body) | blocks=`[thinking, text]`, thinking 301 chars, output_tokens 295 |
| `53-disabled` | `thinking:{type:"disabled"}` | blocks=`[text]`, **no thinking block**, output_tokens 32 |
| `53-budget1` | `thinking:{type:"enabled",budget_tokens:1}` | thinking **599 chars** — budget ignored |
| `53-budget16k` | `budget_tokens:16384` | thinking 306 chars — budget ignored |
| `53-unknownctl` | unknown sibling field `dphysink:true` | accepted, thinking 383 chars (control: unknown fields pass through) |
| **`53-effort-low`** | `output_config:{effort:"low"}` | blocks=`[text]`, **no thinking**, output_tokens 135 |
| **`53-effort-max`** | `output_config:{effort:"max"}` | blocks=`[thinking, text]`, thinking **434 chars**, output_tokens 340 |
| `flash-baseline` | — (flash, plain) | thinking 886 chars, output_tokens 506 |
| `flash-disabled` | `thinking:{type:"disabled"}` | **no thinking**, output_tokens 103 |
| `flash-enabled` | `thinking:{type:"enabled"}` | thinking 376 chars (≈ default, not more) |
| **`flash-effort-low`** | `output_config:{effort:"low"}` | **no thinking**, output_tokens 63 |
| **`flash-effort-max`** | `output_config:{effort:"max"}` | thinking **377 chars**, output_tokens 407 |

The decisive acceptance pair — same prompt, same model, only the effort flag flips:
`glm-5.3` low → no thinking block / 135 output tokens vs max → thinking block 434 chars / 340
tokens; `glm-5.3-flash` low → no thinking / 63 vs max → thinking 377 chars / 407. Same-request
difference, visible in both the response body and the usage telemetry.

Honest caveats: the `validate` phase's `thinking:{type:"banana"}` and one flash retry came back
`1302 rate_limit_error` (raw: `53-banana.json`, `glm53flash-disabled.json`) — so "the compat layer
400s on invalid thinking types" is NOT claimed; the behavioural probes above carry the finding.
An earlier-generation probe pair (`glm53-disabled.json`) returned a 7-char thinking block with
`thinking:{type:"disabled"}` on `glm-5.3` — consistent with the doc's "disabled → converted to
low … still performs lightweight thinking"; the later battery run got a clean no-thinking result,
so the collapse is real but the residual block is provider-side non-determinism at the boundary.

## 3. Wiring (acceptance §2+§3: decision by work kind, one variable, runner adds the parameter)

Dispatcher `plugins/leadv2/scripts/leadv2-dispatch-code.sh`:

- new `_glm_think_for_class()` — **from work class, never a name list**: `heavy|strategic → deep`
  (architecture / safety / root-cause / heavy-diff review), `trivial|light|bulk|standard → off`
  (mechanical, docs, routine dev), unknown class → `off` via `fallback` (never pay deep quota on
  a class the admission classifier did not name);
- `_spawn_worker_body()` resolves `think` from the same raw `DC_TASK_CLASS` the effort map uses,
  then **pins `effort=max` AFTER the review/verify/critic role_override** — the actual gap this
  lane closed: a heavy-diff review previously capped at `high`;
- `think=deep` reaches the runner **as the same one variable** — `GLM_EFFORT=max` on the launcher
  env (`leadv2-dispatch-code.sh:5371`) — because at the provider effort IS the thinking dial.
  No second variable exists to pass, deliberately.

Runner `plugins/leadv2/scripts/glm-coder.sh`: comment-only change at the `GLM_EFFORT` seam
documenting why there is **no `GLM_THINK` flag** — the provider would not read it (acceptance §4:
a knob that does nothing is worse than no knob). The `--effort max` argv append already present
is the parameter deepthink arrives as.

## 4. Decision-line visibility (acceptance §4)

The journal line now reads (live from the suite's dispatcher run):

```
decision effort_applied by=router arm=glm task=XXXXXXXX effort=max think=deep think_source=class_map mechanism=flag source=class_map resolved=medium
```

`think=` sits directly next to `effort=` on the `effort_applied` line — the decision line itself
proves deepthink travelled. When the deep pin changed the value past a role override the effort
source becomes `think_deep` (e.g. `Heavy + critic`), so the pin is individually attributable.

## 5. Negative mutation controls (acceptance §2)

Every control mutates INSIDE the function body of `leadv2-dispatch-code.sh` via
`leadv2-mutation-control.sh`; proof = `baseline_rc`/`mutated_rc` + the red line, not `diff_hash`.

| # | requirement | mutation | result | artifact (`mutation-control/`) |
|---|---|---|---|---|
| 1 | heavy/strategic work gets deep | `printf 'deep' 'class_map'` → `'off'` in `_glm_think_for_class` | baseline_rc=0 → mutated_rc=1, red line below | `20260904T004515Z-69506.txt` |
| 2 | mechanical/routine work must NOT get deep | `'off' 'class_map'` → `'deep'` (off-branch leak) | PENDING | PENDING |
| 3 | deep pins effort=max AFTER role override | pin condition `"deep" &&` → `"never" &&` | PENDING | PENDING |
| 4 | **variable pass-through to the runner** (mandatory) | `GLM_EFFORT="${_glm_effort}"` dropped from launcher env | PENDING | PENDING |
| 5 | think= visible on the decision line | ` think=${_glm_think} think_source=…` stripped from emit | PENDING | PENDING |

Control 1 artifact, verbatim:

```
suite=plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh
file=plugins/leadv2/scripts/leadv2-dispatch-code.sh
anchor=s|printf '%s %s' 'deep' 'class_map'|printf '%s %s' 'off' 'class_map'|
baseline_rc=0
mutated_rc=1
red_line=[TEST] FAIL: dispatch: Heavy expected effort=max think=deep source=class_map — got: append dispatch-38feeb72 decision effort_applied by=router arm=glm task=38feeb72 effort=max think=off think_source=class_map mechanism=flag source=class_map resolved=medium
diff_hash=ff1e1764892dc4a39f86561ebb0934800f853de074ba9f0dc48d52c87c8e69b0
lane_diff_hash=52b6d61cece6214f92300799964a94a343b2dc313fa83b51b28a9e320926667f
```

Controls 2–5: PENDING (battery in flight — filled before commit).

## 6. Ten consecutive runs (acceptance §3)

PENDING — `probes/ten-runs.txt`, filled before commit.

## 7. Self-check / falsification set

- `bash -n` (both Homebrew bash and `/bin/bash` 3.2) on every changed shell file, raw output:

```
bash -n OK: plugins/leadv2/scripts/glm-coder.sh
bash3.2 -n OK: plugins/leadv2/scripts/glm-coder.sh
bash -n OK: plugins/leadv2/scripts/leadv2-dispatch-code.sh
bash3.2 -n OK: plugins/leadv2/scripts/leadv2-dispatch-code.sh
bash -n OK: plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh
bash3.2 -n OK: plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh
python-files-changed=0
```

- no Python files changed (`git diff --name-only main..HEAD | grep -c '\.py$'` → 0, so
  `py_compile` is n/a — the diff is two `.sh` edits + one new test suite);
- changed-scope runner `tests/run-all.sh --scope changed` — PENDING raw output.

## 8. Files changed (lane commit `39982836`)

- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — `_glm_think_for_class`, deep pin after role
  override, `think=` on the `effort_applied` journal line (+39/−1);
- `plugins/leadv2/scripts/glm-coder.sh` — comment-only at the `GLM_EFFORT` seam (+9);
- `plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh` — new suite, self-selects via the
  stem convention (changed `leadv2-dispatch-code.sh` → `test-leadv2-dispatch-code.sh`), 23 checks:
  dispatcher e2e (recorder/journal stubs, no network) ×5 rows, unit class map ×10, transport
  `--effort max` argv ×1, `bash -n` floor ×2, syntax floor ×... (see suite header).

Untouched, as briefed: `main`, `docs/leadv2/`, `tests/known-red-suites.txt`, `tests/run-all.sh`;
no assertions weakened (the new suite is additive; the one existing assertion it neighbours —
GLM-EFFICIENCY-01's `source=class_map` — is kept byte-identical by design, see §3).
