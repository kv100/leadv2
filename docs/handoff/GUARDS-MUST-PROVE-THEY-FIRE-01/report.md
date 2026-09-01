# GUARDS-MUST-PROVE-THEY-FIRE-01 — report

Lane branch: `worktree-GUARDS-MUST-PROVE-THEY-FIRE-01`, code commit `155e056`.
Date: 2026-09-01. Worktree: `.claude/worktrees/GUARDS-MUST-PROVE-THEY-FIRE-01`.

## What shipped

| file | role |
|---|---|
| `plugins/leadv2/scripts/leadv2-guard-census.sh` | the one table: guard · event · state · last ran · last fired · fixture proven? Dead guards sort to the top. |
| `plugins/leadv2/hooks/lib/leadv2-guard-verdict.sh` | the one cheap record a guard leaves (`ran` / `verdict block\|log\|allow\|nap` / `bail <reason>`), so `never-ran` and `ran-never-fired` stop being invisible. |
| `plugins/leadv2/scripts/tests/test-guard-census.sh` | 23 checks covering all 8 acceptance cases against synthetic fixture guards + fixture `hooks.json`. |
| `plugins/leadv2/scripts/tests/fixtures/guards/` | synthetic guards (`hook-dir/`), fixture wiring (`hooks.json`), fixture drivers (`fixtures/`), real-guard drivers (`real/`). |
| `tests/run-all.sh` | `EXTRA_SUITE_MAP` rows + hooks/lib stem filter — **plus repair of pre-existing structural corruption** (below). |

Run it:

    bash plugins/leadv2/scripts/leadv2-guard-census.sh                     # real tree, table
    bash plugins/leadv2/scripts/leadv2-guard-census.sh \
      --fixtures-dir plugins/leadv2/scripts/tests/fixtures/guards/real     # with fire-path proof

## Critical 1 — one honest state per guard, derived not declared

States come from runtime observation only — wiring from `hooks.json`, live
evidence from journals, capability from RUNNING the guard. The census never
greps guard source to decide a guard "works".

| state | derivation (evidence, in priority order) |
|---|---|
| `not-wired` | absent from `hooks.json` for every event |
| `missing` | wired, file absent |
| `bail:<reason>` | fixture run timed out (`bail:timeout`, reason recorded) |
| `blocking` | journal has a `block` verdict row, OR fixture observed exit 2 / `decision:block` |
| `fires-log-only` | journal `log` verdict, legacy journal fire row with log-only marker, or fixture observed output-without-block |
| `disabled` | behavioural: fixture run with default env does NOT block, same run with the arming env DOES (never grepped) |
| `ran-never-fired` | `ran` journal row / legacy `ran` evidence / fixture observed clean nap — no fire evidence |
| `never-ran` | wired, zero evidence anywhere |

`never-ran` vs `ran-never-fired` are separated by exactly one thing today: a
journal row. Until guards source the verdict lib, only legacy journals give
`ran` evidence — which is the founder's point made visible: 83 of 92 guards
have no evidence either way and print `never-ran`.

### Live evidence sources

- New: `${LEADV2_GUARD_VERDICT_DIR:-${CLAUDE_PROJECT_DIR:-$HOME}/.claude/cache/guard-verdicts}/journal.tsv` —
  one TSV row per record: `<iso-ts>\t<guard>\t<event>\t<kind>\t<detail>`.
- Legacy (built into the census): promise-guard's own
  `~/.claude/leadv2-promise-guard.jsonl` — last line matched against
  `"verdict": "fired"` (fire) + `"block_mode": "0"` (log-only).

### Cost of one record (Critical 3's "keep it cheap")

Two `>>` appends of one TSV line each on the full path (`ran` + `verdict`),
one `date` fork per record, zero other subprocesses; write failures are
swallowed (`|| return 0`) so recording can never fail a guard. No locks, no
FSMs, no per-turn growth — the opposite shape of the fork pressure
FORK-STORM-KILLS-HOOKS-01 removes.

### Bail recording

A guard that sources the lib and exits without a verdict gets a `bail
exited-without-verdict rc=N` row from the lib's EXIT trap. A guard killed by
an external timeout (SIGKILL skips traps) gets its bail recorded by the
CENSUS instead (`census-bail.<guard>.tsv` in the sandbox, `bail:timeout` in
the table). The `idle-lead-guard`-failing-open-all-night shape is now the
loudest row in the table, not an invisible one.

## Critical 2 — fixtures prove guards CAN fire (real-tree run, 2026-09-01)

`fixtures/guards/real/` drives four real guards; the census runs them in a
sandbox (env -i with capability parity — see below — sandboxed HOME/STATE,
sandbox journal) and grades observation against the fixture's declared
expectation. Real-tree result (rc=0, `fixtures run: 4 | fixture-proven: 4`):

