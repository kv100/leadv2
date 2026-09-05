Product implementation task dispatch-4a82f993. Implement this mechanism-closed design; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

PREPASS-MECHANISM-CLOSURE-01 — the design is authoritative, but it is not infallible, and you are the one reading the actual code. If discovery FALSIFIES its census — a caller it did not list, a return code whose consequence differs from what it claims, a configuration state it missed — STOP and say so in your report instead of implementing around it. Silently implementing a design whose census is wrong is how a defect becomes the next review round. Correcting the census in your report is a valid, valuable deliverable; quietly widening scope beyond it is not.

===== SCOPED DESIGN (authoritative) =====
# architect prepass — LANE-OBSERVABILITY-02 FINISH ROUND (worker_reason mis-attribution)

Base: worktree-db9a8aa8 @ 9504588 (the package already landed; this is a finisher, not a rewrite).

## Defect (confirmed, from the finish-round brief)

`lv2_worker_reason`'s codex source (`from_codex_rollout`) globs the GLOBAL codex sessions root
and returns the newest rollout's `task_complete.last_agent_message`. The existing cwd hard filter
only bites when `LEADV2_LANE_WORK_ROOT` is set in the caller's env; when it is empty (A7's fixture,
and any dispatch that does not export it) `pool = candidates` and the newest *foreign* rollout wins.
Test A7 (empty sources -> empty reason) is therefore red on a machine with real `~/.codex/sessions`,
and in prod the same path attributes **another lane's last words to this lane** — a worse lie than
the silence this task set out to fix.

Root rule the fix must establish: **a rollout is used only when something ties it to THIS lane.**
Absence of an attributing key is a miss (empty, rc 0), never "take the newest".

## Changes (exact)

### C1 — sessions root becomes overridable (`plugins/leadv2/scripts/lib/leadv2-worker-reason.sh`)

Resolve the sessions ROOT (not the codex home) once, in shell, and pass it as the existing
`codex_home`-slot argument, renamed to `sessions_root`. Precedence, first non-empty wins:

| # | Source | Note |
|---|---|---|
| 1 | `LEADV2_CODEX_SESSIONS_ROOT` | canonical, project `LEADV2_*` convention |
| 2 | `LV2_CODEX_SESSIONS_ROOT` | alias, literal name in the finish-round brief (see D1) |
| 3 | `${LEADV2_WORKER_REASON_CODEX_HOME}/sessions` | existing knob, kept working |
| 4 | `${CODEX_HOME}/sessions` | |
| 5 | `$HOME/.codex/sessions` | default |

The python side stops doing `os.path.join(codex_home, "sessions")` — it receives the root directly.
Header comment block updated to match (it currently documents the old resolution order).

### C2 — task attribution filter (same file, `from_codex_rollout`)

New predicate applied to every candidate before the newest-wins pick. A candidate survives only if
**both** hold:

1. **mtime window** — `mtime >= since` (unchanged).
2. **task attribution** — `sig8` is non-empty AND the rollout file's content contains that literal
   `sig8` string (the codex prompt/mission always names `dispatch-<sig8>` / the handoff dir, so the
   token is present in the session's own bytes). Read bounded: stream the file once, cap at the
   first ~512 KB, case-sensitive substring match on the raw text.

Then, as an additional AND-guard (not an OR), the existing cwd filter stays: when
`LEADV2_LANE_WORK_ROOT` is set, `session_meta.payload.cwd` must equal it.

Degenerate inputs, all -> `""` with rc 0:
- `sig8` empty or shorter than 8 chars → no attributing key exists → miss. (Never fall through to
  "newest".) This is the line that makes A7 green with or without a real `~/.codex`.
- sessions root missing / unreadable → miss.
- zero survivors → miss.

`from_claude_stream` and `from_glm_out` are unchanged — they are already handoff-dir-scoped, so they
cannot cross lanes.

### C3 — A7 fixture isolation (`plugins/leadv2/scripts/tests/test-worker-reason-terminal.sh`)

A7 points `LEADV2_CODEX_SESSIONS_ROOT` at an empty scratch dir under `$TMP` and asserts
`""` / rc 0. Existing codex-source cases (A3/A4-family) keep their fixture rollouts but the fixture
generator now embeds the case's `sig8` in the rollout body (in the `session_meta` payload's
prompt/instructions text, mirroring prod, where the mission text names `dispatch-<sig8>`) and points
the same env var at the fixture root. New case **A9**: a fixture root holding one rollout whose body
carries a DIFFERENT sig8 → `""` (the mis-attribution regression, red before this change).
Suite total goes 17 → 18 asserts; keep every existing assert text intact.

