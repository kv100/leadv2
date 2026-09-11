# PREMISE-GATE-MARKDOWN-BACKLOG-01 — ROUND 2

Round 1 landed as `ded831d9` (auto-checkpoint on worker exit) on branch
`worktree-0e3619bc27e0`. Suite 37/0, negative control mutation (a) confirmed red.
The dispatcher wiring is correct and stays.

**Round 1 has one defect, found by running the reader against the LIVE artifact instead
of its own fixtures. The `md_closed` branch can never fire in the repo it was built for.**

## The defect

`getmany-followup-bot` restructured `docs/projects/post-booking-pipeline/TASKS.md` at
17:44 today, commit `104803d docs(tasks): archive 21 closed rows, refresh the stale work
order`. Closed rows were moved **out of the pipe table into a bullet list** under a
`## Закрыто` heading (line 129):

    ## Закрыто

    Строки убраны из рабочей таблицы 11.09, id сохранены — на них ссылаются
    открытые строки. Подробности каждой — в истории git этого файла.

    - **9** (не нужна) — IMAP-читалка `mailbox-imap-thread.ts` из Sent
    - **10** (в проде) — `addNoteToDeal` — ревью и деплой
    - **81** (в проде) — Снятие паузы домена не включено: 180 доменов выключены из…

Measured consequences:

- The working table now holds **53** numbered rows and **five** distinct statuses, all
  open: `не начато`, `в проде, без потребителя`, `ждёт ответа`, `в проде, флаг OFF`,
  `не проверено`. Not one of the four declared closed statuses remains in the table.
- All **21** closed rows live in the archive list, in one uniform form:
  `- **<id>** (<status>) — <text>` (21 of 21 match `^- \*\*[0-9]+\*\* \(`).
- The reader parses the pipe table only. `--task-id 9` returns `none`, so
  `_premise_probe_gate` takes the `no_backlog_row` branch and **does not refuse**.

So `md_closed` is dead code in the only repo that has a markdown backlog. The gate would
report a named reason and still never refuse — the exact failure the row exists to fix,
reintroduced through a format change rather than through logic.

**Why the suite did not catch it.** The suite is 37/0 and honest; it runs against fixtures
in its own temp dir, deliberately, so that a file changing several times an hour cannot
redden it. That decision is still right. But fixtures only contain forms someone thought
to write, and nobody had seen the archive form. Fixtures protect a suite from churn and,
by the same property, hide any shape the fixtures do not contain. A green suite on
invented data is not evidence of behaviour on the real artifact.

## What to change

### 1. The reader parses a second, declared form

`scripts/lib/leadv2-markdown-backlog-read.py` must also resolve ids from a bullet list.
Both forms are declared per repo — do not hardcode the heading, the bullet shape, or the
Russian word:

    archive:
      heading: "## Закрыто"
      item_pattern: '^- \*\*(?P<id>[0-9]+)\*\* \((?P<status>[^)]*)\)'
      treat_as: closed

**Membership in the archive section is itself the closure signal**, regardless of the
parenthetical status. The document says so in its own words: "Строки убраны из рабочей
таблицы 11.09, id сохранены". The parenthetical (`в проде` / `не нужна` / `решено` /
`разобрано`) is detail to report in `status_text`, not a second test to pass. Report it,
do not gate on it.

Resolution order and precedence, which must be explicit and tested:

1. id found in the working table → its status decides `md_open` / `md_closed` as today.
2. id found only in the archive → `md_closed`, `status_text` = the parenthetical.
3. id in **both** → `md_ambiguous`. Do not silently prefer one. A row that is
   simultaneously live and archived is a real editing error in the founder's file and he
   should be told, not have it resolved behind his back.
4. id in neither → `none`, unchanged.

If the declaration has no `archive:` block, behave exactly as round 1 — repos without one
must be byte-identical.

### 2. Suite additions

Keep the 37 existing cases. Add, as fixtures:

1. Archive-only id → `md_closed`, status_text carries the parenthetical.
2. Archive id `9` must not match archive id `19` or `29` (the substring trap again, now on
   a second parser — it is a different code path and needs its own case).
3. Same id in table AND archive → `md_ambiguous`.
4. Declaration with no `archive:` block, archive-shaped text present in the file → `none`.
   Undeclared structure is not parsed.
5. An archive line that does not match `item_pattern` (a plain prose bullet, a nested
   list item) → ignored, no crash, no false id.
6. Heading present, zero items under it → `none`, exit 0.

### 3. ONE case that runs against the live file

Add exactly one case, clearly marked, that runs the reader against
`~/Projects/getmany-followup-bot/docs/projects/post-booking-pipeline/TASKS.md` **if it
exists**, and asserts only a shape-level invariant that churn cannot break:

> every id the reader resolves is resolved as exactly one of `md_open` / `md_closed`, and
> the count of ids it resolves is not zero.

It must SKIP (not fail) when the file is absent, so the plugin's suite stays green in
repos that do not have it. Never assert a count, a specific id, or a specific status — the
file changes several times an hour and that is not a defect.

This case is the one that would have caught this round's defect, and it is the only way to
notice the next format change. Keep it deliberately weak so it can only go red for a real
reason.

### 4. Negative control additions

`nc-premise-markdown-backlog.sh` — keep both existing mutations. Note that mutation (a)
(`closed-exact`) is confirmed red; mutation (b) was never observed because **my own**
`timeout 280` killed the run at rc=124, which is my instrument and not a defect in the NC.
Verify (b) completes this round.

Add:

- (c) make the archive parser prefer the table silently when an id is in both → case 3
  must go red.
- (d) make archive membership gate on the parenthetical status instead of on membership →
  the archive-only `не нужна` case must go red.

A mutation pattern that is not found must **exit non-zero loudly**. Never print a setup
warning and let the half that ran report a pass.

### 5. The override file, now that its shape is known

Create `~/Projects/getmany-followup-bot/.claude/leadv2-overrides/markdown-backlog.yaml`,
**uncommitted** — another session owns commits in that repo and will review it:

    file: docs/projects/post-booking-pipeline/TASKS.md
    id_column: "#"
    status_column: "Статус"
    id_pattern: '^[0-9]+$'
    closed_statuses:
      - "в проде"
      - "не нужна"
      - "решено"
      - "разобрано"
    archive:
      heading: "## Закрыто"
      item_pattern: '^- \*\*(?P<id>[0-9]+)\*\* \((?P<status>[^)]*)\)'
      treat_as: closed

`closed_statuses` deliberately omits `в проде, флаг OFF`, `в проде, флаг OFF, проверено`
and `в проде, без потребителя`. The document defines all three as "поведение прода не
изменилось" / "его пока никто не вызывает" — shipped, but the thing the row asked for is
not in effect. Matching must stay exact-equality; a prefix match on `в проде` swallows all
three and refuses live work.

## Hard constraints (unchanged from round 1)

- Prove persona-engine is unchanged: a founder id WITH a yaml row and one WITHOUT, before
  and after, emitted `premise_probe` decision lines byte-identical.
- Lane `84c21f86` is editing `scripts/leadv2-router.sh` right now. Do not touch it.
  `scripts/leadv2-plugin-cache-sync.sh` is modified by someone else — keep it out.
  Commit with `git commit -- <your paths>`.
- Never `git stash` / `reset --hard` / `clean` / `worktree prune`.
- Suites must never write to `~/.claude/leadv2-state/`.
- Refuse to write a mock onto a tracked file (`git ls-files --error-unmatch` check).
- Commit in `~/Projects/leadv2`; do not push.

## Report back

Under 300 words: commit sha, suite counts, NC output for all four mutations, the live-file
case's output, and the before/after persona-engine lines.
