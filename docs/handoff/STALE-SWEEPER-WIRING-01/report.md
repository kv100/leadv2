# STALE-SWEEPER-WIRING-01 — report

Source: `docs/handoff/ADMISSION-LIVENESS-REVIEW-20260906/report.md` F3 (commit `24fbbe7f`).
Commit: `ebc09fd5` (code+suite) + this report. Worktree branch `worktree-STALE-SWEEPER-WIRING-01`.

## 1. What was wired, and where

**Carrier: content of an ALREADY-registered hook** — `plugins/leadv2/hooks/leadv2-stale-pid-sweep.sh`
(SessionStart, entry 5 in hooks.json, statusMessage "Sweeping stale leadv2 sessions...").
The SET of hooks is unchanged; one existing entry's timeout moved 5 → 30 (same entry, `hooks.json:37`).

Two-stage invocation (measured: full sweep takes minutes on this tree — GC over ~250 worktrees,
15–20 s/worktree — so a synchronous full sweep would be truncated by any hook timeout):

- **Stage 1, synchronous**: `leadv2-stale-sweeper.sh --non-interactive --mark-only` (new flag) —
  registry stale marks + ghost-spawn recon + summary, ~5 s, `[sweeper]` lines visible in session
  context. Failures log a degrade line, never block session start.
- **Stage 2, detached**: `nohup … sweeper --non-interactive` (full pass: orphan-worktree detection,
  dead-worktree GC, weekly graveyard, budget reset, `outcome-watch --sweep`) →
  `/tmp/leadv2-stale-sweeper.<repo>.log`. Same detach pattern as `leadv2-lane-watch-v2.sh
  --arm-from-hook`. Marks already set are skipped (`already_stale`), so stages compose.
  `LEADV2_SSWEEP_NO_DETACH=1` (tests) suppresses stage 2.

**When it starts working**: the marketplace plugin path is live-from-repo —
`readlink ~/.claude/plugins/local/leadv2/plugins/leadv2` → `/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2`
— so once this lane merges to main, the NEXT session start reads the new hook body and the bumped
timeout automatically. No plugin-cache copy, no version bump (that ritual applies to
marketplace-cached plugins; this one is a symlink to the repo). Sessions started BEFORE the merge
keep the old registration. No founder restart beyond "start a session after the merge".

## 2. Safety floor (mission rule, matched to `_row_dead`)

`leadv2-stale-sweeper.sh` now embeds the predicate verbatim from
`leadv2-active-registry.sh` `_row_dead` (`:1517`/`:1605`): a row is eligible ONLY if
`pid not in (None,"","null","None") and not _pid_alive(pid)`. Live-pid rows and pid-less rows
are skipped before any pulse/agents evidence is even consulted. The old code defaulted
`pid_dead=True` for a missing pid — pid-less rows with an old pulse WERE sweepable; that is fixed.

## 3. Two latent sweeper defects found by the suite (both fixed)

1. **Marks never survived a symlinked layout**: the sweeper marked through
   `docs/leadv2/active.yaml` (a symlink to the control plane) while `_leadv2_yaml_py_lock`
   writes via `mkstemp`+`os.replace` (`leadv2-active-registry.sh:1001`) — rename over a symlink
   replaces the LINK with a regular file, stranding every mark in a shadow copy. Registry path is
   now resolved via `_leadv2_yaml_file` (same file every registry op writes).
2. **Unquoted YAML timestamps crashed the sweep**: `2026-…Z` unquoted loads as `datetime`; the
   pulse parser called `.rstrip` on it → `AttributeError` (not in the except clause) killed the
   whole sweep. Now coerced via `isoformat()`. (The registry's own `yaml.dump` quotes timestamps,
   so live rows load as str — this protects hand-edited rows.)

## 4. Mutation proof — the sweep is REACHED (both colours)

Suite `plugins/leadv2/scripts/tests/test-stale-sweeper-wiring.sh` (registered:
`# run-all-triggers: leadv2-stale-sweeper leadv2-stale-pid-sweep`; self-selects as a changed
test file). Named mutation: **strip-invocation** — `sed '/^SWEEPER=/,/^# end STALE-SWEEPER-WIRING-01$/d'`
removes the sweeper call block from the hook.

- RED (pre-fix colour, reproduced inside every green run): mutant hook leaves the dead row unmarked →
  `PASS: mutant hook (invocation stripped): dead row NOT marked — pre-fix colour reproduced`
- GREEN (wiring works): `PASS: registered hook: dead row marked — the sweep IS reached at SessionStart`
  (plus a faithful-mirror leg proving the red is caused by the stripped invocation, not the mirror layout)

`leadv2-mutation-control.sh` artifact (`mutation-control/20260906T035436Z-46288.txt`):

