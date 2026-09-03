# V3-ENV-GUARDS-01 — architect prepass (scoped implementation design)

Repo: `~/Projects/leadv2` (plugin repo). Three independent guards, one new test suite.
No context.yaml existed for this task (`docs/handoff/dispatch-6632fad9-architect/context.yaml`
absent) — decisions below are architect-owned and flagged where an input is missing.

---

## Item 1 — PUMP-JUNK-IN-LANE-01: pump cache must resolve from the canonical checkout

### Current behaviour (verified on disk)

`plugins/leadv2/scripts/leadv2-backlog-pump.sh`:

- L103–113 — fail-closed root resolution, in order: `LEADV2_PROJECT_ROOT` → `CLAUDE_PROJECT_DIR`
  → `git -C "$PWD" rev-parse --show-toplevel`.
- L219–220:
  ```
  CACHE_DIR="${PROJECT_ROOT}/.claude/cache/backlog-pump"
  LANE_MAP_DIR="${CACHE_DIR}/backlog-pump-lane-map"
  ```
- L284 — `liveness.json` / `liveness.sig` / `liveness.ts` all live under `$CACHE_DIR`.

`--show-toplevel` inside a lane worktree returns **the worktree root**, and a worker session's
`CLAUDE_PROJECT_DIR` is the worktree too. So every one of the three liveness files is written
into the lane tree, and product-close's `unscoped_lane_work` gate sees three files no lane step
declared. Live case: task `6cf5d07e`, 2026-08-20 07:37, offending = exactly those 3 paths.

### Design

Split "where state is read from" (`PROJECT_ROOT`, unchanged) from "where the pump's own cache
lives" (`CACHE_ROOT`, new). Only the cache moves — no other pump semantics change.

Insert immediately above L219:

```
# PUMP-JUNK-IN-LANE-01: the pump's cache is pump-owned scratch, never lane work.
# PROJECT_ROOT may legitimately be a lane worktree (a worker session's
# CLAUDE_PROJECT_DIR / cwd); writing liveness.{json,sig,ts} there makes
# product-close's unscoped_lane_work gate false-block the lane. Resolve the cache
# root from the MAIN checkout via git-common-dir, which is identical from every
# worktree of the same repo (same idiom as leadv2-dispatch-code.sh:635 /
# leadv2-dispatch-ledger.sh:742). The `cd` must happen INSIDE the candidate root:
# --git-common-dir may return a RELATIVE path (".git").
_lv2bp_cache_root() {
  if [[ -n "${LEADV2_BACKLOG_PUMP_CACHE_ROOT:-}" ]]; then
    printf '%s' "${LEADV2_BACKLOG_PUMP_CACHE_ROOT}"; return
  fi
  local r
  r="$(cd "${PROJECT_ROOT}" 2>/dev/null \
       && cd "$(dirname "$(git rev-parse --git-common-dir 2>/dev/null)")" 2>/dev/null \
       && pwd -P)"
  [[ -n "${r}" && -d "${r}" ]] || r="${PROJECT_ROOT}"   # non-git sandbox -> old behaviour
  printf '%s' "${r}"
}
CACHE_ROOT="$(_lv2bp_cache_root)"
```

then `CACHE_DIR="${CACHE_ROOT}/.claude/cache/backlog-pump"`. `LANE_MAP_DIR` is derived from
`CACHE_DIR` and is fixed for free.

**Rejected alternative:** `$HOME`-anchored (`${LEADV2_CANONICAL_ROOT:-$HOME/Projects/leadv2}`).
It works for this machine but hard-codes one repo into a script that already runs in four repos
(persona-engine, m3-market, respiro-ios). `git-common-dir` is repo-agnostic and is the idiom the
rest of the plugin already uses.

**Env-var naming check:** `LEADV2_BACKLOG_PUMP_CACHE_ROOT` matches the file's existing
`LEADV2_BACKLOG_PUMP_*` family (`_MAX`, `_DISPATCH_BIN`, `_QUOTA_BIN`, `_LIVENESS_BIN`,
`_LIVENESS_CACHE_S`). No `LEAD_V2_*` drift. `.claude/settings.json` has no `env` block, so
there is nothing to contradict.

