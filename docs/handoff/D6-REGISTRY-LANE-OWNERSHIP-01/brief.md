# D6 — Registry Lane Ownership: `lead_session_id` stops lying

## Goal
Give every lane registration a session identity that is unique per concurrent lead
process, stable for that process's life, independent of any lane it outlives, and
verifiably dead once the process is gone — so `lead_session_lane_cap` (and any future
per-session accounting: liveness, "whose work is this", cleanup) is computed against the
right set instead of one shared `"direct"` bucket.

## Where "direct" is assigned — file:line, and why
One fallback expression, duplicated inline at FIVE call sites, never a shared function:
`"${LEADV2_LEAD_SESSION_ID:-${LEADV2_PARENT_SESSION_ID:-${CLAUDE_SESSION_ID:-direct}}}"`

| # | Site | Feeds |
|---|------|-------|
| 1 | `leadv2-dispatch-code.sh:7071` (OFF-LIMITS, read-only) | `lane_register` → admission refusal at `:7077` |
| 2 | `leadv2-codex-session-runner.sh:101` | `lane_adopt_pid`→`lane_register` (codex spawn path) |
| 3 | `leadv2-session-runner.sh:197` | `lane_adopt_pid`→`lane_register` (generic runner path) |
| 4 | `leadv2-inbox.sh:123` | default `--lead` for `drain` (inbox scoping) |
| 5 | `leadv2-broad-status.sh:1396` | same, for the beat's own inbox drain |

**An identity is available and is IGNORED — not absent.** Grepped the whole tree
(excl. `.claude/worktrees`, `node_modules`) for a production setter of the first two env
vars: zero. Both, and `CLAUDE_SESSION_ID`, are assigned ONLY inside test files
(`test-lane-placement-pin.sh`, `test-lead-worker-channel.sh`,
`test-question-delivery-ownership-01.sh`) to simulate sessions. No launcher, hook, or
`.claude/settings.json` env block exports any of the three in production, so every real
lead process falls through all three, always — not occasionally.

Meanwhile `leadv2-active-registry.sh:809` (already sourced at the dispatch-code.sh call
site, 20 lines above :7071, for `leadv2_active_register`) defines `_lv2_durable_pid()`:
walks `$PPID` via `ps -o ppid=`/`ps -o comm=` to the ancestor whose `comm` contains
`claude` — the real lead CLI process, not a short-lived bash subprocess — with a paired
`_lv2_pid_birth()` (`ps -o lstart=`, already Darwin-padding-hardened). Both are proven in
production today for a *different* registry's `session_id`. The `lead_session_id` chain
never calls either.

## Identity candidates — verdict each
- **Harness `CLAUDE_SESSION_ID`** — REJECT: never set in prod, test-only.
- **UUID minted at start, persisted** — REJECT: needs a new launcher/hook write-path this
  repo doesn't have; adds a moving part the next candidate avoids.
- **`uds:/tmp/cc-socks/<pid>.sock`** — grep for `cc-socks`/`uds:/tmp` under
  `plugins/`, `.claude/` (excl. worktrees/node_modules) is EMPTY; it only matched inside a
  `developer.stream.jsonl` tool-init blob when the search wasn't scoped. Confirmed
  harness-internal, not a leadv2-addressable primitive — but its PID-keyed addressing
  corroborates PID as the right axis.
- **`_lv2_durable_pid()` + `_lv2_pid_birth()`** (existing, `leadv2-active-registry.sh:809`)
  — unique per concurrent process (real OS PID); stable for session life (built
  specifically to survive a short-lived subshell exiting — its own doc comment); survives
  a lane outliving its lead (stored as an opaque string at register time, never
  re-resolved, needs nothing from the lead afterward); recognisably dead
  (`os.kill(pid,0)` + birth-string match is the exact pattern `leadv2-lane-state.sh`'s own
  `alive()` already uses for lane liveness, lines 57-65 — trivially reusable). **ACCEPT.**

**Chosen:** `lead-<durable_pid>-<birth_hash>` (`cksum` of `_lv2_pid_birth`, to
disambiguate PID reuse over time). Also store `lead_pid`/`lead_pid_birth` as their own
row fields, mirroring the existing `pid`/`pid_start_time` pair — an opaque id is enough
for bucketing, but D4 needs raw pid+birth to check "is the owning lead alive" without
re-parsing a string.

## Migration of live rows
**Do not rewrite existing rows.** The lead PID behind a `"direct"` row was never
recorded — nothing to recover it from; a backfill would be a guess wearing a confident
label. Old rows keep `lead_session_id: direct` until they age out through mechanisms that
already exist, unchanged: a TRUE terminal removes the row
(`_lv2_terminal_unregister_lanes`); `lane_reconcile` marks a row dead once its pid stops
matching its recorded birth. Same posture the registry already takes toward its
`"recovered"` sentinel (`leadv2-lane-state.sh:142`): introduce the new value, let the old
one drain, never mass-edit. `"direct"` also stays alive going forward as the deliberate
fail-open fallback if the resolver errors — but a new row landing on it should be
journalled as an anomaly, not silent.

