# D2-SINGLE-LIVENESS-VERDICT — producer census (read-only, no code changed)

Premise checked first: `docs/handoff/D2-SINGLE-LIVENESS-VERDICT/report.md` exists but
covers only M0/M1 (the finished/finished_unlanded rungs) — not this survey. No prior
producer census exists anywhere under `docs/handoff/`. This is genuinely new work.

## 1. Producer census — who decides "alive/dead/unknown", poimenno

### Family A — `plugins/leadv2/scripts/leadv2-lane-liveness.sh::resolve(tid)` (~926-1420)
The richest and only multi-evidence producer. Ladder order: E0 contradiction guard (976,
`unknown:contradictory_rows`) → child fold (940, `child`) → `finished:` git-commit rung
(1048) → E1/prepass stream (1157-1211: `starting:<age>`, `silent:<age>`,
`dead:silent_<age>s_abandoned`) → E4 deliverable rung (1263, `finished_unlanded:<age>s`) →
handoff-dir checks (1257 `unknown:deliverable_dir_unreadable`, 1273
`unknown:yaml_unreadable`, 1277 `dead:no_handoff_dir`, 1279 `dead:no_log_artifact`) →
provider status (1307, 1310, 1321: `alive` / `dead:provider_<status>`) → wedge/abandon
tail (1356 `dead:wedged_STAT=<stat>`, 1382/1391/1393/1395/1403: `silent:*`/`dead:silent_*`).
17 distinct verdict strings total. **`unknown:*` is a genuine third state** — every
consumer must match it explicitly or it falls through to a `*)` arm (this is exactly
D2's M1-M2 problem: 41/62 callers didn't).

### Family B — `plugins/leadv2/scripts/lib/leadv2-lane-state.sh::proc_verdict/verdict/alive` (60-127)
Narrow and deliberately so: answers only "is the recorded pid still *this* process"
(pid-reuse detection for the single-writer registry row), not "is the lane's work done".
`proc_verdict(pid, recorded_birth)` (104): `os.kill(pid,0)` → `ProcessLookupError`→`'dead'`
(the only proof of death); `PermissionError`→ falls through to birth comparison (EPERM
means alive, owned elsewhere); bare `OSError`→`'unknown'`; missing/unobservable birth on
either side →`'unknown'` (incomparable, never a kill); birth mismatch →`'dead'` (pid
reuse); match →`'live'`. **Three-valued, correctly implemented.** `alive(row)` (127) is
`verdict(row) != 'dead'` — so `'unknown'` collapses to **True (counted alive)**,
explicitly and intentionally (comment at 104-109 cites the exact contract
`leadv2-orphan-reaper.sh`'s `_owner_death_state` already carries, `16efd6fa`).

### Family C — `plugins/leadv2/scripts/leadv2-active-registry.sh` — **5 independent, all still buggy**
This is the finding that matters. Grep for `_pid_alive`/`pid_alive`/`_prlr_alive` in this
one 2187-line file returns **five separate embedded-Python function definitions**, at
lines 322, 1576, 1664, 1827, 2117 — each in its own heredoc, none calling a shared helper.
**All five still use the OLD two-valued collapse**:
```python
except (TypeError, ValueError, ProcessLookupError, PermissionError):
    return False
```
`PermissionError` (EPERM — the pid **exists**, owned by another user — alive) is
collapsed into `False`/dead, the exact bug class D2-M4 spent this session converting
everywhere else in the plugin. **This file was never in M4's scope** (`git log` on it
shows no D2-M4/EPERM/ESRCH commit) and Leadmain's own framing ("counters that never
asked about liveness, already closed, `4aa51b34`") is now **out of date**: `4aa51b34`
landed early THIS MORNING (2026-09-06T05:07) and is exactly what *introduced* two of the
five sites (1576, 1664) by adding `_row_dead()` calling `_pid_alive()` — it fixed a real
overcounting bug (dead-pid tombstones inflating the session count) but did so with a
freshly-copied, still-buggy primitive.

Effect of each site:
- **322** (`_lv2_ws_dead`, 383) — writeset-conflict admission. `_lv2_ws_dead(other)` is
  `pid is not None and not _pid_alive(pid)`. An EPERM-owned (alive, foreign-owned)
  incumbent is misread as dead → the admission check treats a live conflicting lane as
  gone → **a new dispatch can be let through against an active write-set conflict.**
- **1576** (header/table `_row_dead`) — display only, cosmetic (a live foreign-owned
  worker shows `DEAD` in the table).