## Non-goals (do not touch)

- Review-engine verdict logic, deny-floor, profile selector (standing scope guard).
- The other three suites' sources: `leadv2-lane-watch.sh`, `leadv2-broad-status.sh`,
  `leadv2-lanes-snapshot.sh`, `leadv2-dispatch-code.sh`, `leadv2-dispatch-ledger.sh`,
  `leadv2-dispatch-product-close.sh` — re-run their suites, edit nothing.
- The `picked=`-from-journal attribution path. The brief offers it as an alternative ("or"); the
  sig8-content match covers the same cases without teaching a pure lib where journals live, so it is
  explicitly out of scope. If a later round wants it, it arrives as an optional 5th positional
  `rollout_path` arg — additive, no caller change required.
- No new default-on behaviour: this only ever *narrows* what the codex source will return.

## Risks / mitigations

| Risk | Mitigation |
|---|---|
| Prod codex rollouts that never contain the sig8 → worker_reason silently empties out, regressing change 1 | Acceptable and correct-by-design: empty degrades to today's no-token journal line (case B2/C2 already assert that shape). Never guess. Note in the header comment so the next reader does not "fix" it back. |
| 512 KB content-scan cost on large session dirs | Bounded read + mtime `since` window prunes first; scan only survivors of the mtime filter. |
| `LV2_*` alias drifts from `LEADV2_*` convention | Canonical name is `LEADV2_CODEX_SESSIONS_ROOT`; alias documented as brief-compat only (D1). |
| Two tests writing the same fixture root | Every fixture root is per-case under `$TMP`; no shared mutable path. |

## Self-check (mandatory checklist)

1. **Env naming** — brief says `LV2_CODEX_SESSIONS_ROOT`; repo convention is `LEADV2_*`
   (`.claude/settings.json` env block, and every existing knob in this file). Resolution: canonical
   `LEADV2_CODEX_SESSIONS_ROOT`, `LV2_` kept as an accepted alias so the brief's literal name works.
   Recorded as D1 below rather than silently renamed.
2. **Paths** — `plugins/leadv2/scripts/lib/leadv2-worker-reason.sh` and
   `plugins/leadv2/scripts/tests/test-worker-reason-terminal.sh` both exist at 9504588 (verified via
   `git show --stat 9504588`). No `(to-create)` paths.
3. **`claude -p`** — none introduced. N/A.
4. **Concurrent access** — none: the lib is pure-read; fixtures are per-case `$TMP` dirs.
5. **Config contradiction** — `LEADV2_WORKER_REASON_CODEX_HOME` (existing, codex *home*) and the new
   sessions-*root* var have different semantics; both are honoured at distinct precedence levels, so
   an existing caller setting the old var keeps working. No contradiction.

decisions:
- D1 (source: architect(self-check)): canonical env is `LEADV2_CODEX_SESSIONS_ROOT`;
  `LV2_CODEX_SESSIONS_ROOT` accepted as a lower-precedence alias for brief compatibility.
- D2: absence of an attributing key (empty sig8, or no rollout whose body carries it) is a MISS,
  never a fallback to newest-global. This is the whole point of the finisher.

acceptance:
  surface: log_line
  observable: |
    With two lanes dispatched concurrently on the same machine, the lane journal's
    dispatch_terminal line for the lane that stopped with no work either carries a
    worker_reason="..." whose text is that lane's own worker's last words, or carries no
    worker_reason token at all — and never carries the text of the sibling lane's worker.
    A lane whose codex session left no rollout naming its own dispatch id shows the
    no-token form, not a borrowed sentence.
  authored_at: 2026-08-25T11:55:00Z

Suites to run green before commit (in the lane worktree): `test-worker-reason-terminal.sh` (18/18),
`test-prepass-resume-invalidate.sh`, `test-broad-status-foreign-lanes.sh`, `test-lane-watch-poll.sh`,
plus `run-core-offline.sh` for the touched scripts. Commit on `worktree-db9a8aa8`.

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-worker-reason.sh, plugins/leadv2/scripts/tests/test-worker-reason-terminal.sh

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
LANE-OBSERVABILITY-02 — the watch layer lies by silence. Four confirmed defects from the 2026-08-25 fix-round (all evidence in docs/leadv2/tasks/dispatch-16fbe872/journal.md, dispatch-f3ae347e/journal.md, and the rollout ~/.codex/sessions/2026/08/25/rollout-*01a03838*.jsonl):

