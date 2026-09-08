LABEL=critic-dispatch-29eafe96-review-1788894346 SESSION_ID=fd0756c1-8677-463f-9bf6-6ff52eef7bf7
--- body from: docs/handoff/dispatch-29eafe96-review/critic.full.md ---
REVIEW_VERDICT: PASS_WITH_NITS
REVIEW_FINDINGS: critical=0 high=0 medium=1 low=2

# Critic review — dispatch-29eafe96 (E1 Astra design report)

Scope: `docs/handoff/dispatch-29eafe96/review.diff` — one new file, `docs/audits/seamless-account-switching-astra.md` (494 lines, design report, no code). Author: codex. Mission (lane-mission.md) asked for a design-only report in `docs/audits/`; the diff honours that write set (LANE_WRITES includes the astra filename). No production code, no test registration, no state-file writes.

## Method
- Read the full diff.
- Spot-checked every cited source location against the live checkout (`plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py`, `leadv2-claude-profile-select.sh`, `leadv2-quota-read.py`, `lib/leadv2-route-arbiter.sh`, `leadv2-dispatch-code.sh`, `claude-subsession.sh`).
- Checked for secret leakage in embedded raw output (none: fixture token strings are literal placeholders, no registry rows, no real transcript IDs).
- Checked the P3 classifier claim against `git log dbcb984e..HEAD -- leadv2-quota-read.py`.

## Findings

### Medium
**M1 — P3 classifier result for `max` is stale versus current main (review.diff lines 271, 280).**
The report states `classify_account_state max 401 => unknown` and cites `leadv2-quota-read.py:412-435` as "team+401 → unmetered, max+401 → unknown". That was true at the lane base (dbcb984e). Commit 44475674 ("max joins team as unmetered", merged via 39db77c2, after the lane anchored) changed the branch to:
```
if http_code == 401 and subscription_type in ("team", "max"):
    return ACCOUNT_STATE_UNMETERED
```
The report's §3 argument (D1 must not relabel uncertainty as healthy; downstream picker/selector still exclude) survives the change — the picker still ignores `account_state` entirely (verified: `grep account_state lib/leadv2-claude-profile-pick.py` returns no code hits) and the selector still cools an errored account. But the raw P3 line and the "max → unknown" prose will read as a false statement to anyone checking against main. Fix: qualify the P3 classifier output with the lane HEAD it was measured on, or re-run against main and update lines 271/280. Not blocking: the report already hedges ("did not inspect D1's worker or assume its final implementation", §Unchecked #6).

### Low
**L1 — P5 dispatcher line numbers drifted (review.diff lines 312-319, 331).**
`leadv2-dispatch-code.sh:6413` / `6415-6417` / `7721` / case at `6378` are now 6452 / 6454-6456 / 7765 / 6416 on main (135-line diff since lane base). Content claims verified correct: `--requested-profile` parser and forwarding exist; case arm is `sonnet|haiku|opus|fable)`. Report acknowledges "main checkout moved during the audit", but P5 excerpt headers hard-code the numbers without the measured commit. Cosmetic; the flag-spelling correction (`--requested-profile`, not the mission's `--claude-profile`) is the substantive claim and it is right.

**L2 — Fixture root path in P2 raw output (review.diff line 219).**
`fixture_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/...` leaks the operator home path and the codex plugin data directory into a committed doc. Not a secret, but the report elsewhere abbreviates paths deliberately ("Targets above abbreviate the common Projects parent"); consistency would strip it.

## Verified-correct claims (no finding)
- `pick.py:81-104,139-140` — `score_record` returns `unknown_score` unless payload AND account `status == ok`; `scored=[(score_record(r), i, r)]` → `min` on (score, input-order) → first equal wins. Matches P3 "six of six → personal".
- `select.sh:450-478,529-562,580-592` — cooldown skip, error-based cooldown write (any `status != ok` with non-empty `error`, including `http 401`), and `requested_profile_unavailable` rc=3. Matches P3 run 3.
- `arbiter.sh:913,955-977` — `UNKNOWN_PROBE_PENALTY=50.0` still added in `ecost` when `unk[provider]`; the `unmetered` branch only affects `headroom_weight`. Supports the report's "removing the penalty alone is insufficient" argument.
- `claude-subsession.sh:566,590-597` — `export CLAUDE_CONFIG_DIR="$dir"`, `leadv2_select_claude_profile` before `CLAUDE_ARGS` with `--session-id`. Correct.
- Evidence contract: every external-system claim (OAuth continuation, usage-401 premise, refusal codes, `/login` hot swap) is prefixed `UNVERIFIED:` or followed by a probe artifact / doc URL. No untagged decision-driving external claim found.
- Off-limits: profile registry not read, no global settings touched, no real credentials used (P2 env uses a placeholder API key against loopback). Consistent with the mission's constraints.

## Verdict
PASS_WITH_NITS. One stale measurement (M1) should be qualified or refreshed before the report is cited as ground truth for D1 follow-up; nothing in the diff is incorrect in a way that changes the design conclusions.

DELIVERABLE_COMPLETE
