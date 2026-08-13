# CODEX-QUOTA-GUARDRAILS-01 — fix round 1 (critic r1 BLOCK: 2 CRITICAL, 1 HIGH, 3 MEDIUM)

Work IN THIS WORKTREE ONLY (~/Projects/leadv2/.claude/worktrees/28e75319 — the full round-1 diff is already here uncommitted). Do NOT touch the main checkout. Read the original mission docs/handoff/CODEX-QUOTA-GUARDRAILS-01/mission.md (main checkout copy) for context.

FIX EXACTLY THESE, nothing else:

C1 (CRITICAL): plugins/leadv2/scripts/leadv2-codex-session-runner.sh retry loop (~lines 493-570) never DETECTS a usage-limit refusal and never OPENS the circuit it consults — up to 6 full codex exec attempts burn against the wall. Fix: after `rc=$?` (line ~511), grep the log growth in "$LOGF" for the same usage-limit signature codex-task.sh:413 uses (hit your usage limit|usage limit reached|rate limit exceeded); on match, extract the "try again at ..." horizon via codex_circuit_parse_until() from lib/leadv2-codex-circuit.sh (currently dead code — this wires it, closing M6 too) and call codex_circuit_open "<until>" "session-runner" BEFORE the next retry/break, then stop retrying (a wall doesn't yield to retries).

C2 (CRITICAL): zero test coverage for session-runner's gate integration (RUNNER_SH declared at test-codex-quota-guardrails.sh:14, never used). Add a Group F: (f1) pre-opened circuit file → session-runner exits 2 WITHOUT invoking the stubbed codex binary; (f2) stubbed codex binary emitting the usage-limit line → assert circuit marker file appears with parsed horizon + journal line codex_circuit_open fired (same assertion pattern as c3/c5); (f3) fail-closed branch: codex_spawn_gate unavailable → exit 2.

H3 (HIGH): LEADV2_CODEX_SANCTIONED escape hatch in hooks/leadv2-codex-direct-exec-guard.sh is set by NO caller and is structurally unreachable (hook processes never see a sibling subprocess's exports). REMOVE the env-var path and its misleading comment entirely; the name-substring allowlist stays as the only runner-recognition mechanism. Update/remove test d2 accordingly (it manufactured false confidence). Keep LEADV2_ALLOW_DIRECT_CODEX (that one IS reachable — a human exports it in their shell before running a command).

M4: _codex_quota_gate() in codex-task.sh duplicates the case-dispatch of lib/leadv2-codex-quota-gate.sh's codex_spawn_gate. Make codex-task.sh call codex_spawn_gate (exit "$?" on refusal) instead of the hand-copied block.

M5: test c2 never exercises the real unparseable-text path (the printf pipe is decorative — codex_circuit_open doesn't read stdin). Replace with a fixture-log test driving the real watcher path (or, minimally, codex_circuit_parse_until on garbage → empty → open defaults to 24h) so the 24h default is proven through real code.

LOW (only if trivial): drop unused `sub` capture in codex_spawn_gate or use it; keep everything else as-is.

CONSTRAINTS: no changes outside the 9 round-1 files (+ the new Group F test content); preserve exec bit on hooks/leadv2-codex-direct-exec-guard.sh (chmod +x, commit-safe); do NOT write into ~/.claude/plugins cache; do NOT commit.
ACCEPTANCE: bash -n (bash5 + 3.2) on all touched; test-codex-quota-guardrails.sh green (report new count); run-core-offline.sh green vs THIS worktree baseline (30). Report per-finding status.
