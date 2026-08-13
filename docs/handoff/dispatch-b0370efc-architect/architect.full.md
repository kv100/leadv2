# MENUBAR-SHOWS-DEAD-LANES-AND-HASH-NAMES-01 — architect prepass

Repo: `~/Projects/leadv2`. Surface: `plugins/leadv2/scripts/leadv2-status-surface.sh`,
`render_single_lead()` (bash wrapper lines 2600–2626, embedded python 2617–2921).
Design only — no implementation in this pass.

---

## 1. Root causes (evidence, not theory)

All four claims below were checked against live state on 2026-08-04.

### RC-1 — the terminal ledger and the reservation ledger are resolved by two different keys

`render_single_lead` reads two sources with independently-derived paths:

| source | var | resolution |
|---|---|---|
| reservations (open lanes) | `LEDGER_FILE` (:206) | `${LEDGER_DIR}/${REPO}.jsonl`, `REPO` = basename of `git rev-parse --show-toplevel` (:102) |
| terminals (closed lanes)  | `LEADV2_SL_TERMINALS` (:2610) | `${STATE_DIR}/dispatch-ledger.jsonl`, `STATE_DIR` = `leadv2-state-path.sh --no-link root` (:51) |

These two are *not* guaranteed to name the same project. Rendered from a lane worktree
(`.claude/worktrees/<sig8>`) or from any cwd where `--no-link root` resolves to a
`leadv2-lwt.*` scratch state dir, `REPO` still yields the parent project while `STATE_DIR`
points elsewhere. Result: open reservations from project A cross-referenced against
project A's terminal ledger **or** an empty one — a lane that finished shows as open.

Verified: `81ec9717`'s terminal row (`terminal=dead cause=e2e_regression`) lives in
`~/.claude/leadv2-state/leadv2/dispatch-ledger.jsonl` and is **absent** from the
tail-400 window of `~/.claude/leadv2-state/persona-engine/dispatch-ledger.jsonl`
(checked directly). A panel scoped to persona-engine can never see it. Same mechanism,
different direction, is defect 3.

### RC-2 — a terminal match downgrades, it never drops

Line 2850–2852: `state = "closing" if has_terminal else "active"`. The row stays in
`workers`, so it still counts toward the header `active N` and still occupies a dropdown
row forever. Branch (b) (reservation-only rows, :2867) *does* `continue` on
`sig8 in terminals`, so the two branches disagree about what a terminal row means.

### RC-3 — the prepass subsession is counted as a worker lane

Census pattern 1 (:2666) is
`re.search(r'--task-id\s+dispatch-([a-f0-9]{8})', argv)` — **unanchored on the right**.
The architect/critic prepass runs as
`claude-subsession.sh --role architect --model opus --task-id dispatch-<sig8>-architect`
(confirmed in the live `ps` snapshot, e.g. this very run: `dispatch-b0370efc-architect`).
The regex captures `<sig8>` from the *role-suffixed* id, and the row is emitted with
`arm = opus` from `--model`.

That is exactly what the founder saw: `active 1 b5c26011 opus now`. `b5c26011` is a real
lane but its **worker arm is `glm`** (reservation row:
`{"task_sig":"b5c2601113d5…","arm":"glm","repo":"persona-engine"}`) and its handoff tree
contains both `dispatch-b5c26011/` and `dispatch-b5c26011-architect/`. The `opus` row was
the lead-side prepass subsession, not the worker.

(The mission's supporting claim "b5c26011 appears in NONE of the six ledgers" is an
artifact of grepping an 8-char prefix: the *reservation* ledger stores the full 64-char
`task_sig`, the *terminal* ledger stores 8 chars. The conclusion — the row is a lead-side
session, not a lane — is correct; the evidence is the `--role architect` argv.)

### RC-4 — names and phase are on disk and simply not read

* Human name: the reservation row's `task_id` / `founder_task_id`, and the terminal row's
  `task_id` (e.g. `task_sig=0db1da80 → task_id=M1A-FACT-QUALITY-01`). Already parsed into
  `res_by_task_id` / `terminal_task_ids` — used for *matching*, never for *display* on the
  branch-(a) path when the census key is a sig8.
