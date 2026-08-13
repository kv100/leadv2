# KIMI-CHANNEL-REHAB-01 — architect prepass (scoped design)

## Verdict on the premise

Confirmed by inspection, not assumed. The two removal commits took out **only the ladder
membership**, not the channel:

| Removed by | What | Lines |
|---|---|---|
| `79e239a` | `- id: kimi` arm entry in `router_v2.arms` | `config/leadv2-routing.yaml` +9/-6 |
| `5e8730a` | `kimi` from two `candidate_arms=(glm …)` arrays | `scripts/leadv2-dispatch-code.sh` +7/-5 |

Everything else that makes the arm work is **still present and untouched** in
`leadv2-dispatch-code.sh`: the run-id sanitizer case (`:685`), the handle-parse case (`:711`),
`KIMI_BIN` (`:1378`), the rc=77 reroute mapping (`:1491`), and the whole `kimi)` spawn +
refusal block (`:1562-1592`). `kimi-coder.sh` (1786 lines) was never edited. So the revert is
genuinely a two-array + one-yaml-block re-add — no resurrection of deleted machinery.

Second confirmation of the root cause, from the code rather than the run samples:
`kimi-coder.sh` already ships `mission_is_code_shaped()` (`:1217`) and `work_delta_present()`
(`:1245`), and `deadhand_check()` (`:1284`) already computes `reason=no_work_delta` for exactly
the observed failure. It is **detect-only** — it writes a `.no-deliverable` sentinel and
explicitly "never alters status". That is why 19 runs came back `exit=0 / end_turn / writes=0`
and were recorded as *successes* the ladder never spilled past. The detector exists; it just
isn't wired to the exit code. Requirement 3 is a wiring change, not a new subsystem.

---

## Changes

### 1. `plugins/leadv2/config/leadv2-routing.yaml` — restore the arm

Re-add the `- id: kimi` block removed by `79e239a`, in its original position (between `glm`
and `codex`), with its original fields:

```yaml
    - id: kimi
      model: moonshotai/kimi-k3-free
      bucket: kimi
      reserve_threshold: 2
      reserve_allow: [review]
```

Replace the 8-line removal comment with a short REHAB note: the arm is back, admissibility is
now decided at dispatch time by the mission-shape guard, not by membership in this list.
Keep the original "dispatch: hardcoded `kimi)` case … no data-driven channel field" line — it
is still true and still load-bearing for the next reader.

### 2. `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — ladder + admission guard

**2a. Ladder restore (revert of `5e8730a`).** Two sites, both `glm)` cases:

- `:2255` (legacy chain build) → `candidate_arms=(glm kimi codex sonnet)`
- `:2436` (post-`glm_lock_busy` re-resolve) → `candidate_arms=(glm kimi codex sonnet)`

`codex)` and `sonnet)` cases unchanged. Comment rewritten to point at the guard.

**2b. `--kimi-fit` flag.** New arg in the parse loop (`:1910-1953`): `--kimi-fit` sets
`kimi_fit=1`, default `0`. Declared alongside the existing `force`/`lockbusy` locals at `:1910`.

**2c. Admission predicate.** New function, placed next to the other dispatch-time helpers
(after `_harvest_lane_writes`, ~`:1185`):

```
_kimi_admissible <mission> <sig8> <writes_csv> <kimi_fit>  -> 0 admissible / 1 not
```

Returns 0 immediately when `kimi_fit=1` (explicit founder override, no heuristic). Otherwise
**all three** must hold:

| Gate | Rule | Source of truth |
|---|---|---|
| G1 mission size | `${#mission} <= LEADV2_KIMI_MAX_MISSION_CHARS` (default `2500`) | the assembled `mission` string, measured after the `:2102` append so it reflects what the child actually receives |
| G2 write-set size | declared write count `<= LEADV2_KIMI_MAX_WRITES` (default `2`) | row `writes` CSV if non-empty; else `_harvest_lane_writes "$(_prepass_file "${sig8}")"`; if **neither** yields a count → **not admissible** (fail-closed) |
| G3 no prepass design | `[[ ! -f "$(_prepass_file "${sig8}")" ]]` | an architect prepass artifact *is* the broad-product-mission signal — it is only produced for tasks the prepass gate deemed non-trivial |

