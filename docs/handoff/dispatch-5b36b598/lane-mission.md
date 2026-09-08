CODEX-TURN-NEVER-HANGS-01. Make a codex worker survive the two upstream failure modes that are
open with no fix and no maintainer response, so "codex works" stops depending on luck.

REPO: ~/Projects/leadv2. Founder order 2026-09-08: "сделай так чтобы кодекс всегда работал."

## What is already proven, and what is still open

Landed and lead-verified (`9ae5e24e`): the BACKGROUND path gets a worker-owned app-server
(`_codex_worker_owned_app_server` in `codex-task.sh:1894-1905`, called from `_run_node`'s
background branch at `:1924`), so killing the shared broker no longer kills the worker. A live job
completed and the negative control went red on the job record.

Still open, and each one is a way for a codex lane to die silently:

1. **The turn can hang forever.** Upstream openai/codex#21937: the app-server worker exits 0
   mid-turn, emits no `Turn completed`, no error, no socket disconnect, and `broker.log` stays
   0 bytes. Reproduced 4/4 in 24h on 0.129/0.130; still open, no maintainer response. The
   companion waits at `~/.claude/plugins/cache/openai-codex/codex/1.0.4/scripts/lib/codex.mjs:600`
   — a bare `return await state.completion;` with nothing racing it. The client already exposes
   the signal we need: `this.exitPromise` (`scripts/lib/app-server.mjs:70`). The issue's own
   reporter worked around it in the WRAPPER layer with
   `Promise.race([state.completion, exitRace])` watching `client.exitPromise`.
2. **The `--wait` / foreground path still uses the SHARED broker.** Only the background branch
   is patched. A foreground codex run still dies with the shared broker.
3. **A hang is not retried.** Even once detected, nothing re-runs the turn.

## What to build

**Everything in OUR adapter — `codex-task.sh`. Do NOT edit anything under
`~/.claude/plugins/cache/openai-codex/`.** That tree is upstream and is replaced on every
companion upgrade; an edit there is invisible to the next version and to every other machine.
Patch the same way `_codex_worker_owned_app_server` already does: wrap the exported API from
our own node preamble.

1. **Turn completion races worker exit.** Wrap the companion's run/turn entry so the await is
   `Promise.race([<the turn>, client.exitPromise.then(() => { throw <typed> })])`. The typed
   error must be its own string — e.g. `codex_worker_exited_before_turn_completed` — and must
   reach the job record and the lane journal as a distinguishable cause, never as today's
   `worker_died_stale_cause_unknown`. A cause label that cannot tell "the worker exited" from
   "we don't know" is why this took three sessions to find.
2. **Worker-owned app-server on EVERY path**, foreground and `--wait` included, not only the
   background branch. Same `disableBroker: true` override.
3. **Retry exactly once** on that typed error, with a fresh worker-owned app-server, and record
   both attempts. Not a loop: one retry, then a typed terminal failure. A silent infinite retry
   is a worse failure than a hang because it burns quota invisibly.
4. **Version-guard the monkey-patch.** The override depends on `CodexAppServerClient.connect`
   and on `client.exitPromise` existing. If either is absent (companion upgraded, API renamed),
   FAIL LOUDLY with a named reason at launch — never fall through silently to the unpatched
   path. Companion pinned today: 1.0.4; `codex-cli 0.153.4`.

## Acceptance
acceptance:
  surface: log_line
  observable: (a) a REAL background codex job completes and its job record shows the
    worker-owned app-server was used; (b) a job whose app-server is killed mid-turn terminates
    with cause `codex_worker_exited_before_turn_completed` — NOT `worker_died_stale_cause_unknown`
    — and shows exactly one retry attempt in the same record; (c) the same override is proven
    active on the foreground/`--wait` path, shown by its own log line from a foreground run.
    Three separate pieces of evidence, each with its own task id.

## Negative controls (E2E-KILLRATE-01) — run them and SHOW them red
1. Inside the function body, drop the `exitPromise` side of the race (await the turn alone).
   The suite must go red on the CAUSE LABEL of a killed-app-server fixture — the value that has
   never varied — not on a log string and not on a timeout.
2. Inside the same body, make the version guard fall through silently when
   `CodexAppServerClient.connect` is absent. The suite must go red on the launch refusal being
   missing. This is the dangerous direction: a silent fall-through re-arms the original bug on
   the next companion upgrade and looks green forever.
Insert each mutation INSIDE the function body, never at top level — a top-level insert makes
every suite red for the wrong reason and reads as a pass. Self-register with
`# run-all-triggers: codex-task` and verify with
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh`; do NOT edit `tests/run-all.sh`.

## Constraints
- Do NOT edit `~/.claude/plugins/cache/openai-codex/**` (upstream tree).
- Do NOT touch `leadv2-dispatch-code.sh`, `lib/leadv2-route-arbiter.sh`, `config/leadv2-routing.yaml`,
  `leadv2-lane-worktree.sh` (a sibling lane owns that file). Read them freely.
- Never `git add -A`. **`git commit -- <path>` commits the WORKING TREE for that path, not the
  index** — in a dirty repo it silently sweeps in other people's uncommitted edits. Stage
  explicitly, check `git diff --cached --stat`, then commit WITHOUT a pathspec.
- Never `reset --hard`, `clean`, `stash`, `worktree prune`. Never push to origin.
- Every claim carries its artifact: a job record, a journal line, a suite output. Say
  "unverified" out loud; never say "should work".

Upstream references (read them, do not assume they were fixed):
- https://github.com/openai/codex/issues/21937 — worker exits 0 mid-turn, no completion event.
- https://github.com/openai/codex/issues/24048 — app-server memory grows to ~27GB on large tool
  output, then SIGKILL. Relevant context for why an app-server disappears under load.

LANE_WRITES: plugins/leadv2/scripts/codex-task.sh, plugins/leadv2/scripts/tests/test-codex-turn-never-hangs.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-5b36b598" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.