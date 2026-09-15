#!/usr/bin/env bash
# tests/test-leadv2-dispatch-code.sh — DEEPTHINK-MODE-IS-NOT-WIRED-01
# (founder order 2026-09-04: "GLM/GLM-flash calls use effort, and when
# needed — deepthink mode"; the second half was missing entirely).
#
# Probed provider truth this wiring rests on (2026-09-04, live against
# https://api.z.ai/api/anthropic/v1/messages — full battery in
# docs/handoff/DEEPTHINK-MODE-IS-NOT-WIRED-01/report.md):
#   - glm-5.3 and glm-5.3-flash ALWAYS reason; `thinking.type` collapses
#     into the effort vocabulary (disabled -> low; enabled -> max only when
#     no explicit effort), `budget_tokens` is silently dropped, and
#     `output_config.effort` is the ONLY thinking-intensity dial the
#     provider honours — `max` is the documented "Deep Reasoning" level.
#   - Same prompt, only effort flips: glm-5.3 low -> NO thinking block /
#     135 output tokens, max -> thinking block / 340; flash low -> none /
#     63, max -> thinking / 407.
# Therefore deepthink rides GLM_EFFORT (the dispatcher pins it to max) and
# the runner's existing --effort flag. NO second flag exists at the runner —
# a knob the provider does not read would be a dead flag (brief §4).
#
# This suite self-selects under `tests/run-all.sh --scope changed` via the
# stem convention (changed leadv2-dispatch-code.sh -> test-leadv2-dispatch-
# code.sh candidate at tests/run-all.sh:553).
#
# Covers:
#   A. Dispatcher end-to-end (recorder bin, no live spawn): class -> think
#      decision journaled on the effort_applied line next to effort=;
#      think=deep pins GLM_EFFORT=max into the launcher env, INCLUDING when
#      the review/verify/critic role_override would have capped it at high
#      (the actual gap this lane closed).
#   B. Unit: _glm_think_for_class full map incl. Title-case runtime shape
#      and the unknown-class off/fallback arm.
#   C. Transport: GLM_EFFORT=max -> `claude -p` argv carries --effort max
#      (the parameter deepthink arrives as at the provider).
#
# The `claude` binary is stubbed via the GLM_CLAUDE_BIN seam; the launcher
# via LEADV2_DISPATCH_GLM_BIN; journal via LEADV2_JOURNAL_BIN. No network.
#
# Run: bash plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_ROOT="$(cd "${PLUGIN_SCRIPTS}/.." && pwd)"
GLM_SCRIPT="${PLUGIN_SCRIPTS}/glm-coder.sh"
DISPATCH="${PLUGIN_SCRIPTS}/leadv2-dispatch-code.sh"

export LEADV2_BURN_GOVERNOR=0
# Same convention as test-glm-flash-handle.sh / test-glm-lock-per-lane.sh:
# this suite NAMES launcher scripts (and stub-drives the dispatcher), so the
# fg-dispatch hook needs the explicit allow — no live dispatch runs here.
export LEADV2_ALLOW_FG_DISPATCH=1

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/glm-think-fixture.XXXXXX")"
trap 'rm -rf "${FIXTURE}"' EXIT INT TERM

# ── syntax floor on every changed shell file ────────────────────────────────
for f in "scripts/glm-coder.sh" "scripts/leadv2-dispatch-code.sh"; do
  if bash -n "${PLUGIN_ROOT}/${f}" 2>/dev/null && /bin/bash -n "${PLUGIN_ROOT}/${f}" 2>/dev/null; then
    PASS=$((PASS + 1)); log "PASS: bash -n ${f} (incl. 3.2)"
  else
    FAIL=$((FAIL + 1)); log "FAIL: bash -n ${f}"
  fi
done

# ── fixture: repo, stub claude (argv capture), stub secrets ─────────────────
REPO="${FIXTURE}/repo"
mkdir -p "${REPO}"
git -C "${REPO}" init -q 2>/dev/null || true
git -C "${REPO}" -c user.email=think@test -c user.name=think commit -q --allow-empty -m init 2>/dev/null || true

