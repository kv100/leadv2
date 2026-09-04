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

---

## LEAD ADDENDUM — the binding acceptance, and two things already right

### Only ONE acceptance closes this row

The suite keeps both checks, but they are not equal and must not be reported as if they were:

- "the registry shows two distinct owners" — **not sufficient, never quote it as the proof.** It
  shows the strings differ. It does not show anything COUNTS them per session.
- **Binding acceptance:** with the cap set to **1**, the second lane of the SAME session is
  REFUSED and a lane from a DIFFERENT session is PERMITTED. Both halves in one run. This is the
  only assertion that proves the defect dead, because it exercises the accounting, not the label.

Report the cap test with its output. A close that presents the distinct-owners check as the
result will be sent back.

Why this is not pedantry: the cap is 64 today, and at 64 the difference between "ids differ" and
"accounting works" is invisible. There is already a ledger row (`SD-LANE-CAP-BACK-TO-4-01`) to
lower it once the waves close. A weak acceptance here means the original bug returns at exactly
the moment someone lowers the cap, and it will look like a new defect.

### Two questions raised by the dispatcher's owner — both already answered above, do not change them

1. **Where the identity functions live.** `_lv2_durable_pid()` / `_lv2_pid_birth()` are in
   `plugins/leadv2/scripts/leadv2-active-registry.sh` at :809 and :860 — NOT under `lib/`.
   Verified on disk. The brief cites this correctly; keep it. A worker that goes looking under
   `lib/` will come back with "the function does not exist", which is a false negative of the
   same family we have already been burned by today.
2. **How the dispatcher reaches the function.** Not by sourcing the whole registry. The brief
   already prescribes a small dedicated resolver, `lib/leadv2-lead-identity.sh`, exposing
   `leadv2_lead_session_id()`, which both sides pull. Keep that shape: pulling the entire registry
   into the dispatcher for one identifier would add a dependency exactly where old ones are being
   untangled. (Note the registry is in any case already sourced at that call site, ~20 lines above
   :7071 — so this costs nothing and is purely about not widening the coupling.)

### Handover of the one off-limits line

`leadv2-dispatch-code.sh:7071` is owned by another session and this lane does NOT edit it. When
`lib/leadv2-lead-identity.sh` is landed AND visible in `git ls-files`, hand that session the exact
replacement text for the third fallback link — not before. They have said they will apply it from
the finished artifact, never blind.

---

## LEAD ADDENDUM — `pid: 1` makes a registry row IMMORTAL, and that belongs to this lane

Measured on the live registry 2026-09-04 by session persona-engine-c2, and folded into this lane
because it is the same defect this lane exists to fix: **the registry lies about who owns a lane.**

The registry held 106 rows. A naive liveness check called 18 of them alive — and **eleven of those
eighteen carried `pid: 1`.** PID 1 is `launchd`. It is alive always, on every machine, forever.
So `kill -0 1` succeeds for the rest of the machine's uptime and **a row with `pid: 1` can never
be reaped.**

The second half is what turns an annoyance into a permanent lock. `leadv2-dispatch-code.sh:4555`
refuses to unregister when a task does not have exactly ONE row (`not_owner_row_intact`). So:

1. A dispatch fails or is refused, leaving its row behind.
2. The next attempt adds a second row.
3. Unregister now refuses — the count is not one.
4. Every further attempt adds another ghost, and the lane is **unresumable forever**, blocked by
   nothing but its own history. Measured on D4: two rows; on D6: three.

The cleanup rule that worked, use it as your specification: **a row is dead if its pid is not
alive — where `1` does NOT count as alive — AND no process holds `worktrees/<task>`.** Everything
else is preserved. 106 rows became 12; 94 removed under the file lock in one atomic write, with a
backup taken first.

### Required in this lane

- **Refuse to register a row whose pid is `1` or empty.** At the write, not at the read — a bad row
  that reaches the file has already done its damage.
- **Unregister must work for N rows, not only for N=1.** `leadv2_active_unregister <task_id>` in
  `leadv2-active-registry.sh` already removes ALL rows for a task under the lock; the `:4555`
  guard's exactly-one condition is the bug. Removing every row for a task you own is correct;
  refusing because there are two is what created the lock.
- **A scheduled sweep** using the rule above, so ghosts cannot accumulate to the point where a lane
  locks itself.
