#!/usr/bin/env bash
# test-prepass-admission-truth-01.sh — PREPASS-CLASSIFIER-MISREADS-AN-ALLOWED-PAYLOAD-01
#
# Three independent controls, one per defect claimed by the row (lane rules:
# one control per independent claim):
#
#   A (defect 2, :5724 area) `_architect_prepass_admission_status` is
#     quote-blind: JSON "status":"allowed"/"status":"quota_refused" both fell
#     through to unknown (live dispatch 598ff1eb journalled a provider that
#     said allowed as a quota silence). Cases A1/A2 are red on main; A3 is the
#     instrument's positive control (bare status=allowed passes on main too —
#     if IT fails the suite lost its grip, the subject did not regress); A4
#     guards the camelCase anchor (overageStatus must not satisfy admission);
#     A5 is the JSON form of the refused branch.
#
#   B (defect 1, :5672 area) `_ARCH_FAIL_RATE_RE` matched the NAME of
#     informational telemetry: a stream whose only rate strings were
#     rate_limit_event/rate_limit_info was classed rate_limited. B1 is the
#     name-only payload (red on main: rate_limited); B2-B5 prove real limit
#     messages still classify (prose, the rate_limit_error REFUSAL event type,
#     the hyphenated form, HTTP 429); B6 guards the untouched quota class; B7
#     repeats the camelCase guard at the classifier level.
#
#   C (defect 3, :6036 area) the fallback ladder gate was a hardcoded
#     `case ${arm} in codex|glm` name list — no tenant yaml could change it.
#     Launcher eligibility now comes from the ladder entry's own
#     `architect_launcher:` field in router.dispatch_ladder (routing config,
#     not a literal list). C drives a FIXTURE routing yaml through the REAL
#     _load_dispatch_ladder and the REAL _architect_fallback_design in an
#     isolated git fixture: an arm outside codex|glm WITH the field must be
#     used (C1, red on main: skipped no_architect_launcher), entries WITHOUT
#     the field (C2) and with an invalid style (C5) must still be skipped as a
#     config fact, the launched design must land (C3) through the codex-style
#     invocation in a disposable worktree (C4, C6).
#
# Hermetic: no provider, no canonical registry, no live routing yaml is
# contacted. Parts A/B source the dispatcher in source-only mode (the probe
# seam, LEADV2_DISPATCH_SOURCE_ONLY=1); part C runs a copied scripts tree
# against a temporary git repository with stubbed launchers, mirroring
# tests/test-dispatch-prepass-provider-fallback.sh.
#
# Mutation hook: LEADV2_PREPASS_TRUTH_SCRIPTS_DIR points every part at an
# alternative scripts/ tree (a mutated copy), so a negative control can flip
# one hunk without touching the subject in place.
#
# run-all-triggers: leadv2-dispatch-code
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${LEADV2_PREPASS_TRUTH_SCRIPTS_DIR:-${TESTS_DIR}/..}"
DISPATCH_SRC="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"
WORKTREE_ROOT="$(cd "${SCRIPTS_DIR}/../.." && pwd)"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-prepass-truth.XXXXXX")"
PASS=0 FAIL=0
cleanup() { rm -rf "${ROOT}"; }
trap cleanup EXIT
ok() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

[ -f "${DISPATCH_SRC}" ] || { echo "no dispatcher at ${DISPATCH_SRC}"; exit 2; }

# ── Part A + B: source-only seam (same as the acceptance probe) ─────────────
cd "${WORKTREE_ROOT}" || exit 2
export LEADV2_DISPATCH_SOURCE_ONLY=1
# shellcheck disable=SC1090
source "${DISPATCH_SRC}" 2>/dev/null
for _fn in _architect_prepass_admission_status _architect_failure_class; do
  declare -F "${_fn}" >/dev/null || { echo "seam MISSING: ${_fn}"; exit 2; }
done

ADM_DIR="$(mktemp -d "${ROOT}/adm.XXXXXX")"
adm() { # <label> <payload> <expected>
  local label="$1" payload="$2" want="$3" got
  got="$(_architect_prepass_admission_status "${ADM_DIR}" "${payload}" 2>/dev/null)"
  [ "${got}" = "${want}" ] && ok "admission ${label} -> ${got}" \
    || bad "admission ${label}: want ${want} got ${got:-<empty>}"
}

adm 'A1 json status allowed' \
  '{"type":"rate_limit_event","status":"allowed","limits":[{"kind":"session","percent":34}]}' \
  allowed
adm 'A2 json status quota_refused' \
  '{"type":"rate_limit_event","status":"quota_refused"}' \
  quota_refused
adm 'A3 bare status=allowed (instrument control)' 'status=allowed' allowed
adm 'A4 overageStatus only must stay unknown' \
  '{"overageStatus":"allowed","resetsAt":1789489800}' unknown
adm 'A5 json status rate_limited' '{"status":"rate_limited"}' quota_refused

CLS_DIR="$(mktemp -d "${ROOT}/cls.XXXXXX")"
cls() { # <label> <captured-out> <expected-class>
  local label="$1" cap="$2" want="$3" got
  got="$(_architect_failure_class "${CLS_DIR}" "${cap}" 1 2>/dev/null)"
  got="${got%%$'\t'*}"
  [ "${got}" = "${want}" ] && ok "class ${label} -> ${got}" \
    || bad "class ${label}: want ${want} got ${got:-<empty>}"
}

