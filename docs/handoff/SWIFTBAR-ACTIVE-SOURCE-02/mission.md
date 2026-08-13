# SWIFTBAR-ACTIVE-SOURCE-02 — widget active-source from live process census + reservations

Repo: ~/Projects/leadv2 (canonical plugin). Live evidence 2026-08-03 (multiple supervision ticks):
- Widget showed "⚪ idle" while a sonnet build worker (claude-subsession.sh) ran 10+ min; later showed "🛠 73a5652e sonnet 62m" for a worker that had exited ~40 min earlier.
- Current active-source in leadv2-status-collector/surface reads the dispatch ledger, which post-1674dde is TERMINAL-only plus reservation rows — it can't see live workers that predate a terminal, and shows sig8 instead of the human task_id.

REQUIREMENTS:
1. Active lanes = union of (a) live process census: pgrep patterns for claude-subsession.sh (sonnet workers — extract --task-id), codex-companion task-worker, glm-coder.sh __run_child, kimi-coder.sh child, plus direct `codex exec` processes whose cwd or args reference .claude/worktrees/<id>; and (b) unexpired reservation rows (state pending|confirmed, TTL) from the reservation ledger. A lane in either set with NO terminal row = active.
2. Display: prefer human task_id (from reservation row / --task-id arg / worktree name) over sig8; show ALL live workers (multi-line dropdown; menubar title shows count + newest, e.g. "🛠 2: FEED-SCAN sonnet 12m"), each with arm + age. A worker process with terminal already written = show "closing" state, not active (post-1674dde this should be rare).
3. "idle" only when both sets are empty. Keep the existing single-lead blocks (mode/repo facts/SD-due/limits) untouched.
4. Process census must be cheap (<200ms; single ps -Ao pid,args pass, no per-lane subprocesses) — this runs every 10s in the .10s.sh surface. Cache expensive parts if needed (limits already cached).
5. Tests: extend tests/test-status-surface-single-lead.sh (or new fixture suite) with stubbed ps output + stub ledgers: (a) live claude-subsession + no terminal → active with task_id; (b) worker gone + terminal → idle; (c) two live workers different arms → count 2, both listed; (d) terminal row present + process still alive → "closing"; (e) empty everything → idle. Register in run-core-offline.sh if not already.

Touched files expected: plugins/leadv2/scripts/leadv2-status-collector.sh (or surface/render as appropriate), tests. Read the current implementation first; keep the render contract stable for SwiftBar.

ACCEPTANCE: bash -n; focused suite green; run-core-offline green vs baseline (current main: 24 suites after codex-lead merge — verify count first); live probe: run leadv2-status-surface.10s.sh with a real claude-subsession stub running → shows it active. Do NOT commit.
NON-GOALS: no dispatch-pipeline changes, no ledger schema changes, no supervisor blocks.
Rollback: git checkout of touched files.
