Product implementation task dispatch-9c027877. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# BUILDER-SELFCHECK-GATE-01 — architect prepass (scoped design)

Authored against HEAD `85ae886`. No implementation performed.

---

## 1. Where this lands (exact insertion points, verified on disk)

| # | File | Anchor (HEAD 85ae886) | Change |
|---|------|-----------------------|--------|
| A | `plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh` **(to-create)** | — | New helper lib: `lv2_selfcheck_run` |
| B | `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | source block at `:73-75`; gate body inserted after the `asked_into_void` park block ending `:1815`, **before** `_stamp_active_phase "${FOUNDER_TASK_ID}" "e2e"` `:1817` | source lib + new gate step |
| C | `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | the fixed mission suffix appended in `cmd_resolve` at `:3610-3632` (the `QUESTION-CHANNEL-DEAD-01` block, appended **after** the sig is computed) | one additional paragraph |
| D | `plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh` **(to-create)** | — | red-first suite |

The gate sits **after** `pc_scope_diff` (`:1802`) — so `${diff_file}` and `${diff_root}` already
exist and every empty/undiffable/unscoped outcome has already exited — and **before** both the
e2e stage and the review engine (`:1943 _ENGINE_BIN`). That is the only point that satisfies
"after worker exit, before the e2e/review stages" while still having a diff to read.

---

## 2. Data flow (numbered)

1. `pc_await_worker_exit` returns; `pc_scope_diff` writes `${HANDOFF}/review.diff` and exits on
   every no-work/undiffable/unscoped class. Anything past this point has real bytes.
2. New step reads `LEADV2_BUILDER_SELFCHECK` (default `1`). `0` → skip entirely, emit nothing,
   fall through to `_stamp_active_phase … e2e` byte-for-byte as today.
3. `lv2_selfcheck_run "${diff_file}" "${diff_root}" "${ROOT}" "${HANDOFF}/selfcheck.md"`:
   1. **Changed-path extraction** — parse `^\+\+\+ b/(.*)$` from `${diff_file}`, drop `/dev/null`
      (deletions: nothing to compile), dedupe. Path resolution order: `${diff_root}/<p>` →
      `${ROOT}/<p>` → each repo listed in `${HANDOFF}/review.diff.repos`. Unresolvable →
      recorded `SKIP (unresolved_path)`, **never RED** (cross-repo lanes must not be punished
      for a path this gate cannot see — same principle as `cross_repo_elsewhere`).
   2. **C1 syntax/sh** — `bash -n <f>` for every resolved `*.sh`.
   3. **C2 syntax/py** — `python3 -m py_compile <f>` for every resolved `*.py`
      (`PYTHONPYCACHEPREFIX` pointed at a temp dir so no `__pycache__` lands in the lane
      worktree and dirties it — a dirty lane is a real failure mode here, see Risk R4).
   4. **C3 suites** — see §4 (dedup-with-e2e decision).
   5. Writes `${HANDOFF}/selfcheck.md`: header, one row per check (`name · rc · target`), the
      last ~40 lines of raw output per non-zero check, and a final `verdict: GREEN|RED` line.
   6. rc `0` = GREEN, `1` = RED, `2` = degraded (lib present but could not run any check).
4. **GREEN** → emit `selfcheck task=<T> status=green checks=<n> skipped=<k>`; continue to e2e
   unchanged.
5. **RED, or `selfcheck.md` absent after a run that was supposed to write it** →
   * `${HANDOFF}/review-gate.md`:
     ```
     status: blocked
     reason: selfcheck_failed
     kind: <diff|report>
     base: <_pc_base_used>
     failed: <comma-joined check names, capped via _pc_join_capped>
     selfcheck: docs/handoff/dispatch-<TASK>/selfcheck.md
     ```
   * `emit decision "review_gate task=${TASK} status=blocked reason=selfcheck_failed terminal=refused cause=selfcheck_failed failed=<csv>"`
   * `_dl_note refused selfcheck_failed "failed=<csv>"`
   * `_stamp_review_terminal blocked` ; `exit 5`
   No e2e run, no review arm, no `_ENGINE_BIN` invocation — the exit is upstream of both.

**Terminal word:** `refused` (existing ledger vocabulary, retryable, already the word for
"lane-fault but re-dispatchable"). **No new terminal word is introduced** — `reason`/`cause`
carry the diagnosis, exactly as `unscoped_lane_work` / `declared_no_bytes` do today.

