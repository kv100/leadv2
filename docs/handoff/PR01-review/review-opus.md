LABEL=critic-dispatch-PLUGIN-RELIABILITY-01-review-1786562178 SESSION_ID=9e89e16b-4e3f-46ca-8f90-92cfd388647d
--- body from: docs/handoff/dispatch-PLUGIN-RELIABILITY-01-review/critic.full.md ---
# critic — PLUGIN-RELIABILITY-01 round 2 (build-r2.diff)

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=1 high=4 medium=4 low=3

FINDING: severity=Critical file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=1494 dimension=correctness desc=_pc_reap_worker called with ${HANDLE} where the signature requires <run_dir>, so the timeout reap reads no pgid/.lockref and never kills the lock-holding __supervise process
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=813 dimension=correctness desc=pgid files hold a setsid process-GROUP id but are killed as bare pids (kill -TERM "$pid" not -"$pid"), so only the group leader dies and the model child keeps burning quota
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=891 dimension=correctness desc=new "meta.yaml absent -> return 0" grace branch shadows the _PC_ASKED_INTO_VOID terminal-evidence branch at line 913, making legacy no-meta runs wait the full 4200s ceiling
FINDING: severity=High file=plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh line=699 dimension=correctness desc=D2/D4/D5 are grep-on-source or inline re-implementations; pc_worker_alive and claude-subsession.sh are never executed, so the grace guard and the worktree fallback have zero behavioral coverage despite the summary claiming otherwise
FINDING: severity=High file=plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh line=436 dimension=correctness desc=TASK is never set despite the header comment claiming it is, so _pc_reap_worker's SIGKILL-escalation path (which expands ${TASK}) would abort the suite under set -u — that path is consequently untested

---

## Verification method

The diff was not applied to the main checkout; I reviewed against
`.claude/worktrees/PLUGIN-RELIABILITY-01/` (post-patch line numbers below refer to
that tree) and cross-checked every claim against `glm-coder.sh`, which owns the
spawn-record files the new helpers read.

Suite run (bash 5.3, post-patch worktree): `passed=21 failed=0` — green, and the
green is not load-bearing for three of the five defects (see H3).

---

## Critical

### C1 — `_pc_reap_worker` is called with a handle where it requires a run_dir
**File:** `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:1494` and `:1516`
**Category:** correctness

```bash
_pc_reap_worker "${HANDLE}" "$(_pc_meta_value "${_PC_RUNS_ROOT:-${RUNS_ROOT:-${ROOT}}}/${AUTHOR}-runs/${HANDLE}/meta.yaml" pid 2>/dev/null)"
```

The function the same diff introduces is declared `_pc_reap_worker() { # <run_dir> [meta_pid]`
(line 783) and the in-loop call site at line 885 correctly passes `"${run_dir}"`.
These two timeout call sites pass the bare handle string. Consequences, all silent:

- `${run_dir}/pgid` → `<handle>/pgid` — never exists, so the `__run_child` process is never collected.
- `${run_dir}/.lockref` → never exists → `_repo_hash` empty → **the whole lock_dir branch is skipped**, so `lock_dir/pid` — the `__supervise` process that holds the GLM lock, i.e. the entire reason this reap exists — is never collected.
- `dirname "${HANDLE}"` → `.`, so `_runs_dir` is the CWD.

Only the meta pid can ever be reaped here, and that is the `glm-coder.sh start`
process which by this point has normally already exited. So on the
`worker_timeout` path — the exact path the incident report describes — the reap
is a no-op and the lock stays held for the next lane. D1 is unfixed for the
timeout case.

Second defect on the same lines: the meta path is hand-built instead of using
`_pc_run_dir_for` (defined at line 514, and used correctly 16 lines earlier at
line 530 for `_PC_ASKED_INTO_VOID`). `_pc_run_dir_for` honors `GLM_RUNS_DIR` /
`KIMI_RUNS_DIR`; the hand-built path does not. Any run under a non-default
`GLM_RUNS_DIR` (which the hermetic suites set) resolves `meta_pid` to empty, so
the reap degrades from "partial" to "total no-op".

