# GUARD-CENSUS-IS-WRONG-01 — developer round

## Root causes found and fixed

### 1. jq parser bug (31 false "missing")
`leadv2-guard-census.sh`'s old wiring extractor:
`.command | ltrimstr("\"") | split(" ")[0] | split("/")[-1] | rtrimstr("\"")`
assumed the first shell word ends in a clean `"`. ~34 real hooks.json entries use the
degrade-log wrapper shape `"…/leadv2-x.sh"; r=$?; if …` — no space before `";`, so
`rtrimstr("\"")` never matches and the guard name comes out with a literal trailing `";`,
which then fails the `[ -f "$HOOK_DIR/$g" ]` existence check → "missing" for a file that
exists.

Fix: `capture("(?<n>[A-Za-z0-9_.-]+\\.sh)"; "").n`, a layout-independent regex that finds the
first `*.sh` token wherever it sits in the command string.

### 2. Dispatcher-follow (53 false "not-wired")
Guards routed only through `leadv2-bash-pre-dispatch.sh`'s `MANIFEST='script|trigger'` table
(e.g. `leadv2-block-bash-heredoc.sh`) never appear as top-level `hooks.json` entries, so they
were always "not-wired" regardless of firing daily.

Fix: any hook script matching `^MANIFEST=` is scanned; every script named before a `|` in that
block is marked wired under the SAME event(s) the dispatcher itself is wired to.

### 3. Runner-side `ran`/`verdict` recording (partial fix for 39 false "never-ran")
Zero hook scripts (grep confirmed: `grep -rl 'guard-verdict\|leadv2_gv_init' hooks/` → only the
lib file itself) call `hooks/lib/leadv2-guard-verdict.sh`. The census's "never-ran" state
measures adoption of that lib, not whether a guard actually runs.

Fix implemented: `leadv2-bash-pre-dispatch.sh` now writes one `ran` row + one derived
`verdict` row (block/log/allow, from rc and stdout JSON) per dispatched guard invocation,
directly to the guard-verdict journal — centrally, at the one place every dispatcher-routed
guard's exit is already observed. This covers the ~13 guards in that MANIFEST
(`leadv2-block-bash-heredoc.sh`, `leadv2-deny-floor.sh`, `leadv2-codex-*-guard.sh`, etc).

