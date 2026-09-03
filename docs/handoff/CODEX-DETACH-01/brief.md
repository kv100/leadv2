# CODEX-DETACH-01 — a stale broker.json kills every codex worker attached to it

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CODEX-DETACH-01`

LANE_WRITES: plugins/leadv2/scripts/codex-task.sh,plugins/leadv2/scripts/codex-guard.sh,plugins/leadv2/scripts/tests/test-codex-broker-staleness.sh,tests/run-all.sh,docs/handoff/CODEX-DETACH-01/

Main is `95ed6f310` in `~/Projects/leadv2`. Branch from it.

## What is actually broken

Three codex sol-workers died today — `mtgk8ef8`, `mtgl2ea9`, `mtgl96u7`, all
`worker_process_died`, each within 1–3 minutes of starting. Root cause, established by the
parallel session on the live machine, not by reading code:

`~/.claude/plugins/data/codex-openai-codex/state/<task>/broker.json` named a broker process
that no longer existed, and whose `sessionDir` under `/var/folders/.../cxc-*` had been swept
by the OS. Every new worker attached to that corpse and died. Moving `broker.json` aside made
the companion raise a fresh broker and the next sol task ran to completion.

The file's shape:

```json
{ "endpoint": "unix:/var/folders/.../cxc-0pG62a/broker.sock",
  "pidFile": "...", "logFile": "...", "sessionDir": "/var/folders/.../cxc-0pG62a",
  "pid": 77989 }
```

Two things about the diagnosis you must not undo:

- **This is not a timeout.** `codex-task.sh:1534` already sets an 1800s ceiling. The "5m00s"
  in the failure record is `codex-guard.sh:387-393` stamping `worker_died_silent` after 300s
  of log silence. Raising any timeout fixes nothing; a previous ledger row said otherwise and
  I have marked it superseded.
- **The broker belongs to the Codex plugin, which is not ours.** Do not edit anything under
  `~/.claude/plugins/cache/openai-codex/`. Our layer is `codex-task.sh` / `codex-guard.sh`.

## [Critical] validate the broker before attaching

Before `codex-task.sh` hands a job to the companion, check the task's `broker.json`:
alive means `kill -0 <pid>` succeeds **and** `sessionDir` still exists. If either fails, move
the file aside (do not delete — rename with a timestamp) so the companion raises a fresh
broker, and log one line saying which check failed.

Both halves matter: a swept `sessionDir` with a pid that happens to be reused by an unrelated
process is exactly the case a pid-only check waves through.

## [Critical] the death report must name what died

`codex-guard.sh:387-393` reports `worker_died_silent` and nothing else, which is why this
looked like a timeout for two days across two sessions. Add to the failure record: the last
line of the worker log, and the broker's age plus whether its `sessionDir` still existed at
reap time.

## [Medium] a stale broker must not be able to recur silently

The broker lives under `/var/folders/.../T`, which the OS cleans on its own schedule. The
validation above makes each task self-heal; say in `report.md` whether a stable path is
feasible in our layer alone or whether it needs the foreign plugin, and do not attempt the
latter.

## Acceptance — this is the test, run it

Kill a live broker **and** delete its `sessionDir`, then start a task: it must raise a fresh
broker and run to completion. Build that as `test-codex-broker-staleness.sh` against a fixture
state root — never against the real `~/.claude/plugins/data/` — and add its `EXTRA_SUITE_MAP`
rows for `codex-task.sh` and `codex-guard.sh` so `--scope changed` selects it.

## Rules

- Mutation INSIDE the production function body, RED, revert, GREEN, clean `git diff --stat`.
  A suite that stays green with the fix removed is a failed control; a printed `RED control:`
  line that does not change the exit code is not an assertion, and neither is a `FAIL:` line
  that leaves `$?` at 0 — that exact defect shipped in another lane tonight.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- The suite must leave every repo path and every real state root byte-identical, on the
  failure path too. Another lane spent three rounds on exactly this.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

The stale-broker fixture makes a task self-heal, proven by a mutation that removes the
validation and turns the suite red, with the exit code following. Then the lane is
merge-ready.