- Liveness in the sweep obeys this lane's own discipline: the pair **(pid, process start time)**,
  never the pid alone; `kill -0` classified by **stderr** not exit code; anything unanswerable is
  `unknown` and `unknown` is never swept.

### Negative controls (one per changed function, mutation inside the body)

- Registration accepts `pid: 1` → a suite assertion goes red.
- Unregister with two rows present → red if it refuses instead of removing both.
- The sweep treats `pid: 1` as alive → red.
- The sweep removes a row whose liveness is `unknown` → red. This one is the important one: it is
  the difference between a cleaner and a work-destroyer.

Registry row for the record: `SD-REGISTRY-PID-ONE-IS-IMMORTAL-01`.

---

## LEAD CORRECTION — there are TWO registries, and they disagreed. Ignore the "foreign session" theory.

An earlier lead addendum guessed that unregister fails when another session owns the row. **That
guess is retracted — it was measured and it is false.** `leadv2_active_unregister <task_id>` works
on a row written by a different session: rc=0, the task's rows go to 0.

What actually happened is worse, and it is the real requirement for this lane. **The registry
exists in more than one file, and the copies drifted apart:**

| file | rows |
|---|---|
| `~/Projects/leadv2/docs/leadv2/active.yaml` | 106 → 12 → 11 |
| `~/.claude/leadv2-state/leadv2/active.yaml` | **103** (86 of them dead, after the first was called clean) |
| `~/Projects/persona-engine/docs/leadv2/active.yaml` | 0 |

One session cleaned the first file and reported "the registry is clean". The second still held 86
dead rows. A reader looking at one file and a writer touching another produce the observation
"the command did not work" — while both are behaving exactly as written.

Note the two files are not even shaped alike: in the shared one, `pid` is the pid of the SESSION
(70832 / 79117 / 50528), so liveness there is decided differently than in the repo-local file.
A single sweep rule cannot be correct for both, which is itself an argument for one file.

**And path resolution depends on HOW the command was launched.** Under `bash -c` it breaks:

```
_leadv2_state_path_sh:10: BASH_SOURCE[0]: parameter not set
```

so the path silently moves. Which registry you edit depends not only on the repo root but on the
invocation form.

### The requirement for this lane, replacing the retracted one

1. **ONE registry.** The second copy is deleted or becomes a symlink to the first. Two files that
   can disagree is the defect; keeping them in sync is not a fix.
2. **Path resolution must not depend on `BASH_SOURCE` or on the invocation form.**
3. **Unregister must work for N rows**, not only N=1 (`leadv2-dispatch-code.sh:4555`'s
   exactly-one guard is what let ghosts accumulate until a lane locked itself).
4. **Refuse to register a row whose pid is `1` or empty** — `1` is `launchd`, alive forever, so
   such a row is immortal and can never be reaped.

**GO-condition, checkable:** the same command, run from each of the three repo roots AND under
`bash -c`, resolves to the SAME path. That is the acceptance for item 2, and it is a suite
assertion, not a claim.

Registry rows for the record: `SD-TWO-REGISTRIES-DISAGREE-01`, `SD-REGISTRY-PID-ONE-IS-IMMORTAL-01`.

### Order of the negative controls

Keep **"sweeping a row whose liveness is `unknown` turns the suite red"** FIRST. It is the boundary
between a cleaner and a work-destroyer, and that boundary has already been crossed blind twice
tonight. Every other control ranks below it.

---

## LEAD NOTE — do NOT edit `tests/run-all.sh` in this lane

This lane was refused once with `writeset_conflict`: lane `D4-NO-PATH-LOSES-WORK-01` holds
`tests/run-all.sh`, because every lane that adds a suite needs a row in the same
`EXTRA_SUITE_MAP` table. The refusal is CORRECT — two lanes editing one table produce a merge
conflict at best and a silently dropped row at worst.

So, for this lane only:

- **Do not touch `tests/run-all.sh`.** It is outside your declared write set and the dispatcher
  will refuse you again if you add it.
- Instead, put the exact row you need in your report, verbatim and ready to paste — the pattern it
  must match, the suite path it maps to, and the line it belongs after. The lead lands it once the
  file is free.
- Your CI-selection claim then reads honestly: *"the suite exists and is green; its
  `EXTRA_SUITE_MAP` row is specified in this report and is NOT yet landed, so CI does not select it
  yet."* Do not write that CI selects it. A row that is not in the file does not select anything,
  and claiming otherwise is the exact lying-green shape this wave exists to remove.