### Concurrent-access surface (mandatory checklist item 4)

Consolidating the cache means a pump running from the main checkout and one running from a
worktree now write **the same** `liveness.json`/`.sig`/`.ts`. Before this change they were
separate files, so the collision is new. The implementer MUST verify `_resolve_liveness_json`
(L282–300) writes via `mktemp` + `mv -f` (atomic rename), not a direct `>` truncate; if it
does not, add it. The pump's own `PUMP_LOCK_DIR` mkdir-lock does not cover this path.

### Red-first test

Build a scratch git repo, `git worktree add` a real lane worktree (a fake directory will not do
— `--git-common-dir` must resolve), run the pump with cwd = worktree and `CLAUDE_PROJECT_DIR` =
worktree.

- RED (pre-fix): `<worktree>/.claude/cache/backlog-pump/liveness.json` exists.
- GREEN (post-fix): no `.claude/cache` directory under the worktree at all; the liveness files
  appear under `<main>/.claude/cache/backlog-pump/`.

---

## Item 2 — SD-CODEX-SILENT-INSTANT-COMPLETE-01: `arm_dead_instant_complete`

### Why the existing guard misses it (verified)

`_codex_first_byte_deadline_check` (L3377–3403) probes `codex-task.sh log <handle>` for ANY
non-empty output. The dead spawns wrote ~100KB of rollout, so the first byte lands instantly and
the guard returns 0. The dispatcher then confirms the row and detaches; the lane starves.

The dead shape, from a live rollout on this machine
(`~/.codex/sessions/2026/08/04/rollout-2026-08-04T12-32-52-019fcc1e-....jsonl`, last line):

```
{"timestamp":"2026-08-04T09:32:55.683Z","type":"event_msg","payload":{"type":"task_complete",
 "turn_id":"019fcc1e-...","last_agent_message":null,"completed_at":1785835975,"duration_ms":396}}
```

`last_agent_message: null` + sub-second `duration_ms` on a terminal `task_complete` is the
signature.

### Design

New sibling function next to `_codex_first_byte_deadline_check`, and a second branch in the
existing `if [[ "${arm}" == "codex" ]]` block inside
`atomic_dispatch_reserve_spawn_confirm` (L3494–3507). Return contract is deliberately identical
to the first-byte check — `0 = proceed`, `7 = dead, abort + spill` — so the caller branch is a
copy of the one already proven at L3496–3506.

```
_codex_instant_complete_check() {   # <handle> <sig8> <spawn_epoch> -> 0 proceed | 7 dead
```

Behaviour:

| Observation within the window | Verdict |
|---|---|
| newest matching rollout grew since last sample | 0 — alive |
| terminal `task_complete` with NON-null `last_agent_message` | 0 — real completion |
| terminal `task_complete` with `last_agent_message == null` | **7 — dead** |
| no rollout matched at all | 0 — inconclusive, journal `state=no_rollout` |
| window expired, no growth, no `task_complete` | 0 — the first-byte guard owns silence |

**Fail-open on absence of evidence** is deliberate: a false spill costs a healthy arm and a
provider strike, which is strictly worse than the status quo for the common case.

Rollout resolution (testable):

- `CODEX_ROLLOUT_DIR="${LEADV2_CODEX_ROLLOUT_DIR:-${CODEX_HOME:-${HOME}/.codex}/sessions}"`
- newest `rollout-*.jsonl` under it with `mtime >= spawn_epoch` whose content contains
  `dispatch-<sig8>` (the mission text carries the task id — confirmed in the sample rollout
  above, which contains `"dispatch-81ec9717"`). This avoids inventing a jobId→rollout mapping
  that I could not verify exists.
- Parse the terminal event with `python3` reading the last `"type":"task_complete"` line — a
  bare grep for `last_agent_message":null` would match a non-terminal event and mis-fire.

Knobs (naming follows the existing `LEADV2_CODEX_FIRST_BYTE_SECS`):

