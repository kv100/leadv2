# PULSE-STATUS-LEAKS-OTHER-REPOS-01 — the board shows another repo's data

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PULSE-BEATS-IN-IDLE-REPOS-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/scripts/leadv2-status-collector.sh,plugins/leadv2/scripts/tests/test-status-repo-scoped.sh,tests/run-all.sh,docs/handoff/PULSE-BEATS-IN-IDLE-REPOS-01/

Main is `95ed6f310` in `~/Projects/leadv2`. Branch from it.

**This brief REPLACES the previous one in this directory, which had the wrong subject.**
The complaint was never "the beat is noisy in an idle repo" — the beat itself is wanted, the
founder works in that repo too. Do not add an idleness guard. Do not silence anything.

## The report, from the founder

He opened a session in `~/Projects/platform` and the beat there showed him data belonging to a
different repo:

```
08:42 · посты н/д · комменты н/д · реплаи н/д
| Линия | Что делает | Состояние |
| codex:review-… | — | … |
| persona-engine/dispatch-154054d6 | — | foreign repo persona-engine; pid=alive |
(скрыто: 3 строк очереди)
```

His words: "зачем мне в репо который не имеет отношения к моей работе в этом репо инфа про
посты, комменты и т.д.? зачем мне там знать про диспатчи другого репо? Сами пульсы и биты
нужны, так как там я тоже веду работу."

## What I established in the source before writing this

Two independent leaks, both deliberate, both unconditional:

**1. Product metrics are hardcoded and repo-blind.** `leadv2-broad-status.sh:1136-1141` always
emits `посты · комменты · реплаи`. Those are persona-engine's product counters. In any other
repo `_metric` finds no facts and prints `н/д` three times — a line that is meaningless there
and, worse, implies that repo has a posting product.

**2. Foreign lanes are force-shown.** `leadv2-broad-status.sh:46-56` documents that the
collector pins `LEADV2_LANES_ALL_REPOS=1` at its `leadv2-lanes-snapshot.sh` call, deliberately
overriding the `=0` that `~/.claude/settings.json` ships. That pin was added for a real reason
— a lane running in another repo was invisible on the board of the repo that dispatched it —
but it was applied globally, so now every repo's board lists every other repo's lanes.

## [Critical] the product line must be repo-owned, not hardcoded

A repo either declares product metrics or has none. Read them from the repo's own override
tree (`.claude/leadv2-overrides/`) — a repo that declares nothing gets **no product line at
all**, not three `н/д`. persona-engine keeps exactly the line it has today.

Do not invent a new config file if the override tree already has a natural home for this; say
in `report.md` which key you used and why.

## [Critical] foreign lanes belong only to the session that owns them

Restore the distinction the blanket pin destroyed:

- lanes running **in this repo** always render;
- a lane in another repo renders **only** when this session dispatched it — that is the case
  the `=1` pin was added to rescue, and it must keep working;
- a lane in another repo that this session has nothing to do with must not appear.

Read `leadv2-broad-status.sh:44-60` before you touch it: the comment there records a live
incident and a second, unrelated bash-3.2 heredoc failure under the same title. Do not
reintroduce either. In particular, do not "fix" this by setting `LEADV2_LANES_ALL_REPOS=0` at
the collector — that is the state the pin was added to escape, and it makes a dispatching
session blind to its own lane.

## Acceptance

Build `test-status-repo-scoped.sh` against fixture project roots — never a real repo, never a
real state dir — covering:

1. a repo with no declared product metrics ⇒ the rendered board has **no** product line, and
   in particular no `посты`/`комменты`/`реплаи` substring anywhere;
2. a repo that declares them ⇒ the line renders exactly as today;
3. a foreign lane this session did not dispatch ⇒ absent from the board;
4. a foreign lane this session DID dispatch ⇒ present (this is the regression guard for the
   incident the pin was added for);
5. an own-repo lane ⇒ present.

Add the `EXTRA_SUITE_MAP` rows for both touched scripts and prove selection with
`--scope changed`.

## Rules

- Mutation INSIDE the production function body, RED, revert, GREEN, clean `git diff --stat`.
  A suite that stays green with the fix removed is a failed control; a printed `RED control:`
  line that does not change the exit code is not an assertion, and neither is a `FAIL:` line
  that leaves `$?` at 0 — that exact defect shipped in another lane tonight.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- The suite must leave every repo path and every real state root byte-identical, on the
  failure path too. Another lane spent three rounds on exactly this.
- **Do not reorder or restructure the hook arrays in any `settings.json`** — a previous
  reordering evicted the tail of the array, including `scheduled-decisions-inject.sh`.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

A repo that declares no product metrics shows none, a foreign lane this session did not
dispatch does not appear, a foreign lane it did dispatch still does — all five cases proven,
with a mutation that removes the scoping turning the suite red and the exit code following.
