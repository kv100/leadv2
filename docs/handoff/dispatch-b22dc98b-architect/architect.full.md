# BURN-GOVERNOR-01 — architect prepass (mechanism-closed design)

Repo: `~/Projects/leadv2`. Paths below are repo-relative unless noted.

---

## 0. Two places where code discovery contradicts the mission

Both are load-bearing. Design is written against the code, not the mission text.

### 0.1 The `hour_key` format in the mission is WRONG — the stated query silently loses up to 24h of burn

Mission says `hour_key TEXT 'YYYY-MM-DDTHH' UTC`. Live schema and rows:

```
$ sqlite3 ~/.claude/burn/history.db ".schema hourly"
CREATE TABLE hourly (
  hour_key TEXT PRIMARY KEY,
  hour_of_day INTEGER,
  day_of_week INTEGER,
  cc_sum INTEGER DEFAULT 0,
  cr_sum INTEGER DEFAULT 0,
  input_sum INTEGER DEFAULT 0,
  output_sum INTEGER DEFAULT 0,
  turn_count INTEGER DEFAULT 0
);

$ sqlite3 ~/.claude/burn/history.db "select hour_key,cc_sum,cr_sum,input_sum,output_sum from hourly order by hour_key desc limit 3"
2026-08-23-22|1099591|42424075|510|192831
2026-08-23-21|712700|27323031|338|98324
2026-08-23-20|1705391|64841567|792|308445
```

The separator is `-`, not `T`. Because the comparison is lexicographic TEXT and
ASCII `-` (0x2D) sorts **before** `T` (0x54), the mission's cutoff string
`'2026-08-22T22'` excludes **every** row of `2026-08-22-*` regardless of hour.
Measured side by side, same instant:

```
$ sqlite3 ~/.claude/burn/history.db "SELECT COALESCE(SUM(cc_sum+cr_sum+input_sum+output_sum),0) FROM hourly WHERE hour_key >= strftime('%Y-%m-%dT%H','now','-24 hours')"
1728093766

$ sqlite3 ~/.claude/burn/history.db "SELECT strftime('%Y-%m-%d-%H','now','-24 hours'), COALESCE(SUM(cc_sum+cr_sum+input_sum+output_sum),0) FROM hourly WHERE hour_key >= strftime('%Y-%m-%d-%H','now','-24 hours')"
2026-08-22-19|1993175947
```

At 22:xx UTC the `T` form undercounts by 265M (13%). The error is not constant —
the `T` cutoff degenerates to "since 00:00 UTC today", so the window width slides
from 24h down to **0h at 00:xx UTC** and back. That is exactly the 00:00–05:00
block the mission names as unattended fan-out. Shipped as written, the governor
reads `burn24h≈0` during the worst hours and never fires.

**Design decision D1: the cutoff is `strftime('%Y-%m-%d-%H','now','-24 hours')`.**
Not a variant, not a tolerant fallback — the one format the table actually uses.

### 0.2 Exit code 6 is not free — three independent callers already treat "unknown rc" as failure

The mission specifies a new rc 6 and stops at the dispatcher. Every runtime caller
of `leadv2-dispatch-code.sh` has its own `case "$dc_rc"` with a `*)` default, and
each does something wrong (in one case, actively harmful) with rc 6. See §1 and §2.

---

## 1. CALLERS / CALLEES

### 1.1 New: `plugins/leadv2/scripts/leadv2-burn-governor.sh`

Callees (all new file):
- `sqlite3` (`/usr/bin/sqlite3`, v3.51.0 — `sqlite3 --version` above), one `SELECT`.
- `date -u` for nothing; the cutoff is computed **inside** sqlite via `strftime`, so
  no GNU/BSD `date -d`/`-v` portability split is introduced.