* Phase: `<repo_root>/docs/leadv2/tasks/dispatch-<sig8>/journal.md`
  (`leadv2-journal.sh:42-43`), lines of the form
  `- <ts> [decision] <phase_token> task=<sig8> …` — verified live
  (`product_close`, `route_resolved`, `lane_worktree_left`, `review_gate`).

---

## 2. Design

Single point of change: the `render_single_lead()` bash preamble + its embedded python.
No new script, no new daemon, no change to any ledger writer.

### 2.1 One resolved project bundle replaces two independently-resolved paths

The multi-project enumerator already exists and already works:
`leadv2-status-projects.sh` emits `slug<TAB>state_dir<TAB>repo_root`, one line per
project (live output today: persona-engine, leadv2, respiro-ios). It is consumed at
:109–166 for the lanes table but **not** by `render_single_lead`.

Build, in the bash preamble of `render_single_lead`, a newline-separated TSV bundle
(bash 3.2: a plain string, no associative arrays, no `mapfile`):

```
<slug>\t<reservation_ledger>\t<terminal_ledger>\t<repo_root>
```

* `reservation_ledger` = `${LEDGER_DIR}/<slug>.jsonl`
* `terminal_ledger`    = `<state_dir>/dispatch-ledger.jsonl`
* `repo_root`          = enumerator column 3 (journal + handoff lookups)

Two modes, decided by the *existing* contract at :122 (`LEADV2_STATUS_STATE_DIR` pinned):

| condition | bundle | repo column |
|---|---|---|
| `LEADV2_STATUS_STATE_DIR` pinned (every existing test) | exactly one entry: `$REPO`, `$LEDGER_FILE`, `$STATE_DIR/dispatch-ledger.jsonl`, `$LEADV2_STATUS_REPO_ROOT` | hidden |
| not pinned, enumerator returns ≥1 project | one entry per project | shown when >1 project produced a row |
| not pinned, enumerator returns 0 | fall back to today's cwd-derived pair | hidden |

Passed to python as one env var `LEADV2_SL_BUNDLE`. `LEADV2_SL_RESERVATIONS` /
`LEADV2_SL_TERMINALS` are removed from the python contract (they are internal to this one
function; no other caller reads them — checked).

**This kills RC-1 structurally**: a project's reservations can only ever be matched
against *that same project's* terminal ledger, because both come from one bundle row.

### 2.2 Lane identity and the terminal cross-ref

Per bundle row, build:

* `res_by_sig[sig8] → (epoch, row)` and `res_by_task_id[name] → (epoch, row)` (as today)
* `term_by_sig[sig8] → (epoch, row)`, `term_by_task_id[name] → (epoch, row)` — **rows, not
  bare sets**, because the terminal timestamp is now needed
* `name_by_sig[sig8] → task_id` merged from both (reservation wins; terminal is the
  fallback — this is where `M1A-FACT-QUALITY-01` comes from for a lane whose reservation
  has aged out of the tail window)

A lane is keyed by `(repo, sig8)` when a sig8 is known, else `(repo, task_id)`. The
census already carries both (`info["sig8"]` when the run-dir/handoff segment is hex8,
`info["task_id"]` = the lane segment otherwise). Cross-ref order, no substring matching
anywhere:

1. `sig8` exact → `term_by_sig`
2. `task_id` exact → `term_by_task_id`
3. `task_id` exact → `res_by_task_id` → that reservation's `sig8` → `term_by_sig`

Step 3 is the "match on the key the ledger actually stores" requirement: a glm/kimi/codex
lane whose census key is the human name still reaches the terminal row that is keyed by
sig8, via the reservation row that holds both.

### 2.3 Terminal semantics — drop, with a bounded closing grace

```
terminal_ts   = ts of the matched terminal row
superseded    = a reservation for the same (repo, sig8) with epoch > terminal_ts
                → the lane was re-dispatched; the terminal row is EXPIRED, ignore it
grace         = LEADV2_STATUS_SL_CLOSING_GRACE_S (default 120)

if terminal matched and not superseded:
    if process is live and (now - terminal_ts) <= grace:  state = "closing"   (kept, counted separately)
    else:                                                 DROP the row entirely
```

* Requirement "a lane with an unexpired terminal row must not render as `active`": a
  terminal row never yields `active` again.
* Requirement "a finished lane should leave the list, not linger as `closing` forever":
  `closing` is now time-boxed to 120 s of real wind-down and then the row is gone.
