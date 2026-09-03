# LANE-REGISTRY-SELF-DEADLOCK-01 — fix-round prepass (e2e_regression, fanout helper resolution)

Mechanism-closed design. No implementation performed.

## 0. Discovery contradicts the mission's framing — state it plainly

The mission says **one** test fails (`test-fanout-classify-guard.sh` Test 4) and implies the
lane's change caused it ("your change makes fanout load / resolves via `$HOME`"). Both halves
are wrong, and designing to the mission's framing would produce an incomplete fix.

**Fact 1 — three tests fail, not one.** Reproduced on the lane worktree
(`.claude/worktrees/8e705910`, HEAD `f933fb5`) with an empty fixture HOME, exactly what
`run-core-offline.sh:176-186` gives a sharded suite:

```
$ H=$(mktemp -d); HOME="$H" bash plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh
[TEST] PASS: Test 1: bash -n OK (fanout + classify + session-runner)
[TEST] FAIL: Test 2: out=.../leadv2-fanout.sh: line 52: /var/folders/.../tmp.fKfytylJAj/.claude/leadv2-shared/scripts/leadv2-active-registry.sh: No such file or directory
[TEST] FAIL: Test 3: out=... (identical)
[TEST] FAIL: Test 4: out=... (identical)
[TEST] === Results: PASS=1 FAIL=3 ===
```

Tests 2, 3 and 4 all invoke the real `leadv2-fanout.sh` and all die on the same line before any
assertion is exercised. Test 4 is simply the last one named in the failure report.

**Fact 2 — the lane did not cause this.** `git diff HEAD~1 --stat -- plugins/leadv2/scripts/leadv2-fanout.sh`
is empty; the lane's wip commit `f933fb5` touches `leadv2-active-registry.sh`,
`leadv2-dispatch-code.sh`, `leadv2-lane-liveness.sh` and four test files, never `leadv2-fanout.sh`.
The defect is pre-existing in `leadv2-fanout.sh:49-52` and is exposed by
`LEADV2_SUITE_SHARDS>1` (private HOME), not by the lane. In serial mode
(`run-core-offline.sh:174` — "Keep serial mode byte-for-byte") the real `$HOME` is used, the
shared copy exists, and the suite is green. This is a **latent hermeticity hole in fanout's
helper resolution**, and the design targets that.

**Fact 3 — the same defect exists in a second, independent copy nobody named.**
`leadv2-fanout-lane-launcher.sh:82-85` carries a byte-identical two-branch chain. It is a
different process on a different path (the detached per-lane launcher, exercised by
`plugins/leadv2/tests/test-fanout-lane-detach.sh` Part B), so fixing only `leadv2-fanout.sh`
leaves the identical failure armed on the lane-launcher path. This is the classic
"independent copy that nobody named" miss and is in scope.

**Fact 4 — the stated rationale for the current order is stale.** The comment at
`leadv2-fanout.sh:44-48` prefers `$PROJECT_ROOT/.claude/scripts/` because "the shared original
still hardcodes docs/leadv2/active.yaml". That is no longer true — both copies resolve through
`leadv2-state-path.sh`:

```
plugins/leadv2/scripts/leadv2-active-registry.sh:56-64      _leadv2_yaml_file() -> resolver active.yaml
~/.claude/leadv2-shared/scripts/leadv2-active-registry.sh:55-63  identical body
```

So reordering the chain carries no active.yaml-location regression.

**Fact 5 — on the real machine today, fanout runs the WRONG copy.**
`~/Projects/leadv2/.claude/scripts/leadv2-active-registry.sh` **does not exist** (verified:
`ls` → No such file). Therefore every real fanout run in the canonical repo falls through to
`~/.claude/leadv2-shared/scripts/leadv2-active-registry.sh` (39721 bytes, mtime Aug 17), which
this session's start hook already flags as a one-copy REGRESSION real file. That copy has no
`leadv2_active_set_worker_pid` — i.e. the lane's own LANE-REGISTRY-SELF-DEADLOCK-01 registry op
is invisible to fanout and to the lane-launcher on the production path. The SCRIPT_DIR-first
fix closes that gap as a side effect; it is the strongest argument for the reorder, and it is
not a cosmetic test fix.

