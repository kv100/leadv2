REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=1 high=0 medium=4 low=4

# Critic review — dispatch-157a7898 (round 1)

Artifact reviewed: `docs/handoff/dispatch-157a7898/review.diff` (808 lines, 38179 bytes, mtime 2026-09-08 18:42). Declared base: a138edd0. Reviewer independent of author (codex).

## Verdict basis

The review artifact does not contain the lane's change. It cannot be applied to the declared base, every hunk in it is already in main, and its content is the *opposite* of what the lane mission and the developer summary describe. The lane's real diff is therefore unreviewed, and I cannot certify it. FAIL on a single Critical finding; the Medium/Low findings below are on the bytes that *are* in the artifact and are recorded so round 2 does not lose them.

## Critical

### C1 — review.diff is not the lane's diff; the gate has nothing to certify

Evidence:

1. Patch does not apply to the declared base:
   ```
   $ git apply --check docs/handoff/dispatch-157a7898/review.diff   # at a138edd0
   error: patch failed: plugins/leadv2/scripts/codex-task.sh:1
   error: plugins/leadv2/scripts/lib/leadv2-launch-registry.py: already exists in working directory
   ```
2. Every hunk is already merged into main. `git log -S` dating of each hunk lands on commits between 2026-09-05 and 2026-09-07: 425e0e65 (TMPDIR pin), 8913e3e8 (shebang), a0cff94c (state roots, `worker_died_stale_cause_unknown`), 9ae5e24e (worker-owned app-server preload), a91410d5 / 383224cb (astra tier collapse, `gpt-6*` fallback net), 6e279c1e (launch registry + `tests/test-launch-registry-argv.sh`). `plugins/leadv2/scripts/codex-task.sh` is unmodified in the working tree and already contains `_codex_durable_tmpdir` (:84), `_codex_state_environment` (:122), `_APP_SERVER_PROBE["alive"] = None` (:935), `disableBroker: true` (:1965), and 12 occurrences of `gpt-6-astra`.
3. The artifact contradicts the lane's own documents. `lane-mission.md` head: "CODEX-TIERS-COLLAPSED-ONTO-ASTRA-SOL-LUNA-TERRA-UNREACHABLE-01, PART A — make sol / luna / terra launchable as themselves". `developer.summary.md` claims: "Un-collapsed the codex tier table to sol/terra/luna … registry gained `CODEX_MODEL_TIER_TUPLES` … `--effort` flows independently of `--tier` for kind=="code" … New offline suite, 17/17 green". The diff under review does the reverse: it *collapses* both tier tables onto `gpt-6-astra`, and its registry has no `CODEX_MODEL_TIER_TUPLES` and `_argv_codex` drops effort entirely.
4. The claimed work exists nowhere I can reach. `grep -c CODEX_MODEL_TIER_TUPLES plugins/leadv2/scripts/lib/leadv2-launch-registry.py` → 0. `git branch -a | grep 157a7898` → empty. `git worktree list | grep 157a7898` → empty. `git stash list | grep 157a7898` → empty. On-disk registry suite is 13/13 (`tests/test-launch-registry-argv.sh`: PASS=13 FAIL=0), not 17/17. Last commits to codex-task.sh on main are adbaaabe, c7392b7b, 9ae5e24e, a0cff94c, 8913e3e8, 425e0e65 — none is the sol/luna/terra un-collapse.

Consequence: any PASS issued against this artifact would certify code that was merged two days ago under other lanes, while the sol/luna/terra change ships unreviewed. Round 2 must regenerate `review.diff` from the lane branch against a138edd0 (`git diff a138edd0..<lane-head>`), and the developer summary's "17/17 green" and "live-verified 3 tiers reached completed" claims need the lane branch or probe artifacts attached — as of now both are UNVERIFIED.

## Medium (on the bytes present in the artifact; all already in main)

### M1 — dead identical conditional in the top tier, with a stale comment
Both branches of the `top)` case in `_tier_model_effort()` assign `TIER_MODEL="gpt-6-astra"; TIER_EFFORT="high"`; the `jq -e '.models[]? | select(.slug=="gpt-6-astra")' "$MODELS_CACHE"` probe is evaluated and discarded. The else-branch comment still says "lean: sol is gov-gated", which describes a ladder that no longer exists. Per the developer summary this is exactly the region the real lane rewrites, so it must be confirmed gone in round 2. Related: header comment `codex-task.sh:16-19` still documents "top -> gpt-5.6-sol/high, falls back to gpt-5.6-terra/xhigh" and "volume -> gpt-5.6-luna/low" — the file lies about itself in whichever direction the tier table finally lands.

