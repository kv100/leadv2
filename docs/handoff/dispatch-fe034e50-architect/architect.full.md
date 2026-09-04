# CORE-OFFLINE-WORKTREE-GAP-01 — architect prepass (mechanism-closed design)

Base: `9a1de41`, cwd `/Users/kostiantyn.vlasenko/Projects/leadv2` (main checkout).
All findings below are from the live tree, reproduced, not assumed.

---

## 0. Where the mission's framing is wrong (read this first)

The mission says the fanout guard test is red **in a lane worktree** because
`${PROJECT_ROOT}/.claude/scripts/` (an untracked symlink farm) exists only in the main
checkout. **Code contradicts that.** `test-fanout-classify-guard.sh` overrides
`LEADV2_PROJECT_ROOT="${sandbox}/proj"` on every invocation (lines 82, 106, 130), and that
sandbox never contains `.claude/scripts/`. So `leadv2-fanout.sh:49` **already misses in the
main checkout too** — the first branch is dead for this test in *every* environment. The
only thing keeping the test green anywhere is branch 2:
`${HOME}/.claude/leadv2-shared/scripts/leadv2-active-registry.sh`.

The real determinant is therefore **HOME, not the worktree**. Probe (reproduced now, main
checkout, clean tree):

```
$ H=$(mktemp -d); mkdir -p "$H/.claude/cache"
$ HOME="$H" bash plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh
[TEST] FAIL: Test 2: out=.../leadv2-fanout.sh: line 52: /var/folders/.../.claude/leadv2-shared/scripts/leadv2-active-registry.sh: No such file or directory
[TEST] FAIL: Test 3: ... (same)
[TEST] FAIL: Test 4: ... (same)
[TEST] === Results: PASS=1 FAIL=3 ===
```

And `run-core-offline.sh` hands the suite exactly that fixture HOME whenever
`LEADV2_SUITE_SHARDS > 1` (default `min(ncpu,4)`, `_core_offline_default_shards`,
run-core-offline.sh:375-386):

- `_core_offline_run_entry` builds `suite_home` from the **global** shard count
  (run-core-offline.sh:177), *not* from whether the entry is `SERIAL`.
- The `SERIAL` tail loop (run-core-offline.sh:456-468) calls the same
  `_core_offline_run_entry`, so the `SERIAL`-marked fanout suite
  (run-core-offline.sh:281) **also** gets a fixture HOME.
- `_CORE_OFFLINE_SCRUB_ARGS` (run-core-offline.sh:101-114) additionally `-u`'s every
  `LEADV2_*` / `CLAUDE_*` var, so `LEADV2_CANONICAL_ROOT` cannot be smuggled in from the
  caller's env either.

Consequence for the design: **the fix must not depend on `$HOME` or on
`$LEADV2_CANONICAL_ROOT` being exported by the caller.** A `SCRIPT_DIR`-sibling probe is
the only resolution that survives the scrub, the fixture HOME, and a worktree
simultaneously. The canonical copy exists at
`plugins/leadv2/scripts/leadv2-active-registry.sh` (verified on disk), which is
`${SCRIPT_DIR}` for `leadv2-fanout.sh`.

Second contradiction, item 2 of the mission — the deferred-GLM ladder is **not** an env
leak. It fails identically under fixture HOME and real HOME, i.e. it is red on main today:

```
### fixture HOME:
FAIL: (d) expected sonnet-fallback line missing from rendered artifact -- content=2026-08-20T00:00:00Z [BROAD_STATUS] dispatched=1
### real HOME:
FAIL: (d) expected sonnet-fallback line missing from rendered artifact -- content=...
  glm-deferred-ladder suite: FAIL=1
```

Details and design in §5.

---

## 1. CALLERS / CALLEES of everything this change touches

### 1a. `leadv2-fanout.sh:49-53` (the registry source)

Callees of the sourced file — what breaks if the source fails: `set -euo pipefail` is on
(fanout.sh:40) but `source` of a missing file under `-e` prints the bash error and the
script continues in the observed output (the test captured `line 52: ... No such file`
followed by no `class=` line), i.e. **the process dies before any classify/launch output**.
Functions the rest of fanout.sh needs from it: `leadv2_active_*` registry readers.

Callers of `leadv2-fanout.sh` (every entry point that inherits this defect):

