# leadv2 — plan of record

Written 2026-09-03. **This file is the plan.** Until today it did not exist: the plugin repo has no
`docs/tasks.yaml` (the backlog file its own tooling expects at `leadv2-tasks-lib.sh:21`), so the
ordered plan lived only in chat messages and evaporated on every compact. That is filed below as
`PLUGIN-REPO-HAS-NO-BACKLOG-01`.

Order is execution order. A wave does not start until the wave above it is landed, **except** the
lanes already in flight.

---

## Wave 0 — in flight right now

| task | what it fixes | arm | state |
|---|---|---|---|
| `TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01` | both Claude accounts usable from every repo; arbiter scores on each account's own binding window; D5 teaches every repo, `getmany-followup-bot` then `m3` | codex | 2 commits ahead, 9 files dirty, writing |
| `LANE-MERGE-SILENTLY-REVERTS-MAIN-01` | a lane branched early deletes other lanes' work on merge — hit 5 lanes today, one would have removed a 221-line suite | codex | 2 commits ahead, 24 files dirty, writing |
| `CODE-INTEL-IS-INSTALLED-AND-UNUSED-01` | repowise + graph MCP attached to workers but never called | claude | 4 commits ahead, 19 files dirty, writing |
| `SUBSCRIPTION-MIX-DECISION-01` | 2×Max 5x + Codex $100 + GLM Max vs today's Max 20x — three independent assessments, GLM synthesizes | claude done / codex + glm running | `assessment-claude.md` committed; codex + glm pending |

---

## Wave 1 — make the tests a defence again (blocks everything below)

D0 of `CONTROL-PLANE-HAS-NO-OWNER-01` established that our test suites currently prove very little
and actively damage live state. Every deliverable in Wave 2 is *accepted* by these suites, so this
wave is now a precondition rather than cleanup.

| # | task | what is wrong | est |
|---|---|---|---|
| 1.1 | `SUITES-MUTATE-LIVE-CONTROL-PLANE-01` **(new, from D0)** | ≥4 suites `git init` a temp repo in a subshell but never `cd` the test process into it, so they run against the real shared `~/.claude/leadv2-state/leadv2/`. `FOREIGN-PROJECT-ROOT-GUARD-01` (`leadv2-dispatch-code.sh:299-323`) makes the failure silent. Suspected cause of some of today's lane weirdness. | 0.5–1d |
| 1.2 | `DARK-SUITES-UNREACHABLE-BY-RUNNER-01` **(new, from D0)** | of the 23 suites the plan relies on, only **9** are reachable by `tests/run-all.sh`. 14 exist, several are red, CI will never see them. Needs `EXTRA_SUITE_MAP` rows + proof via `--scope changed`. | 0.5–1d |
| 1.3 | `SD-MAIN-CORE-SUITE-RED-01` (**OVERDUE** ledger row) | 16 of 85 suites red on `main`; every lane catches a false `e2e_regression` from them. Burned 3 fix-rounds on `WATCHER-LIFECYCLE-LEAK-01` alone. Founder approved the fix 2026-09-01. | 1d |
| 1.4 | `E2E-GATE-CANNOT-SEE-THE-ALLOWLIST-01` | the gate cannot read `tests/known-red-suites.txt`, so known-red counts as new-red | 0.3d |
| 1.5 | `CI-SUITES-ARE-MACOS-ONLY-01` + `LAST-LINUX-RED-FAST-NAMES-01` + `TWELVE-LINUX-ONLY-SUITES-01` | first CI run (33694115147) red; suites assume macOS. A green mac run is not a green CI run. | 0.5d |
| 1.6 | `LANE-PLACEMENT-PIN-RED-01` | `test-lane-placement-pin.sh` red on main | 0.2d |

**Wave 1 total: 3–4 days.** None of it was in the original 3–5 day estimate.

---

## Wave 2 — the state owner (`CONTROL-PLANE-HAS-NO-OWNER-01`)

The original task. **D0 is done** (`34b31cb6`) — measurement only, produced `census.md`.

| # | deliverable | what it makes true | est |
|---|---|---|---|
| D0 | ~~baseline + census correction~~ | **done.** Verified the architect's map; found 1.1 and 1.2 above | ✔ |
| D1 | single writer for lane state | exactly one component writes lane state; all 24 paths / 9 stores route through it | 1d |
| D2 | single verdict on liveness | one function answers "is this lane alive", by worktree write age — not by a status field | 0.5d |
| D3 | terminal funnel with a death check | "done" is only written after the worker is proven dead; no more `no_work` on a lane holding a real diff | 1d |
| D4 | no path loses work | a dead worker's uncommitted diff is recovered automatically, not by the lead's hand (6 rescues today) | 1d |
| D5 | every status surface is a view of one source | pulse, `/leadv2 status`, broad status, `active.yaml` stop disagreeing. Subsumes `STATUS-SURFACE-SHOWS-CORPSES-AND-BACKLOG-01` | 0.5d |
| D6 | lane registry stops lying about ownership | subsumes `LANE-REGISTRY-STAMPS-THE-LEAD-PID-01` | 0.5d |