- **1664** (`check_limits`'s own `_row_dead`, feeding the `sessions = [... if not
  _row_dead(s)]` filter) — **capacity admission**. An EPERM-owned live pid is filtered
  out of the live count → `check_limits` **undercounts active sessions → can admit more
  lanes than the real cap.** This is the opposite direction of the bug `4aa51b34` was
  fixing (overcounting), landed in the same commit.
- **1827** (`pid_alive` in the refresh_existing branch) — same collapse, refresh-path
  liveness read; not traced further under the read-only mandate.
- **2117** (`_prlr_alive`, release path) — same collapse; used in duplicate-row release
  handling per the surrounding comment ("Liveness is not just PID alive... kind read from
  live process argv").

Filed to backlog as `ACTIVE-REGISTRY-FIVE-EPERM-COLLAPSING-PID-ALIVE-01` (priority 90,
`docs/tasks.yaml`, persona-engine commit `20af518be`) rather than fixed here — this
survey's mandate was read-only, and the file is not one of the two currently
worktree-locked, so it's a clean pickup for whoever takes it next. Two ready-made correct
reference implementations exist to copy from (bash: orphan-reaper's `_pid_alive()` line
130; python: lane-state's `proc_verdict()`), so the fix is a mechanical replace of all
five sites with one shared primitive, not new design.

### Family D — `plugins/leadv2/scripts/leadv2-orphan-reaper.sh` — correct, and a separate question
Two producers here, both correct:
- **`_pid_alive()` (bash, line 130)** — the canonical three-answer bash primitive:
  `kill -0` rc=0 → alive; else stderr pattern-matched for
  `not permitted`/`Not permitted`/`operation not permitted` → alive (EPERM); anything
  else → dead (ESRCH). This is the reference implementation the whole session's D2-M4
  conversions were modeled on.
- **`_owner_death_state()` (223-257)** — a higher-level oracle answering a THIRD, distinct
  question: not "is this pid alive" but "is the **owning claude session** (by
  `CLAUDE_PID=` or `CLAUDE_CODE_SESSION_ID=` in the candidate's env) verifiably gone".
  Returns `live` / `unknown` / `dead(<reason>)`. Verified claim: **unknown never kills**
  — the only branch that calls `_term` on a ppid=1 sweep candidate is line 501,
  `elif [[ "$ppid" == "1" && "$owner" == dead* ]]` — `unknown` and `live` both fall
  through untouched. **Claim confirmed accurate**, with the line number. (One adjacent,
  narrower branch at line 546, the beat-loop sweep, kills purely on age when *no owner
  env is readable at all* — a different, pid-less precondition, not a violation of the
  same rule; the comment there explains why: "new loops carry their own owner-pid +
  transcript belts and self-exit".)

## 2. Verdict: unify or not?

**Do not collapse A/B/D into one function — they answer three genuinely different
questions with different evidence requirements:**
- A (`resolve`) answers "is this **lane's work** finished/abandoned" — needs git commits,
  deliverables, stream freshness; a pid check alone is provably wrong in both directions
  (the brief's own W2/W3 findings).
- B (`proc_verdict`) answers "is the recorded pid still the same OS process" — a narrow
  registry-row single-writer question that would be *harmed* by dragging in git/deliverable
  evidence it has no use for.
- D's `_owner_death_state` answers "is the owning **session**, not this pid, gone" — a
  third axis (session-level, not process- or lane-level).

**Do unify C.** Family C's five sites are not a legitimately different question — they
are the exact same "is this recorded pid still running" primitive that B and D already
answer correctly, just pasted five times with the pre-fix bug. This is D2-M4's exact
mandate, just in a file M4 never reached. One shared primitive, five call-site swaps.

## 3. What `unknown` must mean at each caller

The rule Leadmain is holding — `unknown` never kills, never restarts — is: **correctly
implemented in B (`alive()` counts it as alive) and D (kill gate requires `dead*`
specifically)**. It is **not yet a testable question in C**, because C's five sites don't
have an `unknown` state at all — they collapse `unknown`-shaped evidence (EPERM, and any
other `OSError`) straight into `dead`, which is worse than "no explicit unknown handling":
it's an unknown silently misfiled as the most consequential of the three answers. Fixing
C to use the shared three-answer primitive would, for free, turn each of its five sites
into the same "unknown never kills/restarts" shape B and D already have — the census
photograph didn't have to guess this: the pattern to copy already exists twice.

A's `unknown:*` verdicts are a different case again — they're not binary "unknown vs
resolved", they're a **third state that must propagate up to the lane state-machine
itself** (an E0 contradiction, an unreadable handoff dir), not something a caller should
resolve to alive-or-dead at all. This is D2's own M2 problem (consumer conversion), out
of scope here and already tracked by the D2 migration table.

## Not done here (by design, per Leadmain's instruction)

No code was written. `lib/leadv2-lane-state.sh` and `scripts/anti-silence-pulse.sh`
were read for this census but not touched (both currently under live lanes elsewhere).