---

## 1. CALLERS / CALLEES

### 1.1 The mechanism under change

Two independent resolution sites, both resolving one helper (`leadv2-active-registry.sh`)
and both `source`-ing it at file scope under `set -euo pipefail`.

| Site | file:line | Current chain | Fails when |
|---|---|---|---|
| A | `plugins/leadv2/scripts/leadv2-fanout.sh:49-52` | `$PROJECT_ROOT/.claude/scripts/` → `$HOME/.claude/leadv2-shared/scripts/` | neither exists → `source` on missing path → `set -e` → rc 1 at line 52 |
| B | `plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh:82-85` | identical | identical |

Both sites run **before** `log()` / `log_error()` are defined (`leadv2-fanout.sh:54-55`), so the
current failure surfaces as a bare bash `No such file or directory`, with no `[fanout]` prefix
and no actionable hint. Any fail-closed message the fix adds must therefore use raw `printf`,
not `log_error`.

### 1.2 Callees — what the sourced file provides, and who consumes it

Sourcing defines the registry function family. Consumers inside site A (verified by grep, all
in `leadv2-fanout.sh`):

- `leadv2_active_set_worktree` — :1154, :1178, :1269, :1325, :1339, :1368, :1456, :1472
- `leadv2_active_set_writes` — :1514, :1824
- `leadv2_active_set_attempt` — :1904
- `leadv2_active_unregister` — :1683, :1725, :1910, :1915, :1926, :1932
- `leadv2_active_register` / `leadv2_active_check_limits` — via the Gate1 reserve path (:1027 comment, :282)

Every one of these calls is `|| true` / `>/dev/null 2>&1`-guarded, i.e. **the whole registry
surface in fanout is already best-effort**. Only the `source` itself is fatal. That asymmetry
(fatal load, non-fatal use) is the defect's shape.

Consumers inside site B: `leadv2-fanout-lane-launcher.sh` uses the same family plus
`leadv2-tasks-lib.sh` (sourced at :87 from `${SCRIPT_DIR}` — note the launcher **already** uses
the SCRIPT_DIR idiom for its other helper on the very next line; only the registry line drifts).

### 1.3 Callers of the two sites

| Caller | Path | Effect of an rc-1 at the source line |
|---|---|---|
| `test-fanout-classify-guard.sh` Tests 2/3/4 | `run-core-offline.sh:280` (SERIAL entry, but private-HOME when `LEADV2_SUITE_SHARDS>1`) | 3 of 4 assertions never run; suite rc 1 → e2e gate red |
| founder / lead, interactive `leadv2-fanout.sh --tasks …` | real HOME | today: silently sources the **stale shared** copy (Fact 5) |
| `test-fanout-lane-detach.sh` Part B (`plugins/leadv2/tests/`, :26, :134) | invokes `LAUNCHER_SH` directly | same latent failure under a private HOME |
| `leadv2-dispatch-code.sh` | **not a caller** — it references the launcher only in comments (:2808, :3073, :4836) and sources its own registry via `${SCRIPT_DIR}` (:500, :4919-4920), i.e. dispatch-code is already correct and is the idiom to copy |

Different-path note: site A (fanout selection/funnel) and site B (detached per-lane launcher)
are **separate processes on separate paths**. Neither inherits the other's resolution. A fix
applied to A only leaves B armed.

---

## 2. STATES AND RETURN CODES

### 2.1 Resolution states, current vs designed

