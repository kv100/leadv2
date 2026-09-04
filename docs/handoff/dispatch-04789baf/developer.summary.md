verdict: REVISE
next_action: continue

Item 1 (ENV-GUARDS nits) complete, tested, committed on lane branch worktree-04789baf; items 2-4 not started (turn-cap).

- 1-A/1-B closed in leadv2-backlog-pump.sh (commit dc6f99d): explicit non-empty check before the canonical-root cd chain (zsh-proof); 1-B confirmed obsolete (pump-caller deleted by RESIDUE-SWEEP).
- 2-A/2-B/2-C closed in leadv2-dispatch-code.sh (commit f387f4d): codex rollout scoped by cwd preference + ambiguity journal, early-return on live non-terminal activity, real lockout-file assertion replacing the /bin/true stub.
- test-pump-junk-in-lane.sh pass=2/0; test-codex-instant-complete.sh pass=7/0 (was 5/0). shellcheck -S warning: no new findings on either file.

Full: developer.full.md
