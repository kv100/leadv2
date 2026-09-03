# architect prepass — V3-GLM-LADDER-01 ROUND 3 FINISHER (lane eb2d7143)

Scope: design only. No implementation. All line refs are in worktree
`.claude/worktrees/eb2d7143` at HEAD `4077109`.

---

## 0. State reconciliation (the mission's premise is stale — read this first)

The mission says "the r2 worker finished its edits (uncommitted, 47 files in worktree)".
That is no longer true. Probe:

```
$ git -C .claude/worktrees/eb2d7143 log --oneline -2
4077109 wip(v3-glm-ladder): checkpoint r3 worker output (park-content copy, retry-all as
        new sig, lockout-skip park/count, shared-cache-dir harness, flock->lv2_lock_wait,
        routing-enforcement-p1 + plan-followups fixes) — worker died at acceptance wait
389820a feat(routing): V3-GLM-LADDER-01 — deferred-GLM park queue ...

$ git -C .claude/worktrees/eb2d7143 diff --stat 389820a..HEAD | tail -3
 .../scripts/tests/test-glm-deferred-ladder.sh      | 252 +++++++++++++++--
 .../scripts/tests/test-routing-enforcement-p1.sh   |  11 +
 14 files changed, 532 insertions(+), 84 deletions(-)

$ git -C .claude/worktrees/eb2d7143 status --short | grep -vE '^\?\? docs/handoff/'
 M docs/leadv2/{.bus-offsets,.bus.lock,.merge.lock,active.yaml,active.yaml.lock,
                bus.jsonl,merge-queue.jsonl,open-threads.md,questions}
 ?? .claude/cache/  docs/leadv2/founder-status.md  docs/leadv2/status-snapshot.json
```

**All r2/r3 code work is already committed in `4077109`.** (The mission names this
checkpoint `e9bbd0f`; in this worktree it is `4077109` — same content, same message.)
Everything still uncommitted is lead-owned runtime state under `docs/leadv2/` — NOT lane
work, and per the subagent protocol the implementer must never commit it.