Fail-closed on G2 is deliberate: an undeclared write-set is exactly the unbounded-scope shape
that produced the 19 empties. The cost of a false skip is one rung of ladder; the cost of a
false admit is a whole wasted lane.

**2d. Filter application.** New `_apply_kimi_admission` that rebuilds `candidate_arms` with
`kimi` dropped, modelled byte-for-byte on the existing codex-drop filter at `:2272`
(same `_filtered` array idiom — do not invent a second pattern). On drop it emits:

```
emit decision "kimi_skipped reason=mission_too_broad task=${sig8} chars=${#mission} writes=${w} prepass=${p}"
```

`reason=` stays the literal `mission_too_broad` the mission specifies; the `chars`/`writes`/
`prepass` fields say *which* gate tripped without multiplying reason strings.

**Three call sites — all of them, or the guard has a hole:**

1. legacy chain build, immediately after the `case "${arm}"` block (~`:2262`)
2. **router-v2 branch** (`:2251`), after `IFS=',' read -r -a candidate_arms <<< "${v2_eligible}"` —
   v2 builds its chain from `leadv2-routing.yaml`, so restoring the yaml arm in change 1
   makes kimi reachable on this path too. Missing this site is the single most likely defect
   in the implementation.
3. re-resolve after `glm_lock_busy` (~`:2436`), after the chain is rebuilt.

Ordering constraint: the filter must run **after** the chain is built and **before**
`_rv2_chain="$(IFS=,; …)"` at `:2294` serialises the chain into the journal, otherwise the
journal advertises a rung that will never be tried.

Empty-chain guard: filtering cannot empty the chain in practice (kimi is never the sole arm on
any of the three paths — `codex`/`sonnet` always follow), so no new `all_arms_exhausted` exit
is introduced. The implementation should nonetheless not remove the existing length check.

