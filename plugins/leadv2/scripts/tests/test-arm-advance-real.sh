#!/usr/bin/env bash
# SD-GLM-FLASH-ARM-DEAD-CHAIN-DECORATIVE-01
# Drive the real dispatcher and real product-close gate. The first arm is a
# completed-but-empty glm-flash run; the continuation must spawn freepool and
# must not write the write-once dispatch terminal before that second spawn.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "${TEST_DIR}/.." && pwd)"
DISPATCH="${SCRIPTS}/leadv2-dispatch-code.sh"
PRODUCT_CLOSE="${SCRIPTS}/leadv2-dispatch-product-close.sh"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/armfix.XXXXXX")"
trap 'rm -rf "${FIXTURE}"' EXIT INT TERM

REPO="${FIXTURE}/repo"
CACHE="${FIXTURE}/cache"
JOURNAL="${FIXTURE}/journal.log"
mkdir -p "${REPO}/src" "${CACHE}"
git -C "${REPO}" init -q
git -C "${REPO}" config user.email armfix@test.local
git -C "${REPO}" config user.name armfix
printf 'seed\n' > "${REPO}/src/seed.txt"
git -C "${REPO}" add src/seed.txt
git -C "${REPO}" commit -q -m seed

printf '%s\n' '#!/usr/bin/env bash' \
  'case "$1" in' \
  '  append) printf "%s\n" "$4" >> "$ARMFIX_JOURNAL" ;;' \
  '  tail) cat "$ARMFIX_JOURNAL" 2>/dev/null || true ;;' \
  'esac' > "${FIXTURE}/journal.sh"
chmod +x "${FIXTURE}/journal.sh"

printf '%s\n' '#!/usr/bin/env bash' \
  'route_arbiter() {' \
  '  if [[ "$2" == *allowed_arms* ]]; then' \
  '    printf "%s\n" "arm=freepool model=freepool tier=standard reason=forced chain=freepool util_glm=90 util_codex=90 util_claude=90 util_freepool=0 floor_mode=full floor_mode_source=test"' \
  '  else' \
  '    printf "%s\n" "arm=glm-flash model=glm-5.3-flash tier=standard reason=forced chain=glm-flash,freepool util_glm=0 util_codex=90 util_claude=90 util_freepool=10 floor_mode=full floor_mode_source=test"' \
  '  fi' \
  '}' > "${FIXTURE}/arbiter.sh"

printf '%s\n' '#!/usr/bin/env bash' \
  'case "$1" in' \
  '  bg)' \
  '    mkdir -p "$ARMFIX_CACHE/glm-runs/armfix-glm-flash"' \
  '    printf "%s\n" "status: complete" "pid: 999999" "exit_code: 0" > "$ARMFIX_CACHE/glm-runs/armfix-glm-flash/meta.yaml"' \
  '    printf "%s\n" "armfix-glm-flash"' \
  '    ;;' \
  '  status) printf "%s\n" "status: complete" "exit_code: 0" ;;' \
  '  *) exit 0 ;;' \
  'esac' > "${FIXTURE}/glm.sh"
chmod +x "${FIXTURE}/glm.sh"

printf '%s\n' '#!/usr/bin/env bash' \
  'case "$1" in' \
  '  bg) printf "%s\n" "armfix-freepool" ;;' \
  '  status) printf "%s\n" "status: running" ;;' \
  '  *) exit 0 ;;' \
  'esac' > "${FIXTURE}/freepool.sh"
chmod +x "${FIXTURE}/freepool.sh"

# Run the real close gate only for arm 1. The successor close owner is outside
# this regression's assertion and exits immediately, preventing background work.
printf '%s\n' '#!/usr/bin/env bash' \
  'if [[ "$3" == "glm-flash" ]]; then' \
  '  exec bash "$ARMFIX_REAL_CLOSE" "$@"' \
  'fi' \
  'exit 0' > "${FIXTURE}/close-wrapper.sh"
chmod +x "${FIXTURE}/close-wrapper.sh"

export ARMFIX_JOURNAL="${JOURNAL}"
export ARMFIX_REAL_CLOSE="${PRODUCT_CLOSE}"
export ARMFIX_CACHE="${CACHE}"
: > "${JOURNAL}"

(
  cd "${REPO}" || exit 1
  CLAUDE_PROJECT_ROOT="${REPO}" LEADV2_PROJECT_ROOT="${REPO}" \
  LEADV2_DISPATCH_CACHE_DIR="${CACHE}" \
  LEADV2_PC_RUNS_ROOT="${CACHE}" \
  LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="${FIXTURE}/terminal.jsonl" \
  LEADV2_JOURNAL_BIN="${FIXTURE}/journal.sh" JOURNAL_TASK=dispatch-armfix \
  LEADV2_ROUTE_ARBITER_LIB="${FIXTURE}/arbiter.sh" LEADV2_ROUTER_V2=0 \
  LEADV2_TASK_JUDGE_BIN=/bin/false \
  LEADV2_DISPATCH_GLM_BIN="${FIXTURE}/glm.sh" \
  LEADV2_DISPATCH_FREEPOOL_BIN="${FIXTURE}/freepool.sh" \
  LEADV2_DISPATCH_KIMI_BIN=/bin/false LEADV2_DISPATCH_CODEX_BIN=/bin/false \
  LEADV2_DISPATCH_SUBSESSION_BIN=/bin/false \
  LEADV2_DISPATCH_PRODUCT_CLOSE_BIN="${FIXTURE}/close-wrapper.sh" \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=1 \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_LANE_SHAPE=off \
  LEADV2_REQUIRE_PHASES=warn \
  LEADV2_ARM_EARLY_VERDICT_S=2 LEADV2_PC_WORKER_POLL_S=1 \
  LEADV2_PULSE_MODE=0 LEADV2_BURN_GOVERNOR=0 \
    bash "${DISPATCH}" 'armfix trivial forced-empty first arm' \
      --kind code --task-class Light --writes src/proof.txt >/dev/null 2>&1
)

for _ in $(seq 1 100); do
  [[ "$(grep -c '^worker_spawned' "${JOURNAL}" 2>/dev/null || true)" -ge 2 ]] && break
  sleep 0.1
done
sleep 0.5

SPAWNS="$(grep '^worker_spawned' "${JOURNAL}" 2>/dev/null || true)"
SPAWN_N="$(printf '%s\n' "${SPAWNS}" | grep -c . || true)"
SPAWN_1="$(printf '%s\n' "${SPAWNS}" | sed -n '1p')"
SPAWN_2="$(printf '%s\n' "${SPAWNS}" | sed -n '2p')"
if [[ "${SPAWN_N}" -ne 2 ]]; then
  printf 'FAIL: expected two worker_spawned lines, got %s\n' "${SPAWN_N}"
  cat "${JOURNAL}"
  exit 1
fi
if [[ "${SPAWN_1}" != *'model=glm-flash'* || "${SPAWN_2}" != *'model=freepool'* ]]; then
  printf 'FAIL: models did not advance\n%s\n%s\n' "${SPAWN_1}" "${SPAWN_2}"
  exit 1
fi
if grep -q 'dispatch_terminal' "${JOURNAL}"; then
  printf 'FAIL: terminal written before fallback chain exhausted\n'
  grep 'dispatch_terminal' "${JOURNAL}"
  exit 1
fi

printf '%s\n' "${SPAWNS}"
printf 'PASS: real dispatcher advanced to a second model without a premature terminal\n'