---

## 3. Interface contract — `lv2_selfcheck_run`

| Item | Value |
|---|---|
| Signature | `lv2_selfcheck_run <diff_file> <diff_root> <project_root> <out_md>` |
| stdout | comma-joined names of failed checks (empty when GREEN) |
| rc | `0` GREEN · `1` RED · `2` degraded (no check could run) |
| Writes | `<out_md>` only. Never touches the index, working tree, or ledger. |
| Reads env | `LEADV2_BUILDER_SELFCHECK_TESTS` (`auto`\|`always`\|`never`, default `auto`), `LEADV2_BUILDER_SELFCHECK_TIMEOUT_S` (default `900`), `LEADV2_BUILDER_SELFCHECK_MAX_FILES` (default `200`) |
| Purity | No `emit`, no `_dl_note`, no `exit`. All ledger/terminal side effects stay in product-close, so the lib is unit-testable standalone. |

`selfcheck.md` contract (this is the artifact a human and the gate both read):

```
# builder selfcheck — dispatch-<sig8>
generated_at: <ISO-8601Z>
diff_root: <path>
checks: <n>   failed: <k>   skipped: <s>

| check | target | rc |
|-------|--------|----|
| bash -n | plugins/leadv2/scripts/foo.sh | 0 |
| py_compile | plugins/leadv2/scripts/lib/bar.py | 1 |
| suites | tests/run-all.sh --scope changed | 0 |

## raw — py_compile plugins/leadv2/scripts/lib/bar.py (rc=1)
<last 40 lines>

verdict: RED
```

---

## 4. Decision D2 — suite check vs. the e2e stage (read this one)

The e2e stage already runs `${e2e_cmd} --scope changed` (`:1843`), and in *this* repo
`leadv2-e2e-entrypoint.sh` resolves to `tests/run-all.sh` — i.e. spec item 1(b) is, on the
default path, **the same command the very next stage runs**. Implementing it literally doubles
lane wall-clock for zero added blocking power (both stages sit before the review arm).

Resolution — `LEADV2_BUILDER_SELFCHECK_TESTS`:

* `auto` (default): if `LEADV2_E2E_GATE` is on **and** `leadv2-e2e-entrypoint.sh "${diff_root}"`
  resolves a command, record the suite row as `SKIP (delegated_to_e2e)` and note the delegate
  command in `selfcheck.md`. Syntax checks (the cheap, dominant failure class) still run and
  still block before e2e. Suite failures still block before any review arm — via the existing
  e2e gate, one stage later.
* `always`: run the suites in-selfcheck regardless (use when e2e is off in a consuming repo, or
  to prove the suite path in tests).
* `never`: syntax-only.
* When no e2e entrypoint resolves (a repo without one), `auto` behaves as `always` — falling
  back to stem-matched `plugins/leadv2/scripts/tests/test-<stem>.sh` for each changed file when
  `tests/run-all.sh` is absent, exactly as spec 1(b) describes.

