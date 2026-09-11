# BURN-DB-HAS-NO-ACCOUNT-COLUMN-01

Backlog row: `12cd3a2f6d16` (persona-engine `docs/tasks.yaml`, group leadv2).

The founder asked on 2026-09-11 which repo and which model spent the `max x5` window.
That question cannot be answered by a query today. It can only be inferred, and an
inference is exactly what must not end up in a column people will trust.

## Measured state (2026-09-11)

`~/.claude/burn/history.db`, table `sessions` (16,741 rows), full schema read from the
live DB: `session_id` (PK), `project_name`, `project_dir`, `jsonl_path`, `start_ts`,
`last_asst_ts`, `last_user_ts`, `turns`, `human_msg_count`, `cc_total`, `cr_total`,
`input_total`, `output_total`, `last_model`, `last_cr_snapshot`, `last_input_snapshot`,
`scan_mtime`, `scan_byte_offset`, `scan_line_count`, `updated_at`. Indexes on
`last_asst_ts` and `project_name`.

**There is no account column, on `sessions` or on `turn_events`.** So burn can be sliced
by repo and by model, and not by the thing the founder actually pays for.

The writer is `plugins/leadv2/scripts/leadv2-turn-cost-measure.py`.

`rate_limit_history` does carry `account_key` / `account_label` / `is_active`, and it is
**not** the answer. `is_active` is assigned from `CLAUDE_CODE_CREDENTIALS_SERVICE` by
`resolve_active_account()` (`leadv2-quota-read.py:784-806`), and line 989 forces exactly
one active account per capture by construction. It answers *who was probing*, never *who
paid*. A previous row died on that false premise; do not resurrect it.

## The join already exists and is unused

Every dispatched lane writes `docs/handoff/dispatch-<sig>/claude-profile.log` containing a
`selected=<personal|work>` line, and the spawn record in the **same** handoff directory
carries `SESSION_ID=<uuid>` — which is the key `sessions` is already indexed by. Nothing
new has to be instrumented; what is written has to be joined.

## The coverage number, and the question you must ANSWER rather than assume

Counted across all repos today: **1432** `docs/handoff/dispatch-*/` directories exist, and
only **226** contain a `claude-profile.log` with a `selected=` line. A 40-directory sample
in persona-engine gave 8 with a profile log and 32 without — the same ratio.

Do not report a backfill without explaining that gap. The plausible reading is that lanes
dispatched to codex / glm / kimi never run the Claude profile selector, so they have no
`selected=` line **because they spent no Claude window at all** — in which case 226 is the
correct denominator and the rest are legitimately not Claude spend. That is a hypothesis,
not a finding. Measure it: for a sample of directories without a profile log, determine
the arm actually used, and say plainly whether the missing rows are non-Claude lanes
(fine) or lost data (a second defect). The report must carry that number.

## What to change

### 1. Schema

Add an account column to `sessions`. Migration must be idempotent and must not rewrite
existing rows to a guess. Rows whose account cannot be established get the explicit value
`unknown` — never NULL-as-if-meaningful, and never an inferred account.

### 2. Backfill

Walk `docs/handoff/dispatch-*/` across the repos, pair `selected=` with `SESSION_ID=`, and
stamp the matching `sessions` row. A directory that has one but not the other is not a
match — count those separately and report the count.

### 3. Forward

`leadv2-turn-cost-measure.py` stamps the account as it scans, so the backfill is a
one-time repair and not a recurring chore.

### 4. The scope limit that must not be widened

**This attributes DISPATCHED sessions only.** An interactive lead session never runs the
profile selector, has no `selected=` line, and must be recorded as `unknown`. Do not guess
it from timing, from the keychain, from `rate_limit_history`, or from which account "was
probably active" — an inferred account in a column people will trust is worse than an
empty one, and it is the exact failure the superseded row died of.

## Suite + negative control

`scripts/tests/test-burn-account-attribution.sh` — fixtures in the suite's own temp dir,
against a **throwaway** SQLite file. Cases:

1. A dispatch dir with both `selected=work` and `SESSION_ID=<uuid>` → that session row is
   stamped `work`.
2. `selected=personal` → `personal`.
3. A dir with `SESSION_ID=` but no profile log → the row stays `unknown`, and the pair is
   counted as unmatched.
4. A dir with a profile log but no `SESSION_ID=` → same, counted, no row stamped.
5. An interactive session (a `sessions` row with no dispatch dir at all) → `unknown`.
6. Migration run twice → second run changes nothing (idempotent).

`scripts/tests/nc-burn-account-attribution.sh` — mutate the real script into a scratch
copy, point the suite at the mutant, assert RED:

- (a) make the backfill fall back to the most recent `rate_limit_history` account when no
  `selected=` line exists → case 5 must go red. This is the guess the row forbids.
- (b) make the migration non-idempotent → case 6 must go red.

If a mutation pattern is not found, **exit non-zero loudly**. A row filed today exists
because an NC printed a setup warning and still reported an overall pass. A mutant suite
that goes red on some *other* case is not a pass either — assert the named case.

## Hard constraints

- **Never write to the real `~/.claude/burn/history.db`.** Not in the suite, not in the
  NC, not in a "quick check". Copy it to a temp file if you need real shapes.
- Suites must never write to `~/.claude/leadv2-state/`.
- Refuse to write a mock onto a tracked file:
  `git ls-files --error-unmatch <target>` → if tracked, refuse and exit 2.
- Never `git stash`, `git reset --hard`, `git clean`, or `git worktree prune`.
- Commit in `~/Projects/leadv2` with `git commit -- <your paths>`; do not push.

## Report back

Under 300 words: commit sha, the migration's before/after row counts by account value
(including how many are `unknown` and why), the 1432-vs-226 gap explained with the
measurement that explains it, suite counts, and the NC output for both mutations.
