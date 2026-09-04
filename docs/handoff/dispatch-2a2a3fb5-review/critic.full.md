# critic — dispatch-2a2a3fb5 (REVIEW-ROUND1-EXHAUSTIVE-01, round 1, reviewer=opus-critic)

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=4 medium=2 low=3
diff=67c2ae77 (review.diff 30KB). Scope OK (4 LANE_WRITES files, product-close untouched).
Live path confirmed: generated review-mission-sonnet.md carries the new text.

## HIGH
H1 leadv2-review-run.sh:520,569,1013,1027 — round counter regresses; verify_only embeds STALE
findings. Exhaustive outcomes force REVIEW_ROUND=1; both real-verdict exits persist it; snapshots
are `[[ -f ]] || cp` so never refreshed. Executed repro: r1 fail → fix → r2 verify_only (round=2)
→ re-review unchanged diff → sidecar regresses to round=1 → next real fix gets "VERIFICATION-ONLY
ROUND 2" carrying round-1's ALREADY-FIXED findings while review-findings.round2.json sits unread;
with "admit NEW finding only if fixes introduced it", every High of the preceding round goes
unreviewed. Fix: monotonic REVIEW_ROUND=$((sidecar_round+1)) whenever a real prior verdict exists
(mode-independent); source findings from the highest snapshot / overwrite when live gate differs.
H2 :701 — prior_findings= always 0: PRIOR_FINDINGS_COUNT assigned at :465/:495 inside
_review_prior_findings_body, invoked only as $(...) (:554,:566) — parent never sees it. Fix: emit
count as body's first line, or tempfile + count in parent.
H3 :551 — LEADV2_REVIEW_ROUND=2 (or any empty-body verify_only) bypasses the "0 findings ⇒
exhaustive" guard (exists only at :557). Executed: fresh handoff → VERIFICATION-ONLY ROUND 2,
empty Prior findings, gate pass — operator hatch silently disables review. Fix: empty body ⇒
fall back to exhaustive.
H4 tests/test-review-round-exhaustive.sh:503 — no coverage for the emit line, forced modes,
round>=3/regression, or the 40-finding/300-char cap (:496-506) — exactly where H2/H3 live.

## MEDIUM
M1 :447 — _review_diff_hash swallows stderr, returns "" on failure → sidecar diff= empty → the
-n sidecar_diff guard (:566) never fires → verify_only without change evidence. Fix: empty hash ⇒
exhaustive + no sidecar write; log shasum stderr.
M2 :571 — $((sidecar_round+1)) unvalidated under set -u; corrupt sidecar aborts an "rc always 0"
function. Fix: [[ =~ ^[0-9]+$ ]] guard.

## LOW
Registered suites = 52 (claims 51/50) · T1 `grep -q 'correctness'` tautological (already in base
contract) · pinned 85ae886 archive breaks on squash-merge.

## Raw evidence
bash -n clean (bash5+3.2); shellcheck rc=0; new suite PASS=10 FAIL=0 incl. T7 red-first at
85ae8860; body-persist 13/0, arm-no-verdict 15/0, silence-gate 15/0. Round-1 sample = EXHAUSTIVE
ROUND 1 + 4 lenses + census + report-everything; round-2 sample = VERIFICATION-ONLY ROUND 2 with
prior descs; regression probe: round=1 diff=1a4a8c7f after step 1. Probe scripts: scratchpad
probe.sh, probe2.sh.