STUB_BIN="${FIXTURE}/bin"; mkdir -p "${STUB_BIN}"
ARGV_CAPTURE="${FIXTURE}/spawn-argv.txt"
cat > "${STUB_BIN}/claude" <<STUBEOF
#!/usr/bin/env bash
printf 'ARGV=%s\n' "\$*" | tr '\n' ' ' >> "${ARGV_CAPTURE}"
printf '%s\n' '{"type":"system","subtype":"init","model":"stub"}'
exit 0
STUBEOF
chmod +x "${STUB_BIN}/claude"

SECRETS="${FIXTURE}/zai.env"
printf 'ZAI_AUTH_TOKEN=stub-token-for-test\n' > "${SECRETS}"
chmod 600 "${SECRETS}"

# ── Part C: transport — GLM_EFFORT=max -> spawn argv carries --effort max ───
: > "${ARGV_CAPTURE}"
(
  set +e
  export GLM_CLAUDE_BIN="${STUB_BIN}/claude"
  export GLM_SECRETS_FILE="${SECRETS}"
  export GLM_RUNS_DIR="${FIXTURE}/glm-runs"
  export GLM_SKIP_QUOTA_GATE=1
  export LEADV2_BURN_GOVERNOR=0
  export TMPDIR="${FIXTURE}"
  export CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}"
  export GLM_EFFORT=max
  bash "${GLM_SCRIPT}" run "think transport probe" --out "${FIXTURE}/out-v1.txt" --cwd "${REPO}"
) >/dev/null 2>&1
if grep -q '^ARGV=.*--effort max' "${ARGV_CAPTURE}" 2>/dev/null; then
  pass "run path: GLM_EFFORT=max -> spawn argv carries --effort max (deepthink transport)"
else
  fail "run path: --effort max missing from argv — got: $(grep '^ARGV=' "${ARGV_CAPTURE}" 2>/dev/null | head -1)"
fi

# ── Part A: dispatcher end-to-end — class (+role) -> think + effort ─────────
D_CACHE="${FIXTURE}/dispatch-cache"; mkdir -p "${D_CACHE}"
RECORD="${FIXTURE}/glm-bin-record.txt"
JOURNAL_RECORD="${FIXTURE}/journal-record.txt"
cat > "${FIXTURE}/glm-recorder.sh" <<EOF
#!/usr/bin/env bash
case "\$1" in
  bg)
    printf 'GLM_MODEL=%s GLM_EFFORT=%s\n' "\${GLM_MODEL:-<unset>}" "\${GLM_EFFORT:-<unset>}" >> "${RECORD}"
    printf 'spawn-think-stub\n'
    ;;
  status) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "${FIXTURE}/glm-recorder.sh"
