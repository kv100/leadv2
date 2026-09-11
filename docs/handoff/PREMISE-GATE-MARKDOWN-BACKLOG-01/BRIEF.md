# PREMISE-GATE-MARKDOWN-BACKLOG-01

Backlog row: `0e3619bc27e0` (persona-engine `docs/tasks.yaml`, group leadv2).

Build a markdown-backlog source for the leadv2 premise gate, so the gate stops being a
silent no-op in repos that have no `docs/tasks.yaml`.

## The defect, measured 2026-09-11

`plugins/leadv2/scripts/leadv2-dispatch-code.sh`, function `_premise_probe_gate`
(starts ~line 7916). Its resolver is an inline Python heredoc that loads
`<root>/docs/tasks.yaml`, matches `PP_FOUNDER_TASK` against rows, and prints TSV
`status<TAB>sid<TAB>probe_id<TAB>needs<TAB>root` plus an optional `cmd=<shlex-quoted>` line.

When no row matches it prints `status=none`, and the bash side (~line 8013) does:

    emit decision "premise_probe task=${sig8} verdict=skipped reason=no_backlog_row"
    return 0

The repo `~/Projects/getmany-followup-bot` has **no `docs/tasks.yaml` at all**. So every
dispatch there resolves `none`, skips, and proceeds. The gate reports enforcement and does
nothing — the same fail-open shape as a hook dispatcher whose children are missing.

That repo DOES have a real backlog, just not in yaml:
`docs/projects/post-booking-pipeline/TASKS.md`. Measured: a pipe table whose header is
`| # | Спека | Задача | Зачем | Статус | Блокер | Дальше |`, 73 rows with a numeric id in
the `#` column, and a **declared closed status vocabulary** — the document states
"Статусы, ровно эти" and the live census is exactly: `не начато` 38, `в проде` 15,
`ждёт ответа` 7, `не проверено` 4, `не нужна` 3, `в проде, флаг OFF` 3, `решено` 1,
`разобрано` 1, `в проде, без потребителя` 1.

## What to build

### 1. `plugins/leadv2/scripts/lib/leadv2-markdown-backlog-read.py`

Resolves a founder task id against a markdown pipe table.

- Args: `--root <repo root> --task-id <id>`.
- Reads the repo's declaration (see 2). If the declaration is absent or unreadable →
  print `none\t-\t-` and exit 0. Absence of a declaration must never be an error; most
  repos will not have one.
- Parse the pipe table: split on `|`, strip cells, skip the header row and the `---`
  separator row, keep rows whose id cell matches the declared id pattern.
- Match `--task-id` against the id cell **exactly** after stripping. No fuzzy or substring
  matching — a substring match on numeric ids would make `7` match `17`, `27`, `37`.
- Emit TSV on one line: `<status>\t<row_id>\t<status_text>` where `<status>` is one of
  `md_closed`, `md_open`, `md_ambiguous`, `none`, and `<status_text>` is the raw status
  cell (or `-`). More than one row matching the id → `md_ambiguous`.
- Pure stdlib for the table. The declaration file is yaml, so read it with PyYAML
  **guarded**: `try: import yaml / except ImportError:` → fall back to a minimal literal
  parse, or print `none` and exit 0. PyYAML is a user-level install only on this machine
  and is NOT guaranteed present in every control-plane root; a hard import would turn a
  missing optional dependency into a dispatch refusal.

### 2. `~/Projects/getmany-followup-bot/.claude/leadv2-overrides/markdown-backlog.yaml`

The per-repo declaration. Repo specifics live in the override, never hardcoded in the plugin.

    file: docs/projects/post-booking-pipeline/TASKS.md
    id_column: "#"
    status_column: "Статус"
    id_pattern: '^[0-9]+$'
    closed_statuses:
      - "в проде"
      - "не нужна"
      - "решено"
      - "разобрано"

**Note what is deliberately NOT in `closed_statuses`:** `в проде, флаг OFF`,
`в проде, флаг OFF, проверено`, and `в проде, без потребителя`. The document defines all
three as "поведение прода не изменилось" / "его пока никто не вызывает" — the code shipped
but the thing the row asked for is not in effect. Treating them as closed would refuse live
work. Conservative membership is the point: a false red costs exactly as much as a false green.

Match `closed_statuses` by exact string equality on the stripped cell, **not by prefix** — a
prefix match on `в проде` would swallow all three excluded values and undo this paragraph.

### 3. Wire it into `_premise_probe_gate`, strictly additively