| Caller | Path | Environment it runs in |
|---|---|---|
| the guard test | `plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh:82,106,130` | sandbox `LEADV2_PROJECT_ROOT`, possibly fixture HOME |
| core-offline suite | `plugins/leadv2/scripts/tests/run-core-offline.sh:281` (`SERIAL`) | fixture HOME when shards>1 |
| founder / lead fanout | interactive `leadv2-fanout.sh --n N` | real HOME, main checkout — works today |

### 1b. The independent copy nobody named — `leadv2-fanout-lane-launcher.sh:82-83`

```
plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh:82:_REGISTRY_SH="${PROJECT_ROOT}/.claude/scripts/leadv2-active-registry.sh"
plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh:83:[[ -f "$_REGISTRY_SH" ]] || _REGISTRY_SH="${HOME}/.claude/leadv2-shared/scripts/leadv2-active-registry.sh"
```

Byte-identical two-branch idiom, **on the live lane-launch path**, not just the test path.
This is the "independent copy on a different path" the closure rule asks for. It must get
the same fix or the mechanism is only half-closed: a lane launched from a worktree with an
unpopulated `$HOME/.claude/leadv2-shared` dies the same way, and *that* failure is not
caught by any test.

### 1c. Same-class survey (mission item 2 — census)

`grep -rn 'leadv2-shared/scripts\|PROJECT_ROOT}/.claude/scripts' plugins/leadv2/scripts/*.sh
plugins/leadv2/scripts/lib/*.sh` — every hit classified:

| File:line | Kind | Verdict |
|---|---|---|
| `leadv2-fanout.sh:49-50` | `source` of a helper | **FIX** — the reported failure |
| `leadv2-fanout-lane-launcher.sh:82-83` | `source` of a helper | **FIX** — same class, live path, untested |
| `leadv2-drift-guard.sh:88` | *enumerates* copy roots on purpose | safe — the shared path is the subject of the check, not a dependency |
| `leadv2-one-copy-convert.sh:39,67,76` | *converts* the shared tree | safe — same reason, and already env-overridable (`LEADV2_ONE_COPY_SCRIPTS_SHARED_ROOT`) |
| `leadv2-lanes-snapshot.sh:196` (`PHASE_BACKFILL_SH`) | optional exec, existence-guarded | safe — degrades, does not source |
| `leadv2-status.sh:37-38`, `leadv2-phase8-close.sh:529`, `leadv2-outcome-watch.sh:495`, `leadv2-shadow-apply.sh:322` | optional helper paths, all existence-guarded before use | safe — no `source`, no hard failure |
| `claude-subsession.sh:281`, `leadv2-deploy-classify.sh:33`, `leadv2-lanes-snapshot.sh:8`, `leadv2-drift-guard.sh:25` | comment / prompt text | safe — not executed |

Out of the 20 hits, exactly **two** are unguarded `source`s that hard-kill the script, and
both are in the fanout family. No other core-offline fixture depends on an untracked
`.claude/scripts` or on `$HOME` for a *sourced* file.

### 1d. `leadv2-dispatch-code.sh:5485` → `_arm_exception_bump` (ladder, §5)

- Caller: `cmd_resolve`, sonnet-landed branch, dispatch-code.sh:5471-5485.
- Callee: `_arm_exception_bump` (dispatch-code.sh:1521) → `_leadv2_arm_exceptions_path`
  (dispatch-code.sh:879) → writes `${PROJECT_ROOT}/docs/leadv2/.arm-exceptions-<UTCday>`.
- Reader on the other side of that file: `leadv2-broad-status.sh:622-638`
  (`sonnet_fallbacks_today`, `sonnet_fallback_last_reason`) → rendered at
  `leadv2-broad-status.sh:681-684`.
- `attempted[]`, the array the bump consults, is appended at dispatch-code.sh:5513 and
  :5622 only, with `${LAST_ARM_OUTCOME:-<candidate>_refused}`.

---

## 2. STATES AND RETURN CODES

### 2a. Registry resolution in `leadv2-fanout.sh` (after fix)