1. **dispatch_terminal must carry the worker's own reason.** Three stops in a row journaled `terminal=no_work cause=arm_produced_nothing|empty_diff` while the workers' final messages said "DELIVERABLE_BLOCKED: census falsified" / "Stopped at prepass". The lead had to exhume rollout jsonl by hand. Fix in leadv2-dispatch-code.sh review/terminal path: when classifying no_work/dead, extract the worker's last message head (codex rollout `task_complete.last_agent_message`, claude stream `result`, glm equivalent) and append `worker_reason="<first 120 chars>"` to the dispatch_terminal journal line + review-gate.md. Acceptance: a forced no_work lane journals a non-empty worker_reason.

2. **Resume must invalidate a refuted/stale prepass.** architect-prepass.md persisted in the handoff dir and was re-fed on every resume; after a worker refused with census-falsified (or after the lane base moved — merge/ff in the worktree), the same prepass poisoned rounds 2-3. Fix: on --resume-lane, if (a) the previous terminal carried a census/prepass refusal, or (b) the worktree HEAD moved since prepass generation (record the HEAD sha in the prepass header when generating), archive the old prepass to architect-prepass.<ts>.md and regenerate. Acceptance: test that a resume after HEAD move regenerates.

3. **Heartbeat pulse must cover foreign-repo lanes.** The BROAD_STATUS beat (leadv2-status-watch/founder-status.md) renders only the persona-engine repo's lanes; on 2026-08-25 it showed one dead codex handle while two live lanes ran in ~/Projects/leadv2 unseen. Fix: the status renderer enumerates lanes from EVERY repo's docs/leadv2/active.yaml / lane registry reachable from the plugin's known-repos list (or a lanes-registry dir under ~/.claude/state/leadv2/), each row with repo prefix, phase, stream mtime age, and worker_reason if terminal. Acceptance: with a live lane in ~/Projects/leadv2 and none in persona-engine, founder-status.md shows that lane.

4. **Terminal/question events must reach the lead without tail -F.** Lane journals are written via atomic replace, so tail -F watchers silently miss events. Provide a small poll-based watcher script (plugins/leadv2/scripts/leadv2-lane-watch.sh): args = lane journal paths or repo root; every N seconds (default 60) diff each journal against a stored offset, print ONLY new lines matching `dispatch_terminal|question|ask-lead|stall`, plus one heartbeat line every 30 min with per-lane stream-mtime ages; exits when all watched lanes are terminal. Line-buffered stdout so it works under a Monitor. Tests: fixture journal rewritten via mv (atomic replace) still yields the new terminal line exactly once; heartbeat fires on a mocked clock.

Scope guard: do NOT touch the review engine's verdict logic, deny-floor, or the profile selector. Keep every new behavior additive and default-on only where it is pure observability (worker_reason, prepass invalidation guard); the foreign-repo pulse extension must not break a consumer with a single repo.

Run relevant suites green (core-offline for touched scripts + new tests), commit in the lane worktree.

## FINISH ROUND (lead, 2026-08-25 ~14:50) — one red case, root cause confirmed
Selfcheck refused on your own falsification test A7 (empty sources -> non-empty reason). Root cause: lv2_worker_reason's codex fallback scans the GLOBAL ~/.codex/sessions and returns the newest rollout's last_agent_message even when the handoff dir is an empty fixture — in prod that attributes ANOTHER lane's reason to this lane. Fix properly, not by weakening the test:
1. Make the codex sessions root overridable (LV2_CODEX_SESSIONS_ROOT, default ~/.codex/sessions) and have A7's fixture point it at an empty dir.
2. Filter candidate rollouts by the task: only accept a rollout whose content references the task_sig8 (or whose path was recorded in the lane journal's picked= field), plus the since_epoch window. No sig match -> empty string, rc 0.
3. Re-run test-worker-reason-terminal.sh (17/17) and the other three new suites; commit.
Everything already written stays — this is a finisher, do not rewrite the package.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-4a82f993" "<question>" \
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