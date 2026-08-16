⚠ claude.ai connectors are disabled because ANTHROPIC_API_KEY or another auth source is set and takes precedence over your claude.ai login · Unset it to load your organization's connectors
"glm-5.2" is not a model this version of Claude Code recognizes, so auto-compact will keep this session within 200k tokens (the context window it assumes). If the model accepts more, append [1m] to the model name for 1M, or set CLAUDE_CODE_MAX_CONTEXT_TOKENS to its real window; to make it recognized, map it in the modelOverrides setting or update Claude Code; CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT=1 restores the previous wait-for-the-API behavior.
[claude-code:unrecognized_model] {"model":"glm-5.2","query_source":"sdk"}
REVIEW_VERDICT: PASS_WITH_NITS
REVIEW_FINDINGS: critical=0 high=0 medium=1 low=5

## What the diff is

FORK-RUNS-A-SESSION-01: lets a fork (context-inheriting Agent spawn) carry a task Phase 0→8. New `leadv2-fork-session.sh` (lead-side preflight/ask/commit/postflight wrapper around existing pieces), new mission prompt, docs updates, a 301-line falsifying test harness, plus a follow-up patch threading `PROJECT_ROOT` through every control-plane call. The outer diff also carries dispatch artifacts (`review.diff`, empty `review-codex.md`, one-line `.err`).

## Verification performed

- Ran the test suite myself in this worktree: **30/30 PASS** (preflight idempotency, kill-switch and shared-root-fallback refusals, ask pending/answered/retry-race/different-question/cancel-pending, commit lane-scoping with main tip untouched, postflight dirty-refuse/clean-reap/no-op).
- Cross-checked every wrapped-script contract the new code relies on:
  - `leadv2-ask.sh:184` — QID is `q-<8 hex>`, matches the `^q-[0-9a-f]{8}$` degrade-refusal regex; `--no-block` exists; the stated-default degrade path is real (line ~317), so the refusal is warranted.
  - `leadv2-lane-worktree.sh` — same `LEADV2_WORKTREE_DIR` env name; `ensure` does fall back to the shared root on git failure (line 151-152), so `assert_isolated_lane`'s path check is the right predicate; `path-of` returns `""` when absent.
  - `leadv2-active-registry.sh:530` — register signature matches the 5-arg call; `_leadv2_state_path_sh` is resolved at call time, so the post-source override in preflight works (and the LEADV2-SYMLINK-CLOBBER rationale is sound).
  - `leadv2-deploy-merge.sh:81` — resolves `worktree-<id>`, so the branch assertion in preflight correctly protects the Phase-6 land step.
  - `leadv2-worktree-cleanup.sh` — accepts `--name <n> [--force]`.

The three headline fixes (H1 refuse-don't-degrade, H2 pending-question persistence with mkdir-lock not held across the poll, H3 `-C <lane-root>` commit with re-asserted isolation) are all genuinely implemented and mutation-tested.

## Findings

FINDING: severity=Medium file=plugins/leadv2/scripts/leadv2-fork-session.sh line=747 dimension=correctness desc=postflight reaps the worktree but never calls leadv2_active_unregister — the active.yaml row preflight wrote survives until the lead's claude PID dies and stale-pid-sweep collects it; every other phase-8 closer (leadv2-phase8-close.sh, fanout, backlog-pump) unregisters, so /leadv2 status shows a ghost task pointing at a deleted lane in the interim

Nits (Low):

1. `cmd_commit --all` sweeps `fork-lane.env` (machine-specific absolute `LANE_ROOT`) into the lane branch; deploy-merge then lands it on main. postflight's `rm -f` runs after the fork's commit, so it only helps the uncommitted case.
2. `fa_read` tab-joins the record; a question containing a tab/newline truncates `rec_q` (display-only — fingerprint comparison is authoritative, so no misrouting).
3. Stale-lock break: `rm -rf "$lock_dir" && mkdir "$lock_dir"` — if the re-mkdir loses a race, `set -e` exits silently with no diagnostic and no lock held.
4. `--paths` parsing stops at any `--*` token, so a path beginning with `--` is unpassable.
5. `assert_isolated_lane` header says "Four conjunctive checks" but the function holds three (kill-switch is check 1, done in preflight) — cosmetic comment drift.

Docs (`leadv2.md` phase table, `phases.md`, mission prompt) honestly state the residual (bare `git` banned by mission text, not by hook) and match the code as written.

---

FINISH CONTRACT report:
- Files changed by me: none. No stash created. Review-only session.
- Test results: `test-fork-session.sh` → 30 passed, 0 failed (run directly in this worktree).
- Commit: NOT-COMMITTED — this was a read-only review of /tmp/fork.diff; the diff under review is the author's staged/unstaged work and is theirs to land.