| # | State | Resolved to | rc | What the caller does | User-visible consequence |
|---|---|---|---|---|---|
| S1 | `${SCRIPT_DIR}/leadv2-active-registry.sh` present (normal: canonical, worktree, and the fixture case) | sibling | 0 | sources, proceeds to classify/launch | fanout prints `class=…`, dispatches |
| S2 | sibling absent, repo-vendored `${PROJECT_ROOT}/.claude/scripts/…` present | vendored | 0 | as S1 | as S1 |
| S3 | S1+S2 absent, `${LEADV2_CANONICAL_ROOT:-$HOME/Projects/leadv2}/plugins/leadv2/scripts/…` present | canonical | 0 | as S1 | as S1 |
| S4 | S1+S2+S3 absent, `${HOME}/.claude/leadv2-shared/scripts/…` present | shared | 0 | as S1 | as S1 |
| S5 | **all four absent** | — | **1** | `log_error` + `exit 1` before any launch | founder sees `[fanout] ERROR: leadv2-active-registry.sh not found (looked in: …)` and **no session is launched** — fail-closed, matching fanout.sh's stated "any doubt about session accounting refuses to launch" contract (fanout.sh:37-38) |

Today S5 is `bash: line 52: … No such file or directory` + an `-e` death with a bash-level
rc — an unattributed error with no hint of which four paths were tried. The design turns S5
into one owned diagnostic line. **rc for S5 must stay non-zero** — silently continuing
without the registry means fanout cannot count live sessions and could put two leads in one
worktree.

Terminal trace for S5 today (why lanes died): the fanout suite is one entry in
`SUITE_DEFS`; `_core_offline_run_entry` increments `FAIL`, the final line
`(( FAIL == 0 && MISSING == 0 ))` makes `run-core-offline.sh` exit non-zero, the lane's e2e
gate treats that as a red suite and **kills the lane regardless of what the lane's own diff
touched** — which is exactly the reported blast radius (5 lanes, none touching fanout).

### 2b. Guard-test hermeticity (after fix)

| # | State | Behaviour |
|---|---|---|
| T1 | staged registry copied into the sandbox `proj/.claude/scripts/` | tests 2-4 run against the sandbox root, no host dependency |
| T2 | canonical registry missing from the repo (impossible in-tree; only if someone deletes it) | test fails loudly with `SKIP-worthy` message rather than a bash `source` error |

### 2c. `_arm_exception_bump` (ladder) — rc table

| # | State | rc | Consequence |
|---|---|---|---|
| A1 | `candidate != sonnet` | not called | no counter, correct |
| A2 | `candidate == sonnet`, `_glm_quota_benched` non-empty | bump with `glm_refused_quota_precheck` | line renders |
| A3 | `candidate == sonnet`, `attempted[]` contains `glm_refused_quota_gate` / `glm_refused_postspawn_quota` | bump with that reason | line renders |
| A4 | `candidate == sonnet`, neither | **no bump** | founder-status shows **no** `sonnet-фолбэков сегодня:` line even though a GLM refusal really did fall through to sonnet — a degraded provider is invisible in the beat, which is the exact failure V3-GLM-LADDER-01 exists to prevent |
| A5 | lock timeout (`lv2_lock_wait … || exit 3`) | 3, swallowed by `|| true` | counter silently not bumped; same user-visible consequence as A4 |
| A6 | malformed existing file (no `count=`) | renderer's `int()` raises → caught, `sonnet_fallbacks_today = 0` (broad-status.sh:634-635) | line absent, no traceback — correct |

The observed ladder red is **A4**: `(a)` passes (park row carries
`reason=glm_refused_quota_gate`), `(d)` finds no rendered line, and no
`.arm-exceptions-*` file is produced anywhere in the fixture tree. So the park-row reason
and `LAST_ARM_OUTCOME`/`attempted[]` are **not the same value** on the quota-gate path.

### 2d. run-core-offline shard/serial interaction (observation, not a fix target)

`SERIAL` entries still receive a fixture HOME because `_core_offline_run_entry:177` keys off
the global `LEADV2_SUITE_SHARDS`. Changing that would give `SERIAL` suites the real HOME and
**mask** the fanout defect rather than fix it. **Explicit non-goal** (§7).

---

## 3. CONFIGURATION BOUNDARIES

Every input the fixed mechanism reads:

