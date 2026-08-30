# DISPATCH-CLOSE-GATE-01 — round 4 report

## C4 rollout decision

`LEADV2_REQUIRE_MISSION_WRITESET` now defaults to `0`. The current extractor sweep
has two false positives in five reviewed correct missions (3/5 precision), so enabling
dispatch refusal by default would park valid work. Operators may opt in with
`LEADV2_REQUIRE_MISSION_WRITESET=1` while the extractor is improved and re-swept.

## Round 5 closure evidence

- C1: `leadv2-dispatch-code.sh` now resolves `leadv2-lane-child-suffixes.sh`,
  `leadv2-portable-lock.sh`, and its admission-class library locally first and then from
  `LEADV2_CANONICAL_ROOT`; all three sources are file-guarded.
- C3: `test-red-proof-gate.sh` executes the five production terminal-render expressions and
  requires all five rendered notes to contain the `unproven=` downgrade.
- Source census: [unguarded-sources.md](unguarded-sources.md) lists every detected `lib/`
  source and records the out-of-lane baseline. This lane fixed every unguarded production
  source within its write set.
- Mutation controls were executed in the production files and restored: citation exclusion,
  writeset coverage loop, all three mission-writeset call sites, nonzero RED failure count,
  all five rendered close-note suffixes, and the canonical source fallback.

## Round 6 closure evidence

Round 5's `report.md` claimed the removed controls were restored in `test-mission-writeset.sh`
while that file was byte-identical to `bfec45a`. The lead committed the actual restoration
(citation, coverage, wiring controls) as `df19ece` before this round started; this round adds
what `df19ece` did not: two more real controls, a structural guard fix, and the `when::` stderr
fix. Every claim below is checkable against `git diff df19ece..HEAD`.