| # | State | Current behaviour | Designed behaviour | Caller consequence (designed) |
|---|---|---|---|---|
| S1 | helper next to the script (`$SCRIPT_DIR`) exists — normal repo/plugin/worktree run | **not consulted** | source it; rc 0 | fanout runs the canonical, current registry (gains `set_worker_pid`) |
| S2 | `$SCRIPT_DIR` miss, project override exists (`$PROJECT_ROOT/.claude/leadv2-overrides/scripts/`) | not consulted | source it; rc 0 | project override honoured, matching `lv2_script()` order (`leadv2-helpers.sh:83-108`) |
| S3 | legacy vendored copy exists (`$PROJECT_ROOT/.claude/scripts/`) | branch 1, preferred | branch 3 | unchanged behaviour for repos that still vendor |
| S4 | only canonical root has it (`$LEADV2_CANONICAL_ROOT` / `~/Projects/leadv2/plugins/leadv2/scripts/`) | not consulted → falls to S5/S6 | branch 4; rc 0 | a foreign-repo fanout still gets a current registry |
| S5 | only `$HOME`-shared has it | branch 2 (frequently the live path today, Fact 5) | branch 5, **last** | preserved as a floor; no behaviour loss for legacy installs |
| S6 | **no branch resolves** (fixture HOME + sandbox PROJECT_ROOT) | bare bash error, rc 1, at line 52, before `log_error` exists | explicit fail-closed: `printf '[fanout] ERROR: leadv2-active-registry.sh not found in: <5 paths tried>'` + `exit 1` | fanout refuses to launch, loudly, with the tried paths — same fail-closed posture as the documented header ("Fail-CLOSED: any doubt about session accounting refuses to launch") |
| S7 | a branch resolves but the file is unreadable / syntactically broken | `source` aborts under `set -e`, rc = bash's (1 or 2), no message | unchanged — deliberately not caught | fanout refuses to launch; a corrupt registry must never be papered over |
| S8 | a branch resolves but is an **older** registry lacking `leadv2_active_set_worker_pid` | silent; callers `|| true` | unchanged (branch order makes it far less likely); dispatch-code already guards with `declare -F leadv2_active_set_worker_pid` (`leadv2-dispatch-code.sh:3750`) | worker-pid stamp skipped; lane liveness keeps trusting the lead pid — the exact LANE-REGISTRY-SELF-DEADLOCK-01 symptom, see §4 |

### 2.2 Return codes the mechanism can emit, and what the caller does

| rc | Emitted when | Immediate caller | Terminal user-visible consequence |
|---|---|---|---|
| 0 | S1–S5: a branch resolved and sourced cleanly | fanout continues to the drift-guard preflight (:71+) | normal — tasks are selected and lanes launch |
| 1 (designed, S6) | no branch resolved | `test-fanout-classify-guard.sh` captures stdout+stderr and asserts on substrings; a human sees the message on stderr | **A human running `leadv2-fanout.sh` sees `[fanout] ERROR: leadv2-active-registry.sh not found …` and no lane is launched** — instead of today's unattributed `line 52: … No such file`. In CI the suite prints the same line as the failure body. |
| 1/2 (S7) | resolved file unparseable | same | fanout aborts; no lanes launched; bash's own syntax error is the message |
| — | `source` never partially succeeds | — | there is no half-loaded state: bash aborts at the first error under `set -e`, so no caller ever sees a registry with some functions defined and others missing |

**Terminal trace for the failing-today case.** rc 1 at `leadv2-fanout.sh:52` propagates to
`test-fanout-classify-guard.sh`'s `out="$( … )" || true`, so the test does **not** abort — it
compares `$out` against its expected substring, mismatches, and calls `fail`. `main()` then
exits 1 (`test-fanout-classify-guard.sh:156-160`), `run-core-offline.sh` counts the suite as
FAIL, and the e2e gate refuses the lane. In plain words: **the lane cannot close, and the
reason printed to the founder names a temp-directory path that does not obviously belong to
any test — which is why this round exists at all.**

---

## 3. CONFIGURATION BOUNDARIES

Inputs the mechanism reads. All five are consumed at file scope, before argument parsing.

### 3.1 `$HOME`

