# PREMISE-GATE-MARKDOWN-BACKLOG-01 — ROUND 3

Backlog row: `MARKDOWN-ARCHIVE-MEMBERSHIP-RULE-IS-UNPROVEN-01`.

Round 2 is merged to main and works. This round closes one named limit, and it is small:
a fixture change plus a re-run. Do not redesign anything.

## The limit

`nc-premise-markdown-backlog.sh` mutation **(d) `archive-membership-closed`** rewrites
closure to gate on the parenthetical status instead of on archive membership. The mutant
suite went red (rc=1) but **not on its named case A10** (archive-only id 9), so the NC
refused to call it a pass — correctly, and that refusal is the reason this round exists.

The cause is the fixture, not the mutation. Case A10 uses an archive entry whose
parenthetical is `не нужна`, which **is** one of the declared `closed_statuses`. Under the
mutation, gating on the status still returns closed, so A10's outcome is identical with
and without the mutation and nothing can discriminate the two rules.

The same blindness is in the live data: all 21 rows in getmany's `## Закрыто` carry one of
the four declared closed statuses (`в проде` ×14, `не нужна` ×3, `решено`, `разобрано`).
So a live-file check cannot discriminate them either. Verify that count yourself before
you start — if the file has changed, say so rather than working from this number.

## Why it matters

The two rules diverge exactly where the gate earns its keep. A row archived as
`в проде, флаг OFF` is deliberately **not** in `closed_statuses` — the repo's own document
defines that status as "поведение прода не изменилось": shipped, but the thing the row
asked for is not in effect. Status-gating returns `none` and the gate stays silent;
membership-gating returns `md_closed` and refuses. Today that divergence is untested.

## What to change

1. Give case **A10** an archive fixture whose parenthetical is **outside**
   `closed_statuses` — e.g. `- **9** (в проде, флаг OFF) — …` with `closed_statuses`
   declaring only the four. Unmutated, the reader must return `md_closed` (membership
   decides) with `status_text` carrying `в проде, флаг OFF` verbatim.
2. Keep every existing case. This is an addition to A10's data, not a replacement of the
   suite's coverage.
3. Re-run `nc-premise-markdown-backlog.sh`. **All four mutations must redden their named
   case**, (d) included.

If mutation (d) still fails to redden A10 after the fixture change, do NOT adjust the
assertion to make it pass. Stop and report what the mutant actually returns for that
fixture — that would mean the production rule is not what the round-2 code implements, and
that is a finding, not a test problem.

## Hard constraints

- Suites must never write to `~/.claude/leadv2-state/`.
- Refuse to write a mock onto a tracked file:
  `git ls-files --error-unmatch <target>` → if tracked, refuse and exit 2.
- Never `git stash`, `git reset --hard`, `git clean`, or `git worktree prune`.
- Commit in `~/Projects/leadv2` with `git commit -- <your paths>`; do not push.
- Do not touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` or
  `plugins/leadv2/scripts/leadv2-repo-install.sh` — other lanes are editing both.

## Report back

Under 200 words: commit sha, suite counts, the full NC output showing all four mutations
reddening their named case, and the reader's actual output for the new A10 fixture
(`md_closed` plus the verbatim `status_text`).