**Design consequence:** the r3 finisher is a *debug-and-fix* task on a committed base, not
a "finish the edits" task. Item 1 of the mission ("verify each r2 finding is addressed in
the on-disk diff") is a read of `git diff 389820a..HEAD`, not of `git diff`.

---

## 1. RED-1 — the lead's stated symptom is a red herring (CORRECTION, evidence below)

The gate log FAIL lines quote:

```
FAIL: quota refusal advances chain -- rc=4 ... dispatch_classified class=non_product
      reason=explicit_mission_fast_path kind=unknown
```

and the mission asks the implementer to root-cause "why fixture missions now classify
explicit_mission_fast_path kind=unknown → rc=4", naming 210a439's evidence-contract
mission injection as a suspect.

**That classification is correct, expected, and deterministic. It is not a symptom.**

Evidence — the classifier (`leadv2-dispatch-code.sh:2304-2314`):

```bash
classify_product_work() { # <kind> <mission> -> product|non_product<TAB>reason
  ...
  if [[ "${mission}" =~ ^[[:space:]]*(docs?-only|documentation-only|pure[[:space:]]+diagnosis|diagnosis-only|tooling-only|plugin-only) ]]; then
    printf 'non_product\texplicit_mission_fast_path'; return
  fi
```

Evidence — every fixture mission in the suite literally begins with `plugin-only`:

```
$ grep -c "DISPATCH_WRAPPER}\" 'plugin-only" tests/test-routing-enforcement-p1.sh
17
:296  bash "${DISPATCH_WRAPPER}" 'plugin-only quota refusal advances chain'
:349  bash "${DISPATCH_WRAPPER}" 'plugin-only codex dead-arm no-first-byte spills chain'
:708  bash "${DISPATCH_WRAPPER}" 'plugin-only lockout write read run1'
```

Those are exactly the three failing cases. `kind=unknown` is likewise expected — the
wrapper passes no `--kind`, and `emit decision ... kind=${kind:-unknown}` (`:3881`)
prints the default. `dispatch_classified` is simply the **first line of normal output**,
and `fail` prints the whole captured output, so the lead's excerpt is the head of the
log, not the cause.

**Directive to the implementer: do not spend a turn on 210a439 or on classification.**
The failure is `rc=4`, which happens far downstream.

### 1a. What rc=4 actually means — the diagnostic wedge

`exit 4` has exactly five sites, each preceded by a *distinct* `_dl_note` reason:

| line | emitted reason | meaning |
|---|---|---|
| 4210 | `refused all_arms_not_dispatchable_v2` | v2 chain adopted nothing (initial) |
| 4282 | `dispatch_rolled_back reason=all_arms_quota_locked` | quota-precheck kept zero arms |
| 4313 | `dispatch_rolled_back reason=all_arms_exhausted by=router_v2` | resolver rc=3 / empty eligible |
| 4330 | `refused all_arms_not_dispatchable_v2 chain=` | quota_filter re-adopt empty (documented unreachable) |
| 4358 | `refused all_arms_excluded` | operator exclusion emptied the list |

**Step 1 of the fix, before any code change:** for each of the three failing cases, grep
the captured `*_out` for `dispatch_rolled_back reason=` and `refused all_arms_`. That one
token partitions the entire problem into one of five disjoint code paths. Any root-cause
narrative that does not name which of the five fired is unverified.

### 1b. Prime suspect for the lane leg

The r2 C1 fix ("also park/count when glm is skipped via `quota_precheck_skip
reason=provider_quota_locked`") landed inside the quota-precheck loop that builds
`_qpc_kept` (`:4260-4285`) — i.e. **the same loop whose empty result is `exit 4` at
:4282**. A park/count edit that also benches the arm (rather than only observing the skip)
empties `_qpc_kept` and produces precisely `rc=4` on quota-refusal fixtures. This is the
highest-prior hypothesis for the *lane* leg, and it is cheaply falsifiable:

- A/B the suite at `389820a` vs `4077109` with byte-identical env (`git worktree add` a
  throwaway at 389820a, or `git stash`-free `git checkout 389820a -- <one file>`), same
  `TMPDIR`, same `HOME`. Different verdict ⇒ lane regression; same verdict ⇒ main.

### 1c. Cross-run state leak — ranked surfaces (this is the real architecture finding)

The suite *does* isolate the cache: `:54` exports `LEADV2_DISPATCH_CACHE_DIR` to a
`mktemp -d` root, and the failing cases override it per-case (`:289`, `:341`, `:726`),
with `:727` also setting `LEADV2_QUOTA_LOCKOUT_DIR`. So the ledger/lockout store is NOT
the leak. Every remaining persistent surface is keyed on **`PROJECT_ROOT`** or **`HOME`**,
neither of which `LEADV2_DISPATCH_CACHE_DIR` covers:

| # | surface | ref | why it leaks |
|---|---|---|---|
| L1 | `${PROJECT_ROOT}/docs/leadv2/.codex-credits-empty.stamp` | `:713`, `_codex_credits_watch` `:974-1010` | **24-hour dedup window.** Behaviour differs between the first run of a day and every later run. This is the single best explanation for "same fixture task 52a91b29, `route_headroom→sonnet` on one run and `rc=4` on the next". Lane-introduced in 389820a. |
| L2 | `${PROJECT_ROOT}/docs/leadv2/glm-deferred.jsonl` + `glm-deferred.d/<sig8>.md` | `:711`, `:714` | park rows keyed on fixed fixture sig8s; a surviving row changes the second run's arm set |
| L3 | `${PROJECT_ROOT}/docs/handoff/dispatch-<sig8>/architect-prepass.md` | `_prepass_file` `:2318` | a stale prepass file flips the architect gate |
| L4 | `CACHE_BASE="${LEADV2_DISPATCH_CACHE_DIR:-${HOME}/.claude/cache}"` | `:397` | real `$HOME` for any invocation that loses the export |
| L5 | **`PROJECT_ROOT` precedence bug** | `:264` vs suite `:89` | see below — the root cause *of* L1–L3 |

**L5 is the structural defect and the recommended single fix.** `:264` reads:

```bash
PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}}"
```

`LEADV2_PROJECT_ROOT` is **not in that chain** — yet the suite's dispatch wrapper
(`tests/test-routing-enforcement-p1.sh:89`) does exactly
`[[ -n "$_cr" ]] && export LEADV2_PROJECT_ROOT="$_cr"`. That is a dead lever. Whenever a
nested invocation loses `CLAUDE_PROJECT_ROOT`/`CLAUDE_PROJECT_DIR`, `PROJECT_ROOT` falls
through to `git rev-parse --show-toplevel` — **the real lane worktree**. Every L1–L3 write
then lands in the real `docs/leadv2/`, which simultaneously explains (a) the cross-run
leak, (b) the runner's `HERMETIC-VIOLATION` gate firing on `docs/leadv2` dirt, and (c) the
residue described in §3.

**Recommended fix (no new env var — `LEADV2_PROJECT_ROOT` already exists at `:89`):**
insert it into the `:264` chain, ahead of the `git rev-parse` fallback. Preserve
`CLAUDE_PROJECT_ROOT` first so production precedence is unchanged; this is additive and
backward-compatible.

Whatever the verdict per case, the mission requires a per-case tag —
`main-regression | lane | suite-leak` — with the raw probe attached. Model those verdicts
on the L-numbers above so the critic can check them.

---

## 2. RED-2 — plan-followups-01 is a harness-context flake with exactly two candidate causes

Facts on record: green standalone on main (21/0), red under `run-core-offline.sh` on the
same main. So the delta is entirely what the runner does to a suite that the operator's
shell does not. `run_check` (`tests/run-core-offline.sh:120-129`) does precisely two
things and nothing else:

```bash
    suite_tmp="$(mktemp -d "$RUN_TMP/suite.XXXXXX")"
    cmd=(env "${_CORE_OFFLINE_SCRUB_ARGS[@]}" "TMPDIR=$suite_tmp" "$@")
