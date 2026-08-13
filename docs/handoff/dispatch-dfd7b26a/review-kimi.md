⚠ claude.ai connectors are disabled because ANTHROPIC_API_KEY or another auth source is set and takes precedence over your claude.ai login · Unset it to load your organization's connectors
"moonshotai/kimi-k3-free" is not a model this version of Claude Code recognizes, so auto-compact will keep this session within 200k tokens (the context window it assumes). If the model accepts more, append [1m] to the model name for 1M, or set CLAUDE_CODE_MAX_CONTEXT_TOKENS to its real window; to make it recognized, map it in the modelOverrides setting or update Claude Code; CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT=1 restores the previous wait-for-the-API behavior.
Diff is 61 lines — reviewed in full.

**Checks performed:**

1. **Python `_descendants` walk (lines 22-31):** PID-tree parent relations are acyclic, so no visited-set needed. `pgrep -P` output is numeric-only, `int(x)` safe. Children are collected depth-first and killed leaf-first, then the launcher last — correct order. `pgrep` bounded by `timeout=5`, exceptions degrade to `[]`.

2. **Signal/import availability:** `signal` and `subprocess` must already be imported (pre-existing code used `os.killpg(..., signal.SIGKILL)` and `subprocess.TimeoutExpired`) — consistent.

3. **Error handling gap (Medium):** the per-PID kill at lines 33-34 catches only `ProcessLookupError`. A descendant owned by a different UID (e.g. a helper started via sudo/launchd) raises `PermissionError`, which escapes the `except subprocess.TimeoutExpired` handler entirely — skipping the `killpg` backstop AND the `proc.communicate()` reaper below it. Rare in practice (same-user descendants), but it inverts the intended "killpg stays as a backstop"语义. Fix: `except (ProcessLookupError, PermissionError):` or `except OSError:`.

4. **Walk-then-kill race (Low, inherent):** children spawned between the `pgrep` snapshot and the kill loop are missed; killpg covers only same-group ones. Acceptable as a best-effort cleanup on top of the backstop.

5. **Reparented orphans:** `setsid()` movers keep their PPID until the launcher dies, and the walk runs before the launcher is killed — so pgrep finds them. Correct.

6. **Bash loop (lines 46-59):** `while :;` is bounded — `_pp_wait_tries` increments before the guard, so worst case is 10 × 0.2s = 2s, then the `|| break` fires. `rc` is already in scope (used on line 61 pre-change). rc=0 short-circuits immediately, matching the comment. `sleep 0.2` fractional — fine on both GNU and BSD sleep. Intent matches the ARTIFACT-LAND-AFTER-READ-01 comment.

7. **Heredoc apostrophe quirk:** the new Python comments avoid apostrophes ("launcher own", "--"), consistent with the stated bash `$(...)` + `<<'PY'` parsing quirk. Good.

REVIEW_VERDICT: PASS_WITH_NITS
REVIEW_FINDINGS: critical=0 high=0 medium=1 low=1

- **Medium** `plugins/leadv2/scripts/leadv2-dispatch-code.sh:33` — `os.kill(pid, signal.SIGKILL)` catches only `ProcessLookupError`; a `PermissionError` from a foreign-UID descendant escapes the TimeoutExpired handler, skipping the killpg backstop and the `communicate()` reaper. Catch `OSError` (or add `PermissionError`).
- **Low** — pgrep snapshot/kill race: descendants forked after the walk but before the kills are only caught if still in the launcher's process group. Inherent to snapshot-based tree-kill; noted, not blocking.

Orphan-kill logic, kill ordering, termination-bound of the poll loop, and rc semantics are all correct.

NOT-COMMITTED — reviewer role, read-only; no stash created, no files changed, no tests applicable to a review-only pass.
