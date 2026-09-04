# BUILDER-SELFCHECK-GATE-01 — architect prepass (scoped implementation design)

Design only. No implementation. All line numbers are against HEAD `85ae886`.

---

## 1. Discovery findings that constrain the design

| Question | Answer (verified) |
|---|---|
| Where does the lane sit "after worker exit, before e2e/review"? | `leadv2-dispatch-product-close.sh:1802` `pc_scope_diff` → `:1809-1815` asked-into-void park → **`:1817` `_stamp_active_phase … e2e`**. The insertion point is between `:1815` and `:1817`. |
| Is the changed-file set available there? | Yes. `pc_scope_diff` sets globals (no `local`): `diff_root` (`:1402-1407`, lane worktree), `diff_file` (`:1381`), `_pc_base_used` (`:1386`), and `_PC_SCOPE_WRITES_CSV` (`:1344/1373`, the filtered declared write set). `WRITES_CSV` is the raw lane declaration (`:31`). |
| Canonical changed-file enumeration to copy | `:1883-1886` — `git -C "$diff_root" diff --name-only HEAD` **plus** `git ls-files --others --exclude-standard`, both with `':(exclude)docs/leadv2' ':(exclude)docs/handoff'`. Reuse verbatim; do not invent a second enumerator. |
| Is any review arm spent before `:1817`? | No. The pool resolver is first called at `:1978` (`resolve_review_pool_call`), and the `LEADV2_REVIEW_ENGINE=1` branch is at `:1936`. A gate at `:1816` therefore refuses **before any reviewer exists** — spec item 2 is satisfied structurally, and `leadv2-review-run.sh` needs no edit (respects off_limits). |
| Where is the builder mission preamble injected? | **`leadv2-dispatch-code.sh:2496-2503`, `_spawn_worker_body()`.** `WORKTREE_PIN_LINE` is prepended there *once* for all four arms (glm/kimi/sonnet/codex) — the file's own comment states this is the single insertion point chosen to avoid per-arm drift, and that it must happen **after** `compute_sig`/classify/router so `sig8` and the dedup ledger stay byte-identical. This is the file to change (the `:2224/2226` strings are the *architect* prepass mission, not the builder's). |
| Exit codes already in use by product-close | 4 = e2e blocked, 5 = review blocked / no_work / parked, 8 = e2e regression (`dead`), 6/7/9 = review-engine verdicts. **10 is free** → selfcheck_failed. |
| EXIT-trap interaction | `_pc_exit_handler` (`:181-189`) only synthesises `review-gate.md` when `_PC_REVIEW_ENTERED=1`, and only when the file is absent. Our gate runs before `_PC_REVIEW_ENTERED` is ever set **and** writes `review-gate.md` itself → no clobber, no crash-path ambiguity. |
| `phase-record.sh` phase vocabulary | **Closed enum** — `leadv2-phase-record.sh:759` "Validate phase is known", plus `case "$phase"` at `:125/:166/:401`. `selfcheck` is not a known phase and `phases.yaml` is **outside the declared write set**. → Do **not** call `leadv2-phase-record.sh` for this step (decision D4). |
| Red-first baseline pattern to copy | `tests/test-review-gate-scope-evidence.sh:221-249` — `merge-base origin/main HEAD`, then a **content probe** (`git grep -q <fix-marker> <ref> -- <file>`) that falls back to a pinned pre-fix SHA once the fix lands on `origin/main`. Runner executes each case twice (`PREFIX_SCRIPTS` = `git archive <ref>` extraction, then working tree); a case must be RED pre-fix and GREEN post-fix; counters `GREEN_PRE_FIX` / `COULD_NOT_RUN`. |
| `run-core-offline.sh` registration | `run_check "<name>" bash "$TEST_DIR/test-….sh"` lines; 51 `run_check` calls today, reported as **50 passed** (one is conditionally skipped when the `claude` CLI is unavailable, `:75`). |

---

## 2. Data flow (numbered)