```

- **H-A (env scrub):** `_CORE_OFFLINE_SCRUB_ARGS` (`:64-77`) is `env -u` over
  `DRY_RUN GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE PROJECT_ROOT` plus **every** exported
  `LEADV2_* CLAUDE_* GIT_CONFIG*`. Standalone, the operator's ambient
  `LEADV2_*`/`CLAUDE_PROJECT_DIR` survive into the suite; under the runner they are gone.
  A suite that silently depends on an inherited `CLAUDE_PROJECT_DIR` (see L5 — the
  fall-through to the real repo) is green standalone and red here.
- **H-B (TMPDIR relocation):** the suite's own `TMP="$(mktemp -d)"` (`:24`) now lands
  under `$RUN_TMP` instead of `/tmp`, changing path depth and, on macOS, the
  `/var/folders` vs `/tmp` symlink shape that `cd -P`/`realpath` normalisation resolves
  differently.

**The runner already ships the bisection lever:** `LEADV2_CORE_OFFLINE_NO_SCRUB=1`
(`:121`) disables H-A while leaving H-B in place. One run partitions the two hypotheses.
Do that before touching either file.

Fix placement rule: if H-A, the suite must set its own `CLAUDE_PROJECT_ROOT`/
`LEADV2_PROJECT_ROOT` explicitly rather than inherit — fix in
`test-plan-followups-01.sh`. If H-B, fix in the suite's sandbox construction. **Do not
weaken the runner's scrub** — the scrub is the correct behaviour and weakening it would
re-open the leak RED-1 is about. Note also that `plan-followups-01` is *not* in
`_CORE_OFFLINE_OWNED_SUITES` (`:87-95`), so a `docs/leadv2` dirt from it currently degrades
to WARN, not FAIL — the FAIL therefore comes from the suite's own assertions, not the
hermetic gate.

---

## 3. Repo-hygiene defect introduced by the checkpoint (must be undone, not kept)

`4077109` committed test residue into the plugin tree:

```
plugins/leadv2/scripts/tests/.claude/scripts/lv2                       (126 lines)
plugins/leadv2/scripts/tests/docs/leadv2/.bus-offsets
plugins/leadv2/scripts/tests/docs/leadv2/.bus.lock
plugins/leadv2/scripts/tests/docs/leadv2/.merge.lock
plugins/leadv2/scripts/tests/docs/leadv2/active.yaml
plugins/leadv2/scripts/tests/docs/leadv2/active.yaml.lock
plugins/leadv2/scripts/tests/docs/leadv2/bus.jsonl
plugins/leadv2/scripts/tests/docs/leadv2/merge-queue.jsonl
plugins/leadv2/scripts/tests/docs/leadv2/open-threads.md
```

Eight one-line `docs/leadv2/**` files under the *tests directory* are not a fixture
anybody authored — they are what a dispatch run writes when `PROJECT_ROOT` resolves to the
tests dir. **This is independent confirmation of L5.** Keeping them makes the leak
invisible (a later run finds the files it expects and goes green for the wrong reason —
a lying-green harness, the exact defect r2's C1 called out).

**Decision:** `git rm` all nine from the tree, extend `.gitignore` with the
`plugins/leadv2/scripts/tests/docs/` and `plugins/leadv2/scripts/tests/.claude/` patterns,
and fix L5 so they stop being produced. If any suite genuinely needs `tests/.claude/scripts/lv2`
as a committed fixture, that must be proven by a red-first revert (delete it, watch a
suite go red) before it is kept — otherwise it goes.

---

## 4. Recommended execution order (each step gated on the previous)

| # | step | why this order |
|---|---|---|
| 1 | Read `git diff 389820a..HEAD`; tick off C1-C3, H1-H3, M1-M5 against it | mission item 1; cheap; tells you what is already done |
| 2 | Run `run-core-offline.sh` **foreground**, capture to a file | establishes the baseline; mission explicitly forbids backgrounding + idle-wait (two workers died of `worker_timeout` that way) |
| 3 | RED-1 wedge: grep the 3 failing outputs for `dispatch_rolled_back reason=` / `refused all_arms_` | one grep partitions 5 code paths — do this before any edit |
| 4 | RED-2 wedge: one run with `LEADV2_CORE_OFFLINE_NO_SCRUB=1` | one run partitions H-A vs H-B |
| 5 | Fix L5 (`:264` precedence) | single structural fix; likely collapses L1-L3 and the §3 residue at once |
| 6 | Re-run; only then chase whatever is still red (1b A/B, per-case suite isolation) | avoids stacking speculative fixes |
| 7 | §3 cleanup + `.gitignore`; `bash -n` + `shellcheck -S warning` on changed files; commit on lane branch | mission acceptance |
| 8 | Falsification pass: `LEADV2_CORE_OFFLINE_REVERSE=1` then forward again | the runner's own order-dependence falsifier (`:171-176`); two identical forward runs prove nothing |

---

## 5. Risks

| risk | mitigation |
|---|---|
| Implementer chases `explicit_mission_fast_path` per the mission text and burns the run | §1 is stated as a correction with the grep evidence inline; step 3 forces the real wedge first |
| Weakening the runner's env scrub to make RED-2 green | §2 states the rule explicitly: fix the suite, never the scrub |
| Changing `:264` precedence breaks production root resolution | `CLAUDE_PROJECT_ROOT` stays first; the addition sits ahead of the `git rev-parse` fallback only — purely additive |
| Committing lead-owned `docs/leadv2/**` runtime state (9 dirty files in the worktree) | never `git add -A`; stage the explicit path list only |
| §3 residue turns out to be a real fixture; deleting it manufactures a new red | red-first revert proof required before keeping (§3) |
| Backgrounding the runner and idle-waiting → `worker_timeout` (killed the last two workers) | step 2 pins foreground execution |
| RED-1 is genuinely a main regression; lane cannot make it green | mission already allows a per-case `main-regression` verdict with raw probes — that is an acceptable terminal artifact, not a failure to finish |

---

## 6. Explicit non-goals (implementer: ignore these)

- Routing order and ceilings — unchanged. No edits to arm order, chain defaults, or ladder yaml.
- **No new env vars.** `LEADV2_PROJECT_ROOT`, `LEADV2_CORE_OFFLINE_NO_SCRUB`,
  `LEADV2_CORE_OFFLINE_REVERSE`, `LEADV2_QUOTA_LOCKOUT_DIR` all already exist — reuse only.
- `leadv2-dispatch-product-close.sh`, `supervise*`, `lib/leadv2-builder-selfcheck.sh`
  (another live lane owns it) — off limits.
- Re-doing C1-C3/H1-H3/M1-M5 that the diff already shows as landed.
- Making the other 52 passing suites "better"; no drive-by refactors.
- Deleting/deduplicating `.claude/scripts/tests/` (that is the separate open thread with
  its own blast radius).
- Committing anything under `docs/leadv2/**` or `docs/handoff/**`.
- Merging to main, or any push/deploy. The mission ends at a commit on the lane branch.

---

## 7. Interface contracts touched

| contract | before | after | compat |
|---|---|---|---|
| `PROJECT_ROOT` resolution (`leadv2-dispatch-code.sh:264`) | `CLAUDE_PROJECT_ROOT → CLAUDE_PROJECT_DIR → $PROJECT_ROOT → git toplevel` | `... → $PROJECT_ROOT → LEADV2_PROJECT_ROOT → git toplevel` | additive; production precedence unchanged |
| `run_check` env scrub (`run-core-offline.sh:120-129`) | unchanged | unchanged | — (explicitly not a fix site) |
| test residue paths under `plugins/leadv2/scripts/tests/` | tracked (since 4077109) | untracked + gitignored | removes accidentally-published files |

No DB schema, no migration, no async boundary, no Qdrant/Supabase/Next.js surface is
involved — this lane is entirely shell + test harness.

---

## acceptance:

```yaml
acceptance:
  - surface: log_line
    observable: >-
      The final line printed by run-core-offline.sh in the eb2d7143 lane worktree reads
      "suites passed=<N> failed=0 missing=0" — the failed and missing counts are both
      zero, and no "FAILED: dispatch refusal fallback chain", "FAILED: plan-followups-01",
      or "HERMETIC-VIOLATION (FAIL, lane-owned)" line appears anywhere above it.
    authored_at: 2026-08-20T03:40:00Z
  - surface: log_line
    observable: >-
      A second run of the same runner with the suite list walked back-to-front prints the
      banner "LEADV2_CORE_OFFLINE_REVERSE=1: running suite list back-to-front" and still
      ends on "failed=0 missing=0", so the green is not an artifact of suite ordering.
    authored_at: 2026-08-20T03:40:00Z
  - surface: file_artifact
    observable: >-
      docs/handoff/dispatch-af9735b2/developer.full.md carries, for each of the three
      RED-1 cases, a verdict word (main-regression, lane, or suite-leak) with the pasted
      dispatch_rolled_back / refused all_arms_* line that decided it, plus a RED-2 verdict
      naming which of H-A (env scrub) or H-B (TMPDIR) the NO_SCRUB run implicated.
    authored_at: 2026-08-20T03:40:00Z
  - surface: file_artifact
    observable: >-
      git show --stat on the lane's new commit lists the changed script and test files and
      lists no path under docs/leadv2/ or docs/handoff/, and the eight
      plugins/leadv2/scripts/tests/docs/leadv2/* residue files appear as deletions.
    authored_at: 2026-08-20T03:40:00Z
```

---

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh, plugins/leadv2/scripts/tests/test-plan-followups-01.sh, plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, .gitignore, plugins/leadv2/scripts/tests/docs/leadv2/*, plugins/leadv2/scripts/tests/.claude/scripts/lv2

DELIVERABLE_COMPLETE
