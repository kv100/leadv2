# STALE-SWEEPER-WIRING-01 — report

Source: `docs/handoff/ADMISSION-LIVENESS-REVIEW-20260906/report.md` F3 (commit `24fbbe7f`).
Commits: `ebc09fd5` (code+suite) + this report; branch `worktree-STALE-SWEEPER-WIRING-01`.

## 1. What was wired, and where

**Carrier: content of an ALREADY-registered hook** — `plugins/leadv2/hooks/leadv2-stale-pid-sweep.sh`
(SessionStart, entry 5 in hooks.json; SET unchanged, timeout 5 → 30 at `hooks.json:37`). A full sweep
takes minutes (GC over ~250 worktrees, 15–20 s each) — too slow for a hook timeout, hence:

- **Stage 1, synchronous**: `leadv2-stale-sweeper.sh --non-interactive --mark-only` (new flag) —
  stale marks + ghost-spawn recon, ~5 s, `[sweeper]` lines in session context; failures degrade,
  never block session start.
- **Stage 2, detached**: `nohup … sweeper --non-interactive` (orphan-worktree detection, dead-worktree
  GC, graveyard, budget reset, `outcome-watch --sweep`) → `/tmp/leadv2-stale-sweeper.<repo>.log`
  (same detach pattern as `leadv2-lane-watch-v2.sh --arm-from-hook`); already-set marks are
  skipped, so stages compose; `LEADV2_SSWEEP_NO_DETACH=1` (tests) suppresses stage 2.

**When it starts working**: the plugin path is live-from-repo (`~/.claude/plugins/local/leadv2` →
this repo), so once the lane merges to main the NEXT session start loads the new hook body and
timeout automatically — no cache copy, no version bump, no restart beyond a session after merge.

## 2. Safety floor (mission rule, matched to `_row_dead`)

The sweeper embeds the predicate verbatim from `leadv2-active-registry.sh` `_row_dead` (`:1517`/`:1605`):
a row is eligible ONLY if `pid not in (None,"","null","None") and not _pid_alive(pid)`; live-pid
and pid-less rows are skipped before any pulse/agents evidence is consulted (the old code defaulted
`pid_dead=True` for a missing pid — pid-less rows WERE sweepable; fixed).

Two latent sweeper defects found by the suite (both fixed): (1) marks went through the
`docs/leadv2/active.yaml` symlink while `_leadv2_yaml_py_lock` writes via `os.replace`
(`leadv2-active-registry.sh:1001`) — rename replaces the LINK with a shadow file; registry path
now resolved via `_leadv2_yaml_file`. (2) Unquoted YAML timestamps load as `datetime` and
crash `.rstrip`; coerced via `isoformat()`.

## 3. Mutation proof — the sweep is REACHED (both colours)

Suite `plugins/leadv2/scripts/tests/test-stale-sweeper-wiring.sh` (registered via
`# run-all-triggers: leadv2-stale-sweeper leadv2-stale-pid-sweep`). Mutation **strip-invocation**:
`sed '/^SWEEPER=/,/^# end STALE-SWEEPER-WIRING-01$/d'`.

- RED (reproduced inside every green run): `PASS: mutant hook (invocation stripped): dead row
  NOT marked — pre-fix colour reproduced`
- GREEN: `PASS: registered hook: dead row marked — the sweep IS reached at SessionStart`; a
  faithful-mirror leg shows the red comes from the stripped invocation, not the mirror layout.

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

## 4. Paired negative control (safety rule)

Both `claude agents`-JSON modes (stubbed, and empty = pid-only fallback) + the registered-hook leg:

```
  PASS: mode=agents: dead-pid row marked stale (sweep ran)
  PASS: mode=agents: LIVE-pid row present and survived
  PASS: mode=agents: pid-less row present and survived
… same three PASS lines for mode=empty and the registered-hook leg: 12 passed, 0 failed …
```

Dead-pid fixture = pid 1 (EPERM → dead per `_pid_alive`); live-pid fixture = the suite's own `$$`.

## 5. Live registry, before → after a real sweep (2026-09-06)

Snapshot `6b384a55f0def6b1`; sweep log `/tmp/leadv2-ssw-live.log`. Before: **40 rows, 0 `stale`** (26 pid-less recovered_unowned, 2 pid-alive, 12 pid-dead).
- after: **10 rows marked stale**; audit vs the snapshot: every newly-stale row was provably dead
  at snapshot time (`violations: NONE`); live-pid rows `STALE-SWEEPER-WIRING-01` (pid 33367) and
  `dispatch-c4c38811` (pid 10746) unmarked; pid-less rows marked: NONE; 2 of 12 dead-pid rows
  spared by agents-JSON corroboration (by design). GC removed 35+ dead worktrees (policy-gated).
- fanout's `not s.get("stale")` count: 40 → **30** vs `hard_limit: 3`. Honest residual: the 26
  pid-less rows are unmarkable by the fail-closed rule ordered here; they count toward the cap
  until the lane_reconcile accumulation defect (F3 bullet 3) is fixed — separate lane.

## 6. The four false statements — now true

| Location | Was | Now |
|---|---|---|
| `skills/leadv2-close/SKILL.md:226` | "runs automatically at every SessionStart" (nothing ran it) | names the carrier hook + two stages |
| `scripts/leadv2-outcome-watch.sh:12` | "Called by leadv2-stale-sweeper.sh at every SessionStart" | true again: detached stage calls `--sweep`; says so |
| `docs/phases.md:78` | intake list implied a manual startup call | automatic-at-SessionStart via the hook; manual call = mid-session re-run |
| `scripts/leadv2-phase8-close.sh:322` | "swept at every SessionStart by stale-sweeper" | true again, names carrier + detach |

## 7. Falsification set

- `bash -n` on all changed shell files: OK; `python3 -c json.load` on `hooks.json`: valid. No Python files changed.
- Suite re-run on committed bytes at resume: `test-stale-sweeper-wiring: 12 passed, 0 failed`; CI selection (state file reset first): `[SELECT] …/test-stale-sweeper-wiring.sh` (10 suites).
- Changed-scope runner (foreground, ~25 min):

```
run-all: 8 passed, 2 failed, scope=changed
  Failures (blocking):
    - plugins/leadv2/scripts/tests/run-core-offline.sh
    - plugins/leadv2/scripts/tests/test-phase8-closes-the-backlog-row.sh
```

  **Both are pre-existing, not this lane's** — reproduced on clean `main` (detached temp worktree,
  standalone re-runs): the phase8 suite shows the same `ERROR: Target missing: …/LEAD_V2_STATE.md`
  on main (this lane's phase8-close diff is comment-only); run-core-offline — lane-safety red
  `P14-pid-birth-lib-absent-degrades` (`lib/leadv2-worktree-protected.sh`, untouched) is red on
  main too; other inner reds are allow-listed (`tests/known-red-suites.txt`) or environmental
  (concurrent core-offline; pre-existing dirty `docs/leadv2/`).
- `tests/known-red-suites.txt` / `known-failures.txt`: untouched (may only shrink — nothing added).

## 8. Residual / follow-ups

- 26 pid-less `recovered_unowned` rows still count toward fanout's cap (unmarkable by design) —
  the reconcile-accumulation defect needs its own lane; detached stage-2 has no singleton lock
  (registry ops flock'd per row; GC refusal-gated) — observed benign.
