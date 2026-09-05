Product implementation task dispatch-db9a8aa8. Implement this mechanism-closed design; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

PREPASS-MECHANISM-CLOSURE-01 — the design is authoritative, but it is not infallible, and you are the one reading the actual code. If discovery FALSIFIES its census — a caller it did not list, a return code whose consequence differs from what it claims, a configuration state it missed — STOP and say so in your report instead of implementing around it. Silently implementing a design whose census is wrong is how a defect becomes the next review round. Correcting the census in your report is a valid, valuable deliverable; quietly widening scope beyond it is not.

===== SCOPED DESIGN (authoritative) =====
# LANE-OBSERVABILITY-02 — architect prepass

Scoped design for four confirmed watch-layer defects. Additive only; no verdict/deny-floor/selector changes.

## Discovery corrections to the mission text (verified on disk)

| Mission claim | Reality |
|---|---|
| "Fix in `leadv2-dispatch-code.sh` review/terminal path" | Every `no_work`/`dead` terminal is written by `leadv2-dispatch-product-close.sh` via `_dl_note()` (:108) → `dispatch_ledger_write_terminal()` (`leadv2-dispatch-ledger.sh`:211). `leadv2-dispatch-code.sh` has **no** `write_terminal` callsite. Fix lands in product-close + ledger. |
| "status renderer enumerates … known-repos list" | `leadv2-status-projects.sh` already emits `slug \t state_dir \t repo_root` TSV, cwd-independent. No new registry dir needed. Lane rows come from `leadv2-lanes-snapshot.sh` → `leadv2-status-collector.sh` → `leadv2-broad-status.sh`. |
| "codex rollout `task_complete.last_agent_message`" | Discovery + parse logic already exists in `leadv2-dispatch-code.sh`:4654-4746 (newest `~/.codex/sessions/**/rollout-*.jsonl` by mtime). Extract to a shared lib rather than duplicating. |

---

## Change 1 — `worker_reason` on every no_work/dead terminal

**New** `plugins/leadv2/scripts/lib/leadv2-worker-reason.sh`

```
lv2_worker_reason <handoff_dir> <arm> <task_sig8>   # stdout: <=120 chars, single line; empty on miss; rc always 0
```

Resolution order (first non-empty wins), each source guarded and fail-open-to-empty:

| arm | source | extraction |
|---|---|---|
| sonnet/claude | `<handoff>/developer.stream.jsonl` | last `{"type":"result"…}` → `.result`; else last `type:assistant` text block |
| codex | newest `~/.codex/sessions/**/rollout-*.jsonl` with mtime ≥ lane start (logic lifted from dispatch-code.sh:4657-4746) | last `task_complete.last_agent_message` |
| glm/kimi | `<handoff>/developer.glm.out` (or `<handoff>/<arm>.stream.jsonl` when present) | last non-blank line |

