# critic — dispatch-e2e9d9b2 (PLUGIN-CORE-OFFLINE-4RED-01, round 1, reviewer=opus-critic)

REVIEW_VERDICT: FAIL
diff=fb29baffd9e2b7d0dfe06525935f9e3111bcae4e2854b337c369bca2b0b48d24

## CRITICAL-1 — acceptance not reproducible; order-dependent green
Critic's own run in the lane: suites passed=46 failed=4 (~22 min). Failed set SHIFTED:
plugin sync quarantine/dry-run safety · product-close waits for worker exit · Codex full-cycle
runner · supervisor reconciliation. The recorded "50/0" is not reproducible. Suite 2 fails
INSIDE the runner (`FAIL: quarantine: --dry-run must not reconcile or create quarantine content`)
but passes twice standalone → state/order-dependent green.
Fix: fixtures/pe_run_cache_sync.sh:30 file-level `DRY_RUN="${LEADV2_TEST_DRY_RUN:-false}"` is the
wrong lever — pass mode explicitly at each call site (as test-lane-truth-batch-01.sh does with
--dry-run/--write); then show 50/0 TWICE back-to-back.

## HIGH-1 — test-fg-dispatch-guard.sh:216-221 lying green
`grep -q 'leadv2-block-fg-dispatch.sh' "$DISPATCHER"` matches a COMMENT
(hooks/leadv2-bash-pre-dispatch.sh:47), not registration. Falsified: MANIFEST line 60 replaced
with unregistered entry → suite still PASS=35 FAIL=0; only blanking the comment turned it red.
Fix: assert the MANIFEST entry itself, or run dispatcher with LEADV2_DISPATCH_TRACE=1 on a
guarded command and assert the trace names the guard.

## MEDIUM-1 — non-hermetic: tests write tracked repo files
test-routing-enforcement-p1.sh journals into docs/leadv2/tasks/dispatch-567ba028/journal.md and
dispatch-59ae8b51/journal.md (+90 lines, IN THIS DIFF — must not be committed). Full runner also
dirties docs/leadv2/{active.yaml,bus.jsonl,merge-queue.jsonl,open-threads.md,questions}.
Fix: scope journal root under TMP_ROOT.

## MEDIUM-2 — runtime + premise
Suite 1 is 182–214s (~15s/dispatch), not "seconds". Codex full-cycle suite reads LIVE quota
(`codex spawn refused by quota gate (cooldown/circuit)`) — offline suite coupled to live state;
the 4-red premise must be re-established after hermetization.

## Verified legitimate (falsified, not weakened)
Suite 1: probe contract leadv2-dispatch-code.sh:2974-2977; forcing _codex_first_byte_probe→1/0
flips cases RED both ways; no quota-lockout-codex.json leaked after 5 runs.
Suite 4: --write is the real contract (leadv2-plugin-sync.sh:91-99); neutering cp -p at :236 →
lane-truth pass=13 fail=2, perimeter RED. bash -n OK ×4; shellcheck -S error rc=0; no engine
code edited. Stale (pre-existing): leadv2-fanout.sh:85 advises --write-less sync.