| Input | absent | empty | minimum | maximum / over-cap | malformed |
|---|---|---|---|---|---|
| `SCRIPT_DIR` (derived, `BASH_SOURCE[0]`) | impossible — `cd`+`pwd` at fanout.sh:43 | n/a | any real dir | n/a | if fanout.sh is invoked through a path that no longer exists, `cd` fails under `-e` → immediate exit before line 49; acceptable |
| `LEADV2_PROJECT_ROOT` / `CLAUDE_PROJECT_DIR` / `PROJECT_ROOT` | falls back to `$SCRIPT_DIR/../..` (fanout.sh:44) | same as absent (`:-` chain) | n/a | n/a | points at a non-repo dir → S2 misses, S1 already hit, no impact |
| `LEADV2_CANONICAL_ROOT` | defaults `${HOME}/Projects/leadv2` (repo-wide idiom, 20 call sites) | `:-` → default | n/a | n/a | non-existent path → S3 misses, falls to S4/S5 |
| `HOME` | bash always sets it; if unset, `${HOME}` expands empty → `/.claude/…` miss → S5 | S5 | n/a | n/a | fixture HOME (the reported case) → S1 already resolved, no impact |
| `${SCRIPT_DIR}/leadv2-active-registry.sh` file itself | S5 | zero-byte file: `[[ -f ]]` true, `source` of empty file rc 0, then the first `leadv2_active_*` call fails "command not found" → `-e` death mid-run, **after** partial output. Mitigation: probe with `[[ -s ]]` not `[[ -f ]]` in all four branches | n/a | a 39 KB file is normal (shared copy measured 39721 B); no size cap needed | syntax-broken file → `source` rc≠0 → `-e` death. Acceptable: a corrupt canonical helper is a repo-integrity failure, not a fanout failure, and it takes down only this process |
| `LEADV2_SUITE_SHARDS` (test-runner input, unchanged) | default `min(ncpu,4)` | non-numeric/`<1` → coerced to 1 (run-core-offline.sh:387-389) | 1 = pre-sharding path | >ncpu: more subshells than cores, slow but correct | already guarded |

**Blast-radius rule check.** No boundary above takes down more than the one operation it
belongs to *after* the fix: an unresolvable registry kills only the fanout invocation, and
the guard test's staged fixture means a broken host `$HOME` can no longer red the whole
core-offline suite. Before the fix it did exactly that — one missing host symlink farm
failed a whole suite and killed five unrelated lanes. That is the defect, restated.

---

## 4. COUNTEREXAMPLE — what can still violate the invariant after every listed fix

Invariant: *the core-offline suite's verdict reflects the lane's diff, not the host's
untracked state.*

Three things can still violate it. (i) The fix removes the `$HOME`/`.claude/scripts`
dependency from the two fanout entry points, but I only audited `source`/exec of
*shell helpers*; the census in §1c did not enumerate Python helpers, `config/*.yaml`
lookups, or anything a test reaches through `claude-subsession.sh`, so a fixture that reads
a host YAML through a different idiom (`LEADV2_*_BIN` defaults, `~/.claude/plugins/cache/…`
— e.g. `test-codex-quota-gate.sh:36` genuinely `find`s the real
`~/.claude/plugins/cache/openai-codex` and would red on a machine without Codex installed)
remains a live instance of the same class, out of this lane's scope but real. (ii) The
`SERIAL`-gets-a-fixture-HOME asymmetry (§2d) stays, so any *future* suite that assumes
`SERIAL` means "real environment" will reproduce this bug shape verbatim. (iii) The
`.arm-exceptions` / `founder-status` red (§5) is host-independent and pre-existing on main
— it proves the suite is not currently green on main either, which means "green on main" is
not a safe baseline for this lane and the acceptance below is written against a
before/after delta on the two named suites rather than against a whole-suite `Results: 0
failed`.

---

## 5. Ladder (mission item 2) — design

**Finding, stated plainly against the mission:** `test-glm-deferred-ladder.sh` case (d) is
red on `main`, in the main checkout, with the real `$HOME`. It is **not** an env leak and
the "existing test-env override idiom" the mission proposes does not apply. Fixing it by
making it hermetic would be fixing a symptom that does not exist.