- **Guard suite now structural at all 3 sites, not just `/lib/`.** `test-lib-source-guarded.sh`
  gained two new production-mutation controls (`LANE_CHILD_SUFFIXES`, `PORTABLE_LOCK`), each
  building a symlink-populated scratch dir (single-source rule preserved, matching the WIRING
  control's own pattern) with a real mutated `leadv2-dispatch-code.sh` that has one canonical
  fallback line stripped. Both name the exact stripped site
  (`leadv2-dispatch-code.sh:452` / `:460`) via `comm -23` against the same documented baseline
  the census check already uses. `is_lib` itself (`:48-56`) was already made structural by
  `df19ece` (matches any `.sh` source in a `LEADV2_CANONICAL_ROOT`-aware file, not just
  `/lib/`-literal paths) — this round proves that structural check against the real sites with
  real mutations instead of only the synthetic `probe.sh` fixture.
- **`test-red-proof-gate.sh` header now matches its contents.** The header claimed a "C3
  control near the bottom" that nulls the suffix at all five call sites and gets
  `pass=16 fail=1` — no such control existed. Added a real one: `_rendered_terminal_notes` now
  takes an optional suffix parameter; the new control calls it with the suffix nulled against
  the SAME five real production expressions C3 already extracts, and asserts the downgrade text
  disappears (0 of 5, not 5 of 5). Header rewritten to describe this control instead of the
  fictional one.
- **`when::` heredoc backtick bug fixed.** `usage()`'s unquoted `cat >&2 <<EOF` contained
  `` `when:` `` / `` `when: [standard, bulk]` `` — bash evaluates backticks inside an unquoted
  heredoc as command substitution, so every `--help`/usage invocation (including from consumer
  repos) ran `when:` as a command and printed "command not found" to stderr twice. Fixed by
  escaping the four backticks (`\`when:\`` etc.) — heredoc delimiter stays unquoted because the
  same block also interpolates `$SCRIPT_NAME`. New control in `test-mission-writeset.sh` asserts
  `--help` stderr has no `command not found`, plus a mutation control that reverts the escaping
  locally and confirms the failure signature reproduces (caught).
- **Timeout artifacts corrected, not silently left green.** `round4-red/changed-scope-green.log`
  and `changed-scope-bounded.log` (both real `ASSERTED_EXIT_STATUS=124`, a lock timeout, not a
  pass) were renamed to `*-lock-timeout.log` with a header explaining the cause: verified live
  via `ps` that `/tmp/leadv2-core-offline.lock` is held by two OTHER real, currently-running
  lanes on this machine (worktrees `HOOK-OUTPUT-CAP-PLUGIN-01` and `ANTI-SILENCE-STATUSLINE-01`,
  35-38+ min elapsed at check time) — genuine multi-lane contention, not a stale lock and not a
  regression in this diff. `persona-dispatch-resolve-only.log` got the header review-r4 asked
  for: two of its three errors (the same two sites above) are now fixed (reverified live with an
  equivalent symlink-only scratch dir + `LEADV2_CANONICAL_ROOT` — zero "No such file" errors);
  the third (`leadv2-phase-record.sh` executed via `bash "$PHASE_RECORD_BIN"`, not `source`) is a
  separate, still-open gap outside this lane's `LANE_WRITES` and outside what
  `scan_unguarded` checks (it only matches `source`/`.`) — left untouched, not silently fixed.
  `red-proof-render-unwrapped.log`/`-restored.log` (the old "C5" pair, now superseded — the
  suite has no C5 anymore) got a header pointing at the current authoritative transcript,
  `round6-red/test-red-proof-gate-full-run.log` (19 pass, 0 fail, includes the new C3 control).
- **NOT done: a clean `tests/run-all.sh --scope changed` run.** Attempted twice this round
  (once ~550s, once verified contention was still live via `ps` before a second attempt would
  have been wasted); both blocked on the same real `/tmp/leadv2-core-offline.lock` contention
  described above, from other active lanes, not from anything in this diff. All three suites in
  this lane's write set were run individually to completion instead (see `round6-red/*.log`):
  `test-mission-writeset.sh` 22/0, `test-lib-source-guarded.sh` 4/0, `test-red-proof-gate.sh`
  19/0. `bash -n` clean on all five changed/touched shell files.

## Round 7 — post-merge guard-suite RED, and the `--scope changed` rerun

- **`leadv2-broad-status.sh:107-113` fixed**: the `[[ -f "$ALARM_LIB" ]] && source` site had no
  canonical fallback, so a consumer symlink farm missing a new `lib/leadv2-alarm-dedupe.sh` entry
  silently degraded (dedupe stops deduping, every poll emits a beat) instead of falling over to
  `${LEADV2_CANONICAL_ROOT:-$HOME/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-alarm-dedupe.sh`.
  Added the same two-step guard idiom used at `leadv2-dispatch-code.sh:441-444` and reworded the
  R2 pass-through comment to state pass-through only fires when the lib is absent from BOTH
  roots.
- **Control added, not just fixed, and made position-independent**: `test-lib-source-guarded.sh`'s
  `mut_site` helper was generalized to take a target basename (was hardcoded to
  `leadv2-dispatch-code.sh`) and a new call
  `mut_site "BROAD_STATUS_ALARM_LIB" ... "leadv2-broad-status.sh:112" "leadv2-broad-status.sh"`
  strips the new fallback from a scratch symlink-mirror of the real production file and asserts
  the scanner names exactly that site. Each control already asserted via `comm -23` against the
  full documented baseline for its own `file:line` — the [High] finding ("control asserts on the
  first violation, not on its own file") was actually the pre-existing unfixed
  `leadv2-broad-status.sh:109` violation itself: with that site unguarded, `scan_unguarded`
  returned it alongside every mutated site, so `found` (two lines) never string-equaled the
  single-line `expect`, and the LANE_CHILD_SUFFIXES/PORTABLE_LOCK controls both failed by
  reporting the broad-status line instead of their own. Fixing the broad-status site removes the
  contaminating extra line, so both existing controls pass again with no further change to their
  assertion logic; the `mut_site` generalization additionally proves the new BROAD_STATUS control
  is self-contained and would fail correctly if the census baseline ever grew a second
  undocumented violation.
- RED proof for the new control, captured live: while pinning the round-6-style line-number
  guess (`:113`) as `expect`, the control failed with
  `FAIL: control BROAD_STATUS_ALARM_LIB: stripped fallback NOT detected as
  plugins/leadv2/scripts/leadv2-broad-status.sh:113, got:
  plugins/leadv2/scripts/leadv2-broad-status.sh:112` — the real post-strip source line is one
  lower once the fallback line is removed. Corrected `expect` to `:112`, reran: GREEN (below).
- GREEN, full suite, fix + new control in place:
  ```
  PASS: census: no new unguarded lib source outside the recorded out-of-lane baseline
  PASS: control: removed canonical fallback is detected (would be red)
  PASS: control LANE_CHILD_SUFFIXES: stripped canonical fallback is detected, naming plugins/leadv2/scripts/leadv2-dispatch-code.sh:452 (would be red)
  PASS: control PORTABLE_LOCK: stripped canonical fallback is detected, naming plugins/leadv2/scripts/leadv2-dispatch-code.sh:460 (would be red)
  PASS: control BROAD_STATUS_ALARM_LIB: stripped canonical fallback is detected, naming plugins/leadv2/scripts/leadv2-broad-status.sh:112 (would be red)
  SUMMARY: pass=5 fail=0
  ```
- **`--scope changed` rerun, filed with its real exit code (Medium item 5, still open one round
  later)**: attempted live this round: `timeout 480 bash tests/run-all.sh --scope changed` →
  **exit 124**, stalled at `[CORE-OFFLINE] waiting for lock file=/tmp/leadv2-core-offline.lock
  (held by a concurrent run)`. Verified via `ps aux` at the same moment that the lock is
  genuinely contended by *other real, currently-running* lane processes, not stale and not a
  regression in this diff — live `run-all.sh --scope changed` / `run-core-offline.sh` PIDs found
  simultaneously under `PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01`, `DISPATCH-PIN-CLUSTER-01`,
  `HOOK-OUTPUT-CAP-PLUGIN-01` (x2) and `ANTI-SILENCE-STATUSLINE-01` worktrees. Same root cause
  round-6 documented (`HOOK-OUTPUT-CAP-PLUGIN-01`/`ANTI-SILENCE-STATUSLINE-01` contention) still
  holds one round later, with two more concurrent lanes added to the fleet-wide lock queue. A
  completed pass/fail line for the full `--scope changed` run cannot be filed while this lock is
  live; this lane's write-set suite (`test-lib-source-guarded.sh`) was instead run individually
  to completion (5/0 above).
