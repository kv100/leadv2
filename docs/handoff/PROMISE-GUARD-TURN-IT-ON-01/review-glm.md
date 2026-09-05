REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=1 medium=4 low=3

FINDING: severity=High file=docs/leadv2/scheduled-decisions.md line=59 dimension=product-invariant desc=ROLLBACK section still says "unset LEADV2_PROMISE_GUARD_BLOCK" reverts to log-only, but this diff changes the hook default to 1 — unsetting is now a no-op and the guard stays blocking

---

(Aside, pulse relay: BROAD_STATUS ready-line `at=2026-09-01T21:12:06Z` ≠ founder-status.md line-1 stamp `2026-09-01T21:14:31Z` — file is from a later beat than the relay's; publishing the mismatch, not the file.)

# Review: build-attempt-4.diff (904 lines, 7 files)

Reviewed the diff at the main checkout path (it is absent from this worktree: `docs/handoff/PROMISE-GUARD-TURN-IT-ON-01/` here contains attempts 1–3 only; found via `find /Users/kostiantyn.vlasenko/Projects/leadv2 -name build-attempt-4.diff`, md5 f81f38cc3756d48d7e267124ac58f0fb).

## High

**H1 — Rollback instruction is now wrong on a default-blocking guard** (`docs/leadv2/scheduled-decisions.md`, ROLLBACK paragraph, left as context in the diff at diff-lines 224–225). The diff changes the hook default to `${LEADV2_PROMISE_GUARD_BLOCK:-1}` (hook diff line 382) and edits the FLIP paragraph above, but leaves "ROLLBACK (one step): unset `LEADV2_PROMISE_GUARD_BLOCK` (or set it back to `"0"`)" untouched. With default=1, **unsetting is a no-op** — an operator following the first-named rollback step believes they've disabled a session-blocking hook while it stays on. The hook's own comment gets this right (`LEADV2_PROMISE_GUARD_BLOCK=0 returns the hook to log-only`); the decision-registry doc — the file read at flip/rollback time — does not.

## Medium

**M1 — Duplicated status block** (`docs/leadv2/scheduled-decisions.md`, diff lines 185–211). The hunk replaces CONDITION_BOUND with FLIPPED once, then appends a **second, byte-identical** `status:/due:/CONTEXT:` block. Verified: `grep -c '^+- \*\*status:\*\*'` on the diff = 2. (The live worktree file has since been de-duplicated by a later edit — but the diff under review ships the duplicate.)

**M2 — "Every stem added by TURN-IT-ON-01 carries a word-start anchor" is false** (`plugins/leadv2/hooks/leadv2-promise-guard.sh:372`; added regexes at :347 and :375). Census of all TURN-IT-ON stems: чин-family `\b(?:по)?чин(?:…)\b` ✅ anchored, обнов `\bобнов(?:лю|им|ляю)\b` ✅, беру/берусь `\b(?:беру|берусь)\b` ✅ — but `перепиш\w*` (:375), `мерж\w*`, `мердж\w*` (:347) carry **no `\b`**. This is the exact defect shape the round-3 judge blocked (unanchored Cyrillic stems matching mid-word); practical false-positive risk is low (no common Russian word contains перепиш/мерж/мердж internally — "смерджу" matching via `мердж` is semantically fine), but the universal comment is wrong and will mis-gate future additions. Probed live: `\b(?:по)?чин(?:ю|ишь|it…)\b` matches «чиню/починю», rejects «причина/починка/разбор причины» — the anchored stems behave as claimed (python3 re, re.I|re.UNICODE, live run this session).

**M3 — `_run_hook` comment claims a journal-row could-not-run check that does not exist** (`plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh:81–89`, diff lines 585–609). The comment: "Returns 2 … **or the journal row this call was supposed to append never landed**". The implementation checks only hook-exists, transcript-build, and rc≠0 — no journal-row check anywhere in the function. The journal write inside the hook is itself `|| true` fail-open with exit 0, so a hook that silently fails to journal still returns rc=0.

**M4 — SILENT assertions remain green under a mid-run hook crash** (all three suites; systemic). The round-3 narrative claims "a broken python3/jq/grep … fail open with the exact same empty stdout" is now distinguished from a real SILENT verdict. It is not: the hook's ERR trap (`trap '… exit 0' ERR`, hook:40) plus `2>/dev/null` in the harness means a hook that crashes after the trap produces **rc=0 and empty stdout — a passing SILENT**. Only could-not-run (missing hook/broken transcript/rc≠0) is caught. Case 2 (suppressed_action, which journals a row) could discriminate via its journal row — and per M3 the comment claims it does. Enumerated same-shape instances: binding `case_action_then_promise`, `case_promise_then_action`, work-only; morphology `case_known_verb`, `case_r1_11_podnimayu`, all r4b negatives (7); classified-block cases 2 and 6. (Case 3 and 5 do check journal fields; case 6's no-row check has the L1 hole below.) Suite-level falsifiability is preserved only through the FIRED cases — the falsifiable-runner red cited in the report is driven by them.