Callers of the governor (after this change):
| Caller | file:line | Invocation |
|---|---|---|
| dispatcher burn gate | `plugins/leadv2/scripts/leadv2-dispatch-code.sh:~4449` (new, immediately above `_resolve_pinned_placement` at :4450) | `bash "${BURN_GOVERNOR_BIN}" verdict` |
| dispatcher `burn-deferred --retry-all` | `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (new `cmd_burn_deferred`) | same |
| test suite | `plugins/leadv2/scripts/tests/test-burn-governor.sh` (new) | direct |

`BURN_GOVERNOR_BIN="${LEADV2_BURN_GOVERNOR_BIN:-${SCRIPT_DIR}/leadv2-burn-governor.sh}"`
— the exact override seam every sibling already uses (`GLM_BIN` :3020,
`SUBSESSION_BIN` :3023, `CODEX_BIN` :3028, `LANE_WORKTREE_BIN` :3029,
`LANE_LIVENESS_BIN` :3032). This is the env point the mission asked for; no PATH shim.

### 1.2 Functions touched in `leadv2-dispatch-code.sh`

| Function | file:line | Change |
|---|---|---|
| `cmd_resolve` | :4318 | new `_burn_gate` call inserted at :~4449 |
| `_burn_gate` | new, placed beside `_glm_park_deferred` (:889) | reads verdict, journals, parks, exits 6 |
| `_burn_park_deferred` | new, modelled on `_glm_park_deferred` (:889–:986) | writes `docs/leadv2/burn-deferred.jsonl` |
| `cmd_burn_deferred` | new, modelled on `cmd_glm_deferred` (:988) | `--list/--json/--retry-all` |
| `usage` | :4173–:4204 | rc 6 + subcommand + env knobs |
| main dispatch `case` | :5583 | `burn-deferred) shift; cmd_burn_deferred "$@" ;;` |

Callees of `_burn_gate`: `emit` (:1233 → `leadv2-journal.sh append`), `log`
(`leadv2-helpers.sh`), `_dl_note` (:1261 → `leadv2-dispatch-ledger.sh write-terminal`),
`_burn_park_deferred`, `lv2_lock_wait` (`leadv2-portable-lock.sh`, :435).

**Placement rationale, verified against the file.** `_burn_gate` goes after the
mission/`sig8`/`JOURNAL_TASK` block (`sig8` computed :4245-ish inside `cmd_resolve`;
`JOURNAL_TASK="dispatch-${sig8}"` set there) and after `LANE_DELIVERABLE_DECL`
resolution, immediately **before** `_resolve_pinned_placement` (:4450). That is the
same "refusals are journalable but nothing is committed yet" window `_resolve_pinned_placement`
itself documents at :711–:713: *"BEFORE `record_lane_start_sha`, `_dl_note`,
`dispatch_reserve`, `architect_prepass` — no ledger row, no terminal row, no
reservation, no spawn can precede a refusal."* Consequences of that exact slot:
- Before the `ensure` worktree block (:4474–:4490) → no worktree is created, so
  nothing to reap. ✅ mission requirement.
- Before `record_lane_start_sha` (:4494) and `dispatch_reserve` → no ledger row to
  release, no dedup entry that would make the retry look like a duplicate.
- Before `architect_prepass` (:4587) → the burn refusal costs zero worker tokens,
  which is the entire point.
- **After** `_resolve_pinned_placement` would be wrong: a `--resume-lane` refusal
  (exit 5) is a placement error the founder must see even under burn pressure, and
  putting burn first means a live-lane collision is masked by a burn park. Burn
  first is nevertheless correct because burn is the cheaper check and refuses the
  whole dispatch either way; the ordering trade-off is noted, not silently taken:
  **D2 — burn gate runs first**, and its journal line names `ref=` when
  `--resume-lane`/`--worktree` was passed so a parked resume is not mistaken for a
  fresh lane.

### 1.3 Callers of `leadv2-dispatch-code.sh` — every one, including the copies

Three runtime callers, each with an independent `case "$dc_rc"`. **All three must be
edited.** This is the "independent copy nobody named" for this task.

| # | Caller | Invocation | Existing `*)` default | Behaviour on rc 6 today |
|---|---|---|---|---|
| A | `plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh:379` | `dc_out="$(cd "$_lane_dir" && bash "$DISPATCH_BIN" "${dc_args[@]}" 2>&1)"` | :465–:472 | `log_error "... failed (rc=6)"`, `_fanout_write_lane_terminal dead "dispatch_code_failed_rc_6"`, `_reap_lane_worktree_if_unused`, `exit 1` |
| B | `plugins/leadv2/scripts/leadv2-fanout.sh:1852` (`launch_via_dispatch_code`, :1742; `case` at :1854, default at :1919) | `dc_out="$(bash "$dispatch_bin" "${dc_args[@]}" 2>&1)"` | :1919+ | `log_error "... failed"` **and falls back to `_fanout_launch_full_cycle`** |
| C | `plugins/leadv2/scripts/leadv2-backlog-pump.sh:670` (`cmd_async_dispatch`) | `dc_out="$(bash "$DISPATCH_BIN" "$mission" --kind "backlog-pump" 2>&1)"` | :714–:719 | `jemit decision "pump_skip ... reason=spawn_failed rc=6"`, unclaim, release lane, `return 1` |

Caller **B is the defect that would make this feature net-negative**: the governor
refuses a lane to save tokens, and `leadv2-fanout.sh` responds by launching the
**full Opus lead cycle** for that task instead — strictly the most expensive path
in the system. A burn cap that upgrades refused work to Opus is worse than no cap.

Caller **A** mislabels a deliberate park as `dead`, which is the terminal state the
dead-lane alarm and `retry-dead` machinery consume.

Caller **C** releases the claim with `reason=spawn_failed`, so the pump re-offers the
same task on its next tick, gets refused again, and writes another `pump_skip` — a
refuse-loop that is cheap in tokens but pollutes the ledger every pump interval.

**D3: each of A/B/C gets an explicit `6)` arm before its `*)`:**
- A → `_fanout_write_lane_terminal parked "burn_hard_24h" ""`, unclaim, unregister,
  `_reap_lane_worktree_if_unused`, `exit 3` (reuse the existing "parked, returns to
  pending, not dropped" exit that rc 3 already uses; no new launcher rc).
- B → `parked` + release, **no** `_fanout_launch_full_cycle` fallback. Explicit
  comment that the fallback is deliberately suppressed for rc 6.
- C → `jemit decision "pump_parked_burn task=${tid} reason=burn_hard_24h"`, unclaim,
  release lane, `return 3` (pump's existing "deferred, do not retry this tick"
  code) instead of `return 1`.

### 1.4 `hooks/leadv2-compact-trigger.sh`

Callers: Claude Code Stop hook (registered in `settings.json`); no in-repo caller.
Callees: `jq`, `python3`, optionally `hooks/leadv2-active-cache.sh` (:207–:210).
Function touched: none — the file is a straight-line script. The change is a new
branch between the daemon block (:272–:283) and the once-per-level marker read (:286).

**Read of the existing ladder before designing (mission required this).** Levels are
computed at :233–:237 from `EST_TOKENS` against `WARN_T` 200000 / `HARD_T` 400000 /
`EMERG_T` 650000 (:226–:228), plus a non-token `long_chat` at `FOUNDER_TURNS >= 30`.
`MARKER="/tmp/.leadv2-compact-warned-${SESSION_ID}"` (:231) holds the **level string**,
and the one-shot is `[[ "$LEVEL" == "$PREV_LEVEL" ]] && exit 0` (:287) — i.e. one shot
*per level*, re-armable when the level escalates. The daemon branch uses the same
marker with the same compare (:277–:281).

Critical constraint already in the file, at :257–:262: the human-presence gate
(`COMPACT-FORCED-ON-HUMAN-01`). It exists precisely because a forged
`{"decision":"block","reason":"/compact"}` "arrives as a real user turn the lead
obeys", and `LEADV2_DAEMON` is set repo-wide so env cannot distinguish a human.
`FOUNDER_TURNS > 0` therefore **falls through to warn-only, never blocks**.

Deliverable 3 asks to invert exactly that for `emergency`. It is a real reversal of a
recorded incident fix, not an oversight, so it is designed with the guard rails the
original incident produced and the reversal is stated out loud:

**D4** — interactive emergency block, `LEADV2_COMPACT_INTERACTIVE_BLOCK` default 1:
```
LEVEL == "emergency"
  && STOP_ACTIVE != "true"            # same short-circuit the daemon branch uses (:276)
  && LEADV2_COMPACT_INTERACTIVE_BLOCK != "0"
  && LEADV2_NO_FORCE_COMPACT != "1"   # the existing hard kill-switch still wins
  && MARKER content != "emergency"    # SAME marker file, same string compare
