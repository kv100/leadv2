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
