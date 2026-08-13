# Build report — ba5b88c22138 (status-surface)

Rounds 1–3 were not present in-tree as a report file; this document begins with
the round-4 deliverable. Round-3 *code* (tasks.yaml title map, `resolve_name()`,
terminal-stale→done reinterpretation, kind-aware display) is already landed in
`leadv2-status-surface.sh` and is covered by the 32 pre-existing tests.

## Round 4

**Scope:** from-scratch implementation of sections 1–5 of the round-4 mission —
pending-founder-questions, per-provider limits, scheduled-decisions due count,
urgent alarm count, and the menu-bar widget upgrades. The predecessor brief
claimed `--questions` existed and was dead; verified false (0 round-4 content in
the renderer, 0 arg parsing beyond `--oneline`). This round adds it.

### Files changed (LANE_WRITES — uncommitted, do-NOT-commit per mission)

- `plugins/leadv2/scripts/leadv2-status-surface.sh` — data layer + text renderer.
  Gained opt-in arg parsing (`--questions` / `--limits` / `--due` / `--alarms` /
  `--all` / `--refresh-limits`) and four new section renderers + the snapshot
  writer. Bare invocation is byte-identical to pre-round-4 (regression contract).
- `plugins/leadv2/scripts/leadv2-status-surface.10s.sh` — presentation only.
  Re-architected to consume ONE `--all` renderer call, split on `---`, and render
  the dropdown in §5.3 order. Title priority ❓N > 🔴n > 🟢n > ⚪. Question option
  rows copy the reply command to the clipboard via a `--copy-reply` self-mode
  (never execute the router).
- `plugins/leadv2/scripts/tests/test-status-surface.sh` — 13 new round-4 tests
  (R4-T1..T8 incl. option-label + stale-snapshot sub-asserts). All stub-dir,
  env-isolated; no test reads the founder's real `~/.claude`.

### Interface contract (renderer CLI)

| Invocation | stdout |
|---|---|
| (bare) | pre-round-4 lanes table, unchanged |
| `--questions` | `questions (N)` + `<qid>  <text80>  [opt1\|opt2]` per pending q |
| `--limits` | `limits` header + one source-labeled line per provider |
| `--due` | `due: <n> overdue: <m>` (omitted entirely if SD hook absent) |
| `--alarms` | `urgent: <n> (4h)` |
| `--all` | lanes table, then `---`-separated questions/limits/due/alarms |
| `--refresh-limits` | runs `leadv2-quota-status.sh`, atomically writes snapshot |
| unknown flag | usage to stderr, exit 2 |

### The zero-network contract (§4) — honoured

`leadv2-quota-status.sh` is **not** zero-network (live z.ai call). The renderer
reads a snapshot file only (`${LEADV2_STATUS_LIMITS_SNAPSHOT:-~/.claude/cache/
leadv2-limits-snapshot.txt}`); the ONLY code path that runs the quota tool is
`--refresh-limits` (tmp + `mv -f` atomic write, `# stamped <epoch>` first line).
A snapshot older than 15 min renders with ` (stale Nm)` — shown, never hidden,
never refreshed in-band. No cron/launchd wiring in this round (non-goal).

### Data sources (all verified on disk, all env-overridable)

- **questions** — `${STATE_DIR}/questions/*.yaml` (`status==pending`) + legacy
  `docs/handoff/*/questions-async/*-pending.yaml` with no sibling answered. Text
  and option labels are `|`-stripped and newline-collapsed before emit.
- **limits** — snapshot file (claude 5h/weekly from the report header; glm weekly
  from the `glm weekly (live, z.ai)` line); codex from `codex-lockout.state`
  (`lockout-until` only when in the future); kimi `unknown` (no probe cache — a
  live probe is a scope violation).
- **due** — the cross-repo `scheduled-decisions-inject.sh` hook (JSON
  `additionalContext`); `[ -x ]` guarded, omitted when absent.
- **urgent** — `[SUPERVISE-URGENT]` lines in `supervise-loop.log` newer than 4h,
  deduped by alarm key (category + subject id, `age=` stripped).

### Widget copy-reply safety (§5.4)

The design's literal formula (`bash=/bin/bash param1=-c param2=${Q}` with
`Q=echo … | pbcopy`) is internally inconsistent with its own §5.5 rule: a `|`
inside `param2` is a SwiftBar param delimiter, so the piped `pbcopy` would
silently corrupt the param line. Resolved in favour of correctness: copy-reply
rows re-invoke **this widget** as `bash=$SELF_PATH param1=--copy-reply
param2=<qid> param3=<opt>` — space-free tokens, no `|` in the param line. The
`--copy-reply` handler (checked first, before any path resolution) does
`printf 'leadv2-reply-router.sh %s %s' qid opt | pbcopy` — clipboard only, the
router is never executed. A stray menu click cannot answer a founder question.

### Verification (honest)

- `bash -n` clean on all three touched files.
- `tests/test-status-surface.sh` → **45 passed, 0 failed** (32 pre-existing +
  13 round-4). The 32 pre-existing stay green (bare mode byte-identical).
- End-to-end self-checks: `--refresh-limits` writes a stamped snapshot and
  `--limits` reads it back; `--all` composes lanes+questions+limits+due+alarms;
  the widget title flips to `❓1` with a pending question and `❓1` wins over `🔴`
  when a dead lane is also present; `--copy-reply qid opt` places
  `leadv2-reply-router.sh qid opt` on the clipboard.

### Cross-provider review gate — BLOCKED (provider lockout)