* `superseded` is what makes "unexpired" meaningful — a re-dispatch of the same mission
  signature must not be hidden by the previous attempt's terminal row.
* Branch (b) keeps its existing `continue`, re-expressed through the same helper so the
  two branches can no longer disagree (RC-2).

Header count `active N` counts **only** `state == "active"` rows. `closing` rows are
appended after them in the dropdown and, if any exist, the header gains a
` +<K> closing` suffix **after** the four positional fields (see 2.6 — the wrapper reads
by field position, so nothing may be inserted before field 6).

### 2.4 Never count a lead-side session (RC-3)

Two independent rules, both required:

1. **Anchor the census regex.** `--task-id\s+dispatch-([0-9a-f]{8})(?![0-9a-zA-Z_-])` —
   `dispatch-b0370efc-architect` no longer matches. This alone fixes the observed defect.
2. **Role exclusion.** If the argv carries `--role <r>` with `r` in
   {architect, critic, security-auditor, product-owner, strategist, reviewer}, the process
   is a lead-side subsession — skip regardless of its task-id shape. `--role developer` is
   the only role that is a worker lane.

Both are cheap string tests on the existing single `ps` snapshot — no new process spawn.

Deliberately **not** used as the exclusion rule: "no reservation row anywhere". A live
lane whose reservation has scrolled past `tail -n 400` would be erased by that rule, which
trades defect 1 for a worse one (a real worker made invisible).

### 2.5 Names and phase (RC-4)

`display_name(repo, sig8, task_id)`:

1. reservation `task_id` / `founder_task_id` for this `(repo, sig8)`
2. terminal-row `task_id` / `founder_task_id` for this `(repo, sig8)`
3. the census `task_id` when it is not itself a bare hex8 (glm/kimi/codex lane segment)
4. `sig8` — genuine fallback

`phase(repo_root, sig8)`: `tail -n 40 <repo_root>/docs/leadv2/tasks/dispatch-<sig8>/journal.md`,
take the **last** line matching `^- \S+ \[decision\] (\S+)`, capture group 1, clip to 16
chars. Missing file / unreadable / no match → `?`. The phase is cosmetic and must never
be able to fail the render (see 2.7).

Cost bound: one `tail` per rendered lane, capped at `LEADV2_SL_MAX_ROWS` (default 12)
lanes. If the cap truncates, the renderer prints an explicit
`  (+K more lanes not shown)` row — no silent cap.

### 2.6 Output contract (this is a wire format — the SwiftBar wrapper parses it positionally)

`leadv2-status-surface.10s.sh:199–215` splits the header with `awk '{print $3/$4/$5/$6}'`.
Fields 1–6 are therefore **frozen**:

```
mode=single-lead active <N> <name20> <arm> <age>[ +<K> closing]
```

Detail rows (rendered verbatim by the wrapper, free format):

```
  <name24> · <phase> · <arm> <age>[ · <repo>][ · closing]
```

* `<name24>`: clipped to 24 chars, `|` and whitespace stripped (the wrapper's `|` is a
  SwiftBar attribute separator; the existing `.replace("|","")` must extend to phase and
  repo, which are new operator-controlled strings).
* `· <repo>` present only when the bundle produced rows from more than one project — so a
  founder sees *which* repo a lane lives in (requirement 3), and the single-project
  rendering does not grow a redundant column.
* Truncate the **name**, never the state: `<phase>`, `<arm>`, `<age>` are emitted whole.
* Title-bar width: worst case `name24 + phase16 + arm6 + age4 + repo14 + separators ≈ 70`
  chars in the dropdown (Menlo 12, unconstrained). The menu-bar *title* still uses only
  the header's `name20 arm age`, unchanged in width from today.

### 2.7 Failure honesty (extends the T4 principle to every new source)