Sanitisation: collapse newlines/tabs to space, strip `"` `\` and control chars (same class as `json_safe`), squeeze spaces, cut to 120 bytes. Python3 one-shot inside the function — the file scan is already python elsewhere in this codebase.

**Wire-in (single choke point):**
- `leadv2-dispatch-product-close.sh` `_dl_note()` — when `$1` ∈ {`no_work`,`dead`}, compute once (memoised in `_PC_WORKER_REASON`) and append ` worker_reason="<…>"` to the evidence string it forwards.
- `leadv2-dispatch-ledger.sh` `dispatch_ledger_write_terminal()` — **new optional 10th positional** `worker_reason` (default empty). Appended to the journal line as ` worker_reason="…"` only when non-empty; the JSON row gains a `"worker_reason"` key always-present (empty string when unknown), consistent with the `commit`/`deliverable` precedent at :204. All existing 7/9-arg callsites keep byte-identical output.
- review-gate.md: the two blocked writers (`arm_produced_nothing` at :2225, and the `empty_diff` / `_pc_terminal` writer feeding :2139) gain a `worker_reason: <…>` line after `reason:`. Omitted when empty, so existing `review-gate.md` parsers (`leadv2-review-findings.sh`, `leadv2-phase8-e2e-gate.sh`, `leadv2-pulse-beat.sh`) see an unknown-key line only — all of them are per-key greps.

Default ON (pure observability). Kill switch `LEADV2_WORKER_REASON=0`.

## Change 2 — resume invalidates a refuted / stale prepass

`leadv2-dispatch-code.sh`, prepass generator + cache gate (~:3040 `_prepass_file`, :3710-3728 cache check, :3891 emit).

**Generation:** first line of `architect-prepass.md` becomes a comment header
`<!-- leadv2-prepass base_head=<sha> generated_at=<ISO8601> -->`, and the sha is *also* written to `${f}.head` (sidecar — the header is for humans, the sidecar is the machine read, so a worker that rewrites the body cannot corrupt the check). Existing readers (`leadv2-lane-detail.sh`, `leadv2-lane-status-line-tail.sh`, `leadv2-phase8-e2e-gate.sh` `LANE_WRITES` scan, `leadv2-acceptance-shape.sh`) are line-scanners keyed on headings / `LANE_WRITES:` — an HTML comment first line is inert to all of them.

**Invalidation gate**, evaluated only when the run is a resume (`--resume-lane` / `--worktree` pin resolved at :5247-5360), *before* the `PREPASS_CACHE` sig-match check:

1. `dispatch_terminal_last_state` + last row `cause` for this sig8 matches `census|prepass|falsif|refus` (case-insensitive) → invalidate.
2. `cat ${f}.head` ≠ `git -C "$WORK_ROOT" rev-parse HEAD` → invalidate (covers merge/ff in the worktree). Missing/unreadable `.head` (every pre-existing artifact) → **treat as stale, invalidate once**; the regenerate then stamps it.

Invalidate = `mv architect-prepass.md architect-prepass.<epoch>.md` (and `.sig`, `.head` alongside), then fall through to regeneration. Emit `architect_prepass task=<sig8> status=invalidated reason=head_moved|prepass_refuted old_head=<sha> new_head=<sha> archived=architect-prepass.<epoch>.md`.

Non-resume runs are untouched. Gate `LEADV2_PREPASS_INVALIDATE=1` (default on), `=0` restores today.

## Change 3 — pulse covers foreign-repo lanes

`leadv2-lanes-snapshot.sh` gains `--all-repos` (and env `LEADV2_LANES_ALL_REPOS`, default `1`):

1. Enumerate repos from `leadv2-status-projects.sh` TSV (`slug \t state_dir \t repo_root`).
2. Own repo (`repo_root -ef PROJECT_ROOT`) is read exactly as today.
3. Each foreign repo is read read-only (`active.yaml` + lane registry only — **never** the adopt/tombstone/prune writes at the top of that script; those stay own-repo-only, guarded by an explicit `_own_repo` flag). A foreign read is spawned as a subshell with `PROJECT_ROOT=<repo_root>`.
4. Every row carries a new `repo` field (slug). A foreign repo whose read fails yields one `{"repo":"<slug>","error":"repo_read_error","data":"<stderr head>"}` row — it must **not** zero the table (LANE-DETAIL-BLIND-01 contract: a sub-read failure is loud, never silently empty).

`leadv2-broad-status.sh` renderer (python block from :174): lane name is prefixed `"<slug>/"` **only when `slug != own_slug`**; row gains `stream mtime age` (already computed per-lane by `leadv2-lane-detail.sh`) and `worker_reason` when the lane is terminal. A `repo_read_error` row renders as a named degraded row, reusing the existing "не вижу линии" prefix mechanism.

**Single-repo consumer safety (explicit requirement):** when the TSV yields exactly one repo, no prefix is added and no extra rows appear → `founder-status.md` is byte-identical to today. Locked by a test.

## Change 4 — poll-based lane watcher

**New** `plugins/leadv2/scripts/leadv2-lane-watch.sh`.

```
leadv2-lane-watch.sh [--interval N=60] [--heartbeat N=1800] [--once] [--state-dir DIR] <journal.md|repo-root> ...
```

- A repo-root arg expands to `<root>/docs/leadv2/tasks/dispatch-*/journal.md`.
- **Offsets are LINE COUNTS, not byte offsets** — this is the fix for atomic replace. `mv`-replace swaps the inode but the journal is append-only, so the previous content is a line-prefix of the new file; `tail -n +$((seen+1))` is exactly-once and inode-independent. `tail -F` fails here because it follows the *old* inode. If current line count < stored, treat as rotation and reset to 0. Offsets stored under `<state-dir>/lane-watch/<sha1(abspath)>.lines` (state-dir from `leadv2-state-path.sh`, override via flag).
- Emitted lines: only those matching `dispatch_terminal |question|ask-lead|stall`, printed as `<repo-slug>/<task-id> <line>`. Matching happens in-loop; any `grep` used is `--line-buffered`, and stdout gets no pipeline buffering, so it is usable under a Monitor.
- Heartbeat: one line every `--heartbeat` seconds — `hb <lane> stream_age=<s>s phase=<p>` per watched lane. Clock is injectable via `LEADV2_LANE_WATCH_NOW` / `LEADV2_LANE_WATCH_NOW_BIN` so the heartbeat is testable without sleeping.
- Exit 0 when every watched lane has emitted a `dispatch_terminal task=` line. `--once` does a single pass and exits.
- Read-only w.r.t. journals; the only writes are its own offset files.

## Tests (all hermetic, no network, no real dispatch)

| File | Covers |
|---|---|
| `tests/test-worker-reason-terminal.sh` | forced `no_work` lane (claude stream fixture + codex rollout fixture) journals non-empty `worker_reason`; 120-char clamp; quote/newline sanitisation; empty source → key omitted from journal line |
| `tests/test-prepass-resume-invalidate.sh` | resume after HEAD move regenerates + archives; resume after census-refusal terminal regenerates; same HEAD + sig match still serves cache; pre-existing artifact with no `.head` invalidates exactly once |
| `tests/test-lane-watch-poll.sh` | journal rewritten via `mv` still yields the new terminal line **exactly once**; heartbeat fires on mocked clock; exit-when-all-terminal; non-matching lines never printed |
| `tests/test-broad-status-foreign-lanes.sh` | live lane in a foreign repo + none in own repo → row rendered with repo prefix; single-repo TSV → output byte-identical to baseline; foreign-repo read failure → degraded row, table not zeroed |

All four registered in `tests/run-core-offline.sh`. Suites to run green: `run-core-offline.sh`, plus `test-broad-status-lanes-blind.sh`, `test-broad-status-renderer-truth.sh`, `test-dispatch-silent-arm.sh`, `test-dispatch-outcome-terminal-retry.sh`, `test-dispatch-architect-prepass-*.sh`, `test-dispatch-resume-sentinel.sh`, `test-acceptance-shape.sh`.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| New key in the terminal ledger JSON breaks a reader | All readers are `grep -F` + per-field `sed` (`_dispatch_terminal_last_field`, :137) — key order and unknown keys are irrelevant. Same precedent as `commit`/`deliverable` (:204). |
| Worker text injects shell/JSON into the journal line | Sanitise before use: strip `"` `\` and control chars, collapse whitespace, 120-byte clamp — reuse `json_safe`'s character class. |
| Foreign-repo enumeration slows or hangs the beat | Per-repo read runs with a hard timeout; on timeout the repo yields a `repo_read_error` row and the beat continues. |
| Foreign-repo read mutates another repo's `active.yaml` | The adopt/tombstone/prune paths are gated `_own_repo` — foreign reads are strictly read-only. |
| Prepass invalidation loops (regenerate every resume) | Sidecar `.head` is rewritten at generation, so the second resume at the same HEAD hits cache. Test locks this. |
| Line-count offsets wrong if a journal is edited in place (not appended) | Rotation detection (`lines < seen` → reset). In-place shrink is not a shape this journal produces; documented in the script header. |

