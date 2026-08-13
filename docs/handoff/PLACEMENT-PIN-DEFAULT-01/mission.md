# PLACEMENT-PIN-DEFAULT-01 — WORKTREE PIN prompt line on EVERY dispatch, not only flagged ones

Repo: ~/Projects/leadv2 (canonical plugin). Four placement-drift reproductions on Aug 3-4: workers whose run cwd WAS their lane worktree still wrote their diffs into the MAIN checkout because mission text mentioned "Repo: ~/Projects/leadv2" (QUESTION-DELIVERY 99324dc5, CODEX-QUOTA-GUARDRAILS 28e75319 — both drifted; cluster-M's M-8 fix round; the morning codex lane). LANE-PLACEMENT-NOT-ADDRESSABLE-01 (shipped 21bbdeb) added a "WORKTREE PIN:" line to the worker prompt — but ONLY when --resume-lane/--worktree flags are used. The DEFAULT path (fresh ensure-created worktree) has no pin line, and that is where all four drifts happened.

REQUIREMENTS:
1. leadv2-dispatch-code.sh: emit the same one-line prompt prefix on the DEFAULT (ensure-created worktree) path whenever WORK_ROOT != PROJECT_ROOT: "WORKTREE PIN: all edits go in <WORK_ROOT>; do NOT cd to the main checkout even if the mission text names it." Reuse the exact existing pin-line construction from the flagged path (one implementation, both call sites — factor if needed).
2. When WORK_ROOT == PROJECT_ROOT (shared-tree dispatch, no lane worktree), no pin line (unchanged).
3. NON-GOALS: no changes to --resume-lane/--worktree behavior (just shipped), no changes to lane-worktree ensure semantics, no product-close changes, no changes to any file except leadv2-dispatch-code.sh + tests.
4. TESTS: extend tests/test-lane-placement-pin.sh: (a) default no-flag dispatch with a lane worktree → pin line present in worker prompt naming the ensure-created tree (stub launcher records prompt); (b) WORK_ROOT==PROJECT_ROOT dispatch → no pin line (regression); (c) flagged paths still pin (regression — existing cases keep passing).

ACCEPTANCE: bash -n (bash5 + /bin/bash 3.2); test-lane-placement-pin.sh green (report count); run-core-offline.sh green vs current-main baseline (32 as of 9158921). Do NOT commit.
Rollback: git checkout of touched files.