**2e. Ledger tagging for `channel_no_work`.** In the `kimi)` rc block (`:1562-1592`), when the
launcher/run reports the new no-work bail, set
`LAST_ARM_OUTCOME="kimi_channel_no_work"` (detected via the `KIMI_CHANNEL_NO_WORK` sentinel in
the run's `progress.log`) instead of the generic `kimi_failed_launcher`, and emit
`arm_refused … reason=channel_no_work`. This is what makes the ledger record a **channel**
outcome rather than a **task** failure — the distinction the mission asks for. The spill itself
is already handled: `:1491` maps the fallback rc to a reroute today, unchanged.

### 3. `plugins/leadv2/scripts/kimi-coder.sh` — no-work detector

Single insertion in `cmd_supervise`, in the **success branch** (the `RUN_COMPLETE` path,
~`:1490-1520`), placed after the existing `.asked_into_void` finish-guard and **before**
`finalize_meta` (`:1546`) — `finalize_meta` mv-clobbers `meta.yaml`, so the status/exit flip
must happen upstream of it, unlike `deadhand_check` which is deliberately downstream and
detect-only.

Conditions — bail only when **all** hold:

1. `exit_code -eq 0` (we are in the end_turn/success branch)
2. `[[ -s "${run_dir}/prompt.txt" ]]` — non-empty mission
3. `mission_is_code_shaped "${run_dir}" == 1` — **this is the mission-kind gate.** It reads the
   `LANE_WRITES:` line and returns `0` when every declared path is under `docs/`, and `0` when
   there is no `LANE_WRITES:` line at all. A read-only / discovery mission therefore cannot
   trip the detector. `LEADV2_MISSION_CODE=0` is an existing explicit opt-out that also holds.
4. `work_delta_present "${run_dir}" "${cwd_dir}" == "no"` — strictly `no`. `skip` (no
   `.workbase` baseline captured, or non-git tree) must **not** bail; an undetectable delta is
   not an absent delta.

Effect when all four hold:

```
status="failed"
exit_code="${KIMI_FALLBACK_EXIT_CODE}"    # 78
echo "KIMI_CHANNEL_NO_WORK reason=no_work_delta" >> progress.log
echo "${KIMI_FALLBACK_SENTINEL}"          >> progress.log
```

**Why 78 and not 77.** `77` (`KIMI_PROBE_FAIL_EXIT_CODE`) means *the channel was unreachable
before launch* — it is emitted by the pre-flight probe at `:174` and asserts nothing about the
mission. `78` (`KIMI_FALLBACK_EXIT_CODE`) is the established "the child ran but produced
nothing usable → retryable elsewhere" code, already documented in the two-sentinel contract at
`:1536` and already mapped to a spill by the caller. A no-work end_turn is precisely
retryable-elsewhere. **78 is the right code**; using 77 would falsely claim the endpoint was
down and would corrupt any future channel-health accounting.

Re-using `KIMI_FALLBACK_SENTINEL` (rather than a novel sentinel) keeps every existing Monitor
grep working; `KIMI_CHANNEL_NO_WORK` is additive and is what dispatch 2e keys on.

`deadhand_check` is left exactly as-is. It still runs downstream and still writes
`reason=no_work_delta` — now consistent with, rather than contradicted by, the exit code.

### 4. `plugins/leadv2/tests/test-kimi-admission-guard.sh` (to-create)

No kimi test file exists today (`grep -rl kimi tests/` → only `test-review-arm-pool.sh`, which
is unrelated). Follow the harness style of `test-review-arm-pool.sh` — same shebang,
`set -euo pipefail`, pass/fail counter, temp `PROJECT_ROOT` fixture, no network.

| # | Case | Setup | Expected observable |
|---|---|---|---|
| a | broad → skipped | mission >2500 chars, prepass artifact present | `kimi` absent from the journalled chain; `kimi_skipped reason=mission_too_broad` in the decision journal |
| b | narrow → admitted | mission <2500 chars, `writes` CSV = 1 path, no prepass artifact | `kimi` present in the chain at rung 2; no `kimi_skipped` line |
| c | no-write end_turn → bail + spill | run dir with `prompt.txt` carrying `LANE_WRITES: plugins/x.sh`, `.workbase` baseline, clean tree, child exit 0 | `KIMI_CHANNEL_NO_WORK` in `progress.log`, meta `exit_code: 78`, `status: failed` |
| d | read-only kind → NOT a bail | same, but `LANE_WRITES: docs/handoff/x.md` (or `LEADV2_MISSION_CODE=0`), clean tree, child exit 0 | `RUN_COMPLETE` present, no `KIMI_CHANNEL_NO_WORK`, meta `exit_code: 0`, `status: completed` |

Case (d) is the regression that matters most — it is the one a naive implementation of
requirement 3 breaks.

Add a fifth cheap case if the harness makes it free: `--kimi-fit` on a *broad* mission →
admitted (proves the override bypasses all three gates).

---

## Risks

| Risk | Mitigation |
|---|---|
| **v2 path bypasses the guard.** Restoring the yaml arm makes kimi reachable via `v2_eligible` (`:2192`), a code path that never touches the `case "${arm}"` ladder. Guard applied only to the legacy branch ⇒ silently unguarded on the router the system actually uses. | Filter at all three call sites (2d). Test (a) should be run with `router=v2` if the harness allows, else add a v2 variant. |
| **`skip` treated as `no`.** `work_delta_present` returns `yes/no/skip`; a `[[ != yes ]]` test would bail on every non-git or baseline-less run and permanently blackhole the arm. | Strict `== "no"` equality, stated in condition 4. Worth a comment at the call site. |
| **Bail placed after `finalize_meta`.** `finalize_meta` mv-clobbers `meta.yaml`; a later flip writes a status nobody reads. | Insertion point pinned before `:1546`, explicitly above. |
| **`no_work` recorded as a task failure.** Without 2e the ledger sees `kimi_failed_launcher` and the task's failure count rises for a channel event — re-creating the accounting that got the arm removed. | 2e tags `channel_no_work` distinctly; ledger records a channel outcome. |
| **Guard is too permissive and 19-empties recurs.** G2 fail-closed + G3 prepass-presence are the two strong signals; G1 alone is weak. | Fail-closed on missing write-set. Thresholds are env-overridable (`LEADV2_KIMI_MAX_MISSION_CHARS`, `LEADV2_KIMI_MAX_WRITES`) so a re-tightening needs no code change. |
| **Concurrent access.** The guard is pure computation over already-read locals; the detector writes only to this run's own `run_dir`. `.workbase` is per-run (`:1245` comment is explicit that a bare `git status` would mis-attribute a neighbour lane). No new race surface, no lock needed. | — |

Env-name check: all new vars use the `LEADV2_*` prefix (`LEADV2_KIMI_MAX_MISSION_CHARS`,
`LEADV2_KIMI_MAX_WRITES`), consistent with `LEADV2_REQUIRE_LANE_WRITES` / `LEADV2_MISSION_CODE`
/ `LEADV2_DEADHAND_MIN_BYTES` already in these two files. The existing `KIMI_*` codes
(`KIMI_FALLBACK_EXIT_CODE`) are pre-existing script-local constants and are reused, not renamed.
No `claude -p` invocation is introduced by this change.

---

## Non-goals

Out of scope for the implementing agent — do not touch:

- glm and codex arms, their ladders, refusal handling, or quota buckets
- `glm-coder.sh` (it has a twin of the finish-guard block; **do not** port the detector there)
- any supervisor code (`leadv2-supervise*`)
- any persona-engine file, or any file outside `~/Projects/leadv2`
- `deadhand_check` semantics, `.no-deliverable` sentinel format, `leadv2-lane-outcome.sh`
- the architect-prepass gate itself (G3 only *reads* whether its artifact exists)
- reserve/quota-ceiling logic in `leadv2-routing.yaml` beyond re-adding the arm block
- **no commit.** Leave the diff in the working tree.

---

## acceptance:

```yaml
acceptance:
  - surface: log_line
    observable: >
      In the dispatch decision journal for a task whose mission exceeds 2500 characters or
      carries an architect-prepass artifact, a line reading
      "kimi_skipped reason=mission_too_broad" appears, and the chain line printed for that
      same task lists the arms without kimi between glm and codex.
    authored_at: 2026-08-03T00:00:00Z
  - surface: log_line
    observable: >
      In the dispatch decision journal for a narrow task (short mission, one declared write
      path, no prepass artifact), the chain line lists kimi as the second arm after glm, and
      no "kimi_skipped" line appears for that task.
    authored_at: 2026-08-03T00:00:00Z
  - surface: file_artifact
    observable: >
      For a kimi run on a code-shaped mission that ends with the model reporting completion
      while the working tree is unchanged, the run's progress.log contains the line
      "KIMI_CHANNEL_NO_WORK reason=no_work_delta" and the run's meta.yaml shows status failed
      with exit code 78 — and the dispatch journal for that task shows the next arm being
      tried rather than the task being marked failed.
    authored_at: 2026-08-03T00:00:00Z
  - surface: file_artifact
    observable: >
      For a kimi run whose declared write paths are all under docs/, ending with the model
      reporting completion and an unchanged tree, the run's progress.log contains RUN_COMPLETE
      and contains no KIMI_CHANNEL_NO_WORK line, and meta.yaml shows status completed with
      exit code 0.
    authored_at: 2026-08-03T00:00:00Z
```

LANE_WRITES: plugins/leadv2/config/leadv2-routing.yaml, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/kimi-coder.sh, plugins/leadv2/tests/test-kimi-admission-guard.sh

DELIVERABLE_COMPLETE