| Var | Default | Meaning |
|---|---|---|
| `LEADV2_CODEX_INSTANT_COMPLETE_SECS` | `30` | verification window; `0` disables |
| `LEADV2_CODEX_INSTANT_COMPLETE_LOCKOUT_MIN` | `15` | stand-down minutes on a strike |
| `LEADV2_CODEX_ROLLOUT_DIR` | `${CODEX_HOME:-$HOME/.codex}/sessions` | fixture override for tests |

On dead:

```
emit decision "arm_dead_instant_complete arm=codex task=${sig8} job=${handle} rollout=${f}"
bash "${DISPATCH_SELF_BIN:-${SCRIPT_DIR}/leadv2-dispatch-code.sh}" record-quota-lockout \
  --provider codex --minutes "${LEADV2_CODEX_INSTANT_COMPLETE_LOCKOUT_MIN:-15}" \
  --reason arm_dead_instant_complete >/dev/null 2>&1 || true
return 7
```

`record-quota-lockout --provider … --minutes …` is verified to exist and to accept
`--minutes` in `1..10080` (`leadv2-dispatch-code.sh:4790–4793`); `--reason` is already used by
the first-byte guard at L3396–3397. Note the existing guard uses `--hours 1`; `--minutes` is
used here because the mission asks for a SHORT lockout — an instant-complete is far more likely
to be transient than a never-started job.

Caller branch (immediately after the first-byte block, still inside `arm == codex`):

```
LAST_ARM_OUTCOME="codex_dead_instant_complete"
emit decision "arm_refused by=router model=codex task=${sig8} reason=instant_complete"
log "spawn(codex) instant task_complete with null last message; spilling to next arm"
dispatch_abort "${token}" ; rc0 -> return 7 ; else return 5
```

`return 7` is the candidate loop's existing spill path — no new control flow.

### Red-first test

Stub `LEADV2_DISPATCH_CODEX_BIN` (existing override) + `LEADV2_CODEX_ROLLOUT_DIR` pointing at a
fixture dir.

- RED leg: fixture rollout with `last_agent_message: null` → pre-fix the dispatch confirms and
  reports success; post-fix the journal carries `arm_dead_instant_complete` and the arm spills.
- GREEN leg: same fixture with a non-null `last_agent_message` → no journal line, no spill.
- Third leg: no rollout in the fixture dir → no journal `arm_dead_*` line, no spill (fail-open).

---

## Item 3 — worker env asserts

### A) `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`

**Evidence the risk is live:** the repo sets this nowhere
(`grep -rn AGENT_TEAMS --exclude-dir=.git .` → only a transcript artifact, no config;
`.claude/settings.json` has no `env` block), yet a subagent env dump captured on 2026-08-19
(`docs/handoff/dispatch-6abed111-architect/architect.stream.jsonl:85`) shows
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. So the value reaches workers by **ambient profile
inheritance**, which is exactly the regression path the mission names.

Design: one helper, called once at the top of `spawn_worker()` (L2749), before any arm branch.
`spawn_worker` launches every arm's child from this shell, so a plain `unset` in the dispatcher
process propagates to all arms — no per-arm command-line surgery, no `env -u` wrappers.

```
_worker_env_asserts() {   # <sig8> — journals one line per assert, never fails the caller
  local sig8="$1" v="${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}"
  if [[ -n "${v}" && "${v}" != "0" ]]; then
    unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
    emit decision "worker_env_assert name=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS was=${v} action=unset task=${sig8}"
  else
    emit decision "worker_env_assert name=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS state=ok action=none task=${sig8}"
  fi
  ...
}
```

`unset` (not `export …=0`) is required: the mission's contract is "unset **or** 0", and an
explicit `=0` is a value a future CC release could read differently from absent.

### B) `CLAUDE_CODE_ENABLE_TODO_TOOLS` — **AUDIT INPUT MISSING, do not set**

The mission cites `docs/handoff/CC-RELEASE-AUDIT-230-236.md` as the audit source.
**That file does not exist in this repo** — `find . -name 'CC-RELEASE-AUDIT*' -not -path './.git/*'`
returns nothing. Per the unrecognized-entity rule I will not invent its conclusion, and:

> UNVERIFIED: the claim that CC 2.1.233 requires `CLAUDE_CODE_ENABLE_TODO_TOOLS` on Sonnet 5+ /
> Opus 4.8 has no artifact reachable from this repo.