Everything else in this brief stands unchanged.

### One more reason the registry must be ONE file: a field that means two things

Measured 2026-09-04. In the repo-local registry `pid` is the WORKER's pid. In the shared
`~/.claude/leadv2-state/leadv2/active.yaml` it is the SESSION's pid. So the rule "pid alive means
the row is alive" is TRUE in one file and FALSE in the other, and a sweep that applied it correctly
still preserved a dead row — a correct execution of a wrong rule.

That class of defect is caught by neither a test of the rule nor a test of the file. It is caught
only by the field having ONE meaning. So the requirement is not "keep the two copies in sync" and
not even "delete the second copy" — it is: **one registry, one schema, and every field means
exactly one thing.** If a second file must exist, it is a symlink, never a second shape.

### SCOPE CUT (lead, 2026-09-04): the registry-hardening half moved OUT of this lane

This lane was refused with `writeset_conflict` on `leadv2-active-registry.sh` — another session is
actively editing that file. So this lane now delivers ONLY the lane-identity half:
`lib/leadv2-lead-identity.sh` and its suite. Do NOT touch `leadv2-active-registry.sh`.

The registry-hardening requirements above (one registry, no `pid: 1`, unregister for N rows,
path resolution independent of BASH_SOURCE) stay written down here as CONTEXT — they explain why
the identity must not be a session-scoped guess — but they are delivered by
`SD-REGISTRY-PID-ONE-IS-IMMORTAL-01` / `SD-TWO-REGISTRIES-DISAGREE-01`, not by you.

If your identity work needs a change inside `leadv2-active-registry.sh`, do NOT make it: write the
exact patch into your report and say it is unlanded.

---

## MEASURED PREMISE — the identity does not exist at all. Read this before you design anything.

Measured live on the registry 2026-09-04. The premise of this lane is not "identity is unreliable";
it is stronger and simpler:

```
lead_session_id:  Counter({'direct': 16})   <- EVERY row, of ALL THREE sessions
session_id:       15 distinct values        <- carries the pid: -708, -791, -857
```

**None of the three variables in the fallback chain is set in any session**, so the chain collapses
to its last resort, `direct`, everywhere:

```
${LEADV2_LEAD_SESSION_ID:-${LEADV2_PARENT_SESSION_ID:-${CLAUDE_SESSION_ID:-direct}}}
```

The same chain appears in SIX places: `leadv2-dispatch-code.sh:7083`, `leadv2-session-runner.sh:197`,
`leadv2-codex-session-runner.sh:101`, `leadv2-inbox.sh:123`, `leadv2-broad-status.sh:1396`, and the
test `test-lane-placement-pin.sh:194`.

**A discriminator already exists and is simply not used:** `session_id` carries the session's pid.

### Three consequences — all three belong in the report

1. **The lane cap is SHARED.** `lead_session_lane_cap` counts live lanes per `lead_session_id`, so
   three independent sessions share one bucket of 2. It has not fired yet (no such refusals in the
   logs), but under a live cap two sessions would lock out a third, and the refusal would look like
   anything except the truth.
2. **A lane cannot be attributed to its session** — the field is a constant.
3. **A reader forced to pick one row per task cannot pick the RIGHT one** — the field that would
   distinguish them is identical for all.

Consequence 3 re-reads an existing comment. `leadv2-lanes-snapshot.sh:644` says
`# last-write-wins on dup task_id`. That is not "duplicates were considered normal" — it is
**recorded resignation**: they cannot be told apart, so the last one is taken. And
`lib/leadv2-lane-state.sh:88-91` already names the real repair — *attribute lanes to the correct
session*. A previous author described this fix and did not make it. **This lane is finishing it.**

### GO-condition — live, not by code reading

**≥2 distinct `lead_session_id` values in the registry while two sessions are working.**

Reading the code is NOT proof here: the chain looks functional, it has six links, and it fails into
a constant silently. Only the live count proves it.

### Binding acceptance (unchanged, and it is the cap test)

With cap=1, dispatch must REFUSE a second lane of the SAME session and PERMIT a lane from ANOTHER
session. "Two distinct owners appear in a file" is not the acceptance — the cap behaving
differently for self and other is.

Registry row: `SD-LEAD-IDENTITY-COLLAPSES-TO-DIRECT-01`.
