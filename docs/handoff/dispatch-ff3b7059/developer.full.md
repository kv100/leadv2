# MENUBAR-SHOWS-DEAD-LANES-AND-HASH-NAMES-01 — developer implementation

Implemented the architect's scoped design in full, inside `render_single_lead()`
(`plugins/leadv2/scripts/leadv2-status-surface.sh`, ~L2597-3218 after the edit). No
legacy-mode code was touched. No ledger writers were touched.

## What changed

### Bash layer (source-list build)

- New env: `LEADV2_STATUS_AGGREGATE` (default `1`), `LEADV2_STATUS_STATE_ROOT` (test
  seam; production default `dirname "$STATE_DIR"`).
- `render_single_lead()` now builds `LEADV2_SL_SOURCES`, a tab/newline-joined string
  (bash 3.2 has no arrays): `repo\tres_path\tterm_path\tverifiable`, current repo
  first, then every other `*.jsonl` basename under `LEDGER_DIR` (deduped via a
  space-padded "seen" string, not an array).
- **Deliberate deviation from the design's literal formula for the CURRENT repo**: the
  design says every repo's terminal path is `${STATE_ROOT}/<repo>/dispatch-ledger.jsonl`.
  In production this is byte-identical to the pre-existing `${STATE_DIR}/dispatch-ledger.jsonl`
  expression (leadv2-state-path.sh names `STATE_DIR` after the repo slug, confirmed by
  reading that script: `STATE_ROOT="${STATE_BASE}/${REPO_SLUG}"`). I kept the literal
  `${STATE_DIR}/dispatch-ledger.jsonl` expression for the current repo's source entry
  and only applied the `STATE_ROOT/<repo>/...` formula to aggregated (foreign) repos.
  This preserves every existing single-repo test fixture (which sets `STATE_DIR`
  directly to a flat tmp dir, not nested under a root/`<repo>` structure) without
  restructuring ~15 pre-existing fixtures, while being observably identical to the
  spec in production.
- `LEADV2_SL_STATE_DIR` and `LEADV2_SL_CLOSING_GRACE` (default 300s) are new exports
  the python heredoc reads.

### Python layer

- `tail_lines(path, n)` now takes an explicit depth — reservations still `400`,
  terminals now `2000` (Rule T).
- `_build_pid_argv`, `_codex_pid_is_worker`, `_supervise_pid` (C3): `codex_census()`
  now requires argv corroboration against the one ps snapshot already in scope
  (default-deny — unknown/absent argv rejects, `leadv2-codex-lead.sh` argv rejects,
  only `leadv2-codex-session-runner.sh` / `leadv2-session-runner.sh` /
  `leadv2-session-spawner.sh` / `codex exec` argv accepts). The supervise-sentinel
  pid (`<STATE_DIR>/.supervise-active`) is additionally stripped from `live_procs`
  **after** merging every census source (not just codex), per item 3 of C3.
- Terminal/reservation reading is now per-source, with Rule U: a repo whose terminal
  ledger cannot be read (missing, unreadable, malformed) contributes zero rows and
  emits a `<repo> terminals unreadable` warning line — **except** the current repo,
  which keeps its pre-existing contract (a missing file leaves the terminal index
  empty with no fail/warning; a *read* failure still raises into `fail()`).
- `res_by_sig` / `res_by_name` and `term_by_sig` / `term_by_name` are now **per-repo**
  dicts (never a substring/cross-repo match) — `_match_reservation()` searches sig8
  across all sources (current-repo-first) before falling back to name, and
  `_terminal_hit()` looks up only within the lane's own attributed repo.
- `lane_name()` (C4): `res.task_id → res.founder_task_id → res.lane_label →
  term.task_id → term.founder_task_id → non-hex8 census.task_id → sig8`. Adding
  `lane_label` to this chain is the actual fix for defect 4 (reservation writers
  populate `lane_label`, not `task_id`).
- `lane_phase()` (C4): terminal (within grace) → review-dir → worker (in census) →
  architect-dir → queued. Foreign-repo phase degrades to worker/queued only (no
  `PROJECT_ROOT`/handoff signal available for another repo), exactly as specified.
- Rule R (retention): a terminal hit within `grace` (300s default) → `state=closing`,
  rendered but excluded from the header's active count; older → the lane is dropped
  entirely, never rendered.
- Detail-line format changed from `<task_id[:20]> <arm> <age> <state>` to
  `<name[:24]> · <phase> · <arm> <age>[ · <repo>]` (repo suffix only when the source
  list has >1 entry — verified: single-repo fixtures render byte-identically minus
  the phase field). Header line format is **unchanged**
  (`mode=single-lead active <N> <name[:20]> <arm> <age>`), so `.10s.sh` and the badge
  parser needed no changes — verified by inspection of `leadv2-status-surface.10s.sh`
  lines 191-234, which only ever awk-splits the header on whitespace.

## Tests