Design decision **D-A1**: the assert **records** the state and sets nothing.

```
emit decision "worker_env_assert name=CLAUDE_CODE_ENABLE_TODO_TOOLS state=audit_input_missing action=none task=${sig8}"
```

If the lead supplies the audit doc (or a decision), the follow-up is two lines inside the same
helper — `export CLAUDE_CODE_ENABLE_TODO_TOOLS=1` plus the assert's `action=set` — and the test
leg for it is already parameterized. The implementer must **not** guess. Silently exporting a
flag on the strength of an unreachable document is exactly the class of change round-1 review
treats as BLOCKING.

Net: two journal lines per spawn.

### Red-first test

- RED/GREEN A: run `spawn_worker` (dry-run arm, `do_spawn` path stubbed) with
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in the environment → journal shows
  `action=unset`, and the stub launcher's captured environment does **not** contain the var.
  With the var absent → journal shows `state=ok`.
- Test B: journal shows exactly one `name=CLAUDE_CODE_ENABLE_TODO_TOOLS state=audit_input_missing`
  line and the stub launcher's captured environment does not contain the var.

---

## Files

| File | Change |
|---|---|
| `plugins/leadv2/scripts/leadv2-backlog-pump.sh` | Item 1 — `_lv2bp_cache_root()` + `CACHE_DIR` re-anchor; verify atomic liveness write |
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | Item 2 — `_codex_instant_complete_check()` + caller branch; Item 3 — `_worker_env_asserts()` called from `spawn_worker()` |
| `plugins/leadv2/scripts/tests/test-env-guards-01.sh` | **(to-create)** — new suite, all three items, red-first legs |
| `plugins/leadv2/scripts/tests/run-core-offline.sh` | Register the suite in `SUITE_DEFS` **and** in `_CORE_OFFLINE_OWNED_SUITES` |
| `plugins/leadv2/hooks/leadv2-supervisor-pump-caller.sh` | Item 1b (Addendum A) — sentinel reader must follow the cache root, not `CWD_FROM_INPUT` |

Suite registration — the name string must be **byte-identical** in both places or the
hermeticity gate (L85–101) will not recognise the lane as owning its own suite:

```
"env guards (V3-ENV-GUARDS-01: pump cache root + codex instant-complete + worker env asserts)|||bash $TEST_DIR/test-env-guards-01.sh"
```

## Non-goals (implementer: ignore these)

- `leadv2-dispatch-product-close.sh` and `lib/leadv2-builder-selfcheck.sh` — off_limits, a live
  lane owns them. The `unscoped_lane_work` gate is **not** relaxed; Item 1 fixes the producer.
- Routing order, arm ceilings, candidate-chain composition.
- `supervise*` — deleted; resurrect nothing.
- Any jobId→rollout mapping inside codex-companion.
- Changing `_codex_first_byte_probe` / the existing `--hours 1` first-byte lockout.
- Moving `PROJECT_ROOT` semantics in the pump — only `CACHE_DIR` re-anchors.
- Setting `CLAUDE_CODE_ENABLE_TODO_TOOLS` (see D-A1).
- Retro-cleaning the junk already committed under lane trees.

## Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | New cross-worktree write collision on `liveness.json` (Item 1 consolidates what were separate files) | Require `mktemp`+`mv -f` in `_resolve_liveness_json`'s writer; implementer verifies before landing |
| R2 | Non-git sandbox → `--git-common-dir` empty → cache root unresolved | Explicit `[[ -n && -d ]]` fallback to `PROJECT_ROOT` (old behaviour); no new fail-closed path |
| R3 | Instant-complete check false-fires on a fast, legitimately-completed codex job | The null-`last_agent_message` condition is the discriminator; a real completion carries text. Non-null → proceed |
| R4 | Rollout matched by sig8 grep picks a *previous* run's file | `mtime >= spawn_epoch` filter + newest-first ordering |
| R5 | 30s window added to every codex spawn's critical path | Only entered when the generic early-verdict window found neither terminal failure nor no-work; exits on first growth sample (typically <2s). `…_SECS=0` disables |
| R6 | The audit doc named by the mission does not exist | D-A1 — record, do not set; escalate to lead |
| R7 | Two journal lines per spawn × every arm = journal volume | Accepted; single-line, low-cardinality, and the mission requires one line per assert |
| R8 | Suite name drift between `SUITE_DEFS` and `_CORE_OFFLINE_OWNED_SUITES` silently disables the hermeticity gate | Called out above; verify by string comparison in the same edit |
| R9 | Item 1 lands without Item 1b → below-floor throttle silently degrades 45 s → 180 s, no error, no journal line | Addendum A; both edits in one commit, plus the dedicated red leg that fails on Item-1-only |
| R10 | Hook edit does not reach the running session (plugin hook cache is a separate copy; `plugin update` no-ops on unchanged version) | Implementer copies the hook into the plugin cache and restarts the session; terminal artifact must state this explicitly, else the Item 1b green is unverified |

## Addendum A — Item 1b: the below-floor sentinel READER must move with the cache

Found on a second pass over the same cache dir. This is a consequence of the Item 1 fix, not an
independent bug, and it must land in the SAME commit or Item 1 silently regresses pump cadence.

Verified on disk:

- `plugins/leadv2/scripts/leadv2-backlog-pump.sh:432` — `_set_below_floor_sentinel` writes
  `${CACHE_DIR}/backlog-pump-below-floor`. So today this file is a **fourth** cwd-relative junk
  artifact in a lane worktree, alongside `liveness.{json,sig,ts}`; Item 1's `CACHE_DIR` re-anchor
  fixes its write path for free.
- `plugins/leadv2/hooks/leadv2-supervisor-pump-caller.sh:164` — the reader is anchored to
  `CWD_FROM_INPUT` (hook input cwd, falling back to `$PWD` at L65), *not* to `PROJECT_ROOT` and
  not to the new cache root. It only `-f`-tests the path, so it writes nothing — but after Item 1
  the writer and the reader point at different directories whenever the session's cwd is a lane
  worktree.

**Failure mode after Item 1 alone:** the sentinel is written under the main checkout; a hook
firing in a worker session looks for it under the worktree, never finds it, and
`EFFECTIVE_THROTTLE` stays at `THROTTLE_S` (180 s) instead of dropping to
`THROTTLE_BELOW_FLOOR_S` (45 s). Floor recovery is silently ~4× slower — exactly the regression
`LANE-CONCURRENCY-IN-PLUGIN` C-1 (the comment block at L155–162) was added to prevent. Nothing
errors and no journal line is emitted, so this would not be caught by the Item 1 test.

**Design.** Give the hook the same cache-root resolution, in the same shape, so the two agree by
construction:

```
# PUMP-JUNK-IN-LANE-01 / Item 1b: the pump's cache is anchored to the MAIN checkout
# (git-common-dir), never to the hook's input cwd — a worker session's cwd is a lane
# worktree. Reader and writer must resolve identically or the below-floor throttle
# never fires. Same precedence as leadv2-backlog-pump.sh::_lv2bp_cache_root.
_lv2pc_cache_root() {
  if [[ -n "${LEADV2_BACKLOG_PUMP_CACHE_ROOT:-}" ]]; then
    printf '%s' "${LEADV2_BACKLOG_PUMP_CACHE_ROOT}"; return
  fi
  local r
  r="$(cd "${CWD_FROM_INPUT}" 2>/dev/null \
       && cd "$(dirname "$(git rev-parse --git-common-dir 2>/dev/null)")" 2>/dev/null \
       && pwd -P)"
  [[ -n "${r}" && -d "${r}" ]] || r="${CWD_FROM_INPUT}"
  printf '%s' "${r}"
}
BELOW_FLOOR_SENTINEL="$(_lv2pc_cache_root)/.claude/cache/backlog-pump/backlog-pump-below-floor"
```

The two copies of the helper are deliberate: the hook must stay standalone (it is sourced by
nothing and runs from the plugin cache, where a `source` of a sibling script is a new failure
surface). The shared contract is the env var name plus the `git-common-dir` idiom, both asserted
by the test below. If the implementer prefers one definition, the only safe home is a tiny
`lib/` helper sourced with an existence guard — that is a bigger blast radius than this lane
warrants; `# lean:` duplicate is the recommendation.