→ write "emergency" to MARKER, print {"decision":"block","reason":"/compact"}, exit 0
```
Placed **after** the daemon branch (so a real daemon session keeps its current path
byte-for-byte) and **before** the `PREV_LEVEL` read at :286 (so a session that blocks
does not also queue a pending-warn for the same level). `warn`, `hard`, `long_chat`
reach :286 unchanged.

The reversal, stated plainly: `COMPACT-FORCED-ON-HUMAN-01` was about `warn`/`hard`
firing at a human at every level. This restricts the forced block to `emergency`
(≥650K estimated tokens), where the alternative is the founder paying ~650K input on
every subsequent turn. It is still a forged user turn at a human, it is still
one-shot, and `LEADV2_COMPACT_INTERACTIVE_BLOCK=0` and `LEADV2_NO_FORCE_COMPACT=1`
both disable it. If the orchestrator does not want that incident reversed, drop
deliverable 3; deliverables 1/2/4/5 stand alone.

---

## 2. STATES AND RETURN CODES

### 2.1 `leadv2-burn-governor.sh verdict` — always exits 0, verdict is on stdout

One line: `verdict=<ok|soft|hard> burn24h=<int> soft=<int> hard=<int> reason=<token>`

| State | stdout | Consumer action |
|---|---|---|
| governor disabled (`LEADV2_BURN_GOVERNOR=0`) | `verdict=ok burn24h=0 soft=<S> hard=<H> reason=disabled` | dispatcher: silent, proceeds |
| `sqlite3` not on PATH | `verdict=ok burn24h=0 ... reason=no_telemetry` | proceeds, silent |
| db file missing / unreadable | `... reason=no_telemetry` | proceeds, silent |
| table `hourly` missing | `... reason=no_telemetry` | proceeds, silent |
| **db locked** (rc 5) | `... reason=no_telemetry` | proceeds, silent |
| query returned non-integer | `... reason=no_telemetry` | proceeds, silent |
| `burn24h < soft` | `verdict=ok burn24h=<N> ... reason=under_soft` | proceeds, silent |
| `soft <= burn24h < hard` | `verdict=soft ...  reason=over_soft` | dispatcher prints ⚠, journals, proceeds |
| `burn24h >= hard` | `verdict=hard ... reason=over_hard` | dispatcher refuses, exit 6 |
| `hard <= soft` (misconfigured) | thresholds replaced by defaults; verdict computed against defaults; `reason` gains suffix `+bad_config` | same as the resolved verdict |

The db-locked row is not hypothetical. Observed live during discovery, on the real
file, with no fixture:
```
$ sqlite3 ~/.claude/burn/history.db "SELECT (SELECT COUNT(*) FROM hourly ...), (SELECT COUNT(*) FROM hourly ...)"
Error: in prepare, database is locked (5)
```
The burn collector writes this db continuously, so a plain `SELECT` **will** hit rc 5
in production. Mitigation is two-layer: `-cmd 'PRAGMA busy_timeout=2000'` before the
query, and any non-zero `sqlite3` rc or non-numeric stdout still collapses to
`no_telemetry`. A lock must never be able to park a lane.

Also verified: **do not use `sqlite3 -readonly`.** It fails on this db —
```
$ sqlite3 -readonly ~/.claude/burn/history.db "select 1"
Error: in prepare, unable to open database file (14)
```
(WAL mode needs to create/attach `-shm`/`-wal`). Open normally; the statement is a
`SELECT` and writes nothing.

`bad_config` handling: the mission's own wording here is self-contradictory ("say
reason=bad_config on an ok verdict only when disabled — otherwise just use
defaults"), which would make a misconfiguration invisible on the exact soft/hard
verdicts where it matters. **D5: `bad_config` is always reported**, appended to the
resolved reason (`reason=over_hard+bad_config`), never suppressed. Silent
threshold substitution is the failure mode this whole task exists to end.

### 2.2 `leadv2-dispatch-code.sh` exit codes after the change

| rc | Meaning | Where | Fanout-launcher (A) | fanout.sh (B) | pump (C) | Human-visible consequence |
|---|---|---|---|---|---|---|
| 0 | spawned / resolved | — | register worker | register worker | `pump_dispatched` | lane runs |
| 1 | usage / hard error | `usage`, arg errors | `*)` → `dead` | `*)` → full-cycle | `*)` → skip rc1 | operator sees a usage error |
| 2 | duplicate task-signature | dedup | `refused`, exit 2 | dedup branch | `pump_skip` | task is already running; nothing new starts |
| 3 | arm=opus | router | `parked`, exit 3 | fallback | `pump_deferred_to_founder` | task waits for the founder to run it by hand |
| 4 | spawn failed (retryable) | spawn path | `*)` → `dead` | `*)` | `*)` | next fanout tick retries |
| 5 | placement refused | `_resolve_pinned_placement` :741–:819 | `*)` → `dead` | `*)` | `*)` | operator sees `REFUSE placement:` on stderr |
| **6** | **burn hard cap** | **new `_burn_gate`** | **new `6)` → `parked burn_hard_24h`, exit 3** | **new `6)` → `parked`, NO full-cycle** | **new `6)` → `pump_parked_burn`, return 3** | **the lane does not start, and no worker, worktree, or architect prepass is created for it; the task's mission is written to `docs/leadv2/burn-deferred.jsonl` and the founder restarts it later with `burn-deferred --retry-all`. Nothing is lost and nothing is silently retried.** |

**Terminal trace for rc 6, in plain words.** Fanout launcher A exits 3 → the lane's
active-registry row is removed and its claim released → the task returns to `pending`.
Pump C returns 3 → `_pump_release_lane`, no re-dispatch this tick. Neither retries
automatically. So a founder who dispatches during a hard-burn window sees: one loud
`⛔ BURN GATE` line on stderr, no lane in `/leadv2 status`, and the task listed by
`leadv2-dispatch-code.sh burn-deferred --list`. **Nothing drafts, nothing spawns, and
nothing resumes until burn falls back under the cap or the founder overrides.** If
burn stays over cap for a full day, work simply does not start for that day — which is
the intended behaviour of a hard cap, and is why `LEADV2_BURN_OVERRIDE=1` exists.

**`--force` must not bypass** (mission). `--force` is already scoped to routing, and
:4184 documents "`--force` never bypasses" for dedup — burn follows the same rule.
`LEADV2_BURN_OVERRIDE=1` bypasses and journals `burn_gate verdict=hard overridden=1`,
then continues to `_resolve_pinned_placement` exactly as an `ok` verdict would.

### 2.3 `burn-deferred` subcommand rcs

Mirrors `cmd_glm_deferred` (:988–:1120): 0 success, 2 unknown flag (`usage: ...
burn-deferred [--list|--retry-all|--json]` on stderr). `--json` on a missing file
prints `[]` and exits 0 (:996-ish behaviour, kept identical).

`--retry-all` semantics, per mission: **re-dispatch a row only when the governor
verdict is no longer `hard`.** Concretely — call `verdict` **once** before the loop
(not per row: 200 rows would mean 200 sqlite opens and a verdict that can flip
mid-loop), and if it is `hard`, print `burn-deferred: still over hard cap
(burn24h=<N> >= <H>) — 0 of <M> retried` and exit 0. Rows are re-dispatched from
`docs/leadv2/burn-deferred.d/<sig8>.md`, the mission copy, exactly as
`_glm_park_deferred` does at :887–:899 and for the same recorded reason: the
lane-mission artifact does not exist yet at park time.

### 2.4 `leadv2-compact-trigger.sh` states

| Session state | Level | Output | Consequence |
|---|---|---|---|
| daemon (`LEADV2_DAEMON=1`, `FOUNDER_TURNS==0`), any token level, marker differs | warn/hard/emergency | `{"decision":"block","reason":"/compact"}` | unchanged from today |
| interactive, `emergency`, marker != emergency, `STOP_ACTIVE != true` | emergency | **new** `{"decision":"block","reason":"/compact"}` | the founder's session compacts itself once; the next turn's input drops from ~650K to a summary |
| interactive, `emergency`, marker == emergency | emergency | nothing | already blocked once this level; no loop |
| interactive, `emergency`, `STOP_ACTIVE == true` | emergency | nothing | this Stop came from our own block; hard short-circuit |
| interactive, `emergency`, `LEADV2_COMPACT_INTERACTIVE_BLOCK=0` | emergency | pending-warn `[COMPACT_NOW]` | today's behaviour |
| interactive, `hard`/`warn`/`long_chat` | — | pending-warn file | unchanged |

The hook `exit`s 0 on every path (`trap '_hook_profile_end; exit 0' EXIT` at :24 and
the ERR trap at :7), so no hook state can fail a turn.

---

## 3. CONFIGURATION BOUNDARIES

### 3.1 `LEADV2_CLAUDE_BURN_DIR` (default `$HOME/.claude/burn`)

| Input | Behaviour |
|---|---|
| absent | default `$HOME/.claude/burn`; if `$HOME` unset → path is `/.claude/burn`, file missing → `no_telemetry` |
| empty string | treated as absent (use default) — `${LEADV2_CLAUDE_BURN_DIR:-...}` already does this |
| points at a non-existent dir | `history.db` missing → `no_telemetry` |
| points at a dir with a non-sqlite `history.db` | `sqlite3` errors → `no_telemetry` |
| path containing spaces / globs | every expansion quoted; no `eval`, no word-splitting |

### 3.2 `LEADV2_BURN_SOFT_24H` (default `800000000`) / `LEADV2_BURN_HARD_24H` (default `1300000000`)

| Input | Behaviour |
|---|---|
| absent / empty | defaults |
| non-numeric (`abc`, `1.5e9`, `1_000`) | **both** replaced by defaults, `+bad_config` in reason. Never partially applied — a numeric soft with a garbage hard would silently produce `hard<soft`. |
| negative | non-numeric by the `^[0-9]+$` test → defaults + `bad_config` |
| `0` | valid. `soft=0` → every dispatch is `soft` (warning on every line). `hard=0` → **every dispatch refused**, which is a legitimate operator kill-switch, but only reachable if `hard > soft` holds, i.e. requires `soft` negative → impossible. So `hard=0` always trips the `hard<=soft` check → defaults + `bad_config`. Documented: to stop all dispatch, use `hard=1`. |
| `hard <= soft` | defaults for both + `bad_config` (D5) |
| very large (`999999999999999999999`) | compared in shell arithmetic. Values above 2^63 overflow bash 3.2 integer arithmetic. **D6: the comparison is done in the same `sqlite3`/`awk` step that produces `burn24h`, or with a string-length-then-lexical guard — not bare `(( ))`** — so a 21-digit env value cannot make the gate wrap negative and refuse everything. Over-cap input degrades to `bad_config` + defaults, never to a global dispatch refusal. |
| set to a value below current burn on a fresh machine with no db | irrelevant — `no_telemetry` wins before thresholds are consulted |

### 3.3 `LEADV2_BURN_GOVERNOR` / `LEADV2_BURN_OVERRIDE` / `LEADV2_COMPACT_INTERACTIVE_BLOCK`

| Input | Behaviour |
|---|---|
| absent | `LEADV2_BURN_GOVERNOR=1`, `LEADV2_BURN_OVERRIDE=0`, `LEADV2_COMPACT_INTERACTIVE_BLOCK=1` |
| `0` | governor off / no override / no interactive block |
| any other value including empty | treated as *not* the off-value, i.e. `[[ "${X:-1}" == "0" ]]` for the on-by-default pair and `[[ "${LEADV2_BURN_OVERRIDE:-0}" == "1" ]]` for the opt-in one. Exact string compare, never `-eq` (which errors on non-numeric under `set -e`). |

### 3.4 `docs/leadv2/burn-deferred.jsonl`

| Input | Behaviour |
|---|---|
| absent | `--list` prints "no burn-deferred rows"; `--json` prints `[]`; park creates it (`mkdir -p` on the dirname, :893 pattern) |
| empty | same as absent |
| a line of malformed JSON | skipped by the reader (`except: continue`, the :880-block pattern), never aborts the listing |
| **over-cap size** | same 500-row / 7-day truncation `_glm_park_deferred` applies at :966–:985, **including** the orphan-mission unlink at :972–:985 so `burn-deferred.d/` cannot grow unbounded. A hard-burn day could park 150+ rows; without the cap this file becomes the next unbounded-growth incident. |
| unwritable (read-only FS, full disk) | `mkdir -p ... || return 0`; the park is best-effort and **the exit 6 still happens**. A failed park is journalled (`burn_gate park=failed`) so a refused-and-unrecorded task is visible, not silent. |
| lock contention | `lv2_lock_wait "${path}.lock" 10 || exit 3` inside a subshell, same as :931; on timeout the park is skipped, gate still refuses |

**Concurrent access (mandatory checklist item 4).** Two parallel dispatches can park
to `burn-deferred.jsonl` simultaneously (fanout launches lanes concurrently). Race
surface: append + rewrite-truncate. Mitigation is the existing one, reused verbatim:
`lv2_lock_wait` on `${path}.lock` held on **fd 9 of a subshell**, never across a
spawn. Constraint from :872–:877 that must be honoured: **fd 9 is the dispatch lock fd
and fd 8 is the sidecar's** — `_burn_park_deferred` runs before any reservation
exists, so it may use the `( ... ) 9>"${path}.lock"` subshell form exactly as
`_glm_park_deferred` does. No new fd is introduced.

### 3.5 `hourly` table contents

| Input | Behaviour |
|---|---|
| table empty | `COALESCE(...,0)` → `burn24h=0` → `verdict=ok reason=under_soft`. Note this is **not** `no_telemetry`; an empty table is a real "zero burn" answer. |
| NULL columns | `COALESCE` on the SUM covers an all-NULL result; per-column NULLs make the row's addend NULL. **D7: sum as `COALESCE(cc_sum,0)+COALESCE(cr_sum,0)+COALESCE(input_sum,0)+COALESCE(output_sum,0)` per row**, not a single outer COALESCE — otherwise one NULL column zeroes that whole hour. The schema has `DEFAULT 0` but not `NOT NULL`. |
| future-dated `hour_key` | included (`>=` cutoff, no upper bound). Deliberate: a clock skew that inflates burn is the safe direction for a cap. |
| clock moved backwards | cutoff moves back, window widens, burn over-reported → over-refusal, not under-refusal. Safe direction. |
| local-time vs UTC | `strftime('now')` in sqlite is **UTC by default**; the collector writes UTC keys (confirmed: current key `2026-08-23-22` matches UTC hour at probe time). No `localtime` modifier anywhere. |

---

## 4. COUNTEREXAMPLE — what still violates the invariant after every finding is fixed

The invariant: *the machine must not be able to increase its own token fan-out
without bound.* After all of the above, three things still violate it.

**(a) The governor gates dispatch, not the workers already running.** Burn is measured
over the trailing 24h, but the mission's own numbers say a single worker session is
4–8M tokens and a marathon lead session was 513M. If 40 lanes are already in flight
when burn crosses the hard cap, the gate refuses lane 41 and the 40 in flight keep
running to completion — potentially several hundred million tokens *after* the cap
was hit. The cap therefore bounds the *rate of new starts*, not the burn, and the
overshoot past the hard line is roughly (in-flight lanes × remaining per-lane
context). Nothing in this design cancels running work, and it should not — killing a
mid-flight lane wastes everything already spent. But the cap should be read as a
soft ceiling with a large tail, and the honest name for `LEADV2_BURN_HARD_24H` is
"stop starting", not "stop burning".

**(b) The largest single measured consumer is not gated at all.** The mission's
evidence names one interactive lead session at 513M tokens — ~30% of a full day's
burn from *one* session. Deliverable 3 only fires at ≥650K estimated context, once,
and only nudges a `/compact`; it does nothing about a session that compacts diligently
and still runs 1699 turns. The dispatcher gate cannot see that session at all,
because a lead session is not a dispatch. So after this task ships, one founder in one
long window can still burn a day's budget, and the governor's only response is to
refuse the *lanes* — i.e. it throttles the cheap producer to protect budget the
expensive one is consuming. Turn-count or per-session burn governance is a separate
mechanism and is explicitly out of scope here.

**(c) Refusal has no back-pressure signal to whatever is generating dispatches.**
`leadv2-backlog-pump.sh` runs on a timer; with the §1.3-D3 fix it stops re-offering a
parked task *this tick*, but nothing tells it to slow its tick, and nothing prevents
it from offering the next 20 tasks in the backlog on the same tick — each of which
pays a `sqlite3` open and a journal line before being refused. That is bounded and
cheap (no worker, no prepass), so it is not a token risk; it is a ledger-noise and
log-volume risk. Deliberately not solved here: a pump-side burn check would be a
second copy of the same gate, which is the exact drift this repo's history keeps
punishing. The single gate in the dispatcher is the right place.

Things I checked and found *not* to be holes: the gate cannot be bypassed by a caller
that skips the dispatcher (all three callers in §1.3 go through it — `grep -rn
"DISPATCH_BIN\|dispatch-code.sh\"" plugins/leadv2/scripts/*.sh plugins/leadv2/hooks/*.sh`
returned only `record-review` / `record-quota-lockout` / `advance-arm` subcommand
calls plus the three `cmd_resolve` calls listed); it cannot leave a stuck ledger row
(it runs before `dispatch_reserve`); it cannot leave an orphan worktree (it runs
before `ensure`); and it cannot brick a fresh machine (every telemetry failure is
`no_telemetry` → `ok`).

---

## 5. Mandatory constraint checklist

1. **Env var naming** — all new vars are `LEADV2_*`: `LEADV2_BURN_GOVERNOR`,
   `LEADV2_BURN_SOFT_24H`, `LEADV2_BURN_HARD_24H`, `LEADV2_BURN_OVERRIDE`,
   `LEADV2_BURN_GOVERNOR_BIN`, `LEADV2_CLAUDE_BURN_DIR`,
   `LEADV2_COMPACT_INTERACTIVE_BLOCK`. No `LEAD_V2_*` form introduced. ✅
2. **File paths** — verified on disk: `plugins/leadv2/scripts/leadv2-dispatch-code.sh`
   (5593 lines), `plugins/leadv2/hooks/leadv2-compact-trigger.sh` (310),
   `plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh`,
   `plugins/leadv2/scripts/leadv2-fanout.sh`,
   `plugins/leadv2/scripts/leadv2-backlog-pump.sh`,
   `plugins/leadv2/scripts/tests/run-core-offline.sh`,
   `plugins/leadv2/docs/routing-enforcement.md`, `~/.claude/burn/history.db`.
   `(to-create)`: `plugins/leadv2/scripts/leadv2-burn-governor.sh`,
   `plugins/leadv2/scripts/tests/test-burn-governor.sh`,
   `docs/leadv2/burn-deferred.jsonl`, `docs/leadv2/burn-deferred.d/`. ✅
3. **`claude -p` commands** — this design introduces none. N/A. ✅
4. **Concurrent access** — §3.4. ✅
5. **Config contradiction check** — `grep -rn "LEADV2_DISPATCH_ENFORCE" --include="*.md" .`
   returned **nothing**: no markdown file documents any dispatcher env knob today;
   they live only in `usage()` at :4199–:4204. Deliverable 5's "put it beside where
   LEADV2_DISPATCH_ENFORCE is documented" has no such place. **D8: the knob section
   goes in `plugins/leadv2/docs/routing-enforcement.md`** (the dispatcher-adjacent
   policy doc) as a new `## Burn governor (BURN-GOVERNOR-01)` section, and `usage()`
   gets the same knobs inline. No pre-existing `LEADV2_BURN_*` usage exists anywhere
   in the tree (checked), so there is no semantic contradiction to flag. ✅

---

## 6. Tests — `plugins/leadv2/scripts/tests/test-burn-governor.sh` (new)

Conventions taken from `test-dispatch-silent-arm.sh` and enforced by
`test-core-offline-tmpdir-01.sh`: `set -uo pipefail`, the `compgen -e` ambient-`LEADV2_*`
scrub, `SCRIPT_DIR`/`SCRIPTS_ROOT` resolution, `source "${SCRIPTS_ROOT}/leadv2-temp.sh"`
for sandboxed temp roots, `PASS/FAIL/ERRORS` counters with `log/pass/fail`, a
`bash -n` syntax case first, and no GNU-only `date`/`sed`/`timeout`.

Registration (required — an unregistered suite never runs): one line appended to
`plugins/leadv2/scripts/tests/run-core-offline.sh` beside :310, in the existing
`name|||cmd|||SERIAL` format:
`"burn governor (BURN-GOVERNOR-01: 24h burn gate)|||bash $TEST_DIR/test-burn-governor.sh|||SERIAL"`.

Governor cases (fixture db built with `sqlite3 "$TMP/burn/history.db"` using the
**real** `-` hour_key format, rows stamped via `strftime('%Y-%m-%d-%H','now','-Nh')`):
1. `bash -n` clean.
2. sum just under soft → `verdict=ok`, exit 0.
3. sum == soft exactly → `verdict=soft` (boundary is `>=`).
4. sum == hard exactly → `verdict=hard`.
5. sum above hard → `verdict=hard`.
6. **a row at −25h is excluded and a row at −23h is included** — this is the case
   that fails against the mission's `T` format and passes against `D1`. Without it
   the §0.1 defect ships silently.
7. `LEADV2_BURN_GOVERNOR=0` → `verdict=ok reason=disabled` even with an over-hard db.
8. no db file → `reason=no_telemetry`, exit 0.
9. db present, `hourly` dropped → `reason=no_telemetry`, exit 0.
10. `sqlite3` absent — `PATH` stubbed to a dir containing only `sh`/`bash` (or a
    `sqlite3` shim that `exit 127`) → `reason=no_telemetry`, exit 0.
11. `LEADV2_BURN_HARD_24H=1 LEADV2_BURN_SOFT_24H=100` (hard<=soft) → defaults used,
    reason contains `bad_config`.
12. non-numeric threshold → defaults + `bad_config`.
13. NULL in one column of one row → that hour still contributes its other columns (D7).

Dispatcher cases (`LEADV2_DISPATCH_SPAWN=0`, `CLAUDE_PROJECT_ROOT`/`LEADV2_DISPATCH_CACHE_DIR`
sandboxed to the temp root, governor stubbed via `LEADV2_BURN_GOVERNOR_BIN` pointing at
a 3-line script that echoes a fixed verdict line):
14. stub says `hard` → dispatcher exits **6**, stderr contains `BURN GATE`, and
    `$TMP/docs/leadv2/burn-deferred.jsonl` gains exactly one row whose `reason` is
    `burn_hard_24h` and whose `sig8` matches the mission's signature.
15. stub says `hard` **+ `--force`** → still exit 6 (force does not bypass).
16. stub says `hard` + `LEADV2_BURN_OVERRIDE=1` → exit 0, resolve-only proceeds, no
    burn-deferred row.
17. stub says `soft` → exit 0, stderr contains `BURN GATE` warning, resolve proceeds.
18. stub says `ok` → exit 0 and **zero** `burn_gate` lines in the journal (the
    "no journal noise" requirement is only real if asserted).
19. hard refusal leaves **no** worktree under `$TMP/.claude/worktrees/` and **no**
    ledger row — the placement guarantee from §1.2.

Caller cases:
20. `leadv2-fanout-lane-launcher.sh` with `LEADV2_DISPATCH_LANE_...`-sandboxed env and
    a `LEADV2_...DISPATCH_BIN` stub returning 6 → launcher writes terminal `parked`
    with cause `burn_hard_24h` and exits 3 (not `dead`, not exit 1).

---

## 7. Non-goals (explicit — the implementing agent must not do these)

- No refactor of `leadv2-dispatch-code.sh` beyond the four localized insertions in
  §1.2. 324 recorded bug fixes; the diff stays additive.
- No change to the `glm-deferred` file, its shape, its subcommand, or its helpers.
  `burn-deferred` is a parallel, provider-agnostic sibling that **copies** the
  pattern; it does not generalize it into a shared helper. (Generalizing would touch
  the glm park path, which is the highest-risk code in the file.)
- No auto-retry daemon for `burn-deferred`. Manual `--retry-all` only, same as glm.
- No killing, throttling, or downgrading of lanes already in flight.
- No per-session or per-turn burn governance (see counterexample (b)).
- No burn check inside `leadv2-backlog-pump.sh`, `leadv2-fanout.sh`, or
  `leadv2-fanout-lane-launcher.sh` — they get rc-6 *handling* only, never a second
  copy of the gate.
- No new hook registration in `settings.json`; the compact-trigger hook is already
  wired.
- No changes to `WARN`/`HARD`/`long_chat` behaviour in the compact hook.
- No changes to the burn collector or to `~/.claude/burn/history.db`'s schema — this
  design is a pure reader.
- Nothing outside `~/Projects/leadv2` is edited.
- Operational note for the orchestrator, **not** a lane write: per the shared-trees
  policy, a hook change requires copying the edited hook into the plugin cache and
  restarting the session, or deliverable 3 never loads.

---

## acceptance

```
acceptance:
  - surface: log_line
    observable: "During a window when the machine's own 24-hour token burn is above the hard cap, a founder who starts a lane sees a single loud line naming the burn number and the cap, and the lane simply does not start — no worker appears in the status surface and no new worktree appears on disk."
    authored_at: 2026-08-23T22:55:00Z
  - surface: file_artifact
    observable: "After such a refusal, docs/leadv2/burn-deferred.jsonl contains one new entry for that task, and listing burn-deferred shows the task by name with the time it was turned away, so the founder can see exactly which work was postponed and restart it later."
    authored_at: 2026-08-23T22:55:00Z
  - surface: log_line
    observable: "When burn is between the soft and hard marks, the lane still starts, and the founder sees one advisory line saying burn is elevated and non-critical lanes are worth deferring."
    authored_at: 2026-08-23T22:55:00Z
  - surface: log_line
    observable: "On a machine with no burn telemetry at all — the database absent, or sqlite unavailable — dispatch behaves exactly as it does today: no burn line is printed anywhere and every lane starts normally."
    authored_at: 2026-08-23T22:55:00Z
  - surface: log_line
    observable: "A lane turned away for burn is recorded as postponed and returned to the pending pile; it is never recorded as a dead or failed lane, and it never causes the more expensive full lead cycle to be launched in its place."
    authored_at: 2026-08-23T22:55:00Z
  - surface: log_line
    observable: "In an interactive session whose context has grown past the emergency mark, the session compacts itself exactly once without the founder typing anything, and does not do so again at that same level."
    authored_at: 2026-08-23T22:55:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-burn-governor.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh, plugins/leadv2/scripts/leadv2-fanout.sh, plugins/leadv2/scripts/leadv2-backlog-pump.sh, plugins/leadv2/hooks/leadv2-compact-trigger.sh, plugins/leadv2/scripts/tests/test-burn-governor.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/docs/routing-enforcement.md

DELIVERABLE_COMPLETE