cls 'B1 telemetry-name payload is NOT a rate limit' \
  '{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","rateLimitType":"five_hour","overageStatus":"allowed"}}' \
  failed_rc_1
cls 'B2 prose rate limit exceeded' \
  'Error: rate limit exceeded, retry after 60s' rate_limited
cls 'B3 rate_limit_error refusal event' \
  '{"type":"error","error":{"type":"rate_limit_error","message":"Rate limit exceeded"}}' rate_limited
cls 'B4 hyphenated rate-limited' 'You are rate-limited, slow down' rate_limited
cls 'B5 HTTP 429' 'HTTP 429: too many requests' rate_limited
cls 'B6 quota class untouched' 'quota exceeded for this org' quota_exceeded
cls 'B7 camelCase rateLimitType is not a rate limit' \
  '{"rateLimitType":"five_hour","limit":1}' failed_rc_1

# ── Part C: config-driven fallback gate in an isolated fixture ──────────────
C_DIR="${ROOT}/fallback"
mkdir -p "${C_DIR}/tmp"
cp -R "${SCRIPTS_DIR}" "${C_DIR}/scripts"
# Load the real definitions without dispatching its CLI footer (ppf seam).
awk '/^# ── dispatch / { exit } { print }' \
  "${C_DIR}/scripts/leadv2-dispatch-code.sh" > "${C_DIR}/scripts/dispatch-lib.sh"
C_REPO="${C_DIR}/repo"
mkdir -p "${C_REPO}"
git -C "${C_REPO}" init -q -b main
git -C "${C_REPO}" config user.email fixture@example.invalid
git -C "${C_REPO}" config user.name fixture
printf 'seed\n' > "${C_REPO}/seed.txt"
git -C "${C_REPO}" add seed.txt
git -C "${C_REPO}" commit -qm seed

# Routing config drives the ladder: an arm OUTSIDE codex|glm with a declared
# launcher style must be fallback-launchable; entries without the field (or
# with an invalid style) are skipped as a config fact.
cat > "${C_DIR}/routing.yaml" <<'YAML'
router:
  dispatch_ladder:
    - { id: badstyle, provider: p3, architect_launcher: telnet }
    - { id: barearm, provider: p4 }
    - { id: tssarm, provider: tssprov, architect_launcher: codex }
    - { id: glm, provider: zai }
YAML

cat > "${C_DIR}/provider.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${STUB_ARGS_FILE}"
printf 'acceptance:\n  surface: file_artifact\nLANE_WRITES: seed.txt\n'
EOF
chmod +x "${C_DIR}/provider.sh"
printf 'architect prompt\n' > "${C_DIR}/mission.md"

cat > "${C_DIR}/runner.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "${FIXTURE_DIR}/scripts/dispatch-lib.sh"
PROJECT_ROOT="${FIXTURE_REPO}"
ARCHITECT_PREPASS_TIMEOUT_SEC=10
ROUTING_YAML="${FIXTURE_DIR}/routing.yaml"
emit() { printf '%s\n' "$*" >> "${FIXTURE_DIR}/events.log"; }
_provider_available() { return 0; }
CODEX_BIN="${FIXTURE_DIR}/provider.sh"
GLM_BIN="${FIXTURE_DIR}/provider.sh"
_architect_fallback_design "${FIXTURE_DIR}/mission.md" fixture-sig \
  authentication_failed "${FIXTURE_DIR}/design.md" anthropic
EOF

FIXTURE_DIR="${C_DIR}" FIXTURE_REPO="${C_REPO}" STUB_ARGS_FILE="${C_DIR}/provider.args" \
  TMPDIR="${C_DIR}/tmp" bash "${C_DIR}/runner.sh" >/dev/null 2>&1
C_RC=$?

ev() { grep -q "$1" "${C_DIR}/events.log" 2>/dev/null; }

[ "${C_RC}" -eq 0 ] && ok 'C0 fallback run rc=0 (tssarm produced a design)' \
  || bad "C0 fallback run rc=${C_RC}"
ev 'arm=tssarm outcome=used' && ok 'C1 arm outside codex|glm with architect_launcher USED' \
  || bad 'C1 arm=tssarm was not used (gate still a name list?)'
ev 'arm=barearm outcome=skipped reason=no_architect_launcher' \
  && ok 'C2 entry without the field still skipped' \
  || bad 'C2 barearm skip line missing'
ev 'arm=badstyle outcome=skipped reason=no_architect_launcher' \
  && ok 'C5 invalid style rejected to a config skip' \
  || bad 'C5 badstyle skip line missing'
[ -s "${C_DIR}/design.md" ] && ok 'C3 design landed from the fallback arm' \
  || bad 'C3 design.md empty or missing'
if [ -f "${C_DIR}/provider.args" ] \
   && grep -q -- '--wait' "${C_DIR}/provider.args" \
   && grep -q -- '--cwd' "${C_DIR}/provider.args" \
   && ! grep -q -- "--cwd ${C_REPO}" "${C_DIR}/provider.args"; then
  ok 'C4 codex-style invocation, cwd is the disposable worktree not the repo'
else
  bad 'C4 provider args missing --wait/--cwd or cwd is the fixture repo'
fi
if [ -z "$(ls "${C_DIR}/tmp" | grep '^leadv2-afb\.' || true)" ]; then
  ok 'C6 disposable workspace removed'
else
  bad 'C6 leadv2-afb.* workspace left behind'
fi

printf 'pass=%d fail=%d\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