| Boundary | Behaviour (designed) |
|---|---|
| absent / empty | `${HOME}/…` expands to `/.claude/leadv2-shared/…`; branch 5 misses; earlier branches still resolve (S1) → **no failure**. Today: guaranteed rc 1. |
| set to an empty fixture dir (the actual CI case) | branch 5 misses; branch 1 (`$SCRIPT_DIR`) hits → rc 0. This is the fix. |
| set to real `$HOME` | branch 1 still wins; the stale shared copy is no longer sourced (Fact 5 — an intended behaviour change) |
| malformed (contains spaces/newlines) | all path expansions are quoted (`"${HOME}/…"`); `[[ -f ]]` is safe; no word-splitting |

### 3.2 `$PROJECT_ROOT` / `$LEADV2_PROJECT_ROOT` / `$CLAUDE_PROJECT_DIR`

Resolved at `leadv2-fanout.sh:42` with a `$SCRIPT_DIR/../..` fallback, so it is **never empty**.

| Boundary | Behaviour |
|---|---|
| points at a sandbox with no `.claude/` (the test case) | branches 2 and 3 miss; branch 1 hits |
| points at a repo with a **stale** vendored `.claude/scripts/` copy | branch 3, reached only after branches 1–2 miss. Since fanout ships inside `plugins/leadv2/scripts/`, branch 1 effectively always wins for in-repo runs, so a stale vendored copy can no longer shadow canonical — a strict improvement |
| points at a nonexistent path | `[[ -f ]]` on branches 2/3 is false, not an error; branch 1 still hits |
| over-long / deeply nested | no cap anywhere in the chain; `[[ -f ]]` returns false past PATH_MAX rather than erroring |

### 3.3 `$SCRIPT_DIR`

Computed at `leadv2-fanout.sh:41` via `cd "$(dirname "${BASH_SOURCE[0]}")" && pwd` under
`set -e`; if that `cd` fails the script is already dead before the chain. Cannot be empty or
malformed at the point of use.

### 3.4 `$LEADV2_CANONICAL_ROOT`

| Boundary | Behaviour |
|---|---|
| unset | defaults to `${HOME}/Projects/leadv2`, the repo-wide idiom (`leadv2-drift-guard.sh:58`, `leadv2-plugin-sync.sh:84`, `leadv2-dispatch-code.sh:520`, and seven more sites) |
| set to a path without the plugin tree | branch 4 misses, chain continues to branch 5 |
| set to `""` | `${LEADV2_CANONICAL_ROOT:-…}` treats empty as unset → default applies (`:-`, not `-`) — required, since an empty value would otherwise probe `/plugins/leadv2/scripts/…` |
| set to a hostile path | out of scope: anyone who can set this env var can already set `PATH`; no new trust boundary is crossed |

### 3.5 The helper file itself

| Boundary | Behaviour |
|---|---|
| absent everywhere | S6 → loud fail-closed, exit 1 (**scoped to this one fanout invocation** — it does not touch active.yaml, does not unregister anything, and cannot affect any already-running lane) |
| present but zero-byte | `source` succeeds, defines nothing; every consumer is `|| true`-guarded except the Gate1 reserve path. Accepted risk, unchanged from today — see §4 |
| present but not executable | irrelevant; `source` needs read, not exec. Chain tests `-f`, not `-x`, deliberately |
| present as a dangling symlink | `[[ -f ]]` follows symlinks → false → next branch. Correct |
| two branches present and divergent | first match wins, silently. Mitigation is `leadv2-drift-guard.sh`, which fanout already runs at :71-80 — not this mechanism's job |

**Blast-radius check (per the prepass rule that an over-cap/malformed input must not take down
more than its own operation):** every failure mode above is confined to the single
`leadv2-fanout.sh` (or launcher) process. No branch writes state, takes a lock, or mutates
`active.yaml` before the chain resolves. S6's `exit 1` happens before the drift-guard preflight
and before any registration, so no lane is left half-registered.

---

## 4. COUNTEREXAMPLE — what still violates the invariant after every finding here is fixed

The invariant this mechanism protects is: *a fanout process must run against the same registry
implementation as the dispatcher it launches, or refuse to run.* After the fix, three things
can still violate it.