`CWD_FROM_INPUT` is *not* replaced elsewhere in the hook — `STATE_DIR` / `STAMP` (L146) are a
separate, deliberately session-scoped throttle stamp and must not move.

**Hook-cache caveat (blocking for verification, not for the commit).** Per the shared-trees
policy, the plugin **hook cache is a separate copy** and `claude plugin update` no-ops when
content changed but the version did not. Editing
`plugins/leadv2/hooks/leadv2-supervisor-pump-caller.sh` in the repo does **not** load the fix
into a running session: the file must be copied into the plugin cache and the session restarted,
or the guard never runs. The implementer must state in the terminal artifact whether the cache
copy was done; a "green" claim from a session that never reloaded the hook is a lying-green.

**Red-first test** (add as a leg of the same new suite, reusing Item 1's scratch repo +
`git worktree add` fixture):

- Drive the pump so `_set_below_floor_sentinel 1` runs with cwd = worktree.
- RED (pre-fix): the sentinel exists under `<worktree>/.claude/cache/backlog-pump/`.
- After Item 1 only: sentinel under `<main>/`, and the hook's resolved `BELOW_FLOOR_SENTINEL`
  path (echo it under a test-only debug flag, or assert the resolved string via a `bash -c`
  harness sourcing the same helper) still points under `<worktree>/` → **the leg that must go red
  and prove Item 1b is not redundant.**
- GREEN (post-fix): both paths resolve to the identical `<main>/...` string.

## Acceptance

```yaml
acceptance:
  - surface: file_artifact
    observable: >-
      After the backlog pump runs from inside a lane worktree, that worktree's
      directory listing shows no .claude/cache directory at all, and the main
      checkout's .claude/cache/backlog-pump folder contains the liveness.json,
      liveness.sig and liveness.ts files instead.
    authored_at: 2026-08-20T06:20:00Z
  - surface: file_artifact
    observable: >-
      With the pump run from inside a lane worktree, the backlog-pump-below-floor
      marker file is visible only under the main checkout's
      .claude/cache/backlog-pump folder, and the path the pump-caller hook reports
      it is looking at is that same main-checkout path — the two strings read
      identical, with no worktree path appearing on either side.
    authored_at: 2026-08-20T06:45:00Z
  - surface: log_line
    observable: >-
      When a codex arm reports itself complete within seconds and leaves no agent
      message behind, the dispatch journal for that task shows a line reading
      "arm_dead_instant_complete arm=codex task=<sig8> job=<handle> ...", followed
      by the arm-refused line naming reason=instant_complete, and the lane goes on
      to a different arm instead of sitting idle.
    authored_at: 2026-08-20T06:20:00Z
  - surface: log_line
    observable: >-
      Every worker spawn writes exactly two worker_env_assert lines into the
      dispatch journal — one naming CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS (reading
      action=unset when the value was inherited as 1, state=ok otherwise) and one
      naming CLAUDE_CODE_ENABLE_TODO_TOOLS with state=audit_input_missing.
    authored_at: 2026-08-20T06:20:00Z
  - surface: rendered_line
    observable: >-
      The core-offline run printout lists a suite named "env guards
      (V3-ENV-GUARDS-01: pump cache root + codex instant-complete + worker env
      asserts)" and its summary line reports zero failures; the overall run ends
      with no new failing suites beyond the known parallel-run contention flakes.
    authored_at: 2026-08-20T06:20:00Z
```

---

## Addendum B (re-spawn pass, 2026-08-20T06:35Z) — one gap + refreshed Item-2 evidence

This pass re-derived the design independently and confirms Addendum A and Items 1–3 as written.
Two changes.

### B-1 (NEW, must ship with Item 1) — `EMPTY_STREAK_DIR` is a **fifth** cwd-relative artifact

`plugins/leadv2/scripts/leadv2-backlog-pump.sh:871`:

```sh
EMPTY_STREAK_DIR="${PROJECT_ROOT}/.claude/cache/backlog-pump-empty-streak"
```