This preserves the mission outcome ("no review arm is spent on a diff that fails mechanical
checks") without paying the runner twice. Flagging it explicitly because it is a deliberate,
visible deviation from a literal reading of spec 1(b).

---

## 5. Builder mission preamble (item 3)

Appended in `leadv2-dispatch-code.sh:cmd_resolve`, immediately after the existing
async-question block, guarded by `[[ "${LEADV2_BUILDER_SELFCHECK:-1}" != 0 ]]` so the
kill-switch restores the mission text byte-for-byte:

> Before you finish, run your own falsification set and paste its raw output into your final
> report: `bash -n` every shell file you changed, `python3 -m py_compile` every Python file you
> changed, and the repo's changed-scope test runner. Show the red output you got and the green
> output after your fix. A lane whose self-check is missing or red is refused before any
> reviewer is spent on it — you will have burned the lane for nothing.

The suffix is appended **after** the dedup sig is computed (`:3610` comment states this
explicitly), so lane dedup identity is unchanged. Verified: this is the single injection point
every product lane's mission passes through.

---

## 6. Test plan — `tests/test-builder-selfcheck-gate.sh`

Red-first, content-probe baseline per `test-review-gate-scope-evidence.sh`, with the `85ae886`
lesson applied: probe the `git archive` baseline tree for `lv2_selfcheck_run`; if present (the
fix has landed on the baseline ref), fall back to the **pinned floor `85ae886`**. Never
`git stash`/`reset`/`clean`.

| Case | Setup | Baseline (must FAIL) | Fixed (must PASS) |
|---|---|---|---|
| 1 | lane writes a `*.sh` with a syntax error | reaches e2e/review | `review-gate.md` `reason: selfcheck_failed`, exit 5 |
| 2 | same lane, review-arm sentinel | sentinel created | **sentinel absent** — no review arm spent |
| 3 | clean lane, valid `.sh` + `.py` | — | `selfcheck.md` `verdict: GREEN`, gate not triggered |
| 4 | changed `*.py` failing `py_compile` | reaches e2e/review | blocked `selfcheck_failed` |
| 5 | `LEADV2_BUILDER_SELFCHECK=0` + broken `.sh` | old path | old path — no `selfcheck.md`, no `selfcheck_failed` event |
| 6 | report-only lane (`kind: report`) | — | GREEN, `checks: 0`, not blocked |

Case 2 uses a stubbed `LEADV2_REVIEW_RUN_BIN` that `touch`es a sentinel — that env var is
already the engine's override hook (`:1943`), so **`leadv2-review-run.sh` is not read or edited**
(off_limits honoured).

`run-core-offline.sh` is **not** modified — this is an integration suite, so its 50/0 stays 50/0.
`bash -n` + `shellcheck` clean on every touched file is part of the lane's own dogfooded
selfcheck.

---

## 7. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Fail-closed bricks every lane** if the helper lib is missing (plugin/cache skew). | Source with the canonical-fallback pattern already at `:73-75`. If *neither* path exists → `emit selfcheck status=degraded reason=lib_missing` and **continue** (infrastructure fault ≠ lane fault; same rule as "e2e root failure is blocked, never dead"). "Artifact absent → blocked" applies when the lib *ran* and produced nothing. Deliberate, narrow deviation from spec 2. |
| R2 | Hung suite hangs the lane. | `LEADV2_BUILDER_SELFCHECK_TIMEOUT_S` (900) wrapping the suite run; rc 124 → RED with `cause=selfcheck_timeout` in `selfcheck.md`. |
| R3 | Cross-repo lane: diff paths not resolvable under `diff_root`. | Three-tier resolution then `SKIP (unresolved_path)` — never RED. Directly protects the 019ec29/85ae886 mixed-write-set semantics. |
| R4 | `py_compile` writing `__pycache__` into the lane worktree makes it dirty and perturbs later dirty-based classifiers. | `PYTHONPYCACHEPREFIX=<mktemp -d>` for the compile; temp dir removed on return. (`lib/__pycache__` already exists in-tree — do not add more.) |
| R5 | Double runner cost. | D2 `auto` delegation, §4. |
| R6 | A changed generated/vendored `.py` that legitimately fails `py_compile` blocks a good lane. | `LEADV2_BUILDER_SELFCHECK_MAX_FILES` cap + `selfcheck.md` names the exact file and rc, so the operator's escape is one env flip, not a debugging session. Rollback is `LEADV2_BUILDER_SELFCHECK=0`. |
| R7 | Concurrent access: `${HANDOFF}/selfcheck.md`. | Single writer (product-close, one process per lane) after `pc_await_worker_exit` — the worker is provably dead. No lock needed. |

**Constraint checklist:** env vars all `LEADV2_*` ✓ · every path above exists or is marked
`(to-create)` ✓ · no `claude -p` invocation introduced (n/a) ✓ · concurrency R7 ✓ · no
conflicting env semantics found (`LEADV2_BUILDER_SELFCHECK*` is a new namespace) ✓.

---

## 8. Out of scope (implementing agent: ignore)

* `leadv2-review-run.sh` — **not read, not edited**. Arm/pool/quota logic untouched.
* e2e suite content, `leadv2-e2e-entrypoint.sh`, `leadv2-e2e-ownership.sh`, `lib/leadv2-e2e-root.sh`.
* Ledger vocabulary — no new terminal word; `refused` + `cause=selfcheck_failed`.
* `run-core-offline.sh` registration.
* `shellcheck` as a selfcheck (syntax only — style findings must never block a lane).
* Retry/auto-fix of a RED selfcheck. The lane is refused; re-dispatch is the lead's call.

---

## 9. acceptance

```yaml
acceptance:
  - surface: file_artifact
    observable: >
      docs/handoff/dispatch-<sig8>/review-gate.md opens with "status: blocked" and
      "reason: selfcheck_failed", and names the failing file on its "failed:" line,
      for a lane whose only defect is a shell file that will not parse.
    authored_at: 2026-08-19T00:00:00Z
  - surface: file_artifact
    observable: >
      docs/handoff/dispatch-<sig8>/selfcheck.md exists for every closed lane and ends
      with a line reading either "verdict: GREEN" or "verdict: RED", listing one table
      row per check with its return code and the raw tail of any failing check.
    authored_at: 2026-08-19T00:00:00Z
  - surface: log_line
    observable: >
      The task journal shows a "review_gate ... reason=selfcheck_failed terminal=refused"
      line for the broken lane, and shows no review-arm start line after it — the reviewer
      was never spent.
    authored_at: 2026-08-19T00:00:00Z
  - surface: file_artifact
    observable: >
      With LEADV2_BUILDER_SELFCHECK=0 the same broken lane produces no selfcheck.md and a
      review-gate.md identical in every line to the one today's code writes.
    authored_at: 2026-08-19T00:00:00Z
```

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# BUILDER-SELFCHECK-GATE-01 — builder must prove its own diff before review

## Outcome (one)
The build lane cannot reach review without a green machine self-check. The builder runs a
falsification set BEFORE the diff is submitted, and the gate refuses a lane whose self-check
artifact is missing or red.

## Spec
1. New lane step in the product-close flow (leadv2-dispatch-product-close.sh), after worker
   exit and before the e2e/review stages: `builder-selfcheck` —
   a) `bash -n` every changed *.sh; `python3 -m py_compile` every changed *.py;
   b) run the repo's changed-scope test runner (tests/run-all.sh --scope changed when present,
      else plugins/leadv2/scripts/tests/ suites matching changed files);
   c) write docs/handoff/dispatch-<sig8>/selfcheck.md: per-check rc + raw tail; verdict GREEN/RED.