## Low

**L1 — `-1 == -1` vacuous pass** (`test-promise-guard-classified-block.sh:626–631` + case 6 at :712). The `_journal_lines` comment claims the `-1` sentinel makes "equality checks against it always fail"; false when **both** reads return -1 (journal missing/unreadable both times → `-1 -eq -1` true → case 6 passes without proving anything). Reachable only if the sandbox journal is unreadable throughout, hence Low.

**L2 — Unfilled placeholder shipped in the deliverable** (`docs/handoff/PROMISE-GUARD-TURN-IT-ON-01/report.md:174`): "Round 4 commit: `<pending — filled at commit time>`" — the diff's own content never resolves it.

**L3 — Self-contradictory retained sentence** (`scheduled-decisions.md` FLIP paragraph): "**As of 2026-09-01, the hook defaults to LEADV2_PROMISE_GUARD_BLOCK=1** (see the hook)… **No code change** — the hook already reads this var." The default change *is* a code change (this diff).

## Claims verified live (no finding)

- `af18aaa456…` exists: `git cat-file -t` → `commit`.
- `leadv2-suite-falsifiable.sh` on main = blob `4fccc4a42cab…`: `git ls-tree main -- …` → `100644 blob 4fccc4a…`.
- "runner's default 60s": `grep TIMEOUT` → `TIMEOUT_S="${LEADV2_SUITE_FALSIFIABLE_TIMEOUT:-60}"` (line 51).
- "Берусь за третье — 96 rows": live journal query → fired rows containing that quote = **96** (exact match).
- "423 fired / 402 unclassified / 1968 lines at flip time": current live values 458/430/1979 — consistent with ongoing live Stop-hook traffic (ratio 0.94 vs 0.95), snapshot not falsifiable; no finding.
- `run_case` treats rc=2 as FAIL, never skip: `test-promise-action-binding.sh:260–262`.
- `has_action_anywhere_in_turn` key exists in the embedded dict (hook:599) feeding the new line-7 print.
- FIRED grep pattern `'"decision": "block"'` matches the hook's actual emission (`json.dumps` → `{"decision": "block", …}`, `exit 0`, hook:755–763).
- `grep -F <pat> --` (trailing `--`, no file operand) works on macOS BSD grep — probed, rc=0.

## Tests-can-fail summary
FIRED cases are honestly falsifiable (real block-shape assertion + mutation controls + falsifiable-runner red, all evidenced in the report). SILENT cases are not individually falsifiable under fail-open crash (M4/M3) — that is the residual gap in the round-3 fix narrative.

## Census summary
Same-shape enumerations completed for: unanchored-stem additions (M2, 3 instances), sandbox-control rewrite (3 files, sid-prefix coverage consistent — classified-block's control correctly covers both `classified-$$-` and `sentinel-$$-` prefixes), SILENT-assertion instances (M4), status-block duplication (M1, single file).

---

FINISH CONTRACT: no stash created; no files changed (review-only — read the diff and live tree, ran read-only probes). **NOT-COMMITTED** — nothing to commit; the review itself is the deliverable, reported above in full.