| guard | state | fixture | evidence artifact |
|---|---|---|---|
| `leadv2-idle-lead-guard.sh` | `blocking` | yes | queued task + stub lane-liveness `{"availability":"authoritative","count_live":0}` → `{"decision":"block",...}` on stdout |
| `leadv2-lead-edit-guard.sh` | `disabled` | yes | default env → exit 0; `LEADV2_LEAD_GUARD_FORCE=1` → exit 2 |
| `leadv2-promise-guard.sh` | `fires-log-only` | yes | sandbox journal row `"verdict":"fired"`, `"block_mode":"0"`, exit 0, no output |
| `leadv2-block-bash-heredoc.sh` | proven, but `not-wired` in the plugin | yes | 2122-byte heredoc command → exit 2 (UNVERIFIED as to which non-plugin surface wires it: it fired on this lane's own Bash calls twice this session, so a wiring exists outside plugin `hooks.json` — likely repo `.claude/settings.json`) |

**Coverage, honestly: 4 of 92 guards carry a fire-path fixture.** They are
the ones that gate work hardest (both guards named in the mission brief are
proven). The other 88 print `never-ran` / `not-wired` — a partial census that
tells the truth. Extending `fixtures/guards/real/` is additive: one
`<guard>.fixture.sh` per guard, the census picks it up automatically, and a
fixture that stops making its guard fire exits 1 as loudly as a failing test.

Notable: `idle-lead-guard`'s fire path is REACHABLE today (post-`afb6641`) —
the overnight failure was a hang upstream, which is exactly the
`bail:timeout` shape the census now records.

## The env -i / capability-parity gotcha (for whoever adds fixtures)

Fixture runs use `env -i` so the operator's own flags can't leak (this
session runs `LEADV2_LEAD_GUARD=1`; leaking it would misreport
`lead-edit-guard` as blocking). But PyYAML resolves through the USER
site-packages, which is HOME-keyed — a bare `env -i` makes `import yaml`
fail inside idle-lead-guard, which then fails open silently. The census
therefore carries `PYTHONPATH=<user site-packages>`. Three more silent
gates the fixture work surfaced (probes 2026-09-01, all recorded in the
fixture headers):

- `idle-lead-guard` exits 0 with no output unless `$PROJECT_ROOT/docs/tasks.yaml` exists, even when `LEADV2_IDLE_GUARD_TASKS_FILE` points elsewhere;
- `idle-lead-guard` exits 0 with no output unless `$PROJECT_ROOT/docs/leadv2/` exists;
- promise-guard's journal write dies silently (`|| true`) when `~/.claude/` is absent (harmless live, mandatory to know in a sandbox).

## Critical 3 — "did not run" is impossible to miss

- bail rows carry the reason (`bail:timeout`, `exited-without-verdict rc=N`);
- the table sorts dead states to the top (regressions, bails, not-wired, never-ran);
- a fixture that stops making its guard fire prints
  `REGRESSION: <guard> — fixture no longer makes it fire` to stderr and exits 1.

## Mutation proof (Rules: removing the fixture-proof step must turn case 5 red)

Mutation applied on the real call path (committed `leadv2-guard-census.sh`,
fixture-run loop disabled: `if false; then # MUTATION`), suite run, revert,
clean `git diff --stat`:

```
FAIL: case1 fx-always-block state (got 'never-ran', want 'blocking')
FAIL: case2 fx-disabled state (got 'never-ran', want 'disabled')
FAIL: case3 fx-logonly state (got 'never-ran', want 'fires-log-only')
FAIL: case5 census exited 0 despite fixture regression
FAIL: case5 no REGRESSION line for fx-always-block
FAIL: case5 fixture column not REGRESSION
FAIL: case6 fx-hang state (got 'never-ran', want 'bail:timeout')
... 11 FAILED, exit 1
```

Revert (`git checkout --`), same suite: `ALL PASS: 23 checks passed`, exit 0.

## tests/run-all.sh — pre-existing corruption repaired

The committed file did not parse the way it reads: `stem="$(basename "${cf}" .sh)`
was missing its closing quote, and the swallowed string only terminated
because a stray `"` on a later `continue"` line acted as its compensating
closer; the freepool `if/else` had no reachable `fi` of its own. Consequences:
hook stems never reached `EXTRA_SUITE_MAP` (defeating PROMISE-GUARD-BIND-01's
stated intent), and the `.gitignore` synthetic-stem branch was dead text.
Repaired in this lane (the file is in LANE_WRITES; `bash -n` green; documented
inline). Plus:

```
leadv2-guard-census.sh:plugins/leadv2/scripts/tests/test-guard-census.sh
leadv2-guard-verdict.sh:plugins/leadv2/scripts/tests/test-guard-census.sh
```

and `plugins/leadv2/hooks/lib/*.sh` added to the changed-scope stem filters
(same shape as DISPATCH-CLOSE-GATE-01 for scripts/lib).

## Out of scope, respected

No guard's default was flipped. `promise-guard` remains log-only here; its
flip belongs to PROMISE-GUARD-TURN-IT-ON-01. Wiring the verdict lib into the
92 guards is deliberately NOT done in this lane (the guard scripts are not in
LANE_WRITES); until then, the census reports them honestly as `never-ran`
wired guards, and `hooks/lib/leadv2-guard-verdict.sh` is the two-line wiring
each guard needs.

## Critical 0 — why `leadv2-lane-liveness.sh --all` answered "nothing is alive", probed 2026-09-01 (this lane; the script itself is NOT in LANE_WRITES, so no fix shipped here)

Live re-probe today, same tree:

```
bash plugins/leadv2/scripts/leadv2-lane-liveness.sh --all | awk '{print $2}' \
  | sed 's/_[0-9]*s_abandoned//' | sort | uniq -c | sort -rn | head -4
 108 dead:sentinel_finalized
  90 dead:no_log_artifact
  1 silent:1199            <- the one possibly-live row (a lane silent 20 min)
  +~30 dead:silent_<N>s_abandoned   (weeks-old lanes)
231 rows total
```

Three distinct causes, each verified against the runtime:

1. **`--all` is a graveyard dump, not an alarm.** Discovery enumerates every
   handoff dir ever seen under ONE root — `glob(PROJECT_ROOT/docs/handoff/*/<stream>)`
   for stream in `developer.stream.jsonl, architect.stream.jsonl, session.log,
   fanout.log` (`leadv2-lane-liveness.sh:314,878`) ∪ `active.yaml` sessions
   (`:272`, also PROJECT_ROOT-scoped) — and never prunes finished lanes. The
   108 `dead:sentinel_finalized` rows are lanes whose `.finalized` is past its
   settle window AND whose worker pgid/pid is POSITIVELY dead
   (`kill(-pgid,0)` → ProcessLookupError, `:390-489`) — i.e. genuinely finished
   work reported truthfully, forever. "0 alive" is the steady state of any
   quiet moment; the number that matters is `count_live`, which only JSON mode
   carries.

2. **Codex-lane absence is a single-root scoping defect.** A dispatched lane's
   liveness evidence lives at `${PROJECT_ROOT}/docs/handoff/dispatch-<sig8>/developer.stream.jsonl`
   where PROJECT_ROOT is the repo dispatch ran FROM
   (`leadv2-dispatch-code.sh:2955,5124`). Both of liveness's discovery sources
   are scoped to the root it was invoked in. Probe: the mission's three
   codex-arm lanes left NO discoverable trace anywhere —

   ```
   ls -d docs/handoff/dispatch-{faee3fc5,a605eb2a,cf05539d}*        → no matches (leadv2 + worktree)
   ls -d ~/Projects/{persona-engine,m3-market,respiro-ios}/docs/handoff/dispatch-{faee3fc5,a605eb2a,cf05539d}* → no matches
   grep -rl faee3fc5 docs/leadv2/ docs/handoff/                     → 0 files
   ```

   A lane that no liveness invocation can ever see is the exact blindness
   class the lead's own watchdog fix closed with worktree mtimes — evidence no
   provider can avoid producing. Until discovery gains a provider-agnostic
   source, any guard built on `--all` structurally cannot see codex-arm work.
   Fix belongs in a lane that owns `leadv2-lane-liveness.sh`.

3. **`dead:no_log_artifact` (90 rows) = registry-known lanes with no stream
   file.** Discovered via `active.yaml`/codex jobs, but their handoff dirs
   contain no file matching any of the four stream names (recent dirs carry
   only `phases.d/`: `ls docs/handoff/dispatch-e79701d9/` → `phases.d`).
   These are neither alive nor positively dead — the verdict "no log artifact"
   is honest about the evidence, but idle-lead-guard consumes the verdict
   column alone, so evidence-less lanes read as "not live".

UNVERIFIED (hypothesis, not probed — the run in question predates this
session): the overnight `dead:sentinel_finalized` on a running GLM lane.
Sentinel verdict requires the pgid file's process group to be positively dead;
a relaunch that reuses the run dir would leave the previous attempt's
`.finalized` + stale pgid while the new worker runs under a fresh pgid,
defeating every condition. The settle window (`R1`, `:422-431`) was built for
exactly this race; whether the runner clears `.finalized` on relaunch was not
probed here.

**Guard-side takeaway (what this lane DID ship):** whatever liveness becomes,
`idle-lead-guard`'s dependence on it must fail LOUD when the input is absent
or late — that is the `bail:timeout`/bail-row mechanism in
`leadv2-guard-verdict.sh` plus the census's `bail:` state, both shipped above.
The acceptance case "a lane provably writing within the last minute ⇒ alive"
is recorded here as the acceptance test for the liveness-fix lane.

## Self-check

- `bash -n` on all three changed/new shell files: green.
- `python3 -m py_compile`: no Python files changed.
- `test-guard-census.sh`: 23/23 PASS (run under `LEADV2_SUITE_LOCK_DISABLE=1`).
- Changed-scope runner: `bash tests/run-all.sh --scope changed` — selection of
  `test-guard-census.sh` via the new map rows proven; full-log verdict
  recorded in the lane journal (run includes the known slow `run-core-offline`
  suite from the lane's changed range).
