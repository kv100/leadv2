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