cat > "${FIXTURE}/journal.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${JOURNAL_RECORD}"
EOF
chmod +x "${FIXTURE}/journal.sh"
cat > "${FIXTURE}/dispatch-live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"glm":{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":10}},"codex":{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":20}]},"anthropic":{"status":"ok","accounts":[{"active":true,"five_hour_pct":20,"seven_day_pct":20}]}}'
EOF
chmod +x "${FIXTURE}/dispatch-live.sh"

_dispatch_probe() { # $1 = Title-case task class, $2 = worker role or ""
  : > "${RECORD}"
  : > "${JOURNAL_RECORD}"
  (
    cd "${REPO}" || exit 97
    # Scrub ambient lane env (this suite may itself run inside a live GLM
    # lane whose dispatcher exports GLM_EFFORT / role) so only the
    # dispatcher's own class-map computation reaches the recorder.
    unset GLM_EFFORT
    unset LEADV2_PROJECT_ROOT LEADV2_LANE_WORK_ROOT LEADV2_TASK_ID LEADV2_PARENT_SESSION_ID LEADV2_DISPATCH_LANE_NAME
    if [[ -n "${2:-}" ]]; then
      export LEADV2_WORKER_ROLE="$2"
    else
      unset LEADV2_WORKER_ROLE
    fi
    CLAUDE_PROJECT_ROOT="${REPO}" \
    LEADV2_PROJECT_ROOT="${REPO}" \
    LEADV2_DISPATCH_CACHE_DIR="${D_CACHE}" \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_LANE_SHAPE=off LEADV2_ARM_EARLY_VERDICT_S=0 \
    LEADV2_REQUIRE_PHASES=0 \
    LEADV2_QUOTA_LIVE="${FIXTURE}/dispatch-live.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="${FIXTURE}/dispatch-arb-state" \
    LEADV2_JOURNAL_BIN="${FIXTURE}/journal.sh" JOURNAL_TASK=glm-think-"$1" \
    LEADV2_DISPATCH_GLM_BIN="${FIXTURE}/glm-recorder.sh" \
    LEADV2_DISPATCH_KIMI_BIN=/bin/false LEADV2_DISPATCH_CODEX_BIN=/bin/false \
    LEADV2_DISPATCH_SUBSESSION_BIN=/bin/false \
    LEADV2_WRITESET_PENDING_WINDOW_SEC=0 \
    bash "${DISPATCH}" "think dispatch probe: $1${2:+ role=$2} run=$RANDOM" --kind product --task-class "$1" --writes "src/think-probe-$1-$RANDOM.py" 2>&1
  ) >/dev/null 2>&1
  rm -f "${FIXTURE}/dispatch-arb-state" 2>/dev/null || true
}

# _dispatch_probe <class> <role|"-"> <want-effort> <want-think> <want-effort-source>
expect_dispatch() {
  local cls="$1" role="$2" want_eff="$3" want_think="$4" want_src="$5"
  [[ "${role}" == "-" ]] && role=""
  _dispatch_probe "${cls}" "${role}"
  if grep -q "effort_applied by=router.*effort=${want_eff} think=${want_think}.*source=${want_src}" "${JOURNAL_RECORD}" 2>/dev/null; then
    pass "dispatch: ${cls}${role:+ +${role}} -> journal effort=${want_eff} think=${want_think} source=${want_src}"
  else
    fail "dispatch: ${cls}${role:+ +${role}} expected effort=${want_eff} think=${want_think} source=${want_src} — got: $(grep -E 'effort_applied' "${JOURNAL_RECORD}" 2>/dev/null | head -1)"
  fi
  if grep -q "^GLM_MODEL=[^ ]* GLM_EFFORT=${want_eff}\$" "${RECORD}" 2>/dev/null; then
    pass "dispatch: ${cls}${role:+ +${role}} -> launcher env GLM_EFFORT=${want_eff} (deepthink reaches the runner variable)"
  else
    fail "dispatch: ${cls}${role:+ +${role}} expected launcher GLM_EFFORT=${want_eff} — got: $(head -1 "${RECORD}" 2>/dev/null)"
  fi
}

# The one real behavioural gap: role_override capped heavy reviews at high.
# (No Bulk row: Bulk is not a runtime admission class — the classifier emits
# Trivial/Light/Standard/Heavy/Strategic, and --task-class Bulk normalizes to
# Standard. `bulk` stays covered by the unit map below.)
expect_dispatch Heavy    -       max  deep class_map
expect_dispatch Strategic -      max  deep class_map
expect_dispatch Heavy    critic  max  deep think_deep
expect_dispatch Standard -       high off  class_map
expect_dispatch Light    -       low  off  class_map

# ── Part B: unit — _glm_think_for_class full map ────────────────────────────
MAP_SRC="${FIXTURE}/map-extract.sh"
{
  sed -n '/^_glm_think_for_class()/,/^}$/p' "${DISPATCH}"
  printf 'for c in trivial light bulk standard heavy strategic Heavy Strategic Light bogus-cls; do printf "%%s=%%s\\n" "$c" "$(_glm_think_for_class "$c")"; done\n'
} > "${MAP_SRC}"
MAP_OUT="$(bash "${MAP_SRC}" 2>&1)" || MAP_OUT=""
map_check() { # <class> <want-think> <want-source>
  if [[ "${MAP_OUT}" == *"$1=$2 $3"* ]]; then
    pass "map: $1 -> $2 $3"
  else
    fail "map: $1 expected '$2 $3' — got: $(printf '%s\n' "${MAP_OUT}" | grep "^$1=" | head -1)"
  fi
}
map_check trivial    off  class_map
map_check light      off  class_map
map_check bulk       off  class_map
map_check standard   off  class_map
map_check heavy      deep class_map
map_check strategic  deep class_map
map_check Heavy      deep class_map
map_check Strategic  deep class_map
map_check Light      off  class_map
map_check bogus-cls  off  fallback

printf -- '[TEST] summary: PASS=%d FAIL=%d\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