```
suite=plugins/leadv2/scripts/tests/test-stale-sweeper-wiring.sh
file=plugins/leadv2/hooks/leadv2-stale-pid-sweep.sh
anchor=/^SWEEPER=/,/^# end STALE-SWEEPER-WIRING-01$/d
baseline_rc=0
mutated_rc=1
red_line=  FAIL: faithful mirror failed to sweep — mirror layout is broken, mutation leg proves nothing
diff_hash=8184bd9f086d1e852d5c3a08c3057c756c66923f9c82102cecd44cb1d30caf15
lane_diff_hash=901d9b1c5e9deb21a063d880a2ad1bf86674e82aa042d0305d9c63e826892f05
```

(Red lands on the mirror leg because in the mutated scratch lane BOTH the "real hook" and its
mirror copy derive from the mutated file — either failure is the suite detecting the unwired hook.)

## 5. Paired negative control (safety rule)

Suite output (both `claude agents`-JSON modes — stubbed list, and empty = pid-only fallback):

```
  [sweeper] lines (mode=agents):
    [sweeper] marked stale: ssw-dead-row
    [sweeper] 1 stale session(s) found, 0 ghost-spawn(s)
  PASS: mode=agents: dead-pid row marked stale (sweep ran)
  PASS: mode=agents: LIVE-pid row present and survived
  PASS: mode=agents: pid-less row present and survived
… same three PASS lines for mode=empty, and for the registered-hook leg …
test-stale-sweeper-wiring: 12 passed, 0 failed
```

Dead-pid fixture = pid 1 (EPERM → dead per `_pid_alive`; same convention as
`test-stale-row-starting-grace.sh` M-01). Live-pid fixture = the suite's own `$$`.

## 6. Live registry, before → after a real sweep (2026-09-06)

Snapshot `6b384a55f0def6b1` → real sweep run (sweeper, full pass, foreground-detached, log
`/tmp/leadv2-ssw-live.log`):

- before: **40 rows, 0 `stale`**; census: 26 pid-less (recovered_unowned), 2 pid-alive, 12 pid-dead
- after: **10 rows marked stale** — audit against the snapshot: every newly-stale row was
  provably dead at snapshot time (`violations: NONE`); live-pid rows `STALE-SWEEPER-WIRING-01`
  (pid 33367) and `dispatch-c4c38811` (pid 10746) present and unmarked; pid-less rows marked: NONE
- 2 of the 12 dead-pid rows were spared by the agents-JSON corroboration (their session ids are in
  the live `claude agents` list: ADMISSION-LIVENESS-REVIEW-01, W1-LAND-STRANDED-8F14220D-01) — by design
- fanout's `not s.get("stale")` count: 40 → **30** vs `hard_limit: 3`. Honest residual: the 26
  pid-less `recovered_unowned` rows are unmarkable by the fail-closed rule this mission ordered;
  they still count toward the cap until the lane_reconcile accumulation defect (F3 bullet 3) is
  fixed — separate lane, not this one's scope.
- the sweep's GC stage also removed 35+ dead-and-empty worktrees (policy-gated; live lanes' dirty
  worktrees KEPT), still running at report time — registry marks were complete before it started.

## 7. The four false statements — now true

| Location | Was | Now |
|---|---|---|
| `skills/leadv2-close/SKILL.md:226` | "runs automatically at every SessionStart via `leadv2-stale-sweeper.sh`" (nothing ran it) | names the carrier hook + two stages |
| `scripts/leadv2-outcome-watch.sh:12` | "Called by leadv2-stale-sweeper.sh at every SessionStart" | true again: full pass (detached stage) calls `--sweep`; says so |
| `docs/phases.md:78` | intake list implied a manual startup call | states automatic-at-SessionStart via the hook; manual call = mid-session re-run |
| `scripts/leadv2-phase8-close.sh:322` | "swept at every SessionStart by stale-sweeper" | true again, names carrier + detach |

## 8. Falsification set

- `bash -n` on all changed shell files (sweeper, hook, suite, outcome-watch, phase8-close): OK;
  `python3 -c json.load` on `hooks.json`: valid. No Python files changed (embedded heredoc python
  exercised by the suite).
- Suite: `test-stale-sweeper-wiring: 12 passed, 0 failed` (30 s), run three times across the edit
  sequence; final run on committed bytes.
- CI selection (state file reset first): `[SELECT] …/plugins/leadv2/scripts/tests/test-stale-sweeper-wiring.sh`
  in `LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed` (10 suites selected).
- Changed-scope runner (`bash tests/run-all.sh --scope changed`):

```
<RUNNER_RESULT>
```

- `tests/known-red-suites.txt` / `known-failures.txt`: untouched (may only shrink — nothing added).

## 9. Residual / follow-ups

- 26 pid-less `recovered_unowned` rows still count toward fanout's cap (unmarkable by design) —
  the reconcile-accumulation defect needs its own lane.
- The detached stage-2 sweep has no singleton lock; stacked session starts could overlap full
  sweeps (registry ops are flock'd per row; GC is refusal-gated). Observed benign; note for that lane.