2. Gate rule: selfcheck RED or selfcheck.md absent → lane blocked with reason=selfcheck_failed
   BEFORE any review arm is spent (this is the whole point: stop paying reviewers for diffs
   that fail mechanical checks).
3. Builder mission preamble (the template product lanes inject) gains one paragraph: run your
   falsification set and paste red/green output; your lane is refused without it.
4. Env kill-switch LEADV2_BUILDER_SELFCHECK=0 restores today's behavior byte-for-byte (default 1).

## Premise (2026-08-19)
65% of first reviews FAIL (190/293 journal events); many findings are mechanical (syntax,
dead tests, vacuous suites) that a self-check catches for free. Founder-approved batch item 2.

## Write set
plugins/leadv2/scripts/leadv2-dispatch-product-close.sh · plugins/leadv2/scripts/lib/** (new helper ok)
· plugins/leadv2/scripts/tests/** (new suite) · the lane-mission preamble template (find it; likely
under plugins/leadv2/scripts or skills — cite the file you change).

## Non-goals / off_limits
- leadv2-review-run.sh (another lane may touch it — do NOT edit).
- No changes to review pool/arm selection, quota gates, or e2e suite content.
- Do not conflict with commits 019ec29/85ae886 semantics (mixed write-set handling).

## Acceptance
- New red-first suite: lane with failing bash -n → blocked reason=selfcheck_failed, no review arm
  invoked; lane with green selfcheck proceeds; kill-switch=0 restores old path. Prove each RED first
  against a pinned pre-fix baseline (content-probe pattern, see test-review-gate-scope-evidence.sh).
- run-core-offline.sh stays 50/0. bash -n + shellcheck clean.

## Rollback
LEADV2_BUILDER_SELFCHECK=0 (one flip) or single revert.

## Terminal artifact
Commit on lane branch + selfcheck.md of your OWN lane (dogfood) + raw red/green + DELIVERABLE_COMPLETE.

## Dispatch note
Retry 2 (2026-08-19): first lane 9aa06fd5 died worker_timeout after 4091s (Codex arm) with no diff; re-dispatching fresh.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-9c027877" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.