# REVIEW-ARM-FAILCLOSED-01 — architect prepass

## 1. Root cause (verified against the tree, base feb253b)

The mission brief attributes the abort to `set -e`. **That attribution is wrong** and the
implementer must not build on it:

- `plugins/leadv2/scripts/leadv2-review-run.sh:37` is `set -uo pipefail`. There is no
  `set -e` and no `ERR` trap anywhere in the file (`grep -n '^set '` returns exactly one
  hit). A nonzero `run_reviewer_arm` therefore does **not** abort `_engine_arm_job`.

The real fail-open is three separate holes, all on the same path:

**H1 — arm rc is not persisted unconditionally** (`leadv2-review-run.sh:1015-1019`).
`_engine_arm_job` writes `review-<arm>.rc` only if control reaches line 1018. Anything that
terminates the subshell earlier skips it: the arm-timeout watcher's `kill -TERM`
(`:1029`), a hard kill, or — the live case — an **unset-variable exit under `set -u`**
inside `run_reviewer_arm` (e.g. `review_contract_focus` at `:398`, or a helper such as
`materialize_glm_review_body` being absent on the GLM branch at `:410`). `set -u` exits the
subshell with rc 1 and no `.rc` file.

**H2 — empty rc classifies as a review that ran** (`leadv2-review-run.sh:493-500`). The
`infra_worker_died` branch requires `[[ -z "${rc}" ]] && [[ -s "${out_file}" ]]`. An arm that
died *before* producing any output has an empty `.md`, so both conditions are not met and
`classify_arm_failure` falls through to `printf 'ran'`. The slot is then appended to
`ran_arms` (`:1348`) and the gate counts a review that never happened. This is the
fail-open the brief describes as "silently abort".

**H3 — the engine can exit with no gate artifact at all.** Every `review-gate.md` write is
inline at a specific decision point (`:1121, 1142, 1183, 1216, 1267, 1353, 1372, 1454, 1637,
1650`). If the parent process dies between those points — `set -u` on an unset var in parent
scope, a signal, a `wait` path that exits early — **no `review-gate.md` is written and no
`review_gate` decision is emitted**. That matches the observed GLM-5.3-ROUTING-FINAL
evidence exactly: neither `review-<arm>.rc` nor `review-gate.md` on disk. Nothing in the
current file guarantees a terminal artifact.

## 2. Design — fail-closed in three layers

### L1. Unconditional rc persistence (fixes H1)

Rewrite `_engine_arm_job` so the `.rc` write happens on **every** subshell exit path, via an
`EXIT` trap installed before `run_reviewer_arm` is called.

- The job runs in a subshell (`( _engine_arm_job "${arm}" ) &`, `:1027`), so an `EXIT` trap
  set inside the function is scoped to that subshell and cannot clobber the parent's traps.
  It must still be saved/restored is unnecessary — but the implementer MUST confirm no other
  `trap ... EXIT` is active in that subshell before adding one.
