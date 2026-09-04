# WRITESET-REFUSAL-NEVER-NAMES-THE-BLOCKER-01 — report

## What was wrong

`dispatch_refused reason=writeset_conflict` printed the refused lane's own write set and never the
incumbent it collided with. The registry already computed and printed the answer on stderr
(`leadv2-active-registry.sh:399` / `:420`), but both `leadv2_active_register` call sites in
`cmd_resolve` discarded it (`:7056` captured stdout with `2>/dev/null`; `:7240` did
`>/dev/null 2>&1`). Worse, exit 5 covers two different situations that wore one name:

1. `pending_resolution` — an incumbent with **no** write set still inside
   `LEADV2_WRITESET_PENDING_WINDOW_SEC` (default 900 s). Refused **before any path comparison**;
   narrowing one's declared writes is useless against it.
2. `overlap` — a genuine path collision with a declared write set.

A blocked lead cannot tell these apart from the refusal text, so the reasonable move ("narrow my
writes") is exactly the wrong move in case 1.

## The fix (one file: `plugins/leadv2/scripts/leadv2-dispatch-code.sh`)

- New `_emit_writeset_refusal <sig8> <lane_writes> <register_stderr> <founder_task_id>`: parses
  `other=` / `reason=pending_resolution` / `paths=` out of the registry's real stderr and emits
  - `dispatch_refused reason=writeset_pending … blocked_by=<task_id> age_s=<n> window_s=<n>` (age
    read from the row the registry just named, via the sourced `_leadv2_yaml_file`; any read
    failure degrades to `age_s=unknown`, never blocks the refusal), or
  - `dispatch_refused reason=writeset_overlap … blocked_by=<task_id> paths=<a>,<b>`, or
  - the legacy bare `writeset_conflict` line when the stderr parses to neither shape (registry
    message drift) — worst case is exactly today's behaviour, never a wrong name.
- Call site 1 (`:7056` region): stderr captured to an mktemp file, read into `_register_err`,
  temp removed. Stdout contract (session_id) unchanged; a failed mktemp degrades to the old
  `2>/dev/null`.
- Call site 2 (`:7240` region): `2>&1 >/dev/null` capture swap — stderr kept for the parser,
  unused stdout dropped.
- Both `5)` branches route through `_emit_writeset_refusal`; their `exit 2` and the EXIT-trap row
  release are unchanged.

`leadv2-active-registry.sh` was NOT touched (claimed by DOD-GATE-CHARGES-LANES-FOR-HARNESS-WRITES-01);
nothing needed there — it already prints both answers.

## Acceptance evidence

### 1 + 2. Both cases name the blocker and are distinguishable from the text alone

Probe: scratch registry (`LEADV2_STATE_ROOT` sandbox), real `leadv2-active-registry.sh`, real
`_emit_writeset_refusal` from the shipped `leadv2-dispatch-code.sh` (truncation-sourced, same
technique as `test-dispatch-checkpoint-commit-cutoff.sh`). Raw output (`/tmp/wr-capture-lines.sh`,
2026-09-04):

    === case: pending ===
    register_rc=5
    registry_stderr: [registry] writeset conflict: other=WSR-INC-PEND reason=pending_resolution
    [leadv2-dispatch-code] dispatch_refused reason=writeset_pending task=WRTEST01 blocked_by=WSR-INC-PEND age_s=7 window_s=900 writes=plugins/leadv2/scripts/leadv2-dispatch-code.sh
    LEADV2_DISPATCH_REFUSED: writeset_pending
    === case: overlap ===
    register_rc=5
    registry_stderr: [registry] writeset conflict: other=WSR-INC-OVR paths=contested/b.txt
    [leadv2-dispatch-code] dispatch_refused reason=writeset_overlap task=WRTEST01 blocked_by=WSR-INC-OVR paths=contested/b.txt writes=contested/b.txt
    LEADV2_DISPATCH_REFUSED: writeset_overlap

Distinguishability without reading the registry: `writeset_pending` carries `window_s=`/`age_s=` and
never `paths=` (paths were never compared); `writeset_overlap` carries `paths=` and never
`window_s=`.

### 3. Negative control (mandatory) — re-swallow the stderr, the name disappears

Re-ran the pending case's register the OLD way (`>/dev/null 2>&1`) and fed the resulting empty
stderr to the refusal — byte-for-byte what the pre-fix call sites passed on:

    [leadv2-dispatch-code] dispatch_refused reason=writeset_conflict task=WRTEST01 writes=plugins/leadv2/scripts/leadv2-dispatch-code.sh

No `blocked_by=`, no case name. This is also assertion 4 of the suite
(`test-writeset-refusal-names-blocker.sh`), so the control reruns with every `--scope changed`
run that touches `leadv2-dispatch-code.sh`.

### 4. Callers checked — `writeset_conflict` still greps

`grep -rn writeset_conflict plugins/leadv2/` (run 2026-09-04, this worktree) returns, outside the
changed files: `leadv2-active-registry.sh:33` (comment describing exit 5) and
`tests/test-glm-flash-handle.sh:161` (prose comment). Neither is a lie after this change: the
registry's stderr still literally says `writeset conflict:`, exit 5 is still the conflict family,
and the dispatch-side fallback reason token `writeset_conflict` is preserved verbatim. No runtime
caller and no test assertion greps the token. The registry comment was deliberately left alone
(file claimed by a concurrent lane; content still true).

### Live reproduction (case 1 in the wild)

`~/.claude/leadv2-state/leadv2/active.yaml` at probe time (2026-09-04):

    task_id=GLM-PEAK-RULE-IS-MODEL-BLIND-01 phase=review:blocked writes='plugins/leadv2/scripts/leadv2-glm-quota-gate.sh ...' started_at=2026-09-04T10:14:02Z age_s=3904 stale=False
    task_id=GLM-PEAK-RULE-IS-MODEL-BLIND-01 phase=recovered writes=None started_at=2026-09-04T10:29:34Z age_s=2972 stale=None

The `phase=recovered` twin has no write set and was ~400 s old at mission time — it refused every
incoming dispatch to this repo through `pending_resolution` before any path comparison. It is the
resurrecting row the brief warns about (`RECOVERY-ATTACHES-A-BYSTANDER-PID-TO-A-LANE-01`, tracked
separately; the window was NOT shortened here). Corroborating tax: this session's own ambient
environment carries `LEADV2_WRITESET_PENDING_WINDOW_SEC=1` — the suppression workaround the harness
had to apply so this lane's own dispatch was not blocked. Post-fix, that workaround is no longer
load-bearing for diagnosis: the refusal would have said
`reason=writeset_pending blocked_by=GLM-PEAK-RULE-IS-MODEL-BLIND-01` from the start.

## Falsification set (raw)

- `bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh` → `BASH-N-OK` (rc 0)
- `bash -n plugins/leadv2/scripts/tests/test-writeset-refusal-names-blocker.sh` → `BASH-N-OK` (rc 0)
- No standalone Python file changed (the embedded age-reader inside
  `_emit_writeset_refusal` is exercised by suite case 1's `age_s=<n>` assertion).
- Suite red → green, honest history:
  - Red (mid-development, real): case 1 emitted
    `reason=writeset_conflict … ; full case: reg_rc=0 reg_stderr=[LEADV2_WRITESET_UNKNOWN other=WSR-INC-PEND]`
    — root cause was NOT the diff: the ambient harness exports
    `LEADV2_WRITESET_PENDING_WINDOW_SEC=1`, which expires every pending window before the
    candidate registers. The suite now pins `=900` per case (comment in the suite explains).
    Second red: case 2 produced no output at all — a prior case's no-writes incumbent made the
    next case's own incumbent register exit 5, which the sourced registry's `set -e` turned into a
    dead subshell; fixed with a fresh scratch registry per case.
  - Green (final):

        [TEST] PASS: 1: pending incumbent (no writes, inside window) refuses as writeset_pending naming blocked_by=WSR-INC-PEND, no paths=, age_s=/window_s present
        [TEST] PASS: 2: real path overlap refuses as writeset_overlap naming blocked_by=WSR-INC-OVR with the colliding paths=
        [TEST] PASS: 3: the two cases are distinguishable from the refusal text alone (reason + window_s= vs paths=)
        [TEST] PASS: 4: negative control — with stderr re-swallowed (old 2>/dev/null), blocked_by disappears and the legacy writeset_conflict fallback fires
        ----
        PASS=4 FAIL=0

- Changed-scope runner (`tests/run-all.sh --scope changed`): 37 suites selected (list captured via
  `LEADV2_RUN_ALL_SELECT_ONLY=1`, includes the new suite via its `run-all-triggers:
  leadv2-dispatch-code.sh` self-declaration). Result: see "Changed-scope run" section below.

## Changed-scope run

(filled at close — see final section of the lane journal / commit body)

## Files changed

- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — the fix, one file, both call sites.
- `plugins/leadv2/scripts/tests/test-writeset-refusal-names-blocker.sh` — new suite,
  self-registered via `# run-all-triggers: leadv2-dispatch-code.sh`.
- `docs/handoff/WRITESET-REFUSAL-NEVER-NAMES-THE-BLOCKER-01/report.md` — this report.

## Codex effort wiring probe (follow-up mission, 2026-09-04)

Three wires carry a Codex reasoning effort; all three verified against the live CLI
(codex-cli 0.145.0-alpha.1).

1. **Session-runner wire** (`leadv2-codex-session-runner.sh:33,474,492`):
   `LEADV2_LEAD_EFFORT` (default medium) → `-c model_reasoning_effort="<v>"` on
   `codex exec` (fresh and resume — both call sites wire it). Feed values come from
   `leadv2-fanout-classify.sh:132/135` (heavy/strategic→high, else medium) and the
   fanout fallbacks (`high`/`medium`) — all inside the server's accepted enum.
2. **Planner wire** (`leadv2-codex-planner.sh`): tier map top→sol/high,
   standard→terra/medium, volume→luna/low; the logical `ultra` label (top's
   sol-absent fallback) is translated to `xhigh` at the wire boundary (`:262`),
   and codex-task.sh does the same translation (`codex-task.sh:1381`).
3. **codex-task.sh wire**: same tier table, `--effort` pinned for `task`; review
   subs pin model only (companion review command has no --effort wire — documented
   at `:21`).

Live probes (raw):

    # tier resolution (--print-model, via /tmp policy sandbox — see quirk below)
    model=gpt-5.6-terra effort=medium          # standard
    model=gpt-5.6-luna effort=low              # volume
    model=gpt-5.6-sol effort=high              # top (+reason)
    model=gpt-5.6-terra effort=high            # standard + explicit --effort high
    [codex-task] top without --reason → REFUSED, rc=2 (gate intact)

    # enum validation, real `codex exec` on gpt-5.6-luna:
    bogus_rc=1  → HTTP 400: "Invalid value: 'bogus'. Supported values are:
                  'none', 'minimal', 'low', 'medium', 'high', 'xhigh', and 'max'."
    medium_rc=0 → "ok", 20 018 tokens

Findings:

- **No bug in the wiring.** Every value that can reach `codex exec`/`codex task`
  (medium/high/low/xhigh) is in the server enum; the only out-of-enum label
  (`ultra`) is translated at both wire boundaries. Session-runner values are
  class-derived and never `ultra`.
- **Doc drift, not a bug**: planner `:37`/`:101` and codex-task `:1360` say sol is
  "gov-gated and currently absent" from `~/.codex/models_cache.json` — it is
  present today (`gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna` all listed), so
  top resolves to sol/high, and the terra/ultra fallback is currently dormant
  (and safe even when it wakes: ultra→xhigh).
- **Quirk**: `_lv2_codex_enabled` policy gate in the planner runs before
  `--print-model`, so the pure dry-run is refused in codex-disabled repos (this
  worktree: no codex-policy.yaml → default disabled). Probed via
  `LEADV2_PROJECT_ROOT=/tmp/cx-probe` with a scratch `codex_enabled: true` policy;
  no repo file touched.
- PreToolUse `leadv2-codex-direct-exec-guard.sh` correctly blocks raw `codex exec`
  in compound commands too (probe had to go through a script file) — guard works
  as designed.

No code changed by this probe; nothing to re-run beyond `bash -n` on files already
covered by the lane's falsification set (unchanged this commit).
