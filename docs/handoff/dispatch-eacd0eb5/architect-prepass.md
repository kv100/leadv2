# SUPERVISOR-DELETE-01 — architect prepass

Design only. No implementation. All greps below were run in this subsession against
`/Users/kostiantyn.vlasenko/Projects/leadv2` at HEAD `b9959aa`.

---

## 0. Headline — the mission's Phase-2 delete list cannot be executed as written

`plugins/leadv2/scripts/leadv2-supervise.sh` is **on the live single-lead path**, not
supervise-only. It is the `lanes` section of the founder-status pipeline that fired the
`BROAD_STATUS_READY` line at the top of this very session:

```
plugins/leadv2/scripts/leadv2-status-collector.sh:112
    bash "$_SC_DIR/leadv2-supervise.sh" --json
plugins/leadv2/scripts/leadv2-broad-status.sh:37
    COLLECTOR_SH="${LEADV2_STATUS_COLLECTOR_BIN:-$SCRIPT_DIR/leadv2-status-collector.sh}"
plugins/leadv2/hooks/leadv2-single-lead-beat.sh:65
    PULSE_BEAT_SH="${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-pulse-beat.sh"   → leadv2-broad-status.sh
```

`leadv2-status-collector.sh:100-103` says so explicitly:

```
# ── generic section: lanes — delegate to the already-correct, already-tested
#    leadv2-supervise.sh --json (arm-aware liveness: pid/mtime for Sonnet
#    lanes, codex-task.sh status for Codex lanes — re-deriving that split
#    here would just re-risk the exact trap it already solves). ──────────
```

A bare `git rm leadv2-supervise.sh` therefore does not "delete dead code" — it silently
removes the lanes table from `docs/leadv2/founder-status.md` (the collector's
`_sc_run_section` isolates the failure, so the pipeline stays green and the table just
goes empty; a silent-loss failure mode, exactly the PULSE-IN-SINGLE-LEAD-01 shape).

Second live dependency inside the same file: **D-d active.yaml reconciliation**
(`leadv2-supervise.sh:277-860` — triple-proof tmux adoption, corroborated-death prune,
`tombstones.yaml` write). It rides the same `--json` call. Grep shows **no other live-path
caller** — `leadv2-backlog-pump.sh` and `leadv2-phase-backfill` only *mention* it in
comments (`leadv2-backlog-pump.sh:67,73,102,800` are all comment lines). So the only thing
that keeps dead lane rows from accumulating in `active.yaml` forever is a code path the
mission asks to delete.

**Design ruling: migrate by rename-and-strip, not by extract-rewrite.**
`git mv leadv2-supervise.sh → leadv2-lanes-snapshot.sh`, then delete the supervisor-only
surfaces from inside it. This keeps the 1519-line arm-aware liveness/reconciliation core
byte-identical (zero re-risk), satisfies the mission's zero-hits acceptance grep, and
costs one commit. Extracting a fresh `lanes` builder would mean rewriting the exact logic
the comment above warns against rewriting.

---

## 1. Phase-1 classification table

Sources: `grep -rn "leadv2-supervise" plugins/leadv2/{scripts,hooks,skills,docs} .claude`
and `grep -rn "supervisor-role.md" plugins/leadv2`. Raw output in §7.

### (b) LIVE-PATH DEPENDENCY — migrate first, own commit

