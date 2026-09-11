# BURN-DB-HAS-NO-ACCOUNT-COLUMN-01 — REVISION 2

Backlog row: `12cd3a2f6d16` (persona-engine `docs/tasks.yaml`, group leadv2).

The founder asked on 2026-09-11 which repo and which model spent the `max x5` window.
That cannot be answered by a query today. It can only be inferred, and an inference is
exactly what must not end up in a column people will trust.

## Revision 1 was refused, correctly. Read this before anything else.

Revision 1 named `plugins/leadv2/scripts/leadv2-turn-cost-measure.py` as the writer of
`~/.claude/burn/history.db`. **That was false, and the codex worker blocked on it rather
than working around it — the right call, and it changed nothing and left the lane clean.**
Its evidence:

    plugins/leadv2/scripts/leadv2-turn-cost-measure.py:  no history.db / sqlite3 / sessions refs
    ~/.claude/burn/aggregator.py:                        SELECT * FROM sessions / INSERT INTO sessions
    ~/.claude/burn/lib.py:                               CREATE TABLE sessions (...)

How the false premise got in: the brief author grepped the plugin scripts for the word
`sessions` and reported the file that matched as "the writer". Matching a word is not a
census of writers. If any statement in this brief does not survive your own measurement,
block the same way — do not substitute a nearby file because the named one is wrong.

## Measured state (2026-09-11, verify it yourself)

- `~/.claude/burn/history.db` — 15.5 MB live SQLite. Table `sessions`, 16,741 rows:
  `session_id` (PK), `project_name`, `project_dir`, `jsonl_path`, `start_ts`,
  `last_asst_ts`, `last_user_ts`, `turns`, `human_msg_count`, `cc_total`, `cr_total`,
  `input_total`, `output_total`, `last_model`, `last_cr_snapshot`, `last_input_snapshot`,
  `scan_mtime`, `scan_byte_offset`, `scan_line_count`, `updated_at`. Indexes on
  `last_asst_ts` and `project_name`. **No account column, here or on `turn_events`.**
- The real writers are `~/.claude/burn/aggregator.py` (289 lines) and `~/.claude/burn/lib.py`
  (199 lines). **`~/.claude/burn/` is NOT a git repo**, the files are real (not symlinks
  into any repo), dated April 2026, installed by their own `install.sh`, and no repo on
  this machine holds a copy.
- `rate_limit_history` does carry `account_key` / `account_label` / `is_active`, and it is
  **not** the answer. `is_active` comes from `resolve_active_account()`
  (`leadv2-quota-read.py:784-806`); line 989 forces exactly one active account per capture
  by construction. It answers *who was probing*, never *who paid*. A previous row died on
  that premise; do not resurrect it.

## The consequence, and the approach that follows from it

Because the writer is unversioned and outside every repo, **this task does not modify the
burn tool and does not alter its schema or its database.** Editing an unversioned 289-line
script that owns a 15.5 MB live DB, from a lane pinned to another repo, has no rollback
worth the name.

Build the attribution as a **separate, read-only artifact inside the plugin repo**:

    plugins/leadv2/scripts/leadv2-burn-attribute.py

It opens `history.db` **read-only** (`file:...?mode=ro` URI, or a copy), joins it against
the evidence already on disk, and writes its own output. It never writes to
`history.db` — not a column, not a row, not a temp table.

## The join already exists and is unused

Every dispatched lane writes `docs/handoff/dispatch-<sig>/claude-profile.log` containing a
`selected=<personal|work>` line, and the spawn record in the **same** handoff directory
carries `SESSION_ID=<uuid>` — the key `sessions` is already indexed by. Nothing new has to
be instrumented; what is already written has to be joined.

## The coverage number, and the question you must ANSWER rather than assume

Counted across all repos: **1432** `docs/handoff/dispatch-*/` directories exist, and only
**226** contain a `claude-profile.log` with a `selected=` line. A 40-directory sample in
persona-engine gave 8 with and 32 without — the same ratio.

Do not report an attribution without explaining that gap. The plausible reading is that
lanes dispatched to codex / glm / kimi never run the Claude profile selector, so they have
no `selected=` line **because they spent no Claude window at all** — in which case 226 is
the correct denominator and the rest are legitimately not Claude spend. That is a
hypothesis, not a finding. Measure it: for a sample of directories without a profile log,
determine the arm actually used, and say plainly whether the missing rows are non-Claude
lanes (fine) or lost data (a second defect). The report must carry that number.

## Output contract

`leadv2-burn-attribute.py` emits, for a requested window (default: the last 7 days):

1. Per account (`personal` / `work` / `unknown`): sessions, turns, `cc_total`, `cr_total`.
2. Within each account, a breakdown by `project_name` and by `last_model`.
3. An explicit `unknown` line with its count and the reason it is unknown.

Report the 5-hour and weekly window position, never dollars — that is a standing rule.

## The scope limit that must not be widened

**This attributes DISPATCHED sessions only.** An interactive lead session never runs the
profile selector, has no `selected=` line, and must be reported as `unknown`. Do not guess
it from timing, from the keychain, from `rate_limit_history`, or from which account "was
probably active". An inferred account in a number people will trust is worse than an
honest `unknown`, and it is the exact failure the superseded row died of.

## Suite + negative control

`scripts/tests/test-burn-attribute.sh` — fixtures in the suite's own temp dir, against a
**throwaway** SQLite file built by the suite. Cases:

1. Dispatch dir with `selected=work` + `SESSION_ID=<uuid>` → that session counts as `work`.
2. `selected=personal` → `personal`.
3. Dir with `SESSION_ID=` but no profile log → `unknown`, counted as unmatched.
4. Dir with a profile log but no `SESSION_ID=` → same, counted, nothing attributed.
5. A session row with no dispatch dir at all → `unknown`.
6. The script opens the DB read-only: point it at a read-only file and it still succeeds;
   assert the DB's mtime and size are unchanged after a full run.

`scripts/tests/nc-burn-attribute.sh` — mutate the real script into a scratch copy, point
the suite at the mutant, assert RED, naming the case:

- (a) fall back to the most recent `rate_limit_history` account when no `selected=` line
  exists → case 5 must go red. This is the guess the row forbids.
- (b) open the DB read-write → case 6 must go red.

If a mutation pattern is not found, **exit non-zero loudly**. A mutant suite that reddens
some *other* case is not a pass either — assert the named case. A row filed today exists
because an NC printed a setup warning and still reported an overall pass.

## Hard constraints

- **Never write to `~/.claude/burn/history.db`**, and never edit anything under
  `~/.claude/burn/`. Read-only, always. Copy to a temp file if you need real shapes.
- Suites must never write to `~/.claude/leadv2-state/`.
- Refuse to write a mock onto a tracked file:
  `git ls-files --error-unmatch <target>` → if tracked, refuse and exit 2.
- Never `git stash`, `git reset --hard`, `git clean`, or `git worktree prune`.
- Commit in `~/Projects/leadv2` with `git commit -- <your paths>`; do not push.
- If a premise in this brief fails your own measurement, **block and name it**, as the
  previous round correctly did. Do not work around it.

## Report back

Under 300 words: commit sha, the attribution output for the last 7 days (accounts,
projects, models, and the `unknown` line with its reason), the 1432-vs-226 gap explained
by the measurement that explains it, suite counts, the NC output for both mutations, and
the before/after mtime+size of `history.db` proving nothing wrote to it.