All in `tests/test-status-surface-single-lead.sh` unless noted, exactly the 6 cases
architect specified (§4 items 1-5, with T-term and T-lead each having 2 sub-assertions
matching the spec's "second variant" / "companion positive"):

1. **T-term** (×2): stale (10m) terminal drops the lane entirely; fresh (60s) terminal
   renders it `closing` and excluded from the active count.
2. **T-lead** (×2): a `.session-runner.pid` whose argv is `leadv2-codex-lead.sh` never
   renders; the identical shape with `leadv2-codex-session-runner.sh` argv does.
3. **T-multi**: a second repo's reservation-only lane is visible with `· repo-b` on its
   detail line.
4. **T-unverifiable**: a repo with a reservation ledger but no terminal ledger
   contributes zero rows and prints `⚠ repo-c terminals unreadable`.
5. **T-name** (×2): `lane_label` resolves the human name + `architect` phase from a
   `dispatch-<sig8>-architect` handoff dir; a sibling row with no name fields at all
   falls back to the sig8, phase `queued`.
6. **`tests/test-status-surface-bash32.sh` T7** (new): `env -i` minimal-PATH single-lead
   render directly against the renderer (`--single-lead`), proving the new bash 3.2
   source-list loop parses and runs under the stripped SwiftBar launch shape.

### Existing-fixture format-migration note

The detail-line format change (mandated by C4) required updating the *assertions* in
5 pre-existing cases in `test-status-surface-single-lead.sh` — cases (a), (c), (d),
(f), (g) — from matching the old trailing `active`/`closing` word to the new
`· <phase> · <arm> <age>` shape. Case (d)'s fixture terminal row also needed a
`created_epoch` added: the pre-existing fixture omitted a timestamp entirely (relying
on the old code's presence-only check), which under the new Rule R defaulted to
`epoch()`'s `0` fallback and made the terminal look ~55 years stale, dropping the lane
instead of marking it `closing`. Verified real production writer
(`leadv2-dispatch-ledger.sh` line 234) always stamps `"ts"` — this was a fixture gap,
not a real-data risk. Case (g)'s `PS_STUB` was given a corroborating `codex exec` argv
line so it continues to exercise `codex_census()` (rather than silently falling through
to the reservation-only path, which would have made the test pass without actually
testing what its name claims).

Two of my own new tests (T-lead, T-name) needed their handoff-dir fixture path moved
from the suite's general-purpose `$HANDOFF` (`$FIX/handoff`) to `$PROJECT/docs/handoff`
— `codex_census()` and `lane_phase()`'s architect/review-dir check both hardcode
`<PROJECT_ROOT>/docs/handoff` (matching the architect's evidence and design), which
does not equal the suite's separately-sandboxed `$HANDOFF` var used by unrelated
legacy-lane-naming tests. This is a pre-existing fixture-vs-production-path mismatch
(also present, silently, in the untouched case (g) fixture, which "passes" only via
its reservation-only fallback path, not via exercising `codex_census()` at all) — I did
not fix the pre-existing case (g) instance since it wasn't part of my mandated test
set and already passes; flagging it here as a follow-up-worthy observation, not
touching it.

### T6/T7 in test-status-surface-bash32.sh needed adjustment for a new legitimate signal

T6's "no broken substring" check treated any occurrence of `"unreadable"` as a failure
signature (originally written to catch the PyYAML-fallback `"active.yaml unreadable"`
message). My Rule U warning (`"<repo> terminals unreadable"`) legitimately fires
against the *live* machine's real state in T6 (which runs the wrapper against real
`~/.claude` state, unstubbed) — the founder's own evidence table shows 4 of 6 live
repos in `~/.claude/cache/dispatch-ledger/` have no matching state dir. Narrowed the
check to the literal `"active.yaml unreadable"` string, which is the actual failure
signature T6 exists to catch.

## Full test output

### tests/test-status-surface-single-lead.sh (23 passed, 0 failed)

```
== single-lead fixture titles ==
  ok   - status-render consumes snapshot single_lead section
  ok   - no-dispatch idle -> ⚪ idle
  ok   - active dispatch -> 🛠 abcdef12 codex 2m
  ok   - bogus state filtered -> 🛠 abcdef12 codex 2m
  ok   - pending question -> ❓1
  ok   - malformed ledger -> ⚠
  ok   - python3 unavailable -> ⚠ (no legacy fallthrough)

== process census (SWIFTBAR-ACTIVE-SOURCE-02) ==
  ok   - (a) live claude-subsession → active with sig8
  ok   - (a2) human task_id from reservation preferred over sig8
  ok   - (b) worker gone + terminal → idle
  ok   - (c) exactly 3 entries (2 live + 1 reservation-only)
  ok   - (d) glm worker + terminal → closing state
  ok   - (e) empty everything → idle

== founder-named lanes (human task_id in run-id segment) ==
  ok   - (f) founder-named glm lane → ACTIVE once with human name
  ok   - (g) founder-named codex pid-file → ACTIVE once with human name

== T-term: fresh vs stale terminal rows (Rule R retention) ==
  ok   - (T-term-1) stale terminal (10m) drops the lane entirely
  ok   - (T-term-2) fresh terminal (60s) shows closing, excluded from active count

== T-lead: the lead's own session is never a lane (C3) ==
  ok   - (T-lead-1) lead's own session excluded from lanes
  ok   - (T-lead-2) real codex session-runner still visible (exclusion is targeted)

== T-multi: aggregation across repos (repo label on foreign lanes) ==
  ok   - (T-multi) foreign-repo lane visible with its repo label

== T-unverifiable: repo lacking a terminal ledger contributes zero rows ==
  ok   - (T-unverifiable) repo with unreadable terminals contributes no rows + warns

== T-name: lane_label fallback + architect phase (C4) ==
  ok   - (T-name-1) lane_label resolves the human name + architect phase
  ok   - (T-name-2) no name fields at all -> sig8 fallback

test-status-surface-single-lead: 23 passed, 0 failed
```

### tests/test-status-surface-bash32.sh (12 passed, 0 failed, 0 skipped)

```
== T1: /bin/bash -n on the renderer ==
  ok   - renderer parses clean under bash 3.2
== T2: /bin/bash -n on the wrapper ==
  ok   - wrapper parses clean under bash 3.2
== T3: env -i minimal PATH (the actual SwiftBar launch shape) renders lanes ==
  ok   - wrapper renders 9 lane row(s) under minimal PATH + bash 3.2
== T4: a dead renderer produces the failure title, never a confident 0/0 ==
  ok   - wrapper reports renderer failure, not a confident 0/0
== T5: STATUS-SURFACE-R5-01 — name resolution, unnamed, age-out, limits ==
  ok   - R5-C1: legacy stays unnamed; single-lead may resolve handoff title
  ok   - R5-C2: no-name lane renders exactly 'unnamed' (no dispatch-<sig8> in NAME)
  ok   - R5-C3: age-out boundary — live@100000 + done@899 present, done@901 absent, header counts drop
  ok   - R5-C4: heuristic cap -> 'не измеряется', no fabricated 'claude: N%'

== T6: STATUS-SURFACE-R5-01 round 2 — minimal-env parity (PyYAML-optional reader) ==
  ok   - _t6a: minimal-env render has no broken substring
  ok   - _t6b: lane row-count parity (min=9 full=9)
  ok   - _t6c: urgent parity (min=-1 full=-1)

== T7: env -i minimal PATH single-lead render (MENUBAR-SHOWS-DEAD-LANES-AND-HASH-NAMES-01) ==
  ok   - T7: single-lead source-list loop parses/runs under stripped env (rc=0, no ⚠)

test-status-surface-bash32: 12 passed, 0 failed, 0 skipped
```

### plugins/leadv2/scripts/tests/test-status-surface.sh (81 passed, 9 failed — pre-existing)

Ran this suite as required by the design (§4, third suite). It reported the same
`81 passed, 9 failed` **both before and after** my change — confirmed by copying the
pre-edit file (`git show HEAD:...`) back into place, re-running, and diffing the two
runs' failure lists (identical). Root cause of all 9: this suite's fixtures never stub
`LEADV2_STATUS_PS_SNAPSHOT`, so the renderer's live `ps -Ao pid=,args=` call picks up
this very session's own real claude-subsession worker processes, which several BADGE/
`--limits`/`[[`-lint assertions were not written to tolerate. Unrelated to this task;
not touched, per the "never weaken a fixture to get green" / "establish whether it
fails on clean main first" instructions.

## Non-goals honored

- No legacy-mode (`LEGACY_MODE=1`) code path touched.
- No edit to `leadv2-status-surface.10s.sh`, any dispatch/ledger writer, or any file
  outside the 3 authorized `LANE_WRITES` paths.
- No ledger writes of any kind (read-only throughout).
- No new lane-journal file — phase is derived, not persisted.
- No commit/push/merge (per role boundaries).
- One untracked-artifact cleanup: running the pre-existing
  `plugins/leadv2/scripts/tests/test-status-surface.sh` suite leaked
  `docs/leadv2/tasks/dispatch-tid0{1,2,3}001/` (a pre-existing fixture-isolation gap in
  that suite's TID-1/2/3 cases, unrelated to my change) into the worktree; removed it
  so the tree stays clean for review.

## Bash/Python syntax verification

```
$ bash -n plugins/leadv2/scripts/leadv2-status-surface.sh && echo OK1
OK1
$ bash -n plugins/leadv2/scripts/leadv2-status-surface.10s.sh && echo OK2
OK2
$ /bin/bash -n plugins/leadv2/scripts/leadv2-status-surface.sh && echo OK3
OK3
$ /bin/bash -n plugins/leadv2/scripts/leadv2-status-surface.10s.sh && echo OK4
OK4
```

DELIVERABLE_COMPLETE
