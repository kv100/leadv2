T14 FIX-ROUND (review verdict BLOCK, findings verbatim below). Base branch: t14-worker-mcp (79c25d5). Fix ALL of F1-F3, plus F4/F5 cheaply. Suite tests/test-t14-worker-mcp.sh must stay green and gain regression coverage for each fix; run it and show output.

F1 [HIGH] lib never propagated: persona-engine/.claude/scripts/lib/ is a REAL dir with per-file symlinks; glm-coder.sh:108 resolves WORKER_MCP_LIB relative to the INVOKING symlink dir, so on persona-engine the lib is missing and every worker journals worker_mcp_skipped reason=lib_missing. Fix: (a) in glm-coder.sh, fall back to resolving the lib via the canonical repo (readlink -f of BASH_SOURCE before dirname) so a symlinked caller still finds it; (b) add to the T14 suite an assertion that resolution works when glm-coder.sh is invoked VIA A SYMLINK from a foreign dir (simulate persona-engine layout in a tmpdir).
NOTE: ~/.claude/leadv2-shared/scripts/lib/leadv2-worker-mcp.sh symlink already healed by LINK-TREE-HEAL; your job is the code-level resolution so the class of bug dies.

F2 [MEDIUM] glm-coder.sh:325 run_claude() leaks mktemp -d /tmp/glm-worker-mcp.XXXXXX per synchronous spawn. Fix: trap rm -rf on RETURN/EXIT or reuse out_file dir. Add a test that the dir is gone after run.

F3 [MEDIUM] role mapping incomplete: only developer(default)+critic set LEADV2_WORKER_ROLE; other callers (leadv2-dispatch-product-close.sh, leadv2-glm-session-runner.sh, architect/PO/strategist flavors) silently get developer allowlist though config/mcp-role-architect.json exists. Fix: set LEADV2_WORKER_ROLE at each caller you can identify (grep for glm-coder.sh invocations); unknown roles keep fail-open developer default.

F4 [LOW] test T14-03: assert full argv against a captured pre-T14 baseline, not just absence of --strict-mcp-config.
F5 [LOW] one-line doc note in the lib header: LEADV2_SUBSESSION_SLIM_MCP and LEADV2_WORKER_MCP are intentionally separate switches (disjoint spawn paths, one resolver).

Constraints: no behavior change beyond the findings; bash -n on every touched script; commit on the lane branch with clear message.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-6d02253f" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.