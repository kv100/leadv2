#!/usr/bin/env bash
# PREPASS-RETRY-THEN-PARK-01 (2026-07-29, founder decision) SUPERSEDED this test's
# original premise ("architect failure and timeout are advisory: a product dispatch
# must still launch") -- see leadv2-dispatch-code.sh's own dated doc comment at its
# architect_prepass retry loop. A product task that exhausts ARCHITECT_PREPASS_ATTEMPTS
# retries is now PARKED (exit 3, no worker_spawned), never dispatched unrefined.
# Assertions below were stale (asserting the pre-2026-07-29 degrade-to-raw behavior,
# unrelated to SUPERVISOR-AUDIT-01 items A/B/C) and are updated here to match; the
# test's PURPOSE is unchanged: prove architect failure/timeout is handled loudly and
# promptly (retried, then parked) rather than hanging or crashing dispatch-code.sh.
set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0

ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
REPO="$ROOT/repo"; mkdir -p "$REPO/.claude/ref" "$REPO/docs/leadv2/.bus-offsets"
(cd "$REPO" && git init -q && git config user.email test@example.com && git config user.name test && : > seed && git add seed && git commit -qm seed)
printf 'router:\n  glm_policy:\n    sonnet_exceptions: [safety_gate_publish_payments]\n    opus_only_mission_kinds: []\n    codex_fitting_mission_kinds: []\n' > "$REPO/.claude/ref/leadv2-routing.yaml"
WORKER="$ROOT/worker"; ARCH="$ROOT/architect"
printf '#!/usr/bin/env bash\nnohup sleep 60 >/dev/null 2>&1 &\nprintf "PID=%%s LABEL=test SESSION_ID=test\\n" "$!"\n' > "$WORKER"
printf '#!/usr/bin/env bash\ncase "${PREPASS_MODE:-fail}" in timeout) sleep 60;; *) exit 9;; esac\n' > "$ARCH"
chmod +x "$WORKER" "$ARCH"
DISPATCH="$(cd "$(dirname "$0")/.." && pwd)/leadv2-dispatch-code.sh"
run() {
  CLAUDE_PROJECT_ROOT="$REPO" LEADV2_PROJECT_ROOT="$REPO" LEADV2_DISPATCH_CACHE_DIR="$ROOT/cache" \
  LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" LEADV2_DISPATCH_ARCHITECT_BIN="$ARCH" \
  LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC=1 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
  LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off bash "$DISPATCH" "$1" --kind product --protected
}
out="$(run 'product failure must park, not dispatch unrefined')"; rc=$?
[[ $rc -eq 3 && "$out" != *worker_spawned* ]] || { echo "FAIL repeated architect failure did not park cleanly: rc=$rc out=$out"; exit 1; }
journal="$(find "$REPO/docs/leadv2/tasks" -name journal.md -print -quit)"
grep -q 'status=parked reason=no_design_after_2_attempts' "$journal" || { echo 'FAIL missing parked-after-retries journal line'; exit 1; }
# LOW-4 (fixround-tails): the pre-fix version of this assertion only checked the FINAL
# park -- a regression that parked on the FIRST failure (never actually retrying) would
# still pass. Assert the retry half of retry-then-park is real too.
grep -q 'status=retrying attempt=1/2' "$journal" || { echo 'FAIL missing retry-half journal line before park (retry-then-park regressed to park-on-first-failure)'; exit 1; }
start=$(date +%s); out="$(PREPASS_MODE=timeout run 'product timeout must park, not dispatch unrefined')"; rc=$?; elapsed=$(( $(date +%s) - start ))
[[ $rc -eq 3 && $elapsed -lt 8 && "$out" != *worker_spawned* ]] || { echo "FAIL repeated architect timeout did not park promptly: rc=$rc elapsed=$elapsed out=$out"; exit 1; }
grep -R -q 'status=parked reason=no_design_after_2_attempts' "$REPO/docs/leadv2/tasks" || { echo 'FAIL missing parked-after-timeout journal line'; exit 1; }
grep -R -q 'status=retrying attempt=1/2' "$REPO/docs/leadv2/tasks" || { echo 'FAIL missing retry-half journal line before the timeout park'; exit 1; }
echo 'PASS: repeated architect failure/timeout parks promptly (PREPASS-RETRY-THEN-PARK-01), never dispatches an unrefined product task'