**Required fix:**
```bash
_pc_rd="$(_pc_run_dir_for "${AUTHOR}" "${HANDLE}")"
_pc_reap_worker "${_pc_rd}" "$(_pc_meta_value "${_pc_rd}/meta.yaml" pid)"
```
at both 1494 and 1516. Add a test that asserts a live pid written to
`<run_dir>/.lockref`-derived `lock_dir/pid` is killed **via the timeout path**,
not only via a direct `_pc_reap_worker` call.

---

## High

### H1 — `pgid` values are process-GROUP ids, killed as bare pids
**File:** `leadv2-dispatch-product-close.sh:813, 824` (reap) and `:757, 767` (alive)
**Category:** correctness

`glm-coder.sh:1294-1301` writes the **setsid'd** child into `run_dir/pgid` and
`lock_dir/pgid`:

```bash
setsid_wrapper "${SELF}" __run_child "${run_dir}" >>"${run_dir}/child.log" 2>&1 &
local child_pid=$!
echo "${child_pid}" > "${run_dir}/pgid"
```

Because it is setsid'd, that value is a process-group leader, and every other
consumer in the codebase treats it as a group — `glm-coder.sh:351-356`:

```bash
if [[ -n "${lock_pgid}" ]] && kill -0 -"${lock_pgid}" 2>/dev/null; then
  kill -TERM -"${lock_pgid}" 2>/dev/null || true
  sleep 5
  kill -KILL -"${lock_pgid}" 2>/dev/null || true
```

Note the leading `-` on every signal. The new code drops it:
`kill -TERM "${_pid}"` / `kill -KILL "${_pid}"` / `kill -0 "${_pid}"`. This kills
only the group leader; the actual model process (`claude`/glm CLI) running inside
that group survives as an orphan and keeps burning quota — which is the symptom
the task was opened to fix. `_pc_process_alive` has the mirror-image bug: it
reports **dead** when the leader has exited but the group is still running, which
then drives `terminal=dead` on a live worker.

**Required fix:** track pid-sourced and pgid-sourced values separately. For
pgid-sourced values use `kill -0 -"$g"`, `kill -TERM -"$g"`, `kill -KILL -"$g"`;
keep bare-pid semantics for `meta.yaml pid` and `lock_dir/pid` only. Test with a
victim that spawns a `setsid` child and assert the *child* dies, not just the
leader.

### H2 — the new grace branch shadows `_PC_ASKED_INTO_VOID` terminal evidence
**File:** `leadv2-dispatch-product-close.sh:890-912` (new block) vs `:913`
**Category:** correctness

The inserted block:
```bash
if [[ -z "${status}" && "${registry_alive}" == 0 ]]; then
  if [[ ! -f "${meta}" ]]; then
    return 0
  fi
  ...
```
sits immediately *above*:
```bash
# The coder writes this only from its finish guard. It is terminal provider
# evidence for legacy runs that predate meta.yaml, once no exact registry or
# process evidence remains.
[[ -n "${_PC_ASKED_INTO_VOID:-}" && -f "${_PC_ASKED_INTO_VOID}" && "${registry_alive}" == 0 ]] && return 1
```

The comment on line 911-912 says in as many words that this branch is for runs
**that have no meta.yaml**. The new `[[ ! -f "${meta}" ]] → return 0` makes that
branch unreachable for exactly those runs: `pc_worker_alive` now returns 0 on
every poll forever, so the gate burns the full 4200s ceiling and then writes a
false `terminal=dead cause=timeout` row. This is the same failure class D4 claims
to fix, newly introduced for the legacy path. It also applies to any run whose
`run_dir` has been GC'd.

**Required fix:** move the `_PC_ASKED_INTO_VOID` check above the new empty-status
block, or fold it into the `! -f "${meta}"` arm (`if void-marker present → return 1`).

### H3 — three of five defects have no behavioral coverage, contradicting the summary
**File:** `plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh:585-763`
**Category:** correctness (test coverage)

The summary (`docs/handoff/PLUGIN-RELIABILITY-01/summary.md:57-69`) states "Complete
test rewrite… No grep-on-source tests (the lying-green disease)" and lists
"Grace guard: fresh meta → not dead; old meta → dead-eligible" and
"agents_worktree_fallback frontmatter stripped correctly" as behavioral. They are not:

- **D4 (lines 699-751):** test 1 is `grep -B15 'empty_status_pid_gone' "$src" | grep -q '! -f.*meta'` — grep-on-source. Tests 2 and 3 re-implement `stat -f %m` / `_meta_age_s` arithmetic **inline in the test** and assert on the test's own copy. `pc_worker_alive` is never called. The entire new branch, including the H2 regression above, is uncovered — H2 would not have been caught by any of these 3 assertions.
- **D2 (lines 616-674):** the block advertised as "Full integration: run claude-subsession.sh in a simulated worktree" never runs `claude-subsession.sh`. It re-implements the `ROLE_SOURCE` derivation inline, and because `${TMP_ROOT}/wt` is not a git repo, `git rev-parse --git-common-dir` fails and the test **hardcodes `_main_checkout="${fake_main}"` — the exact value the production code is supposed to compute**. The real fallback expression (`cd "$PROJECT_ROOT" && cd "$_common_dir/.."`) is never executed. `git init -q "${fake_main}"` on line 626 is dead setup.
- **D3 (678-696) and D5 (754-763):** pure `grep -q` on source.

Only the D1 tests (lines 439-582) are genuinely behavioral, and they are good —
they spawn real victims and assert real kills. Per the review contract, a new
logic branch with no test coverage is blocking.

**Required fix:** for D4, source `pc_worker_alive` (or the file with a stubbed
`_pc_job_registry_has_handle` / `_pc_meta_value`) and assert `rc` for the four
states: no meta → 0; meta <30s → 0; meta >30s → 1; void-marker present, no meta →
1 (H2). For D2, invoke `claude-subsession.sh` against a real `git worktree add`
sandbox with `--dry-run`-equivalent env, and assert the rendered system prompt
contains no `^role:` line.

### H4 — `TASK` unbound; the SIGKILL-escalation path is untested and would abort the suite
**File:** `plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh:418-436`
**Category:** correctness

Header comment, lines 418-419:
> `The functions use: $$, $PPID, $TASK, ...` / `We provide emit as a no-op stub and TASK as a test sentinel.`

`TASK` is never assigned anywhere in the file. It is expanded by
`_pc_reap_worker`'s final line (`emit decision "product_close task=${TASK} worker_reaped ..."`,
source line 826), and the suite runs under `set -uo pipefail`. Verified:

```
$ bash -c 'set -uo pipefail; f(){ echo "task=${TASK}"; }; f; echo AFTER'
bash: line 1: TASK: unbound variable
outer_rc=127
```

An unbound expansion under `set -u` terminates the whole shell, not just the
function. The suite passes only because every victim (`sleep 300`) dies on
SIGTERM, so the 5s wait loop and the `kill -KILL` escalation — the branch that
reaches the `emit` — are never entered. That is precisely the branch most likely
to matter in production (a wedged model process that ignores TERM).

**Required fix:** set `TASK=plugin-reliability-test` before the eval, and add a
victim installed with `trap '' TERM` so the 5s escalation and the `kill -KILL`
path actually execute.

---

## Medium

### M1 — `local -A` violates the file's own documented bash-3.2 invariant
**File:** `leadv2-dispatch-product-close.sh:748, 785, 787`

The same file, at lines 1243-1247, records the decision:
> `M8/M9 (LANDING-BLOCKER-R2): no associative arrays -- declare -A hard-errors under bash 3.2, and dispatch-code.sh resolves bash from PATH, which can be /bin/bash 3.2 without homebrew on PATH`

The new helpers introduce three `local -A`. Verified on the shipped
`/bin/bash 3.2.57`:

```
$ /bin/bash -c 'f(){ local -A s=( ["$$"]=1 ); }; f'
/bin/bash: line 0: local: -A: invalid option
local: usage: local name[=value] ...
```

Behavior happens to survive — the `local` builtin fails but the compound
assignment still lands, and because every subscript is a numeric pid it degrades
into an equivalent sparse *indexed* array (I confirmed `${_skip[$$]}` is `1` and
`local -A _seen=()` still resets). But:
1. `_pc_process_alive` runs on **every poll** of `pc_worker_alive` for up to 4200s, so this emits two stderr lines per poll — thousands of `invalid option` lines into the close-gate log.
2. Because `local` failed, `_skip` and `_seen` leak to **global** scope.
3. It is a knowing regression against a written prior decision in the same file.

**Fix:** use the two-parallel-indexed-array idiom already present at lines
1249-1252, or the cheaper `case " ${_skip} " in *" ${_pid} "*) ;; esac` string form.