Consult the markdown source **only** on the branch where the yaml resolver already returned
`status=none`. Nothing else changes.

    none → md_open      : emit "premise_probe task=… row=md:<id> verdict=skipped reason=markdown_row_open_no_probe" ; return 0
    none → md_closed    : emit "premise_probe task=… row=md:<id> verdict=refused reason=row_closed_in_markdown_backlog" ;
                          log_err naming the row id, its status text, and the file ; exit "${PREMISE_REFUSED_RC}"
    none → md_ambiguous : refused, reason=markdown_row_ambiguous, exit "${PREMISE_REFUSED_RC}"
    none → none         : UNCHANGED — "verdict=skipped reason=no_backlog_row", return 0

**A missing row must NOT refuse.** The code at line 8013 carries a measurement in its
comment: `test-leadv2-lane-shape.sh` and `test-plugin-papercuts.sh` dispatch with
`--acceptance-cmd 'true'` and no row, and gating those would have refused them. Preserve
that exactly.

**The reason string is the deliverable, not a label.** `reason=markdown_row_open_no_probe`
must never collapse into `reason=no_backlog_row`. The whole point is that the journal
distinguishes "no backlog exists here" from "a row was found, it is open, and it carries no
runnable probe". Half a gate that reports half a gate is acceptable; half a gate that
reports a whole one is the defect being fixed.

Do not touch the probe-running path, the yaml resolver, or any exit code other than adding
the two new refusal reasons.

### 4. Suite: `plugins/leadv2/scripts/tests/test-premise-markdown-backlog.sh`

Fixtures in the suite's OWN temp dir. Cases, at minimum:

1. No declaration file → `none`, gate unchanged.
2. Declaration + row `не начато` → `md_open`.
3. Declaration + row `в проде` → `md_closed`.
4. Declaration + row `в проде, флаг OFF` → `md_open` (the prefix trap).
5. Declaration + row `в проде, без потребителя` → `md_open`.
6. Task id `7` must NOT match a row whose id is `17` or `27` (the substring trap).
7. Two rows with the same id → `md_ambiguous`.
8. Declaration present but the named file missing → `none`, exit 0, no traceback.
9. PyYAML unavailable → `none`, exit 0 (simulate with a `PYTHONPATH` shim whose `yaml`
   module raises ImportError, or an env flag the script honours).
10. A yaml row that DOES resolve still takes precedence — the markdown source is never
    consulted. Assert on the emitted decision line.

### 5. Negative control: `plugins/leadv2/scripts/tests/nc-premise-markdown-backlog.sh`

Mutate the **real** `lib/leadv2-markdown-backlog-read.py` into a scratch copy that the suite
is pointed at via an env var, run the suite against the mutant, assert the suite goes RED.
Two mutations, each proving a different case:

- (a) `closed_statuses` matching becomes a prefix match → case 4 must go red.
- (b) id matching becomes a substring match → case 6 must go red.

If a mutation pattern is not found, **exit non-zero loudly**. Do not print a warning and let
the half that ran report a pass — row `BALANCER-NEGATIVE-CONTROL-HALF-ROTTED-01` was filed
today against exactly that shape in `nc-claude-profile-select.sh`, where `NC2-SETUP-FAIL`
degraded into an overall green.

The NC must not write into the tracked tree. Before writing any mock, refuse if the target
is tracked:

    git -C "$(dirname "$T")" ls-files --error-unmatch "$(basename "$T")" >/dev/null 2>&1 \
      && { echo "REFUSED: mock target is tracked"; exit 2; }

A suite in this repo overwrote its own production `codex-task.sh` twice on 2026-09-11 by
skipping that check.

## Hard constraints

- **Prove persona-engine is unchanged.** Before and after the change, dispatch-resolve
  (`--no-spawn`) a persona-engine founder id that HAS a yaml row and one that has none, and
  show the emitted `premise_probe` decision lines are byte-identical. A behaviour change in
  the 548-row repo is a failure of this task, not a side effect.
- Suites must never write to `~/.claude/leadv2-state/`.
- Do NOT touch `~/Projects/getmany-followup-bot/.claude/settings.json` or `.claude/anatomy.md`.
  Another session owns commits in that repo; the only file added there is the override yaml,
  left UNCOMMITTED for that session to commit.
- Never `git stash`, `git reset --hard`, `git clean`, or `git worktree prune` — several
  sessions share these trees.
- Commit the plugin-side work in `~/Projects/leadv2` (the plugin repo is the single source;
  committing to main IS the deploy). Do not push.
- `plugins/leadv2/scripts/leadv2-plugin-cache-sync.sh` is already modified in the working
  tree by someone else. Leave it alone and keep it out of the commit — use
  `git commit -- <your paths>`.

## Report back

Under 300 words: the commit sha, the suite's pass/fail counts, the NC's output for both
mutations, and the before/after persona-engine decision lines proving no change. If any case
cannot be made to work, say which and why rather than dropping it.