| source | failure | behaviour |
|---|---|---|
| project enumerator | non-zero / empty output | fall back to the cwd-derived single pair; **not** an error (that is today's behaviour at :161) |
| reservation or terminal ledger, file absent | — | normal (project never dispatched): contributes no rows |
| reservation or terminal ledger, present but `tail` fails or a **non-final** line is malformed | — | `fail()` → `mode=single-lead active ⚠ ledger unreadable: <reason>`, never a count |
| reservation or terminal ledger, **final** line malformed | torn append under `flock` | skip that one line only (see risk R-3) |
| journal.md unreadable / absent | — | `phase = ?`; never fatal |

`fail()` already emits the `⚠` header the wrapper keys on (`*"active ⚠"*` → `⚠️ ledger не
прочитан`), so T4 keeps passing unchanged and every new source inherits it.

---

## 3. Files

| file | change |
|---|---|
| `plugins/leadv2/scripts/leadv2-status-surface.sh` | `render_single_lead()` only: bundle builder in the bash preamble; census regex anchoring + role exclusion; per-repo cross-ref; drop-on-terminal + grace; name/phase resolution; new detail-row format |
| `tests/test-status-surface-single-lead.sh` | existing 3-arg `run_render` harness keeps working (it pins `LEADV2_STATUS_STATE_DIR`); update the detail-row assertions to the new format |
| `tests/test-status-surface-lane-truth.sh` *(to-create)* | the four new acceptance tests below |
| `plugins/leadv2/scripts/tests/run-core-offline.sh` | one `run_check` line registering the new suite |
| `tests/test-status-surface-bash32.sh` | only if its file sweep is an explicit list that must gain the new test file; must stay green either way |

`plugins/leadv2/scripts/leadv2-status-surface.10s.sh` is **not** modified — 2.6 preserves
its positional contract deliberately.

### Test plan (the four "done means" proofs)

| # | fixture | assertion |
|---|---|---|
| T-A | reservation for `aaaaaaaa` (5 min old) + terminal row `task_sig=aaaaaaaa,terminal=no_work,task_id=FOO-01`, ts newer than the reservation; ps stub shows the worker alive | header is `active 0`; no row is labelled `active`; after `LEADV2_SL_CLOSING_GRACE_S=0` the row is absent entirely |
| T-B | ps stub with `claude-subsession.sh --role architect --model opus --task-id dispatch-bbbbbbbb-architect` **and** `--role developer --model sonnet --task-id dispatch-cccccccc` | exactly one row; it is `cccccccc`; `bbbbbbbb` appears nowhere |
| T-C | stub `LEADV2_STATUS_PROJECTS_SH` emitting two projects; a live reservation only in project B's ledger | the row renders and carries `· <slugB>`; `active 1` |
| T-D | reservation with `task_id=NAMED-LANE-01` + journal at `<rootB>/docs/leadv2/tasks/dispatch-dddddddd/journal.md` ending in `[decision] review_gate …`; second lane `eeeeeeee` with no name and no journal | row 1 renders `NAMED-LANE-01 · review_gate · …`; row 2 renders `eeeeeeee · ? · …` |

Plus: T4 (`dead renderer → ⚠, never a confident 0/0`) unchanged and green;
`bash -n` and `/bin/bash --version 3.2 -n` clean on both changed scripts;
`tests/test-status-surface-bash32.sh` and `tests/test-status-surface-single-lead.sh` run
and pasted in full. **Do not** run `run-core-offline.sh`.

---

## 4. Risks

| id | risk | mitigation |
|---|---|---|
| R-1 | Reading N ledgers instead of 1 multiplies `tail` subprocesses per 10 s tick (3 projects × 2 files = 6, plus ≤12 journal tails) | cap lanes at `LEADV2_SL_MAX_ROWS=12`; skip bundle rows whose files do not exist (no spawn); measure once — if a tick exceeds ~300 ms, read the files in python with a seek-to-tail instead of `tail(1)` |
| R-2 | Any *new* ledger becoming reachable also makes its corruption reachable → a foreign project's broken ledger blanks the whole panel with `⚠` | acceptable and correct per the mission's "never a confident 0"; the reason string must name the project slug so the founder knows which ledger to fix |
| R-3 | `tail -n 400` can catch a torn final line from a concurrent `flock`-protected append → spurious `⚠` every ~10 s | tolerate a malformed **final** line only (skip it); a malformed earlier line is real corruption and still fails loudly. This is a strict improvement on today's behaviour |
| R-4 | Role exclusion misclassifies a future worker role → a real lane disappears (worse than a ghost lane) | exclusion list is a *deny* list of known lead-side roles, not an allow-list of workers; the anchored regex is the primary defence and is role-agnostic |
| R-5 | `closing` grace of 120 s hides a lane that writes a terminal row and then keeps working (product-close re-entry) | grace applies only while the process is live; a re-dispatch writes a newer reservation, which supersedes the terminal row (2.3) and the lane returns as `active` |
| R-6 | Detail-row format change breaks a consumer other than the wrapper | grep before landing: `mode=single-lead` / `active ` consumers are the `.10s.sh` wrapper and the test suites only (checked); header fields 1–6 frozen regardless |
| R-7 | `leadv2-status-projects.sh` enumerates a project the founder is not working in → noise | rows only appear for projects with a live process or an unexpired reservation, so an idle project contributes nothing |

### Constraint checklist

1. **Env vars** — new: `LEADV2_SL_BUNDLE` (python-internal, matches the existing
   `LEADV2_SL_*` convention), `LEADV2_STATUS_SL_CLOSING_GRACE_S`,
   `LEADV2_STATUS_SL_MAX_ROWS`. Both operator-facing vars use the file's established
   `LEADV2_STATUS_*` prefix (cf. `LEADV2_STATUS_ACTIVE_TTL_S`). No `LEAD_V2_*` drift.
2. **Paths** — all read paths verified on disk: `~/.claude/cache/dispatch-ledger/<slug>.jsonl`,
   `~/.claude/leadv2-state/<slug>/dispatch-ledger.jsonl`,
   `<repo_root>/docs/leadv2/tasks/dispatch-<sig8>/journal.md`,
   `plugins/leadv2/scripts/leadv2-status-projects.sh`. Only
   `tests/test-status-surface-lane-truth.sh` is `(to-create)`.
3. **`claude -p`** — n/a, this change spawns no Claude session.
4. **Concurrent access** — the surface is read-only against ledgers that dispatch appends
   under `flock`; it does not take the lock (a 10 s render must never block a dispatch).
   The torn-final-line tolerance in R-3 is the ordering-free mitigation.
5. **Config contradiction** — `LEADV2_STATUS_ACTIVE_TTL_S` (2 h) keeps its meaning:
   reservation expiry. The new grace is a *separate*, shorter clock for post-terminal
   wind-down; the two never gate the same decision.

## 5. Out of scope

* The lanes table (`_ss_lanes_py`, :532–1290) — untouched. This mission is `--single-lead`.
* Any ledger *writer* (`leadv2-dispatch-ledger.sh`, `leadv2-dispatch-code.sh`).
* The `.10s.sh` wrapper (contract preserved by design).
* De-duplicating the `leadv2-lwt.*` state dirs, or fixing `leadv2-state-path.sh --no-link
  root` inside worktrees — RC-1 is neutralised here by construction, but the underlying
  state-path behaviour is a separate task.
* `run-core-offline.sh` aggregate execution (explicitly forbidden by the mission).
* Adding the repo to the menu-bar *title* — dropdown only.

acceptance:
- surface: rendered_line
  observable: "In the SwiftBar dropdown, a lane whose dispatch has finished is no longer
    listed; the header count above it drops by one, and within two minutes of finishing the
    lane disappears from the list entirely instead of sitting there marked closing."
  authored_at: 2026-08-04T16:05:00Z
- surface: rendered_line
  observable: "While the lead is running an architect prepass, the dropdown shows only the
    real worker; no extra opus row appears alongside it."
  authored_at: 2026-08-04T16:05:00Z
- surface: rendered_line
  observable: "With a worker running in one repo and the panel opened from another, the
    founder still sees that worker in the dropdown, and the row names the repo it lives in."
  authored_at: 2026-08-04T16:05:00Z
- surface: rendered_line
  observable: "A lane row reads as a human task name followed by its phase, e.g.
    'M1A-FACT-QUALITY-01 · review_gate · sonnet 12m', and a lane with no recorded name still
    shows its 8-character id rather than being blank."
  authored_at: 2026-08-04T16:05:00Z
- surface: file_artifact
  observable: "Running tests/test-status-surface-bash32.sh and
    tests/test-status-surface-single-lead.sh prints a passing summary with no FAIL lines."
  authored_at: 2026-08-04T16:05:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-status-surface.sh, tests/test-status-surface-single-lead.sh, tests/test-status-surface-lane-truth.sh, tests/test-status-surface-bash32.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