Same defect class as `CACHE_DIR` (L219) and the hook's below-floor sentinel (Addendum A): anchored
to `PROJECT_ROOT`, which resolves to `CLAUDE_PROJECT_DIR` / `git rev-parse --show-toplevel` of the
calling session — a lane worktree for any worker-side invocation. It is written by `cmd_reap`, so
it produces junk under a lane worktree *and* silently defeats its own purpose: the empty-outcome
retry bound is a per-directory counter, so a per-worktree copy resets the streak and the bound
never trips.

**Fix:** re-anchor to the same `_lv2bp_cache_root()` helper Item 1 introduces —
`EMPTY_STREAK_DIR="${CACHE_ROOT}/.claude/cache/backlog-pump-empty-streak"`. No new helper, no new
file, no behaviour change on the main checkout (where `git-common-dir`'s parent == `PROJECT_ROOT`).

**Test leg (add to the Item-1 red-first suite):** run the pump's reap path with cwd = a fake
worktree; assert `<fake-worktree>/.claude/cache/` does not exist afterwards. Today that assertion
fails (RED); after the re-anchor it passes.

`LANE_WRITES` is unchanged — B-1 touches a file already in the set.

### B-2 — Item 2 dead-shape evidence refreshed to tonight's spawns

The full.md cites an 08-04 rollout. Three of tonight's four dead spawns, probed live on this
machine at 2026-08-20T06:33Z, carry the identical shape and are the better artifact:

```
$ for f in ~/.codex/sessions/2026/08/20/*.jsonl; do grep -o '"type":"task_complete"[^}]*}' "$f" | head -1; done
"type":"task_complete","turn_id":"01a01c6e-2702-...","last_agent_message":null,"completed_at":1787183377,"duration_ms":893}
"type":"task_complete","turn_id":"01a01cd0-777d-...","last_agent_message":null,"completed_at":1787189819,"duration_ms":660}
"type":"task_complete","turn_id":"01a01cfa-8ccd-...","last_agent_message":null,"completed_at":1787192578,"duration_ms":946}
```

Contrast — the same day's healthy spawn, same file family:

```
"type":"task_complete","turn_id":"01a01c5c-c0bb-...","last_agent_message":"Blocked on an explicit scope conflict ...","completed_at":1787182640,"duration_ms":404419,"time_to_first_token_ms":2658}
```

Two design points this confirms:

1. The `last_agent_message == null` discriminator is sound — the healthy job carries text
   (risk R3 in the table above is correctly rated low).
2. **Rollout→task association can use `cwd`, not a content grep for `dispatch-<sig8>`.** The
   `session_meta` first line carries the worker's cwd verbatim:
   `"cwd":"/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9c027877"`. Matching on
   `session_meta.cwd == <lane worktree path>` is exact and structural, where the mission-text grep
   is heuristic (it fails if the mission is truncated or the sig8 appears in an unrelated job).
   Recommend the implementer prefer `cwd`, keeping the sig8 grep only as a secondary filter.
   `duration_ms` is deliberately **not** part of the discriminator — a legitimately fast job must
   not be killed; nullness is the signal.

---

## Escalations for lead

1. `docs/handoff/CC-RELEASE-AUDIT-230-236.md` is missing. Item 3B ships as record-only.
   If the founder wants `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` on workers, that needs the doc or an
   explicit decision.
2. No `context.yaml` was present for this task id, so no `decisions:`/`off_limits:` block was
   available; off_limits was taken verbatim from the mission text.
3. Addendum A adds `plugins/leadv2/hooks/leadv2-supervisor-pump-caller.sh` to the write set. It is
   not in the mission's off_limits list, but it is a **hook**, so the plugin-cache copy + session
   restart caveat applies (R10). If the lead would rather keep hooks out of this lane, Item 1 must
   ship with the below-floor throttle regression documented as a known, accepted degradation —
   shipping Item 1 alone and calling it clean is not an option.

LANE_WRITES: plugins/leadv2/scripts/leadv2-backlog-pump.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/hooks/leadv2-supervisor-pump-caller.sh, plugins/leadv2/scripts/tests/test-env-guards-01.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