Root cause is narrowed to **A4** in §2c: on the `glm_refused_quota_gate` path,
`_arm_exception_bump` (dispatch-code.sh:5485) never fires, so
`${PROJECT_ROOT}/docs/leadv2/.arm-exceptions-<day>` is never created and
`leadv2-broad-status.sh:681` renders no provider-health line. Evidence: `(a)` passes (park
row reason is `glm_refused_quota_gate`), `(d)` fails, and a run with a pinned `TMPDIR`
produced **zero** `.arm-exceptions-*` files anywhere in the fixture tree. The remaining
unknown is one of exactly three, and one instrumented run settles it:

1. `LAST_ARM_OUTCOME` at dispatch-code.sh:5513 is not literally
   `glm_refused_quota_gate` (the park row's reason is written from a different variable),
   so the `case` at :5477-5482 never matches → **fix: match on the same value the park row
   uses, or normalise once**;
2. `candidate` at :5471 is not literally `sonnet` in this stub path;
3. `PROJECT_ROOT` inside `_arm_exception_bump` differs from the render root (the test sets
   `CLAUDE_PROJECT_ROOT` for dispatch but `LEADV2_PROJECT_ROOT` for the renderer — two
   different variable names, and dispatch-code resolves its root at :330/:373/:384).

**Implementer's bounded diagnostic (one run, ≤2 tool calls):** re-run `(a)` with
`set -x`-equivalent tracing or a `printf` at dispatch-code.sh:5484 dumping `candidate`,
`${attempted[*]}`, `_glm_quota_benched` and `PROJECT_ROOT`; whichever of the three is wrong
names the one-line fix. Fix the **product** (dispatch-code.sh or the test's root-variable),
not the assertion — deleting or weakening the `(d)` assertion is forbidden: it is the
CLAIM-EVIDENCE-GATE-01 artifact assertion that proves a degraded provider is visible to the
founder.

If the diagnostic lands on cause 3 (root-variable mismatch), the fix is in the **test**
(use one root variable for both halves) and is legitimate; causes 1 and 2 are product bugs
in `leadv2-dispatch-code.sh` and mean the sonnet-fallback counter has been silently dead in
production since V3-GLM-LADDER-01 shipped — flag that in the summary regardless of scope.

---

## 6. The change

### C1 — `plugins/leadv2/scripts/leadv2-fanout.sh:49-53`

Replace the two-branch resolution with the repo's canonical four-branch idiom
(`leadv2-review-run.sh:47-49`, `leadv2-dispatch-product-close.sh:34,80,90`), **sibling
first**, plus a fail-closed error:

```
_REGISTRY_SH="${SCRIPT_DIR}/leadv2-active-registry.sh"
[[ -s "$_REGISTRY_SH" ]] || _REGISTRY_SH="${PROJECT_ROOT}/.claude/scripts/leadv2-active-registry.sh"
[[ -s "$_REGISTRY_SH" ]] || _REGISTRY_SH="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/leadv2-active-registry.sh"
[[ -s "$_REGISTRY_SH" ]] || _REGISTRY_SH="${HOME}/.claude/leadv2-shared/scripts/leadv2-active-registry.sh"
if [[ ! -s "$_REGISTRY_SH" ]]; then
  printf -- '[fanout] ERROR: leadv2-active-registry.sh not found (sibling/vendored/canonical/shared) — refusing to launch\n' >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$_REGISTRY_SH"
```

Ordering rationale, and it matters: sibling-first is what makes the mechanism
worktree-safe *and* fixture-HOME-safe in one move, because `SCRIPT_DIR` is the only root
that is always correct for the script actually executing. The existing
`LEAD-CONTROL-PLANE-01` comment (fanout.sh:46-48) justifies preferring the repo-vendored
copy over the *shared* original; sibling-first does not contradict it — in the canonical
repo the sibling **is** the control-plane-aware copy. Preserve that comment, amended.

The `log_error` helper is defined at fanout.sh:56, *after* line 49, so the error line must
use a raw `printf` (as written above), not `log_error`. Flagging this because the obvious
edit is to call `log_error` and it would be a `command not found` at exactly the moment the
mechanism is supposed to be loudest.

### C2 — `plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh:82-83`

Same replacement, same ordering. Without it the census is open and the live lane-launch
path keeps the defect.

### C3 — `plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh`, `_new_sandbox()`

Stage the helper into the sandbox so the test is hermetic and asserts the **vendored**
branch too:

```
mkdir -p "${d}/proj/.claude/scripts"
cp "${SCRIPTS_ROOT}/leadv2-active-registry.sh" "${d}/proj/.claude/scripts/leadv2-active-registry.sh"
```

`SCRIPTS_ROOT` is already defined (test line 35). This makes S2 the resolving branch inside
the sandbox and keeps S1 as the real-world path — both are then exercised across the suite.

### C4 — new test case in the same file: `test_5_registry_resolution_no_host_deps`

Run `--dry-run` with `HOME="${sandbox}/emptyhome"` and the sandbox `.claude/scripts` copy
removed, and assert stdout contains `class=Standard` — i.e. the sibling branch alone is
sufficient. This is the regression that would have caught today's outage; without it C1 can
be reverted silently.

### C5 — ladder, per §5

One-line product or test fix at the site the diagnostic names. Do not touch the `(d)`
assertion.

---

## 7. Non-goals (implementer: ignore these)

- Do **not** change `run-core-offline.sh` shard/`SERIAL`/HOME logic (§2d). It would mask
  the defect.
- Do **not** create, populate, or repair `~/.claude/leadv2-shared/` or any repo's
  `.claude/scripts/` symlink farm. Host state is the problem, not the fix.
- Do **not** touch the 18 "safe" census hits in §1c.
- Do **not** touch `test-codex-quota-gate.sh` / `test-codex-doc-pointer.sh` host
  dependencies (§4-i) — real, different class, out of scope; mention in the summary only.
- Do **not** weaken, skip, or delete any assertion to reach green.
- Do **not** commit the `.arm-exceptions-*` files already present under `docs/leadv2/`.
- No refactor of the registry helper itself.

## 8. Risks

| Risk | Mitigation |
|---|---|
| Sibling-first resolution shadows the repo-vendored control-plane copy in a repo where the two differ (`LEAD-CONTROL-PLANE-01`) | In this repo the sibling *is* canonical (`plugins/leadv2/scripts/leadv2-active-registry.sh` verified present). In a downstream repo, `.claude/scripts/` is a per-file symlink to canonical (global CLAUDE.md, one-copy policy), so both branches resolve to the same inode. Keep branch 2 so a genuinely divergent vendored copy still wins over canonical/shared. |
| `log_error` used before definition in the new fail-closed branch | Use raw `printf … >&2` (C1 note). |
| `[[ -s ]]` vs `[[ -f ]]` change alters behaviour for a legitimately empty helper | An empty registry helper is never valid; `-s` converts a confusing late "command not found" into an early owned error. |
| Ladder cause turns out to be a live product bug (§5, causes 1-2) and blows the lane's scope | Fix it if it is one line at the named site; otherwise report it in the summary with the diagnostic output and leave `(d)` red **with an explicit statement that it was red on main before this lane** — never claim green. |
| Suite still non-zero at the end because of an unrelated pre-existing red | Acceptance below is a per-suite delta, not a whole-suite exit code. |

---

acceptance:
  - surface: log_line
    observable: "Running the fanout guard suite with an empty fixture home prints `PASS: Test 2`, `PASS: Test 3`, `PASS: Test 4` and a final `Results: PASS=5 FAIL=0` line, where before the change the same run printed three `No such file or directory` failures naming `.claude/leadv2-shared/scripts/leadv2-active-registry.sh`."
    authored_at: 2026-08-24T13:45:00Z
  - surface: log_line
    observable: "The core-offline run performed from inside a lane worktree no longer prints `[CORE-OFFLINE] FAILED: fanout classifier/runner guard`, and its summary line reports one fewer failed suite than the same run on the base commit."
    authored_at: 2026-08-24T13:45:00Z
  - surface: log_line
    observable: "Launching fanout with every one of the four registry locations absent prints a single `[fanout] ERROR: leadv2-active-registry.sh not found` line and no session-launch line, instead of a bare bash `No such file or directory` trace."
    authored_at: 2026-08-24T13:45:00Z
  - surface: file_artifact
    observable: "For the deferred-GLM ladder: either the rendered founder-status.md written by case (d) now contains the Russian sonnet-fallback line naming the real refusal reason, or the lane's summary states in one sentence that case (d) was already red on the base commit with identical output under both a real and a fixture home, quoting both runs."
    authored_at: 2026-08-24T13:45:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-fanout.sh, plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh, plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh, plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh

DELIVERABLE_COMPLETE