## Non-goals (implementer: ignore)

- Review-engine verdict logic, deny-floor, arm ladder, profile selector — untouched.
- Replacing `tail -F` callers elsewhere; the new watcher is additive and opt-in.
- Any new cron/Monitor wiring; the beat stays plugin-owned.
- Changing `founder-status.md` layout beyond the repo prefix + two new fields.
- Migrating existing `architect-prepass.md` artifacts (they invalidate lazily, once).
- Any `docs/leadv2/**` or `docs/handoff/**` content changes.

acceptance:
  - surface: log_line
    observable: "In a lane's docs/leadv2/tasks/dispatch-<sig>/journal.md, the dispatch_terminal line for a no_work stop ends with worker_reason=\"…\" containing the worker's own words (e.g. DELIVERABLE_BLOCKED: census falsified), not just cause=arm_produced_nothing."
    authored_at: 2026-08-25T10:33:16Z
  - surface: file_artifact
    observable: "After a lane worktree's HEAD moves and the lane is resumed, docs/handoff/dispatch-<sig>/ contains an archived architect-prepass.<timestamp>.md alongside a freshly written architect-prepass.md whose first line names the new HEAD sha."
    authored_at: 2026-08-25T10:33:16Z
  - surface: rendered_line
    observable: "With a live lane in ~/Projects/leadv2 and none in persona-engine, docs/leadv2/founder-status.md shows a row for that lane prefixed with its repo slug, with its phase and stream age — instead of ДОСКА ПУСТА."
    authored_at: 2026-08-25T10:33:16Z
  - surface: log_line
    observable: "Running leadv2-lane-watch.sh against a lane journal that is later replaced by an atomic mv prints the new dispatch_terminal line once and only once, and prints a heartbeat line listing each lane's stream age."
    authored_at: 2026-08-25T10:33:16Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-watch.sh, plugins/leadv2/scripts/lib/leadv2-worker-reason.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/leadv2-dispatch-ledger.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/leadv2-lanes-snapshot.sh, plugins/leadv2/scripts/leadv2-broad-status.sh, plugins/leadv2/scripts/tests/test-worker-reason-terminal.sh, plugins/leadv2/scripts/tests/test-prepass-resume-invalidate.sh, plugins/leadv2/scripts/tests/test-lane-watch-poll.sh, plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

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

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-db9a8aa8" "<question>" \
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