### M2 — `once(2)` retries a non-idempotent turn against a partially modified tree
The worker-exit race in `_codex_worker_owned_app_server()` retries the whole turn exactly once when the app-server exits before `turn/completed` (cause `codex_worker_exited_before_turn_completed`). A codex turn writes to the worktree; the first attempt may have applied part of its edits before the process died. The retry re-runs the same prompt on top of those partial writes, with no snapshot/reset and no journal line distinguishing "attempt 1 wrote N files" from a clean run. Acceptable only if the caller treats the turn as best-effort; nothing in the diff says so.

### M3 — preload mode detection reads `process.argv[2]` positionally
The `--import` data: URL decides review vs. turn mode from `process.argv[2]`, matching `codex-companion.mjs:982` (`const [subcommand, ...argv] = process.argv.slice(2)`) as of 1.0.4. If a future companion accepts global flags before the subcommand, the facade silently installs nothing and the broker is re-enabled with no error. Fail-open on a version-coupled assumption; a `process.stderr.write` + non-zero exit when no mode matches would make the coupling visible.

### M4 — four unrelated concerns in one diff
TMPDIR durability, state-root alignment + reaper cause attribution, worker-owned app-server preload, tier collapse, and a new 375-line launch registry are bundled together. Each has its own failure mode and its own test surface; a revert of any one drags the others. This is a process finding, and moot once C1 is fixed, but the round-2 artifact should be a single-concern diff.

## Low

### L1 — `_argv_codex` discards `effort`
`def _argv_codex(role, model, tier, effort)` returns `["--tier", tier]` (+ `--reason` for top) and `effort_supported=False`. `EFFORT_BY_KIND_AND_CLASS` is computed and thrown away for codex. Developer summary says the real lane fixes this; unverifiable here.

### L2 — `_canonical_model` returns the first codex row
With three codex rows in `leadv2-routing.yaml` (:213-218) all currently `gpt-6-astra` this is harmless; the moment the tiers diverge (the lane's stated goal) `check(arm="codex", model=...)` will refuse two of three legitimate tier models.

### L3 — `LEADV2_CODEX_EVENT_BIN` exported globally while `NODE_OPTIONS` is `local`
Inside `_run_node` the preload's journaling env var leaks into every subsequent child of the shell, unlike `NODE_OPTIONS` which is correctly scoped. Cosmetic today; a later subprocess that honours the same variable would journal to the wrong sink.

### L4 — preload fails closed if `module.registerHooks` is absent
Node 26.7.0 (verified locally) has it; older Node would abort the turn rather than degrade to broker mode. Fine as a hard floor, but the failure text should name the Node version requirement.

## Verified against companion 1.0.4 source (no finding)
`lib/app-server.mjs`: `static async connect(cwd, options = {})` :332, `if (!options.disableBroker)` :334, `this.exitPromise` :70, `close()` :228/:308, `spawn("codex", ["app-server"])` :189. `lib/state.mjs`: `PLUGIN_DATA_ENV = "CLAUDE_PLUGIN_DATA"` :9, `path.join(pluginDataDir, "state")` :42 (so the `/state` suffix refusal in `_codex_state_environment` matches the companion's layout). `lib/codex.mjs` exports `runAppServerReview` :908 / `runAppServerTurn` :964; `lib/tracked-jobs.mjs` `runTrackedJob` :142. All API names the preload monkeypatches exist. Registry CLI probes: `codex/heavy → {"tier":"standard","argv":["--tier","standard"],"effort_supported":false}`; `--check --arm codex --model gpt-6-astra → ok`; `--check --arm fable --model sonnet → refuse rc=1`; `fable/code → not_a_build_arm`.

## UNVERIFIED (no probe artifact in the handoff)
- UNVERIFIED: the "14 of 360 broker records in /tmp/claude-503/cxc-*" measurement cited in the TMPDIR hunk's comment.
- UNVERIFIED: "npm-only install cannot run the standalone daemon" — `~/.codex/packages/standalone/current/codex` is indeed absent locally, which only shows the tri-state probe returns None here, not that the claim about npm installs is true.
- UNVERIFIED: developer summary's "17/17 green" and "live-verified 3 tiers reached completed at 19:59:49Z" — no suite, branch, or log attached.

## Required for round 2
1. Regenerate `review.diff` from the lane head against a138edd0; confirm `git apply --check` passes.
2. Attach the 17-case suite and the live tier-reach log (or mark them UNVERIFIED in the summary).
3. Confirm M1's dead conditional and the stale header comment (:16-19) are gone in the un-collapsed table; confirm L1/L2 are resolved by `CODEX_MODEL_TIER_TUPLES`.

DELIVERABLE_COMPLETE