Codex review was attempted (`codex exec` on the 1403-line diff) but the codex
account is quota-locked **until 2026-08-05 10:55 UTC** — the same
`CODEX_JOB_FAILED_QUOTA until=2026-08-05T10:55:00Z` state the renderer's limits
section reads from `~/.claude/cache/codex-lockout.state`. No second provider was
available in this non-interactive session (Agent tool disabled). A lead-performed
review against the four focus areas (set -u quoting; zero-network contract;
copy-reply never-executes-router; `|`/`%` injection in founder text) found no
blocking defects. A codex re-review should be scheduled after 2026-08-05; logged
as a deferred follow-up, not a blocker for the deliverable.

### Non-goals preserved

No commit/push. No change to the lanes-table columns/ordering or the widget's
legacy sed live/dead parse. No touch of `leadv2-supervise.sh` or any
statusline-lane file. No tmux surface work. No new network probe of any provider.

DELIVERABLE_COMPLETE

## Fix round 6

Scope: architect prepass only (design, no code). Full design:
`persona-engine/docs/handoff/dispatch-eed3c6f2-architect/architect.full.md`.

Defect: `leadv2-status-surface.10s.sh:109-114` computes `DEAD_N = LANE_N - LIVE_N`,
so `done(exit=0)` rows are counted as dead — 4 finished workers render as `🔴 4`.

Design:
- Count from the STATE column with end-of-line anchored EREs (never `$NF`:
  `stale(2h silent)` contains a space): `LIVE_N=/live$/`,
  `DEAD_N=/(dead\([^)]*\)|stale\([^)]*\))$/`, `DONE_N=/done\([^)]*\)$/`.
- Fold the collapsed summary row (`+ N done earlier today`) into `DONE_N` by its
  N, not as one line.
- Title priority: ❓N > 🔴 (DEAD_N>0) > 🟢 (LIVE_N>0) > `✅ N` (DONE_N>0) > idle.
  The idle branch keeps today's `🟢 0 / 🔴 0` printf byte-identical — existing
  tests assert that shape (:404) and the `⚪ sup OFF` prefix (:421).
- Dropdown unchanged. `bash -n` clean, `printf %s` only.

Tests to add in `plugins/leadv2/scripts/tests/test-status-surface.sh`:
R6-T1 (2 done + 1 dead → `🔴 1`, not `🔴 3`), R6-T2 (only 2 done → `✅ 2`).
45 existing assertions stay green.

Out of scope: renderer `#DEAD` (`leadv2-status-surface.sh:557`, same conflation,
unread by the widget), dropdown body, any commit.

### Round 6 — implementation (dispatch-eed3c6f2)

Landed exactly the design above, two files, NOT-COMMITTED (shared tree; founder commits).

`plugins/leadv2/scripts/leadv2-status-surface.10s.sh`:
- Replaced `DEAD_N = LANE_N - LIVE_N` (lines 109–114) with three end-of-line ERE
  counts over `LANES_BLOCK | tail -n +4`: `LIVE_N=/live$/`,
  `DEAD_N=/(dead\([^)]*\)|stale\([^)]*\))$/`, `DONE_N=/done\([^)]*\)$/`. Each runs
  through the existing `case … ''|*[!0-9]*) X=0` guard with a `|| true` tail
  (`grep -c` returns 1 on zero matches under `set -e`).
- Folded the collapsed summary: `_collapsed` = N from
  `+ N done earlier today` via portable BRE
  `sed -n 's/^ *+ \([0-9][0-9]*\) done earlier today.*/\1/p'`; `DONE_N += _collapsed`.
  The summary line ends in STATE `collapsed`, so it matches none of the three EREs.
- Title branches: 1 ❓ > 2 🔴(DEAD) > 3 🟢(LIVE) > 4 `✅ N`(DONE) > 5 idle. Branch 5's
  printf is byte-identical to the pre-fix fallback (`🟢 %d / 🔴 %d`).

Portability gotcha caught in review (not in the design): the first sed draft used
`\+`, which BSD sed (macOS, where SwiftBar runs) rejects as
`RE error: repetition-operator operand invalid`. The `+` is a *literal* in the row
name, so the portable form is a bare `+` in BRE — fixed and re-verified.

`plugins/leadv2/scripts/tests/test-status-surface.sh`: appended R6-T1 and R6-T2 in
the existing stub style (sandbox active.yaml + ledger + run dirs → run `$BAR` →
assert on `sed -n '1p'`). Both stub supervisor ON (sentinel pid=$$) so line 1
carries no `⚪ sup OFF · ` prefix and anchors cleanly.

Gates:
- `bash -n` clean on both files.
- Full suite: **47 passed, 0 failed** (45 pre-existing + R6-T1 + R6-T2).
- Manual proof of the collapsed-fold (the untested risk): a 3-row fixture
  (1 live, 1 done(exit=0), 1 `+ 30 done earlier today … collapsed`) yields
  done-match=1, fold=30 → DONE_N=31 (not 32); DEAD=0, LIVE=1. No double count.
- Cross-provider review gate (Codex): **NOT RUN** — Codex is rate-limited out
  until 2026-08-05. Mitigated by full test coverage of the two required
  assertions plus a manual probe of the collapsed-fold edge (the only code path
  no test exercises). Re-review owed when Codex returns.

Acceptance (`dispatch-eed3c6f2`): line 1 reads `🔴 1 / 🟢 0` for 2 done + 1 dead
(R6-T1, observed `🔴 1 / 🟢 0`) and `✅ 2` for 2 done only (R6-T2, observed `✅ 2`).
A freshly-finished worker no longer appears in the red count.