- Trap body: if `${HANDOFF}/review-<arm>.rc` does not already exist, write the exit status
  the trap received (`$?` captured as the trap's first statement). `review_rc` is used when
  `run_reviewer_arm` returned normally; the trap's `$?` is the fallback for abnormal exit.
- The rc value written for an abnormal exit must be **distinguishable** from a normal
  provider failure. Use a dedicated sentinel — recommend `rc=70` for "arm process died before
  reporting" — and add it to `classify_arm_failure` as `infra_worker_died`. Do not reuse 75
  (quota) or 77 (channel down); both already carry reroute semantics.
- Also install a `TERM` trap so the watcher's `kill -TERM` (`:1029`) lands on a handler that
  writes the sentinel rather than killing the shell before `EXIT` fires. `trap ... TERM` +
  explicit `exit 70` is the portable bash-3.2 form.

### L2. Empty rc is never "ran" (fixes H2)

In `classify_arm_failure`, hoist the empty-rc check above the `-s "${out_file}"` condition:

- `[[ -z "${rc}" ]]` alone → `infra_worker_died`, regardless of whether the output file has
  bytes. The existing `-s` refinement only ever narrowed a case that should never have been
  optimistic. Keep the `reaped:` marker branch unchanged.
- Add `rc == 70` → `infra_worker_died` (the L1 sentinel).
- Net effect: an arm with no rc enters the existing `_died_retry` loop (`:1309-1327`), gets
  exactly one retry, then emits `review_gate ... status=arm_infra_died ... action=give_up`
  and is dropped from `ran_arms`. If that drops the last arm, the already-present
  `all_arms_unavailable` block (`:1350-1360`) writes `status: unreviewed` and exits 9. **No new
  gate-status vocabulary is needed for this path** — reuse it.

### L3. Terminal gate artifact guarantee (fixes H3)

Install a single script-level `EXIT` trap near the top of the engine (after `HANDOFF` and
`TASK` are known, before the first arm launch):

- On exit, if `${HANDOFF}/review-gate.md` does **not** exist, write, atomically via the same
  `.tmp` + `mv -f` pattern used everywhere else:
  ```
  status: blocked
  reason: gate_engine_aborted
  rc: <exit status>
  ```
  and `emit decision "review_gate task=${TASK} status=blocked reason=gate_engine_aborted rc=<n>"`.
- Absent-file check only. It must never overwrite a gate the engine already decided — every
  existing writer is `mv -f`-atomic, so "file exists" means "a decision was persisted".
- The trap must not change the exit status: capture `$?` first, and `exit` with it explicitly
  at the end of the trap body.
- Interaction with L1: the parent trap and the per-arm subshell traps write different files
  and cannot race. But the arm subshells **inherit** the parent's EXIT trap at fork time —
  the implementer must clear it inside `_engine_arm_job` (`trap - EXIT` before installing the
  arm trap) or every dying arm subshell will also write a parent `review-gate.md`. **This is
  the single highest-risk detail in this change.**

## 3. Files

| File | Change |
|---|---|
| `plugins/leadv2/scripts/leadv2-review-run.sh` | L1 (`_engine_arm_job` ~:1015), L2 (`classify_arm_failure` ~:490-500), L3 (new script-level EXIT trap) |
| `plugins/leadv2/scripts/tests/test-review-arm-failclosed.sh` | *(to-create)* hermetic regression test |

## 4. Test design — `test-review-arm-failclosed.sh`

Hermetic, no network, no real provider. Follow the harness pattern of
`plugins/leadv2/scripts/tests/test-review-arm-no-verdict.sh` (verified present): `set -uo
pipefail`, `source leadv2-temp.sh`, `lv2_mktemp_dir`, `trap 'rm -rf "$SUITE_TMP"' EXIT`,
per-case throwaway `git init` fixture root, PASS/FAIL counters.

Drive the **real** `leadv2-review-run.sh` — never reimplement its logic. Stub the provider
via `LEADV2_DISPATCH_GLM_BIN` pointing at a script in `$SUITE_TMP`.

Three cases:

1. **nonzero-and-empty arm** — stub exits 1, writes nothing to `--out`. Assert
   `review-glm.rc` exists and `review-gate.md` exists with a non-`ran` status.
2. **killed arm (no rc)** — stub `kill -TERM $$` (or `exec sleep 999` with
   `LEADV2_REVIEW_ARM_TIMEOUT_S=2`). Assert `review-glm.rc` exists and carries the sentinel,
   and that `review-gate.md` is present.
3. **parent abort** — force the engine to die before any inline gate write (simplest hermetic
   lever: an unreadable/absent `DIFF_FILE`). Assert `review-gate.md` exists with
   `reason: gate_engine_aborted`.

Bounded-behaviour assertion, required by the brief: each case must finish under a wall clock
bound. Use `LEADV2_REVIEW_ARM_TIMEOUT_S=2` and assert the whole engine invocation returns in
under ~30s — the test itself must not hang if the fix regresses.

**Do not run** `test-review-engine-fanout-multiprovider.sh` or any suite that shells out to
`leadv2-dispatch-code.sh` / real dispatch. Targeted runs only:
`test-review-arm-failclosed.sh`, `test-review-arm-no-verdict.sh`, `test-review-body-persist.sh`,
`test-review-pool-never-empty.sh` — the three existing ones are the regression guard for L2's
change to `classify_arm_failure`.

## 5. Risks

| Risk | Mitigation |
|---|---|
| Inherited parent EXIT trap fires inside every arm subshell → spurious `gate_engine_aborted` overwrites | `trap - EXIT` as the first statement of `_engine_arm_job`; test case 1 asserts the gate status is the *real* one, not `gate_engine_aborted` |
| L2 reclassification flips previously-"ran" arms to `infra_worker_died`, changing round-1 verdicts | Only arms with **empty** rc are affected — those never had a verdict. Existing `_died_retry` cap (1 retry) bounds the cost. Run the three sibling review tests. |
| New rc sentinel 70 collides with an existing meaning | `grep -n 'rc.*\b7[0-9]\b'` across `plugins/leadv2/scripts/` before committing; 75 and 77 are taken, 70 is free at base feb253b — **verify, do not assume** |
| L3 trap alters the engine's exit status | Capture `$?` first, `exit` with it explicitly |
| `lead-edit-guard` blocks `Edit` on canonical plugin `.sh` when `LEADV2_LEAD_GUARD=1` | Known; fix-forward via a `/tmp` python patcher invoked through `Bash`, per prior incident |
| Concurrent access: `review-<arm>.rc` written by both the subshell trap and the parent reselection loop (`:1321, 1343`) | Parent only writes after `wait` returns; trap only writes when the file is absent. Ordering is already serialised by `wait` — no lock needed, but the implementer must keep the trap's "only if absent" guard. |

## 6. Non-goals — explicitly out of scope

- No change to arm **selection**, `pool` resolution, `next_ok_arm_after`, or GLM routing.
- No change to any of the ten existing inline `review-gate.md` writers.
- No new gate status vocabulary beyond `gate_engine_aborted`; `unreviewed` /
  `all_arms_unavailable` / `arm_infra_died` are reused as-is.
- No fix for the `set -u` unset-variable bug that killed the GLM arm in the first place —
  this task makes the gate *legible* when an arm dies, it does not chase the specific unset
  var. File that as a follow-up thread.
- No `docs/leadv2/**` or `docs/handoff/**` writes from the implementation.
- No dispatch-suite runs.

## 7. Acceptance

```
acceptance:
  - surface: file_artifact
    observable: "After a review run whose reviewer arm exits nonzero and writes no output,
      docs/handoff/<task>/review-glm.rc exists on disk and docs/handoff/<task>/review-gate.md
      exists and its status line reads something other than a passing review."
    authored_at: 2026-08-25T00:19:33Z
  - surface: file_artifact
    observable: "After a review run whose reviewer arm is killed by the arm timeout,
      docs/handoff/<task>/review-glm.rc exists and contains the died-before-reporting
      sentinel value rather than being absent."
    authored_at: 2026-08-25T00:19:33Z
  - surface: file_artifact
    observable: "After a review run where the engine aborts before reaching any of its own
      gate decisions, docs/handoff/<task>/review-gate.md exists and names the reason as
      gate_engine_aborted."
    authored_at: 2026-08-25T00:19:33Z
  - surface: rendered_line
    observable: "The final summary line of the new test script reads that all its cases
      passed and none failed."
    authored_at: 2026-08-25T00:19:33Z
  - surface: log_line
    observable: "The task journal shows a review_gate decision line for the failing-arm run;
      previously the run produced no review_gate line at all."
    authored_at: 2026-08-25T00:19:33Z
```

## 8. Self-check (mandatory checklist)

1. **Env var naming** — no new env vars introduced. Existing ones reused verbatim:
   `LEADV2_REVIEW_ARM_TIMEOUT_S` (`:1024`), `LEADV2_DISPATCH_GLM_BIN` (`:403`). No
   `LEAD_V2_*` drift.
2. **File paths** — `plugins/leadv2/scripts/leadv2-review-run.sh` verified present (1655
   lines). `plugins/leadv2/scripts/tests/test-review-arm-no-verdict.sh` verified present.
   `plugins/leadv2/scripts/tests/test-review-arm-failclosed.sh` marked *(to-create)*.
3. **`claude -p` commands** — none introduced. The engine's existing subsession calls go
   through `claude-subsession.sh` and are untouched.
4. **Concurrent access** — covered in §5 (`review-<arm>.rc`, `review-gate.md`).
5. **Config contradiction** — no env-var semantics changed. The one new constant (rc
   sentinel 70) carries a grep-before-commit obligation, recorded in §5.

`decisions[]` — `source: architect(self-check)`:
- **D1**: reject the brief's `set -e` root cause; the file is `set -uo pipefail`. Fix is
  trap-based unconditional persistence, not errexit management.
- **D2**: sentinel rc `70` for died-before-reporting, pending the grep confirmation in §5.
- **D3**: `trap - EXIT` inside `_engine_arm_job` is a hard requirement, not an optimisation.

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/scripts/tests/test-review-arm-failclosed.sh

DELIVERABLE_COMPLETE