**(a) Version skew is still silent, not refused.** The chain proves a registry exists, never
that it is the *current* one. If branch 1 misses in some deployment and branch 5 hits the
Aug-17 shared copy, fanout sources a registry with no `leadv2_active_set_worker_pid`; every
call site is `|| true` or `declare -F`-guarded, so nothing errors — the worker-pid stamp is
simply skipped and `leadv2-lane-liveness.sh` keeps treating the lead session's durable pid as
lane-liveness evidence. That is precisely the LANE-REGISTRY-SELF-DEADLOCK-01 symptom the lane
exists to fix, re-entering through a path the lane never touched. A capability assertion after
the source (`declare -F leadv2_active_set_worker_pid` → warn loudly and name the resolved path)
would close it; I am **not** proposing it in this round because it is a behaviour change beyond
the e2e-gate scope and belongs in its own task. Recorded as a follow-up, not silently dropped.

**(b) The real machine's one-copy regression is untouched.** `~/.claude/leadv2-shared/scripts/`
holds ~15 real files that should be symlinks (this session's start hook enumerated them). The
fix stops *fanout* from reading them; every other consumer of that tree keeps its stale view.
Out of scope here — it is a one-copy remediation task.

**(c) A zero-byte or truncated registry still loads clean.** `source` on an empty file succeeds.
Nothing in the chain distinguishes "present" from "usable". Same mitigation as (a).

What I checked and found nothing on: partial-source states (impossible under `set -e`),
ordering races between the two sites (they are separate processes with no shared state at load
time), and lock interactions (no lock is taken before or during resolution — verified by reading
`leadv2-fanout.sh:38-56` and `leadv2-fanout-lane-launcher.sh:79-88` in full).

---

## 5. THE CHANGE

### 5.1 Site A — `plugins/leadv2/scripts/leadv2-fanout.sh:44-52`

Replace the two-branch chain and its now-false rationale comment with an ordered candidate
loop mirroring `lv2_script()` (`leadv2-helpers.sh:83-108`) plus a canonical-root branch and a
loud fail-closed tail:

1. `${SCRIPT_DIR}/leadv2-active-registry.sh`
2. `${PROJECT_ROOT}/.claude/leadv2-overrides/scripts/leadv2-active-registry.sh`
3. `${PROJECT_ROOT}/.claude/scripts/leadv2-active-registry.sh` (legacy vendored)
4. `${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/leadv2-active-registry.sh`
5. `${HOME}/.claude/leadv2-shared/scripts/leadv2-active-registry.sh` (floor, last)

On no match: `printf -- '[fanout] ERROR: leadv2-active-registry.sh not found; tried: %s\n' "${_tried}" >&2; exit 1`
(raw `printf`, because `log_error` is defined below this point).

The stale LEAD-CONTROL-PLANE-01 comment must be **replaced**, not deleted silently — the
replacement records that both copies became state-path-aware and that SCRIPT_DIR-first now also
guarantees fanout and dispatch-code load the same registry build.

### 5.2 Site B — `plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh:82-85`

Identical replacement. Note the launcher's `SCRIPT_DIR` is already in scope and already used on
the following line for `leadv2-tasks-lib.sh`, so this is a one-idiom alignment.

### 5.3 Regression coverage — `plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh`

Add one test (Test 5) that pins the hermeticity property directly instead of relying on Tests
2–4 to catch it by accident: run `leadv2-fanout.sh --dry-run` with `LEADV2_PROJECT_ROOT`
pointing at the sandbox **and** `HOME` pointing at an empty dir, and assert the output contains
no `leadv2-active-registry.sh: No such file` and no `[fanout] ERROR: leadv2-active-registry.sh not found`.
Existing Tests 1–4 keep their assertions **verbatim** — the mission's "do not weaken the
assertion" is honoured by changing the script under test, not the test.

### 5.4 Explicitly NOT done (non-goals)

- No change to `leadv2-active-registry.sh`, `leadv2-lane-liveness.sh`, or `leadv2-dispatch-code.sh` — the lane's existing LANE-REGISTRY-SELF-DEADLOCK-01 work stands untouched.
- No staging of shared scripts into the fixture HOME. There is no such idiom to match: grep over `plugins/leadv2/scripts/tests/*.sh` finds `leadv2-shared` in exactly three files (`test-drift-guard-quarantine-perimeter.sh`, `test-drift-guard-safety-fixes.sh`, `test-one-copy-drift.sh`), and all three build a *synthetic* shared tree as the subject of the test, not as a fixture prerequisite. Staging would also hide the production defect in Fact 5.
- No `LEADV2_SUITE_SHARDS` / `run-core-offline.sh` change. The private HOME is correct; fanout was wrong.
- No one-copy remediation of `~/.claude/leadv2-shared/`.
- No post-source capability assertion (§4a) — recorded as a follow-up task.
- No weakening, re-authoring, or skipping of any existing assertion in any suite.

---

## 6. RISKS

| # | Risk | Mitigation |
|---|---|---|
| R1 | SCRIPT_DIR-first changes which registry real fanout runs (Fact 5) — a live behaviour change, not just a test fix | Intended and stated. Both copies are state-path-aware (§0 Fact 4), and the canonical copy is a strict superset (it has `set_worker_pid`). Verify with a `--dry-run` fanout after the change. |
| R2 | A repo whose vendored `.claude/scripts/` copy was deliberately patched now loses precedence to `$SCRIPT_DIR` | Branch 2 (`leadv2-overrides/scripts/`) is the sanctioned override surface per global policy; branch 3 still exists. Repos vendoring an intentional patch should move it to overrides — call this out in the commit message. |
| R3 | Fixing site A only, leaving site B armed | Both sites are in `LANE_WRITES`; the acceptance surface covers the launcher path via `plugins/leadv2/tests/test-fanout-lane-detach.sh`. |
| R4 | The new fail-closed `exit 1` fires in an environment that previously limped along | Impossible to be a regression: today that same state is already rc 1, just with a worse message. |
| R5 | Concurrent-access surface | None. Neither site reads or writes shared state before resolution; no lock is held. No ordering constraint required. |

## 7. Mandatory constraint checklist

1. **Env var naming** — only pre-existing `LEADV2_*` vars are read (`LEADV2_PROJECT_ROOT`, `LEADV2_CANONICAL_ROOT`, `LEADV2_SUITE_SHARDS`). No new env var introduced. No `LEAD_V2_*` drift.
2. **File paths** — all five chain paths and all edited files verified on disk except `${PROJECT_ROOT}/.claude/scripts/leadv2-active-registry.sh` (verified **absent** in this repo — that absence is Fact 5, and the branch is retained for other repos) and `${PROJECT_ROOT}/.claude/leadv2-overrides/scripts/…` (may be absent; both are `[[ -f ]]`-guarded, never assumed).
3. **`claude -p` commands** — none in this change.
4. **Concurrent access** — see R5: no race surface.
5. **Config contradiction** — `LEADV2_CANONICAL_ROOT` semantics (`${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}`) match all 10+ existing usages verified by grep; no contradiction.

---

acceptance:
  - surface: log_line
    observable: "A founder running `bash plugins/leadv2/scripts/tests/run-core-offline.sh` sees the fanout classifier/runner guard suite report four passes and zero failures, and nowhere in the run output does a line appear saying that leadv2-active-registry.sh was not found under a leadv2-shared path."
    authored_at: 2026-08-24T12:26:51Z
  - surface: log_line
    observable: "A founder running leadv2-fanout.sh by hand in the canonical repo sees it proceed past startup to task selection with no bash 'No such file or directory' line naming leadv2-active-registry.sh, and the lanes it launches behave as before."
    authored_at: 2026-08-24T12:26:51Z
  - surface: file_artifact
    observable: "A reviewer reading the lane branch's commit sees both leadv2-fanout.sh and leadv2-fanout-lane-launcher.sh changed together, each resolving the registry helper from the directory the script itself lives in before any home-directory path, and sees a plain-language error message listing every path tried when none resolves."
    authored_at: 2026-08-24T12:26:51Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-fanout.sh, plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh, plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh

DELIVERABLE_COMPLETE