## Blast radius
| Reader | Change | Owner |
|---|---|---|
| `leadv2-dispatch-code.sh:7071-7083` | cap becomes genuinely per-session | off-limits — prescribe only |
| `lib/leadv2-lane-state.sh` (`lane_register`/`lane_count_live`) | none — already groups correctly by whatever string it's given | D6, no edit |
| `leadv2-broad-status.sh:1396`, `leadv2-inbox.sh:123` | fixes a second, currently-silent bug: two "direct" sessions share one inbox-drain bucket today, so session A can drain a message meant for session B's status line | D6 |
| `leadv2-codex-session-runner.sh:101`, `leadv2-session-runner.sh:197` | same admission fix, alternate spawn paths | D6 |
| D4 (`docs/handoff/D4-NO-PATH-LOSES-WORK-01/` — checked, currently empty, no artifacts) | gains `lead_pid`/`lead_pid_birth` fields + an alive-check pattern to copy for "which lanes died with this session" | D4's own lane — flagged, not built here |
| `leadv2-dispatch-ledger.sh` terminal path | unaffected — deregisters by `task_id`, never touches `lead_session_id` | none |
| `leadv2-active-registry.sh` | becomes a sourced dependency (two functions), not edited | none |

## Files allowlist
- Write: `plugins/leadv2/scripts/lib/leadv2-lead-identity.sh` (new),
  `leadv2-codex-session-runner.sh`, `leadv2-session-runner.sh`, `leadv2-inbox.sh`,
  `leadv2-broad-status.sh`, `plugins/leadv2/scripts/lib/leadv2-lane-state.sh` (additive
  fields only), `plugins/leadv2/scripts/tests/test-lead-session-identity.sh` (new),
  `tests/run-all.sh` (append-only, `EXTRA_SUITE_MAP` block).
- Read only: `leadv2-active-registry.sh`, `leadv2-dispatch-code.sh`.
- Off limits, do not write: `leadv2-dispatch-code.sh`, `leadv2-route-arbiter.sh`,
  `leadv2-claude-profile-select.sh`, `tests/known-red-suites.txt`.

## Steps
1. New `lib/leadv2-lead-identity.sh`: `leadv2_lead_session_id()` — source
   `leadv2-active-registry.sh` (guard double-source), call `_lv2_durable_pid` +
   `_lv2_pid_birth`, print `lead-<pid>-<cksum-of-birth>`. Fail-open: any error prints
   `direct` and logs one stderr line, never a hard failure.
2. Edit the 4 permitted call sites: replace only the third fallback link,
   `${CLAUDE_SESSION_ID:-direct}` → the new resolver call, keeping
   `LEADV2_LEAD_SESSION_ID`/`LEADV2_PARENT_SESSION_ID` untouched as the two
   higher-priority explicit overrides (a deliberately-nested child can still inherit its
   parent's bucket via `LEADV2_PARENT_SESSION_ID` — see `NESTED-SPAWNS.md`, unchanged).
3. Add `lead_pid`/`lead_pid_birth` to `lane_register`'s row write and a
   `lane_lead_alive <lead_session_id>` helper reusing the existing `alive()` pattern —
   both in `lib/leadv2-lane-state.sh`, additive, no signature break.
4. Write `test-lead-session-identity.sh` (below). Append `EXTRA_SUITE_MAP` rows for all
   five changed stems → `test-lead-session-identity.sh`. Prove with
   `tests/run-all.sh --scope changed`.
5. **Hand off, do not edit:** notify the session owning `leadv2-dispatch-code.sh` (via
   `ask-lead.sh` off_limits-conflict) to change line 7071's third fallback link the same
   way as step 2, and re-run `test-lead-session-identity.sh` +
   `test-lane-placement-pin.sh` + `test-dispatch-terminal-deregisters-lane.sh` before
   landing.

## Acceptance (re-runnable)
- **Distinct owners:** two `bash -c` subshells (real, distinct PIDs, no
  `CLAUDE_SESSION_ID` override — exercises the real resolver) each source
  `lib/leadv2-lane-state.sh` and `lane_register`. Assert the two rows' resolved
  `lead_session_id` differ, and `lane_count_live <each-id>` returns `1`, not `2`.
- **Cap proves the defect dead:** `LEADV2_LANE_CAP=1`. Subshell A: lane1 rc 0, lane2 rc 3
  (refused — same session). Subshell B: lane3 rc 0 (permitted — other session).
- **Orphan detection:** register a lane under a resolver id whose pid belongs to a
  subprocess this test spawns and waits to exit; assert `lane_lead_alive` reports
  dead/orphaned once it has.
- **Legacy rows resolve:** seed a fixture `active.yaml` row with `lead_session_id: direct`
  directly (fixture data, no code path); `lane_count_live direct` returns the right count,
  no exception.

## Negative control
Suite: `plugins/leadv2/scripts/tests/test-lead-session-identity.sh`. Mutation: inside the
BODY of `leadv2_lead_session_id()` (new `lib/leadv2-lead-identity.sh`) — after computing
pid/birth, force the final `printf` to unconditionally emit `direct`, discarding the
computed value. Run the suite: "distinct owners" and "cap proves the defect dead" must go
RED (both subshells collapse to one bucket again). Revert, confirm GREEN. Record both
exit codes verbatim, macOS and Linux container per shared-constraints.md.

## Out of scope
- Lowering `LEADV2_LANE_CAP` back down from 64 (founder decision) — only safe once this
  lane ships; a lower cap on top of the old collision reproduces the original bug.
- D4's own session-death sweep logic — D6 exposes `lead_pid`/`lead_pid_birth` +
  `lane_lead_alive`; D4's lane (currently empty handoff dir) consumes them.
- Any edit inside `leadv2-dispatch-code.sh`, `leadv2-route-arbiter.sh`,
  `leadv2-claude-profile-select.sh` — hand off per Step 5.
- Nested-spawn propagation policy (when a child should inherit
  `LEADV2_PARENT_SESSION_ID` vs mint its own) — governed by `NESTED-SPAWNS.md`, unchanged
  here; this lane only fixes what happens when neither override is set.