1. Worker exits; product-close resolves the lane diff (`pc_scope_diff`, `:1802`) → `diff_root`, `diff_file`, `_PC_SCOPE_WRITES_CSV`.
2. Empty-diff / asked-into-void terminals fire as today (`:1802-1815`). Unchanged.
3. **NEW `builder-selfcheck` step** (`:1816`, before the `e2e` phase stamp):
   1. If `LEADV2_BUILDER_SELFCHECK != 1` → skip entirely, emit nothing, fall through (D3).
   2. Enumerate changed files in `diff_root` with the `:1883-1886` pathspec.
   3. **Scope filter:** if `${_PC_SCOPE_WRITES_CSV:-$WRITES_CSV}` is non-empty, intersect with it — the lane is checked on *its own* files only. Foreign paths are listed in `selfcheck.md` under `foreign_skipped:` and never affect the verdict (preserves 019ec29 / 85ae886 mixed-write-set semantics and the GATE-FOREIGN-FAILURE-01 lesson: a lane never dies on a fifth lane's mid-edit file).
   4. Check **A — shell syntax:** `bash -n <f>` for every changed `*.sh` (also `/bin/bash -n` for bash-3.2 parity, matching the existing suite convention).
   5. Check **B — python syntax:** `python3 -m py_compile <f>` for every changed `*.py`, with `PYTHONPYCACHEPREFIX="$tmp"` **(mandatory — see R2)**.
   6. Check **C — changed-scope tests:** suites under `plugins/leadv2/scripts/tests/` whose name matches the changed files (mapping in §4). Full `tests/run-all.sh --scope changed` only when no targeted mapping resolves **and** the e2e gate will not run it anyway (D2).
   7. Write `${HANDOFF}/selfcheck.md` (schema in §5) — always, on every branch, including infra failure.
   8. Verdict: any check rc≠0 → `RED`; all rc=0 → `GREEN`; helper missing/uncallable → `RED` with `reason: selfcheck_infra` (fail closed).
4. **Gate:** `selfcheck.md` absent **or** its `verdict:` is not `GREEN` →
   - write `${HANDOFF}/review-gate.md`: `status: blocked` / `reason: selfcheck_failed` / `verdict:` / `failed_checks:` / `artifact:`;
   - `emit decision "selfcheck_gate task=… status=ran verdict=RED failed=…"`;
   - `emit decision "review_gate task=… status=blocked reason=selfcheck_failed terminal=dead cause=selfcheck_failed"`;
   - `_dl_note dead selfcheck_failed "failed=…"`;
   - `exit 10`.
5. GREEN → `emit decision "selfcheck_gate task=… status=ran verdict=GREEN checks=…"` and fall through to `:1817` unchanged.

---

## 3. Files to change

| File | Change |
|---|---|
`plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh` *(to-create)* | Sole owner of the falsification set + `selfcheck.md` writer. One entrypoint: `leadv2_builder_selfcheck <diff_root> <handoff> <task> <writes_csv> <e2e_on>` → rc 0 GREEN / 1 RED / 2 infra (caller treats 2 as RED). Bare, self-contained: no product-close helper functions, no `emit`, no `set -e` assumptions. Overridable for tests via `LEADV2_BUILDER_SELFCHECK_LIB`.
`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | Source the lib near the `_REVIEW_FINDINGS_SH` block (`:73-75`, same canonical-root fallback pattern). Insert the ~35-line gate at `:1816`. No other edit.
`plugins/leadv2/scripts/leadv2-dispatch-code.sh` | In `_spawn_worker_body` (`:2499-2503`), prepend `SELFCHECK_MISSION_LINE` next to `WORKTREE_PIN_LINE`, gated on `LEADV2_BUILDER_SELFCHECK=1`. **After** `compute_sig` — non-negotiable, or `sig8`/dedup shifts.
`plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh` *(to-create)* | Red-first suite, 5 cases (§6).
`plugins/leadv2/scripts/tests/run-core-offline.sh` | One `run_check` line registering the new suite.

---

## 4. Interface contracts

### Env
| Var | Default | Meaning |
|---|---|---|
`LEADV2_BUILDER_SELFCHECK` | `1` | Master switch. `0` → gate and mission paragraph both vanish; no artifact, no journal line.
`LEADV2_BUILDER_SELFCHECK_LIB` | `<SCRIPT_DIR>/lib/leadv2-builder-selfcheck.sh` | Test seam only.
`LEADV2_BUILDER_SELFCHECK_TIMEOUT` | `900` | Per-suite wall clock in check C. Exceeded → that suite is `RED` with `reason: selfcheck_timeout`.
`LEADV2_BUILDER_SELFCHECK_MAX_SUITES` | `6` | Cap on check C. Dropped suites are **printed** in `selfcheck.md` under `suites_skipped_cap:` (no silent truncation).
`LEADV2_BUILDER_SELFCHECK_FULL` | `0` | `1` → run `tests/run-all.sh --scope changed` even when the e2e gate will (D2).

All five carry the mandated `LEADV2_` prefix. Grep confirmed no pre-existing `LEADV2_BUILDER_*` or `LEAD_V2_*` name in the tree to collide with.

### Helper contract
```
leadv2_builder_selfcheck <diff_root_abs> <handoff_abs> <task_sig8> <writes_csv> <e2e_on>
  rc 0 → selfcheck.md written, verdict: GREEN
  rc 1 → selfcheck.md written, verdict: RED
  rc 2 → selfcheck.md written, verdict: RED, reason: selfcheck_infra
  stdout: one line  failed=<csv-of-check-ids>  (empty on GREEN)
  never writes outside <handoff_abs> and its own mktemp -d
```

### Changed-file → suite mapping (check C)
For a changed `plugins/leadv2/scripts/<name>.sh`, candidate suites are, in order:
1. `tests/test-<name-with-leading-'leadv2-'-stripped>*.sh`,
2. any `tests/test-*.sh` whose body greps for `<name>.sh` (`grep -l`, bounded to `tests/`).
For a changed `plugins/leadv2/scripts/tests/test-*.sh` → that suite itself.
De-duplicate, sort, truncate at `MAX_SUITES`, report the truncation.

### Builder mission paragraph (exact intent, wording is the builder's)
> SELF-CHECK CONTRACT: before you report done, run your own falsification set and paste its raw output into your final report — `bash -n` on every `*.sh` you touched, `python3 -m py_compile` on every `*.py` you touched, and the test suites matching your changed files. Show the red you started from and the green you ended on. A lane whose self-check is missing or red is refused before any reviewer is seated; you will not get a review, you will get a bounce.

---

## 5. `docs/handoff/dispatch-<sig8>/selfcheck.md` schema

```
task: <sig8>
verdict: GREEN|RED
generated_at: <ISO-8601 Z>
diff_root: <abs path>
scope: lane_writes|whole_tree_fallback
checked_files: a.sh,b.py
foreign_skipped: other.sh
suites_skipped_cap: <csv or ->
failed_checks: <csv of ids, or ->

## check bash_n:plugins/leadv2/scripts/x.sh
rc: 0
<last 20 lines of raw output>

## check py_compile:…
…
## check suite:tests/test-….sh
rc: 1
<last 20 lines>
```
Every check contributes an `rc:` and a raw tail (≤20 lines each, bounded) — spec item 1c.

---

## 6. Test plan — `tests/test-builder-selfcheck-gate.sh`

Harness copied from `test-review-gate-scope-evidence.sh:221-249`: baseline = `merge-base origin/main HEAD`, **content probe** `git grep -q leadv2_builder_selfcheck <ref> -- plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` → on hit, fall back to pinned pre-fix SHA **`85ae886`**. Each case runs against `PREFIX_SCRIPTS` (must FAIL) then the working tree (must PASS); a pre-fix green increments `GREEN_PRE_FIX` and fails the suite.

| # | Case | Post-fix assertion |
|---|---|---|
1 | Lane writes a `*.sh` containing `if then fi` (syntax error) | rc 10; `review-gate.md` = `status: blocked` + `reason: selfcheck_failed`; `selfcheck.md` `verdict: RED`; **resolver-stub sentinel file absent** (proves no review arm was seated).
2 | Green lane (valid `.sh` + `.py`) | `selfcheck.md` `verdict: GREEN`; execution reaches the e2e stamp (assert via `e2e-gate.md`/journal `e2e_gate` line); rc ≠ 10.
3 | `LEADV2_BUILDER_SELFCHECK=0`, broken `.sh` | No `selfcheck.md`; no `selfcheck_gate` journal line; lane behaves as pre-fix (old terminal reached).
4 | Mixed write-set: lane writes a valid `.sh`, a **foreign** untracked `.sh` in the same tree is broken | `verdict: GREEN`; foreign path appears under `foreign_skipped:`; rc ≠ 10. (Guards 019ec29/85ae886.)
5 | `LEADV2_BUILDER_SELFCHECK_LIB` → stub that exits 0 and writes nothing | Gate still blocks: `reason: selfcheck_failed`, artifact-absent branch.

Plus the file's own `bash -n` + `/bin/bash -n` self-checks, per house convention. Fixtures use `mktemp -d` git repos + a resolver stub that *touches a sentinel* (`make_resolver_stub` pattern, `:64-70`), never the real resolver, never network, never a model.

---

## 7. Risks & mitigations

| # | Risk | Severity | Mitigation |
|---|---|---|---|
R1 | **False RED on a shared working tree.** Another lane's mid-edit `.sh` is syntactically broken; a naive "all changed files" sweep kills an innocent lane — the exact 2026-07-31 four-lane incident (GATE-FOREIGN-FAILURE-01). | CRITICAL | Scope filter (§2.3.3): only `_PC_SCOPE_WRITES_CSV ∩ changed` is checked; foreign paths are reported, never scored. Test case 4 locks it.
R2 | **`py_compile` pollutes the lane diff.** Default `py_compile` writes `__pycache__/*.pyc` beside the source → new untracked files → the e2e ownership enumerator (`:1883-1886`) and `pc_scope_diff` see writes the lane never declared → `unscoped_lane_work` bounce *caused by the gate itself*. | CRITICAL | `PYTHONPYCACHEPREFIX="$tmp"` (or `-` to a temp dir) on every `py_compile` call, and `rm -rf "$tmp"` in the helper's own trap. Assert in test case 2 that `git status --porcelain` gains no `__pycache__` entry.
R3 | **Empty write-set → whole-tree fallback.** A lane with no `LANE_WRITES` would be scored on the whole dirty tree. | HIGH | Mirror the e2e gate's precedent (`:1912-1916`): record `scope: whole_tree_fallback` in `selfcheck.md`, and in that mode restrict checks to files **modified since `_pc_base_used`**, not the whole tree. `LEADV2_REQUIRE_LANE_WRITES=1` already makes this rare.
R4 | **Duplicated test cost.** The e2e gate at `:1843` already runs `<e2e_cmd> --scope changed`; re-running the same runner in check C doubles lane wall clock for zero new signal. | HIGH | D2: check C defaults to *targeted suites* (a strict subset); the full runner branch fires only when no mapping resolves and (`E2E_ON != 1` or `LEADV2_BUILDER_SELFCHECK_FULL=1`). **This is a deliberate narrowing of spec item 1b — flagged, not silent.**
R5 | **Exit code 10 unknown to callers.** `leadv2-dispatch-code.sh` / supervisor loops may `case` on product-close's rc. | HIGH | Before shipping, grep every caller of `leadv2-dispatch-product-close.sh` for rc handling; if any has a closed `case`, either add `10` there (in-write-set only if the file is `leadv2-dispatch-code.sh`) or reuse **5** (`blocked`) with the distinguishing `reason: selfcheck_failed`. The ledger terminal (`_dl_note dead`) and `review-gate.md` are the authoritative surfaces either way.
R6 | **Phase-record enum is closed** (`leadv2-phase-record.sh:759`), and `phases.yaml` is outside the write set. | MEDIUM | D4: do **not** call `leadv2-phase-record.sh`. Use `_stamp_active_phase "$FOUNDER_TASK_ID" selfcheck` (free-text, same call shape as `:1817`) plus the ledger `emit decision` lines. Verify `_stamp_active_phase` does not itself validate before relying on it; if it does, drop the stamp and keep only `emit decision`.
R7 | **Runaway suite in check C** hangs the lane forever (no timeout today on `run-all`). | MEDIUM | `LEADV2_BUILDER_SELFCHECK_TIMEOUT` (default 900s) per suite; a timeout is RED with its own reason, so a hang converts to a fast, legible bounce. Note macOS has no GNU `timeout` by default — use a `( cmd & watchdog )` shell pattern, not `timeout(1)`.
R8 | **Recursion.** A lane whose write set *is* `tests/test-builder-selfcheck-gate.sh` will run that suite in check C; that suite in turn spawns product-close fixtures with the flag on. | MEDIUM | The fixtures always set an explicit `LEADV2_BUILDER_SELFCHECK_LIB`/flag value and run in `mktemp -d` repos, so nesting terminates at depth 1. Add `LEADV2_BUILDER_SELFCHECK_DEPTH` guard (unset→1, ≥1→skip check C) if depth-2 is ever observed.
R9 | **`selfcheck.md` is not crash-proof.** If the helper is SIGKILLed mid-write, the file exists but is truncated → gate reads no `verdict:` → blocks. | LOW | Write to `selfcheck.md.tmp.$$` then `mv -f` (the atomic pattern already used at `:2443-2448`). Absent/partial both land on `blocked`, which is the fail-closed direction the spec wants.
R10 | **`run-core-offline` count changes.** Acceptance says "stays 50/0"; registering a 52nd `run_check` makes it **51 passed / 0 failed**. | LOW | Read the acceptance as *zero failures, zero missing*. The builder must state the new number explicitly in its report (`51/0`) rather than quietly "confirming 50/0" — otherwise the count itself becomes a lie.
R11 | **Concurrent access to `${HANDOFF}`.** The lane worker may still be flushing files while the gate reads them. | LOW | The gate runs strictly after worker exit is confirmed (product-close's own contract, header `:1-8`) and after `pc_scope_diff`. `selfcheck.md` has exactly one writer (this helper) and one reader (this gate) in the same process. No lock needed; documented per checklist item 4.

### Mandatory checklist results
1. **Env naming** — all new vars `LEADV2_*`; no `LEAD_V2_*` drift; no collision found in `.claude/settings.json` or the scripts tree.
2. **Paths** — every path in §3 exists on disk except the two marked *(to-create)*.
3. **`claude -p`** — this change introduces **no** `claude -p` invocation. N/A.
4. **Concurrency** — R11, R1.
5. **Config contradiction** — no existing consumer of the five new names; `LEADV2_E2E_OWNERSHIP` semantics (lane-writes scoping) are *reused*, not contradicted.

---

## 8. Out of scope (implementer: ignore)

- `plugins/leadv2/scripts/leadv2-review-run.sh` — **do not open**. The gate sits before both the engine branch (`:1936`) and the inline body, so no edit is needed.
- Review pool / arm selection / quota gates / `leadv2-review-signals.sh` / `leadv2-e2e-ownership.sh`.
- e2e suite *content*, `leadv2-e2e-entrypoint.sh`, `leadv2-e2e-root.sh`.
- `phases.yaml` / `leadv2-phase-record.sh` (R6/D4).
- Retro-fitting `selfcheck.md` onto already-closed lanes; any change to `review-gate.md`'s pass/fail schema; any change to the findings renderer.
- Docs under `docs/leadv2/` and `docs/handoff/` (never in `LANE_WRITES`).

## 9. Decisions taken (source: architect(self-check))

- **D1** New exit code `10` for `selfcheck_failed`; fallback to `5` if a caller's `case` is closed (R5).
- **D2** Check C defaults to targeted suites, not the full changed-scope runner — deliberate narrowing of spec 1b, rationale in R4, override `LEADV2_BUILDER_SELFCHECK_FULL=1`.
- **D3** `LEADV2_BUILDER_SELFCHECK=0` emits **nothing at all** (no `disabled` journal line), to honour "byte-for-byte" literally.
- **D4** No `leadv2-phase-record.sh` call for the new step (closed enum, file out of scope).
- **D5** Foreign changed files are reported and excluded from the verdict, never scored (R1).

---

acceptance:
- surface: file_artifact
  observable: For a lane whose own changed shell script contains a syntax error, `docs/handoff/dispatch-<sig8>/review-gate.md` reads `status: blocked` with `reason: selfcheck_failed`, and `docs/handoff/dispatch-<sig8>/selfcheck.md` shows `verdict: RED` with the offending file's `bash -n` error text under its `## check bash_n:<file>` heading — while no `critic.full.md` / reviewer deliverable exists anywhere for that lane.
  authored_at: 2026-08-19T08:30:14Z
- surface: log_line
  observable: The task journal shows `selfcheck_gate task=<sig8> status=ran verdict=RED` immediately followed by `review_gate task=<sig8> status=blocked reason=selfcheck_failed`, with no `review_pool_resolve` line for that task between them.
  authored_at: 2026-08-19T08:30:14Z
- surface: file_artifact
  observable: For a green lane, `docs/handoff/dispatch-<sig8>/selfcheck.md` shows `verdict: GREEN` listing every checked file with `rc: 0`, and the lane's `e2e-gate.md` / review artifacts exist as before; with `LEADV2_BUILDER_SELFCHECK=0` no `selfcheck.md` is produced at all and the lane's artifacts are indistinguishable from today's.
  authored_at: 2026-08-19T08:30:14Z

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
