CODEX-TIERS-COLLAPSED-ONTO-ASTRA-SOL-LUNA-TERRA-UNREACHABLE-01, part B. Part A taught the
LAUNCHER to reach sol / terra / luna. This half teaches the ARBITER to choose them. Until both
halves are in, gate row 1b stays FAIL.

REPO: ~/Projects/leadv2.

## Where part A left it

Part A (branch `worktree-cd486551a5cb`, commit `fe55a781`) fixed the tier table in
`plugins/leadv2/scripts/codex-task.sh`: `top -> gpt-5.6-sol/high`, `standard -> gpt-5.6-terra/medium`,
`volume -> gpt-5.6-luna/low`, each with a NAMED fallback journaled as
`CODEX_FALLBACK_EVENT ... reason=absent_from_models_cache` instead of a silent slide onto astra.
Suite `test-codex-tier-model-table.sh` is green (17/17) and extracts the tier functions verbatim
from the live file. Lead-verified, control red on the resolved model.

What is still broken: `plugins/leadv2/config/leadv2-routing.yaml` carries exactly three codex rows
and **all three are astra**. The arbiter cannot select a model that is not in its matrix, so the
launcher's new capability is unreachable from a live dispatch. Measured: zero
`worker_spawned model=codex-sol|codex-terra|codex-luna` in any lane journal, ever.

## ORDERING — read this before you commit

Part A is NOT merged to main yet (its close gate is being re-run as you start). If this half lands
first, the arbiter starts choosing `sol` while the unfixed launcher still resolves every tier to
astra — a silently wrong model with a confident log line, which is worse than today's honest
collapse. So:

- Build and test against a tree that HAS part A. Merge `worktree-cd486551a5cb` into your lane
  branch (or branch from it) and say in the commit message which base you used.
- If part A is already merged to main by the time you finish, rebase onto main and say so.
- Do NOT merge this to main while part A is unmerged, and do not merge part A yourself — the lead
  sequences that.

## What to build

Give the arbiter one row per real codex tier, with prices/capabilities that reflect what the tier
actually is, so `cheapest_capable` can distinguish them. Today all three rows are the same model
under different names, which makes the choice meaningless whichever way it goes.

- Keep the row count honest: a tier that the account cannot actually serve must not appear as
  selectable. `~/.codex/models_cache.json` is the source of truth for which of
  `gpt-5.6-sol` / `gpt-5.6-terra` / `gpt-5.6-luna` exist; read it, do not assume all three.
- The capability/price cells are a JUDGEMENT — state the reasoning in the commit body (why sol is
  priced above terra, why luna is the volume arm), because a number nobody can explain is a number
  the next session will silently "fix".
- Do NOT edit `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` — a sibling lane (P1b, task
  `5fcc9823fa3b`) owns that file right now and you will be blocked on the write-set. If this half
  genuinely cannot be done in data alone, STOP and say so in the journal rather than reaching into
  that file.

## Acceptance
acceptance:
  surface: command_output
  observable: a resolve-only dispatch (`LEADV2_DISPATCH_SPAWN=0`) for a codex-shaped task prints a
    `route_resolved` / `route_headroom_chosen` line naming a REAL tier model — `codex-sol`,
    `codex-terra` or `codex-luna`, whichever the matrix says is cheapest-capable — and not a bare
    `codex`. Paste the line. Then show the negative side: a task the matrix should NOT send to the
    top tier does not get sol. Two lines, two different answers, from the same matrix.

## Negative controls (E2E-KILLRATE-01) — run them and SHOW them red
1. Inside the body of the function/loader you changed, collapse the three tier rows back onto one
   model. The suite must go red on the RESOLVED ARM NAME — the value under test — not on a log
   string.
2. Inside the same body, mark a tier as available that `models_cache.json` does not list. The suite
   must go red: a matrix that offers a model the account cannot serve is the astra bug wearing a
   different name.
Insert each mutation INSIDE the body, never at top level. Self-register with
`# run-all-triggers: <the real script stem>` and verify with
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh`.

## Constraints
- Bash 3.2 only: no associative arrays in new code, no `${x^^}`, no `readarray`/`mapfile`.
- Never `git add -A`. `git commit -- <path>` commits the WORKING TREE, not the index: stage
  explicitly, check `git diff --cached --stat`, then commit WITHOUT a pathspec.
- Never `reset --hard`, `clean`, `stash`, `worktree prune`. Never push to origin.
- Every claim carries its artifact. Say "unverified" out loud; never "should work".

LANE_WRITES: plugins/leadv2/config/leadv2-routing.yaml, plugins/leadv2/scripts/tests/test-codex-tiers-selectable.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-67dddef9" "<question>" \
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