### M2 — the parked-prepass question is unanswerable and un-deduped
**File:** `leadv2-dispatch-code.sh:3110-3116`

The ask offers `retry|Retry prepass` / `abort|Abort task` with
`--default-option retry`, then `exit 3` runs unconditionally two lines later and
nothing ever reads the answer. A founder who picks "retry" gets no effect — the
control plane now carries a question that cannot change any outcome. There is
also no idempotency key: every re-entry into `cmd_resolve` for the same parked
task writes another record to the questions dir.

**Fix:** either make it informational (single `ack|Acknowledged` option), or wire
a consumer for the answer. Either way, guard the write on the absence of an
existing open question for `dispatch-${sig8}`.

### M3 — the D3 negative assertion is vacuous
**File:** `test-plugin-reliability-01.sh:684`

```bash
if grep -q '\-\-no-block' "$src" && ! grep -q 'prepass.*--timeout 1800' "$src"; then
```
`grep` is line-oriented and the round-1 code had `--timeout 1800` on a
continuation line that contains no `prepass`, so the negative arm could never
have matched even before the fix — it cannot detect the regression it exists to
detect. The positive arm matches `--no-block` anywhere in a 3600-line file, not
in the prepass block.

**Fix:** assert on the extracted prepass-park block (`awk` between the
`architect_prepass ... status=parked` emit and the `exit 3`), not on the whole file.

### M4 — `_pc_process_alive` and `_pc_reap_worker` duplicate the pid-collection logic
**File:** `leadv2-dispatch-product-close.sh:746-777` vs `783-812`

~25 lines of identical meta/pgid/lockref reading exist twice and have **already**
diverged in structure (one short-circuits, one accumulates). H1's fix has to be
applied to both, and any future source added to one will be missed by the other.

**Fix:** extract `_pc_collect_worker_pids <run_dir> [meta_pid]` that prints the
live pids one per line; `_pc_process_alive` becomes `[[ -n "$(_pc_collect_worker_pids "$@")" ]]`.

---

## Low

- **L1 — `$PPID` exclusion is broader than the bug requires** (`:748, 785`). The round-1 Critical was self-match via `pgrep -f`; only `$$` needs excluding. Excluding `$PPID` means that if the close gate is ever launched as a child of `__supervise`, a live worker is silently reported dead. Advisory: drop `$PPID` or comment why it is required.
- **L2 — misplaced stderr redirect** (`claude-subsession.sh:172`). `"$(cd "$PROJECT_ROOT" && cd "$_common_dir/.." && pwd 2>/dev/null || true)"` attaches `2>/dev/null` to `pwd`, not to the `cd` that can fail. A failing `cd` prints to stderr and `pwd` then returns the wrong directory. Benign today (the subsequent `-f` test fails and the script exits 1 as intended), but the redirect is on the wrong command.
- **L3 — unverified green in the summary** (`summary.md:87`). "test-no-work-terminal (42/1 — the 1 failure is pre-existing 'revived waited to timeout')" ships a known-red suite with a prose exemption and no baseline reference. Name the commit at which that assertion was already failing, or the claim is unfalsifiable.

---

## Type/lint evidence

No Python or TypeScript in this diff — `mypy`/`tsc` are not applicable. Shell
evidence instead:

```
$ bash -n leadv2-dispatch-product-close.sh; echo $?   → 0
$ bash -n leadv2-dispatch-code.sh;          echo $?   → 0
$ bash -n claude-subsession.sh;             echo $?   → 0
$ bash tests/test-plugin-reliability-01.sh
[PLUGIN-RELIABILITY-01] passed=21 failed=0

$ /bin/bash --version | head -1
GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)
$ /bin/bash -c 'f(){ local -A s=( ["$$"]=1 ); echo ok; }; f'
/bin/bash: line 0: local: -A: invalid option
local: usage: local name[=value] ...
ok

$ bash -c 'set -uo pipefail; f(){ echo "task=${TASK}"; }; f; echo AFTER'
bash: line 1: TASK: unbound variable
(outer rc=127 — shell terminated, "AFTER" never printed)
```

Note that `passed=21 failed=0` is reproduced under `/bin/bash 3.2` as well —
the suite is green on both, and green on neither H1 nor H2.

**VERDICT: BLOCK** — 1 Critical, 4 High.

DELIVERABLE_COMPLETE
