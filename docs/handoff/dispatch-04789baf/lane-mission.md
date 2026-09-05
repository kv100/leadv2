# COMBO: 4 dispatch-code.sh items in one lane (~/Projects/leadv2, base main 585ad7f)

Four queued items share leadv2-dispatch-code.sh — one lane, sequenced smallest-risk first.
Suites: FOREGROUND, strictly SOLO (parallel runs = false reds); on fail rerun solo once.
COMMIT after EACH item (four commits), never one blob.

## 1. ENV-GUARDS nits (critic report docs/handoff/dispatch-6632fad9-review/critic.full.md —
read it first; nits 1-A/1-B target backlog-pump, 2-A/2-B/2-C target dispatch-code):
- 1-A: canonical resolver relies on bash rejecting `cd ""` — make the guard explicit
  ([[ -n ]] check), zsh-proof.
- 1-B: OBSOLETE — pump-caller was deleted (RESIDUE-SWEEP); verify nothing else needs the
  LEADV2_BACKLOG_PUMP_CACHE_DIR seam symmetry, note in artifact.
- 2-A: _codex_newest_rollout_since scans all of $CODEX_HOME/sessions globally — bind the
  rollout to THIS dispatch (cwd/workspace marker in the rollout, or narrow the window +
  journal a warning on ambiguity when 2 candidates match).
- 2-B: healthy codex dispatch pays the full 30s instant-complete window — return early as
  soon as a NON-terminal event newer than spawn is seen (job is alive → stop waiting).
- 2-C: test case 5 stubs DISPATCH_SELF_BIN=/bin/true so the strike never proves requirement
  (c) — make the leg assert the lockout file actually lands.

## 2. CODEX-ARM-WORKTREE-SCOPE-01 (row exists): codex WORKER arm died 5x today
(no_first_byte / vanished job / turn_aborted) when spawning long missions; short direct-door
jobs from repo root work. Root-cause the worker-arm spawn shape in dispatch-code.sh
(_codex spawn path): ensure the job's workspaceRoot is the LANE WORKTREE and registered
(state dir <wtname>-<hash> appears; e.g. e93d9162-ce0636... worked for a review job), and
add a post-spawn liveness probe: if the rollout shows turn_aborted or the job store has no
row within 60s → arm_dead journal + strike + spill (extend the existing
arm_dead_instant_complete machinery). Red-first test with a stubbed codex bin.
NOTE: worker arm is currently under 12h lockout (quota-lockout-codex.json,
SD-CODEX-WORKER-ARM-ABORTED-01) — your fix is what unlocks it; do NOT remove the lockout.

## 3. V3-TIERED-REVIEW-01 (row 12395): machine round-0 before any LLM review — dispatch-code
review arm runs bash -n/shellcheck/changed-scope suites FIRST (builder-selfcheck already
does most of this at build; wire the review arm to consume its verdict instead of paying an
LLM round on a diff that fails mechanics); opus critic = round-1 only; verify-only rounds on
sonnet. Keep scope to the review-arm ordering + journal lines; the sonnet-pilot part is a
flag default-off.

## 4. V3-WORKER-MESSAGING slice-1 (spec docs/specs/worker-messaging-v3.md §slice-1, read it):
leadv2-event.sh emitter (JSONL per repo at ~/.claude/cache/leadv2-events/<repo>.jsonl) + 4
emit call sites in dispatch-code.sh (worker_spawned, arm_refused, worker_terminal,
question_asked). Ships alone, no transport. Red-first test for the emitter + one emit.

## Acceptance
Per-item suites green (red legs shown) · full run-core-offline FOREGROUND SOLO green at the
end · bash -n + shellcheck -S warning · 4 commits on the lane branch.

## Off_limits
leadv2-dispatch-product-close.sh (combo-1 lane owns it); routing order/ceilings; supervise*.

## Terminal artifact
4 commit shas + per-item raw evidence + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-04789baf" "<question>" \
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