**NOT covered**: the ~110 guards wired directly as top-level `hooks.json` entries (e.g.
`leadv2-loop-detect-hook.sh`, `leadv2-model-inherit-guard.sh`, `leadv2-block-fg-agent.sh` —
the three "never-ran" examples named in the brief). A truly central fix for these requires
adding the same record-write to the `hooks.json` wrapper template itself (the "cmd"; r=$?; ...
degrade-log shape, 34/172 entries already use it; 138 don't use any wrapper at all). `hooks.json`
is **not** in this lane's `LANE_WRITES`
(`plugins/leadv2/scripts/leadv2-guard-census.sh,plugins/leadv2/hooks/lib/leadv2-guard-verdict.sh,
plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh,plugins/leadv2/hooks/*.sh,...`), and touching
each of ~121 individual hook scripts to source a common verdict preamble was explicitly the
scale the brief said to avoid ("without touching 125 files"). Flagging as a decision conflict
rather than guessing: **founder/architect needs to decide whether hooks.json is added to
LANE_WRITES for a follow-up round, or whether per-hook preamble edits are accepted.**

## Not done (explicit, due to scope/budget)
- Item 4 (founder columns `default`/`last-fired-days`, "candidates to delete" section) — not
  implemented. `leadv2-idle-lead-guard.sh` is a concrete candidate the re-run surfaced: wired=no,
  fixture=yes (it fires under fixture but has zero hooks.json wiring) — worth the founder's eyes.
- Item 3 (fixture per BLOCKING guard) — untouched beyond the 3 new structural fixtures
  (fx-degrade-wrapped, fx-dispatcher, fx-dispatched), which exist to lock the census's OWN
  wiring logic, not to prove individual real guards fire. The `real/` fixture set is unchanged
  (still 4 fixtures) — real-tree re-run still shows `fixture-proven: 4`.
- persona-engine's repo-local `leadv2-bash-hook-dispatcher.sh` (named in the brief) — not found
  anywhere in this worktree or the persona-engine checkout by that exact name; the
  dispatcher-follow logic is generic (`^MANIFEST=` in any `$HOOK_DIR/*.sh`) so it would pick it
  up automatically if/when that file is symlinked into this plugin's hook dir, but it was not
  verified against the real persona-engine tree (out of reach from this worktree).

## Evidence

### Before (founder-supplied, saved verbatim at census-20260901.txt)
`guards: 125 | fixtures run: 4 | fixture-proven: 4 | regressions: 0`
missing: 31 | not-wired: 53 | never-ran: 39

### After — full re-run on the live tree, real fixtures
```
LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/leadv2-guard-census.sh \
  --fixtures-dir plugins/leadv2/scripts/tests/fixtures/guards/real
```
```
GUARD CENSUS — GUARDS-MUST-PROVE-THEY-FIRE-01 (2026-09-01T23:05:30Z)
guards: 94 | fixtures run: 4 | fixture-proven: 4 | regressions: 0
```
- `missing`: 31 -> 1. The 1 remaining (`leadv2-lane-watch-v2.sh`) is a REAL scope gap, not a
  parser bug: the script actually lives in `plugins/leadv2/scripts/`, not `plugins/leadv2/hooks/`
  (`hooks.json` invokes `${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-lane-watch-v2.sh`) — the census
  only searches `HOOK_DIR`. Left as-is; noting it rather than silently "fixing" it by widening
  the search path, which risks false-negatives elsewhere without a deliberate design pass.
- `not-wired`: 53 -> 13. All 13 remaining are genuinely absent from `hooks.json` AND every
  dispatcher `MANIFEST` (verified by grep — none appear in `leadv2-bash-pre-dispatch.sh`).
- `never-ran`: 39 -> 79 out of a smaller total (94 vs 125 — row count dropped because the old
  parser also polluted the `find $HOOK_DIR` universe scan with mismatched names). This RISE is
  expected, not a regression: guards previously mis-slotted into "missing"/"not-wired" now
  correctly enter evidence-tracking, and the guard-verdict journal has no history for most of
  them yet (my dispatcher fix only started recording as of this commit). Evidence accumulates
  from here forward; it cannot be back-filled.
- Full re-run output saved locally (gitignored, not committed):
  `docs/handoff/GUARD-CENSUS-IS-WRONG-01/census-rerun-20260902.txt`

### Self-check (falsification)
```
$ bash -n plugins/leadv2/scripts/leadv2-guard-census.sh && echo OK
OK
$ bash -n plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-guard-census.sh && echo OK
OK
$ LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-guard-census.sh
...
PASS: case9 fx-degrade-wrapped state
PASS: case9 degrade-wrapped guard not falsely reported missing
PASS: case9-mutation: reverting the parser fix turns fx-degrade-wrapped missing (kills the fix)
PASS: case10 fx-dispatched state (wired via dispatcher)
PASS: case10 dispatcher-routed guard correctly seen as wired
PASS: case10-mutation: removing dispatcher-follow turns fx-dispatched not-wired (kills the fix)

----------------------------------------
ALL PASS: 29 checks passed
```
Mutation controls (`case9-mutation`, `case10-mutation`) reconstruct the OLD parser / a
no-dispatcher-follow census on the fly (python3 exact-string-replace / awk block-strip) and
prove the corresponding case goes red without the fix — both pass, i.e. both mutations were
caught.

`test-guard-census.sh` is already registered in `tests/run-all.sh` (pre-existing, lines
152-153); no change needed there.

## Files changed
- `plugins/leadv2/scripts/leadv2-guard-census.sh` — parser fix + dispatcher-follow block (§1b)
- `plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh` — runner-side ran/verdict record
- `plugins/leadv2/scripts/tests/test-guard-census.sh` — cases 9/10 + 2 mutation controls
- `plugins/leadv2/scripts/tests/fixtures/guards/hooks.json` — wired fx-degrade-wrapped.sh,
  fx-dispatcher.sh
- `plugins/leadv2/scripts/tests/fixtures/guards/hook-dir/{fx-degrade-wrapped,fx-dispatcher,
  fx-dispatched}.sh` — new fixtures

## Do NOT list — respected
No guard deleted or disabled, no guard's blocking behavior changed, beat/pulse loops and the
lane watcher untouched.

Committed on `worktree-GUARD-CENSUS-IS-WRONG-01` (commit a2251c4, on top of an auto-commit
1b9d59b that had already captured the census.sh/dispatch.sh/test file edits mid-session).

DELIVERABLE_COMPLETE