| # | Path | Why live | Migration |
|---|---|---|---|
| b1 | `scripts/leadv2-supervise.sh` `--json` lanes snapshot | `status-collector.sh:112` → `broad-status.sh` → `founder-status.md` (pulse beat) | `git mv` → `leadv2-lanes-snapshot.sh`; repoint collector |
| b2 | same file, D-d adopt/prune/tombstone (`:277-860`) | only live writer that tombstones corroborated-dead `active.yaml` rows | carried for free by b1 |
| b3 | `hooks/leadv2-task-anchor.sh:238` → `docs/supervisor-role.md` | UserPromptSubmit hook, fires on **every founder prompt** (visible in this session's anchor block) | replace the pointer line before deleting the doc |
| b4 | `hooks/pre-compact-task-freeze.sh:449` → `docs/supervisor-role.md` | PreCompact hook; `tests/test-open-threads-prune.sh:152` asserts the pointer string | same as b3, plus retarget that assertion |

`scripts/leadv2-supervise-resume.sh` is a **borderline b/a**: it is invoked only from
`leadv2-supervise.sh:138,1394` (the `--print` path and the embedded `resume` JSON block),
and `:1386` notes it "rides this mandatory first `--json` call" — i.e. the collector pays
for it today, but nothing downstream of `broad-status.sh` reads the `resume` key. Ruling:
**class (a), delete**, and strip the embed at `leadv2-supervise.sh:132-145` and
`:1386-1470` as part of b1. Single-lead's handoff surface is `founder-status.md`.

### (a) SUPERVISE-ONLY — delete

Scripts (4): `leadv2-supervise-loop.sh` (874L), `-pick.sh` (102L), `-resume.sh` (275L),
`-watchdog.sh` (132L).

Hooks (6) + their `hooks.json` registrations (6 rows at `:128,268,306,362,411,608`):
`leadv2-supervise-fanout-guard.sh`, `leadv2-supervisor-guard.sh` (3 registrations),
`leadv2-supervisor-pump-caller.sh`, `leadv2-supervisor-mode-reinject.sh`,
`leadv2-supervise-bash-guard.sh`, `leadv2-supervise-sentinel-cleanup.sh`.
Also the dispatcher row `hooks/leadv2-bash-pre-dispatch.sh:56` (`MANIFEST='leadv2-supervise-bash-guard.sh|ALWAYS`).

Skill: `skills/leadv2-supervise/{SKILL.md,VERIFICATION.md}`.
Doc: `docs/supervisor-role.md` (after b3/b4).

Tests under `plugins/leadv2/scripts/tests/`: `test-supervise-v2.sh`,
`test-ensure-adopt.sh`, `test-question-delivery-01.sh`, `test-alarm-dedupe-transition.sh`,
`test-broad-status-duty.sh`, `test-supervisor-mode-reinject.sh`,
`test-supervisor-reason-honest.sh`.
Tests under `plugins/leadv2/tests/`: `test-supervise-fanout-guard.sh`,
`test-supervise-sentinel-readonly.sh`, `test-supervise-stale-truth.sh`.
Lib: `scripts/lib/leadv2-alarm-dedupe.sh` — verify it has no non-loop caller before
deleting; if any, keep and scrub comments only.

### (c) DOC / COMMENT MENTION — text edit only

`scripts/`: `leadv2-backlog-pump.sh`, `leadv2-status-render.sh`, `leadv2-writes-overlap.sh`,
`leadv2-helpers.sh:2330`, `leadv2-active-registry.sh:31,223,557`,
`leadv2-lane-liveness.sh:435`, `leadv2-lane-heartbeat.sh:37,45`, `leadv2-lane-detail.sh:7`,
`leadv2-ask.sh:7`, `leadv2-reply-router.sh:6`, `leadv2-pulse-beat.sh:5,9`,
`leadv2-broad-status.sh:19`.

Anti-recursion prompt strings naming `leadv2-supervise.sh` as a forbidden launcher:
`leadv2-codex-session-runner.sh:457,475`, `leadv2-glm-session-runner.sh:344`,
`leadv2-kimi-session-runner.sh:373`. Drop the token from the forbidden list (the other
launchers stay). **Note:** `tests/test-codex-session-runner.sh` uses
`leadv2-supervise.sh` as its *fixture command string* in ~20 assertions — it tests the
recursion-detector regex, not supervise. Retarget those fixtures to
`leadv2-session-runner.sh` rather than deleting the suite.

`hooks/`: `leadv2-async-question-guard.sh:12,43`, `leadv2-bash-pre-dispatch.sh:39-40`,
`leadv2-pulse-json.sh:7`, `leadv2-single-lead-beat.sh:5,13,17,19,82-83` (the
`supervise-loop.log` filename is a **live state-path key** — see risk R4).

`docs/`: `single-lead-pulse.md:7,9,18`. `commands/leadv2.md:48,72,267`.
`.claude/anatomy.md`. `skills/leadv2-plan/SKILL.md:437` is an acceptance *example string*
("supervise status line") — leave it, it is not a reference.

**Out of scope, leave untouched:** every hit under `.claude/worktrees/6bbcca99/**` (a
stale worktree copy, ~40 files) and all of `docs/handoff/**`.

---

## 2. Correction to the mission's acceptance criteria

- **"suite count drops by 1" is wrong.** `run-core-offline.sh` has 56 `|||` rows today.
  Supervise rows: `:193 "supervisor fail-closed"`, `:194 "supervisor reconciliation"`,
  `:195 "supervisor/lead PID isolation"`. Two are deleted; `supervisor fail-closed`
  (`test-supervise-failclosed.sh`) tests root resolution + registry honesty, which
  **survives the rename** — retarget it to `leadv2-lanes-snapshot.sh` and rename the row
  to `lanes-snapshot fail-closed`. Plus `test-supervisor-mode-reinject.sh` and
  `test-broad-status-duty.sh` rows if registered. **Expected: 56 → 54**, plus
  the header comment at `run-core-offline.sh:4,93`.
- **Suites that reference supervise but must be REPAIRED, not deleted** (they test the
  lane/liveness/status contract, not the supervisor):
  `test-supervise-failclosed.sh:22`, `test-lane-liveness-lies.sh:16,28` ("drive the REAL
  leadv2-supervise.sh --json binary"), `test-lane-liveness-authoritative.sh:49`,
  `test-status-surface.sh:120,407` (T-F writer-parity assertion pairs supervise.sh with
  status-surface.sh), `test-active-registry-failclosed.sh:4`,
  `test-codex-session-runner.sh` (fixtures, above),
  `test-open-threads-prune.sh:152` (supervisor-role.md pointer).
- The mission's zero-hits grep is achievable **only after** the comment scrub in class (c)
  — it is `grep -rlE`, so a single stale comment fails it.

---

## 3. Commit sequence

1. `migrate(lanes): rename leadv2-supervise.sh → leadv2-lanes-snapshot.sh; repoint status-collector + plugin-sync + lane/liveness suites`
   — `git mv`; strip `--print`/`--enter`/resume-embed/`.supervise-active` sentinel write/
   `LEADV2_SUPERVISE_MODE`; edit `status-collector.sh:112`; edit the `plugin-sync.sh`
   curated set (`:529-530`); retarget the 6 repairable suites. **Green here proves the
   founder-status lanes table survives independently of the delete.**
2. `migrate(anchor): point task-anchor + pre-compact-freeze at single-lead-pulse.md instead of supervisor-role.md`
   — b3/b4; retarget `test-open-threads-prune.sh:152`.
3. `feat(leadv2): delete the supervisor machinery — founder order 2026-08-19`
   — all class (a) deletions, `hooks.json` rows, `bash-pre-dispatch` MANIFEST row,
   `SUITE_DEFS` rows, class (c) comment scrub, `/leadv2 supervise` retirement stub.

Rationale for the split: if commit 3 has to be reverted, commits 1–2 leave the live path
strictly healthier than today (no supervisor coupling), so revert is safe.

The `/leadv2 supervise` stub replacing `commands/leadv2.md:72` — one row, refuses:

> `| `/leadv2 supervise` | **Retired 2026-08-19 (founder order).** Single-lead mode is
> permanent; the supervisor machinery was deleted in SUPERVISOR-DELETE-01. This subcommand
> does nothing — dispatch lanes directly. |`

---

## 4. Risks

| id | risk | mitigation |
|---|---|---|
| R1 | `founder-status.md` silently loses its lanes table — `_sc_run_section` isolates a failing section, so the pipeline stays green and the table just empties | commit 1 lands and is verified via a real `leadv2-broad-status.sh` run **before** commit 3; acceptance A1 below is stated at the founder-visible surface, not at exit code |
| R2 | **Hook plugin-cache drift.** Per the shared-trees policy, `claude plugin update` no-ops for a directory-source marketplace when content changes but the version does not. Deleted hooks remain in the cache's `hooks.json` until re-synced → the session keeps firing hooks whose scripts are gone (`command not found` on every prompt) | run `leadv2-plugin-sync.sh` in the same lane; state in the terminal artifact that the founder must restart the session; keep the 6 deleted hooks' `hooks.json` rows and the scripts in the SAME commit so a stale cache never has half a pair |
| R3 | `leadv2-plugin-sync.sh:529-530` hard-codes `leadv2-supervise.sh`, `-loop.sh`, `-pick.sh` in a **fixed** (deliberately non-wildcard) curated set. If not edited, every downstream repo's sync errors or silently keeps stale copies | edit the curated set in commit 1 (for the rename) and commit 3 (for loop/pick removal); comment at `:513-517` explains why the set is fixed — preserve that intent |
| R4 | `hooks/leadv2-single-lead-beat.sh:82-83` resolves the state-path key **`supervise-loop.log`** and falls back to `docs/leadv2/supervise-loop.log`. That file is live state read by the beat. Renaming the key orphans the throttle history and re-fires a duplicate `[BROAD_STATUS]` | **do NOT rename the log key in this lane.** Leave `supervise-loop.log` as-is; it does not match the acceptance grep (`\.sh` suffix required). Log as a follow-up |
| R5 | `active.yaml` D-d reconciliation stops if b2 is missed → dead lane rows accumulate forever and founder-status shows phantom lanes | covered by b1 (rename carries it); add a suite assertion that `leadv2-lanes-snapshot.sh --json` still emits `pending_prunes`/`applied_adopts` |
| R6 | `.supervise-active` sentinel: `leadv2-supervise-bash-guard.sh:34` and `status-collector.sh:140` both read it. Deleting the guard but leaving a stale sentinel on disk makes the collector's `single_lead` section report "supervise active" forever | commit 3 also removes the `supervise_path` probe from `status-collector.sh:136-143`; the sentinel file itself is user-state, document that it can be deleted by hand |
| R7 | Two SUITE_DEFS rows point at `plugins/leadv2/tests/` (`:195`) while the rest point at `$TEST_DIR` — the `.claude/scripts/tests/` duplication thread in `open-threads.md` is adjacent. Touching it widens blast radius | strictly out of scope; delete the row, do not restructure the paths |
| R8 | Reverse-order suite run (`LEADV2_CORE_OFFLINE_REVERSE=1`) can expose an ordering dependency the forward run hides (precedent: the C7 red-first leg at `b9959aa`) | mission already requires both; keep it |

### Constraint checklist
1. **Env vars** — `LEADV2_SUPERVISE_*` (`_EVENT_POLL_S`, `_BROAD_STATUS_S`, `_REAP_S`,
   `_PRUNE_V2`, `_MODE`, `_BASH_GUARD`) keep their names in this lane. Renaming them to
   `LEADV2_LANES_*` is a config-contradiction surface (`.claude/settings.json` `env`
   block, `commands/leadv2.md:267`) with zero functional gain — explicit non-goal.
2. **Paths** — every path in §1 verified on disk this subsession except
   `scripts/leadv2-lanes-snapshot.sh` **(to-create)**.
3. **`claude -p`** — this lane introduces no `claude -p` invocation. N/A.
4. **Concurrent access** — `active.yaml` is written by both the D-d block and
   `leadv2-active-registry.sh`; the rename preserves the existing lock discipline
   (`leadv2-supervise.sh:31` tombstone-before-prune under a separate lock). Do not
   restructure locking in this lane.
5. **Config contradiction** — `hooks.json` and `leadv2-bash-pre-dispatch.sh:56` both
   register the bash guard; both must be edited in the same commit or the dispatcher
   invokes a deleted script on every Bash call. Flagged CRITICAL.

---

## 5. Non-goals (explicit — implementing agent must ignore)

- `leadv2-dispatch-product-close.sh` (T2 lane owns it).
- Worker-side turncap checkpoint machinery.
- `docs/handoff/**`, `docs/leadv2/**` history and archive docs.
- `.claude/worktrees/6bbcca99/**` — stale worktree, ~40 supervise hits, not ours.
- The `.claude/scripts/tests/` vs `plugins/leadv2/scripts/tests/` duplication thread.
- Renaming `LEADV2_SUPERVISE_*` env vars, or the `supervise-loop.log` state-path key.
- Any restructuring of `active.yaml` locking or the lane-liveness arm split.
- `skills/leadv2-plan/SKILL.md:437` (example string, not a reference).

---

## 6. Acceptance

```yaml
acceptance:
  authored_at: 2026-08-20T00:00:00Z
  items:
    - id: A1
      surface: file_artifact
      observable: >
        After the delete commit, docs/leadv2/founder-status.md regenerated by the pulse
        beat still shows one table row per live lane with its task id, phase and worker —
        not an empty lanes table, not a "lanes: unavailable" line, and not a table whose
        row count dropped versus the pre-change file.
    - id: A2
      surface: rendered_line
      observable: >
        A founder typing /leadv2 supervise sees a single line saying the subcommand was
        retired on 2026-08-19 by founder order and that single-lead mode is permanent —
        no supervisor picker, no lane reconciliation output, no error trace.
    - id: A3
      surface: log_line
      observable: >
        The core-offline suite report prints 54 suites with zero failures on both the
        forward and the reverse run, and the report contains no line naming a supervisor
        suite other than the renamed "lanes-snapshot fail-closed".
    - id: A4
      surface: rendered_line
      observable: >
        On the next founder prompt after the change, the task-anchor block at the top of
        the session shows a role-definition pointer to a file that exists on disk — not a
        path ending in supervisor-role.md.
    - id: A5
      surface: file_artifact
      observable: >
        docs/leadv2/active.yaml, after a lane dies, still gains a tombstone entry and
        loses the dead row — the reconciliation behaviour is visibly unchanged by the
        rename.
```

---

## 7. Raw greps (verbatim, this subsession)

```
$ grep -n "supervis" plugins/leadv2/scripts/tests/run-core-offline.sh
4:# supervisor isolation, active registry, and Phase-8 completion guards.
93:  "supervisor reconciliation"
193:  "supervisor fail-closed|||bash $TEST_DIR/test-supervise-failclosed.sh"
194:  "supervisor reconciliation|||bash $TEST_DIR/test-supervise-v2.sh"
195:  "supervisor/lead PID isolation|||bash $PLUGIN_ROOT/tests/test-supervise-fanout-guard.sh"
$ grep -c '|||' plugins/leadv2/scripts/tests/run-core-offline.sh
56

$ grep -n "supervis" plugins/leadv2/hooks/hooks.json
128:  "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-supervisor-pump-caller.sh\"",
268:  "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-supervise-fanout-guard.sh\"",
306:  "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-supervisor-guard.sh\"",
362:  "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-supervisor-guard.sh\"",
411:  "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-supervisor-guard.sh\"",
608:  "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-supervise-sentinel-cleanup.sh\"",

$ wc -l plugins/leadv2/scripts/leadv2-supervise*.sh
 874 leadv2-supervise-loop.sh
 102 leadv2-supervise-pick.sh
 275 leadv2-supervise-resume.sh
 132 leadv2-supervise-watchdog.sh
1519 leadv2-supervise.sh

$ grep -rn "supervisor-role.md" plugins/leadv2 | grep -v worktrees
plugins/leadv2/hooks/leadv2-task-anchor.sh:238
plugins/leadv2/hooks/pre-compact-task-freeze.sh:449
plugins/leadv2/hooks/leadv2-supervisor-mode-reinject.sh:24,134
plugins/leadv2/tests/test-open-threads-prune.sh:13,141,152,154
plugins/leadv2/scripts/tests/test-supervisor-mode-reinject.sh:10,86,96,97,99
plugins/leadv2/scripts/tests/test-broad-status-duty.sh:386
plugins/leadv2/skills/leadv2-supervise/SKILL.md:137,207
```

Full file lists per area (files, not lines) are reproduced in §1; the underlying commands
were `grep -rln "leadv2-supervise" plugins/leadv2/{scripts,hooks,skills,docs} .claude`.

---

LANE_WRITES: plugins/leadv2/scripts/leadv2-lanes-snapshot.sh, plugins/leadv2/scripts/leadv2-supervise.sh, plugins/leadv2/scripts/leadv2-supervise-loop.sh, plugins/leadv2/scripts/leadv2-supervise-pick.sh, plugins/leadv2/scripts/leadv2-supervise-resume.sh, plugins/leadv2/scripts/leadv2-supervise-watchdog.sh, plugins/leadv2/scripts/leadv2-status-collector.sh, plugins/leadv2/scripts/leadv2-plugin-sync.sh, plugins/leadv2/scripts/leadv2-broad-status.sh, plugins/leadv2/scripts/leadv2-pulse-beat.sh, plugins/leadv2/scripts/leadv2-backlog-pump.sh, plugins/leadv2/scripts/leadv2-status-render.sh, plugins/leadv2/scripts/leadv2-writes-overlap.sh, plugins/leadv2/scripts/leadv2-helpers.sh, plugins/leadv2/scripts/leadv2-active-registry.sh, plugins/leadv2/scripts/leadv2-lane-liveness.sh, plugins/leadv2/scripts/leadv2-lane-heartbeat.sh, plugins/leadv2/scripts/leadv2-lane-detail.sh, plugins/leadv2/scripts/leadv2-ask.sh, plugins/leadv2/scripts/leadv2-reply-router.sh, plugins/leadv2/scripts/leadv2-codex-session-runner.sh, plugins/leadv2/scripts/leadv2-glm-session-runner.sh, plugins/leadv2/scripts/leadv2-kimi-session-runner.sh, plugins/leadv2/scripts/lib/leadv2-alarm-dedupe.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/scripts/tests/test-supervise-v2.sh, plugins/leadv2/scripts/tests/test-supervise-failclosed.sh, plugins/leadv2/scripts/tests/test-ensure-adopt.sh, plugins/leadv2/scripts/tests/test-question-delivery-01.sh, plugins/leadv2/scripts/tests/test-alarm-dedupe-transition.sh, plugins/leadv2/scripts/tests/test-broad-status-duty.sh, plugins/leadv2/scripts/tests/test-supervisor-mode-reinject.sh, plugins/leadv2/scripts/tests/test-supervisor-reason-honest.sh, plugins/leadv2/scripts/tests/test-lane-liveness-lies.sh, plugins/leadv2/scripts/tests/test-lane-liveness-authoritative.sh, plugins/leadv2/scripts/tests/test-status-surface.sh, plugins/leadv2/scripts/tests/test-active-registry-failclosed.sh, plugins/leadv2/scripts/tests/test-codex-session-runner.sh, plugins/leadv2/tests/test-supervise-fanout-guard.sh, plugins/leadv2/tests/test-supervise-sentinel-readonly.sh, plugins/leadv2/tests/test-supervise-stale-truth.sh, plugins/leadv2/tests/test-open-threads-prune.sh, plugins/leadv2/hooks/hooks.json, plugins/leadv2/hooks/leadv2-supervise-fanout-guard.sh, plugins/leadv2/hooks/leadv2-supervisor-guard.sh, plugins/leadv2/hooks/leadv2-supervisor-pump-caller.sh, plugins/leadv2/hooks/leadv2-supervisor-mode-reinject.sh, plugins/leadv2/hooks/leadv2-supervise-bash-guard.sh, plugins/leadv2/hooks/leadv2-supervise-sentinel-cleanup.sh, plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh, plugins/leadv2/hooks/leadv2-async-question-guard.sh, plugins/leadv2/hooks/leadv2-pulse-json.sh, plugins/leadv2/hooks/leadv2-single-lead-beat.sh, plugins/leadv2/hooks/leadv2-task-anchor.sh, plugins/leadv2/hooks/pre-compact-task-freeze.sh, plugins/leadv2/skills/leadv2-supervise/SKILL.md, plugins/leadv2/skills/leadv2-supervise/VERIFICATION.md, plugins/leadv2/docs/supervisor-role.md, plugins/leadv2/docs/single-lead-pulse.md, plugins/leadv2/commands/leadv2.md, .claude/anatomy.md
DELIVERABLE_COMPLETE