**Wave 2 total: 4–5 days** (original estimate held for D1–D6; D0 did not shrink it).

---

## Wave 3 — dispatcher and arbiter defects

| # | task | what is wrong | est |
|---|---|---|---|
| 3.1 | `CLAUDE-PROFILE-DEFAULT-TOKEN-EXPIRED-01` | the inherited default slot's credential is dead; 198 fail-opens. Re-measure first — the founder logged in again after that count | 0.3d |
| 3.2 | `CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01` | arbiter sees a ceiling percentage but not remaining quota or the weekly reset date | 0.5d |
| 3.3 | `QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01` | `binding_window` is written once and overwritten — nobody can answer "is our wall the 5-hour or the weekly one" from history. **This is the measurement the subscription decision waits on.** | 0.3d |
| 3.4 | `CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01` | safety-touched work classified as simple | 0.3d |
| 3.5 | `HEAVY-TIER-VS-SAFETY-OPUS-01` | the FABLE merge moved the high-risk route off Opus | 0.3d |

---

## Wave 4 — hygiene and measurement

| # | task | what is wrong | est |
|---|---|---|---|
| 4.1 | `PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01` | phase records land in the wrong repo | 0.3d |
| 4.2 | `PHASE-PLAN-PROOF-IS-FILENAME-BASED-01` | a phase gate passes on a filename existing, not on content | 0.3d |
| 4.3 | `MUTATION-CONTROL-DIFF-HASH-IS-THE-EMPTY-HASH-01` | negative-control evidence records the empty hash — the control proves nothing | 0.3d |
| 4.4 | `INSTALLER-WRITES-ENV-INTO-A-TRACKED-SETTINGS-FILE-01` | installer writes into a git-tracked `settings.json`; in `m3` that file is the employer's | 0.3d |
| 4.5 | `BROAD-STATUS-READY-FIRES-ON-A-DAY-OLD-FILE-01` | status pulse fires on a stale file | 0.2d |
| 4.6 | `SKILL-USAGE-IS-UNMEASURED-01` | no measurement of whether skills are used or help | 0.5d |
| 4.7 | `MYTHICALGAMES-REPOS-HAVE-NO-OVERRIDES-01` | 8 adopted employer repos have no override tree | 0.5d |
| 4.8 | `PLUGIN-REPO-HAS-NO-BACKLOG-01` **(new)** | no `docs/tasks.yaml` in the plugin repo, so `/leadv2` cannot propose next work there and the plan has no home | 0.3d |

---

## Decisions, not code

| decision | waits on | who decides |
|---|---|---|
| `SUBSCRIPTION-MIX-DECISION-01` — drop Max 20x for 2×Max 5x, spend the freed $100 on Codex, GLM Max yes | **3.3** — one probe sample is not a basis for a $1 200/year call | founder, after all three assessments + GLM synthesis |
| move the lead to Codex | never tested as a full interactive lead; Codex $100 weekly cap not established | founder |

---

---

## LEAD-DOES-MACHINE-WORK-01 — where it lands (added after the founder asked)

It was **not** in the waves above; that was an omission. It is filed in `docs/tasks.yaml` with a
census taken from the live 2026-09-03 session — every line happened that night, none is theory.
It is not one task, it is a debt paid by three different rows:

| what the lead does by hand | who removes it | wave |
|---|---|---|
| merging lanes into main by hand — 5 lanes, ~2h, judging "this is state noise, this is work" | `REVIEW-GATE-IS-MUTE-01` + `LANE-MERGE-SILENTLY-REVERTS-MAIN-01` | 0 (in flight) / 1 |
| rescuing a dead worker's uncommitted diff — 6 times in one night | **D4** | 2 |
| deciding a lane is dead by reading `ps` and worktree mtimes | **D2** | 2 |
| choosing the arm and the `--protected` flag per dispatch | classifier rows 3.2–3.4 | 3 |
| writing design briefs itself instead of the architect | already changed: briefs go to `Agent(architect)` from 2026-09-03 | done |

Only the last one is fixed today. The rest is mechanism that does not exist yet — which is why it
reads as "the lead keeps doing it".

## Honest read on the estimate

The original **3–5 days** covered Wave 2 only, and it still does. Wave 1 is **3–4 days that were not
in it**, because D0 found the tests could not be used as acceptance. Realistic total to the end of
Wave 2: **7–9 days.** Waves 3 and 4 are another ~4 days and can run in parallel lanes.

"The plugin will be stable after this" means, precisely: lane work stops being lost, "busy" means
busy, and the status surfaces stop disagreeing. It does not mean bug-free.
