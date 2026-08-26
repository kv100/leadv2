#!/usr/bin/env bash
# tests/test-t14-worker-mcp.sh — T14: role-scoped MCP for dispatched workers.
#
# glm-coder.sh must pass --strict-mcp-config --mcp-config <resolved role file>
# on every worker spawn (run AND bg paths), gated by LEADV2_WORKER_MCP
# (default 1; =0 restores the pre-T14 spawn line), role selected by
# LEADV2_WORKER_ROLE (developer default, critic for review missions), with
# one machine-greppable journal line per spawn (worker_mcp_attached /
# worker_mcp_skipped) and FAIL-OPEN behaviour when the resolver cannot
# produce a config (spawn proceeds with NO flag).
#
# The `claude` binary is stubbed via the GLM_CLAUDE_BIN seam (captures argv);
# secrets/quota/runs-dir are stubbed via GLM_SECRETS_FILE / GLM_SKIP_QUOTA_GATE
# / GLM_RUNS_DIR. No network, no real provider.
#
# NEGATIVE CONTROL (run every time, per E2E-HARNESS-AUDIT-01): T14-NC applies
# a mutation INSIDE worker_mcp_resolve()'s body (`return 1` on line 1) to a
# SCRATCH COPY of glm-coder.sh and proves this suite goes RED against it --
# never against the working tree, never via git stash/reset.
#
# Run: bash plugins/leadv2/scripts/tests/test-t14-worker-mcp.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_ROOT="$(cd "${PLUGIN_SCRIPTS}/.." && pwd)"
GLM_SCRIPT="${PLUGIN_SCRIPTS}/glm-coder.sh"
WORKER_MCP_LIB="${PLUGIN_SCRIPTS}/lib/leadv2-worker-mcp.sh"

PASS=0
FAIL=0
ERRORS=()

log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

CLEANUP_PATHS=()
_cleanup() {
  local p
  for p in "${CLEANUP_PATHS[@]+"${CLEANUP_PATHS[@]}"}"; do
    rm -rf "${p}" 2>/dev/null || true
  done
}
trap _cleanup EXIT INT TERM

# ── bash 3.2 syntax floor on every changed shell file ────────────────────────
for f in "scripts/glm-coder.sh" "scripts/claude-subsession.sh" "scripts/lib/leadv2-worker-mcp.sh"; do
  if bash -n "${PLUGIN_ROOT}/${f}" 2>/dev/null && /bin/bash -n "${PLUGIN_ROOT}/${f}" 2>/dev/null; then
    PASS=$((PASS + 1)); log "PASS: bash -n ${f} (incl. 3.2)"
  else
    FAIL=$((FAIL + 1)); ERRORS+=("bash -n ${f}"); log "FAIL: bash -n ${f}"
  fi
done

# ── fixture: stub claude, stub secrets, fixture repo with .mcp.json ──────────
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/t14-fixture.XXXXXX")"
CLEANUP_PATHS+=("${FIXTURE}")

# Fixture repo: defines BOTH allowlisted servers, so the resolved config must
# carry both. Deliberately does NOT rely on the ambient $HOME config chain.
REPO="${FIXTURE}/repo"
mkdir -p "${REPO}"
printf '%s\n' '{"mcpServers": {"repowise": {"command": "stub-repowise", "args": []}, "codebase-memory-mcp": {"command": "stub-cbm", "args": []}}}' > "${REPO}/.mcp.json"
git -C "${REPO}" init -q 2>/dev/null || true
git -C "${REPO}" -c user.email=t14@test -c user.name=t14 commit -q --allow-empty -m init 2>/dev/null || true

# Stub claude: captures argv (one arg per line), emits a minimal coherent
# envelope for both --output-format json (run) and stream-json (bg).
STUB_BIN="${FIXTURE}/bin"
mkdir -p "${STUB_BIN}"
ARGV_FILE="${FIXTURE}/argv.txt"
cat > "${STUB_BIN}/claude" <<STUBEOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "${ARGV_FILE}"
printf '%s\n' '{"type":"system","subtype":"init","model":"stub"}'
exit 0
STUBEOF
chmod +x "${STUB_BIN}/claude"

SECRETS="${FIXTURE}/zai.env"
printf 'ZAI_AUTH_TOKEN=stub-token-for-test\n' > "${SECRETS}"
chmod 600 "${SECRETS}"

RUNS_DIR="${FIXTURE}/glm-runs"
mkdir -p "${RUNS_DIR}"

# _glm_run <script> [extra env NAME=VALUE ...] — runs the v1 `run` path with
# the standard seam env; returns via globals G_OUT / G_STDERR / G_RC / G_ARGV.
_glm_run() {
  local script="$1"; shift
  : > "${ARGV_FILE}"
  G_OUT="${FIXTURE}/out-$$.txt"
  G_STDERR="${FIXTURE}/stderr-$$.txt"
  local env_name
  (
    set +e
    export GLM_CLAUDE_BIN="${STUB_BIN}/claude"
    export GLM_SECRETS_FILE="${SECRETS}"
    export GLM_RUNS_DIR="${RUNS_DIR}"
    export GLM_SKIP_QUOTA_GATE=1
    export LEADV2_BURN_GOVERNOR=0
    export TMPDIR="${FIXTURE}"
    # Deterministic allowlist source (this checkout's config/), overridable
    # per-case (T14-04 passes its own CLAUDE_PLUGIN_ROOT after the defaults).
    export CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}"
    for env_name in "$@"; do export "$env_name"; done
    bash "${script}" run "t14 probe mission" --out "${G_OUT}" --cwd "${REPO}"
  ) > /dev/null 2>"${G_STDERR}"
  G_RC=$?
  G_ARGV="$(cat "${ARGV_FILE}" 2>/dev/null || true)"
}

_argc() { grep -c '^--mcp-config$' "${ARGV_FILE}" 2>/dev/null || true; }
_flag_value() { # $1=flag -> the arg immediately after it
  awk -v f="$1" 'prev==f{print; exit} {prev=$0}' "${ARGV_FILE}" 2>/dev/null
}

# ── T14-01: default ON, developer role — flags + journal + resolved content ──
test_01_default_developer() {
  log "T14-01: default (gate unset=1, role unset=developer) attaches --mcp-config"
  _glm_run "${GLM_SCRIPT}"
  local v
  v="$(_flag_value --mcp-config)"
  if [[ $(_argc) -eq 1 && -n "${v}" && "$(basename "${v}")" == "mcp-role-developer.resolved.json" ]] \
     && grep -q '^--strict-mcp-config$' "${ARGV_FILE}" && [[ "${G_RC}" -eq 0 ]]; then
    pass "spawn line carries --strict-mcp-config --mcp-config <developer resolved file> (rc=0)"
  else
    fail "default spawn missing/dup MCP flags (rc=${G_RC}, value=${v:-none}): $(head -30 "${ARGV_FILE}" | tr '\n' ' ')"
    return
  fi
  if grep -q 'worker_mcp_attached config=mcp-role-developer.resolved.json role=developer' "${G_STDERR}"; then
    pass "journal line worker_mcp_attached config=...developer... on stderr"
  else
    fail "worker_mcp_attached journal line missing: $(cat "${G_STDERR}" 2>/dev/null | grep worker_mcp | head -3)"
  fi
  if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); s=d['mcpServers']; sys.exit(0 if 'repowise' in s and 'codebase-memory-mcp' in s else 1)" "${v}" 2>/dev/null; then
    pass "resolved config is valid JSON carrying both allowlisted servers"
  else
    fail "resolved config invalid or missing servers: ${v}"
  fi
}

# ── T14-02: LEADV2_WORKER_ROLE=critic — critic allowlist file ────────────────
test_02_role_critic() {
  log "T14-02: LEADV2_WORKER_ROLE=critic resolves mcp-role-critic"
  _glm_run "${GLM_SCRIPT}" "LEADV2_WORKER_ROLE=critic"
  local v; v="$(_flag_value --mcp-config)"
  if [[ $(_argc) -eq 1 && "$(basename "${v:-}")" == "mcp-role-critic.resolved.json" ]] \
     && grep -q 'worker_mcp_attached config=mcp-role-critic.resolved.json role=critic' "${G_STDERR}"; then
    pass "critic role picks mcp-role-critic.json + journals it"
  else
    fail "critic role not honoured (value=${v:-none}): $(grep worker_mcp "${G_STDERR}" | head -3)"
  fi
}

# ── T14-03: LEADV2_WORKER_MCP=0 — no flags, spawn still succeeds ─────────────
test_03_killswitch_off() {
  log "T14-03: LEADV2_WORKER_MCP=0 -> no --mcp-config, rc=0, skip journaled"
  _glm_run "${GLM_SCRIPT}" "LEADV2_WORKER_MCP=0"
  if [[ $(_argc) -eq 0 && "${G_RC}" -eq 0 ]] && ! grep -q '^--strict-mcp-config$' "${ARGV_FILE}"; then
    pass "kill-switch=0 restores the pre-T14 spawn line (no MCP flags, rc=0)"
  else
    fail "kill-switch=0 still emits MCP flags (rc=${G_RC})"
  fi
  if grep -q 'worker_mcp_skipped reason=disabled' "${G_STDERR}"; then
    pass "kill-switch=0 journals worker_mcp_skipped reason=disabled"
  else
    fail "worker_mcp_skipped reason=disabled not journaled"
  fi
}

# ── T14-04: allowlist/config dir missing — fail-open + journaled skip ────────
test_04_missing_config_fails_open() {
  log "T14-04: CLAUDE_PLUGIN_ROOT with no config/ -> spawn proceeds WITHOUT flag"
  local empty_root; empty_root="$(mktemp -d "${TMPDIR:-/tmp}/t14-empty-plugin.XXXXXX")"
  CLEANUP_PATHS+=("${empty_root}")
  _glm_run "${GLM_SCRIPT}" "CLAUDE_PLUGIN_ROOT=${empty_root}"
  if [[ $(_argc) -eq 0 && "${G_RC}" -eq 0 ]]; then
    pass "missing config file => spawn proceeds WITHOUT the flag (fail-open, rc=0)"
  else
    fail "missing config should fail open with no flag (rc=${G_RC}, flags=$(_argc))"
  fi
  if grep -q 'worker_mcp_skipped reason=resolve_rc_11' "${G_STDERR}"; then
    pass "missing config journals worker_mcp_skipped reason=resolve_rc_11"
  else
    fail "worker_mcp_skipped reason=resolve_rc_11 not journaled: $(grep worker_mcp "${G_STDERR}" | head -3)"
  fi
}

# ── T14-05: bg path — flags on the detached spawn + journal into progress.log
test_05_bg_path() {
  log "T14-05: bg path attaches flags + journals into <run>/progress.log"
  : > "${ARGV_FILE}"
  local bg_out bg_stderr run_id run_dir i
  bg_out="${FIXTURE}/bg-$$.txt"; bg_stderr="${FIXTURE}/bg-stderr-$$.txt"
  (
    set +e
    export GLM_CLAUDE_BIN="${STUB_BIN}/claude"
    export GLM_SECRETS_FILE="${SECRETS}"
    export GLM_RUNS_DIR="${RUNS_DIR}"
    export GLM_SKIP_QUOTA_GATE=1
    export LEADV2_BURN_GOVERNOR=0
    export TMPDIR="${FIXTURE}"
    export CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}"
    export LEADV2_WORKER_ROLE=critic
    bash "${GLM_SCRIPT}" bg "t14 bg probe mission" --cwd "${REPO}"
  ) > "${bg_out}" 2>"${bg_stderr}"
  run_id="$(tail -1 "${bg_out}" 2>/dev/null | tr -d '[:space:]')"
  run_dir="${RUNS_DIR}/${run_id}"
  for i in $(seq 1 60); do
    [[ -f "${run_dir}/exit_code" ]] && break
    sleep 0.5
  done
  if [[ ! -f "${run_dir}/exit_code" ]]; then
    fail "bg run never finished (run_id=${run_id:-none}); stderr: $(tail -5 "${bg_stderr}" 2>/dev/null)"
    return
  fi
  local v; v="$(_flag_value --mcp-config)"
  if [[ $(_argc) -ge 1 && "$(basename "${v:-}")" == "mcp-role-critic.resolved.json" ]]; then
    pass "bg spawn line carries --mcp-config <critic resolved file>"
  else
    fail "bg spawn missing --mcp-config (value=${v:-none})"
  fi
  if grep -q 'worker_mcp_attached config=mcp-role-critic.resolved.json' "${run_dir}/progress.log" 2>/dev/null; then
    pass "bg path journals worker_mcp_attached into progress.log"
  else
    fail "bg path journal line missing from progress.log"
  fi
}

# ── T14-NC: negative control — mutation INSIDE worker_mcp_resolve's body ────
# Applied to a SCRATCH COPY of glm-coder.sh. T14-01's pass condition (flag on
# the spawn line) must go RED against the mutant: this proves the suite can
# actually fail, i.e. its green is not theatre.
test_nc_mutation_kills_suite() {
  log "T14-NC: mutation 'return 1' inside worker_mcp_resolve body -> T14-01 must fail"
  local mutant="${FIXTURE}/glm-mutant.sh"
  sed 's|^worker_mcp_resolve() { # \$1=project root (worker cwd) \$2=journal file \$3=out dir for resolved json$|worker_mcp_resolve() { # mutated for negative control\n  return 1|' \
    "${GLM_SCRIPT}" > "${mutant}"
  if ! grep -q 'mutated for negative control' "${mutant}"; then
    fail "negative control mutation did not apply (anchor line drifted) — suite invalid"
    return
  fi
  _glm_run "${mutant}"
  if [[ $(_argc) -eq 0 ]]; then
    pass "mutant suppresses the flag -> T14-01 assertions would be RED (control kills)"
  else
    fail "mutant still emits --mcp-config — negative control does NOT kill the suite"
  fi
}

# ── T14-06: review missions request the critic allowlist ────────────────────
test_06_review_run_uses_critic() {
  log "T14-06: leadv2-review-run.sh glm arm sets LEADV2_WORKER_ROLE=critic"
  local line
  line="$(grep -n 'LEADV2_WORKER_ROLE=critic' "${PLUGIN_SCRIPTS}/leadv2-review-run.sh" | head -1)"
  if [[ -n "${line}" ]] && grep -A1 'LEADV2_WORKER_ROLE=critic' "${PLUGIN_SCRIPTS}/leadv2-review-run.sh" | grep -q 'run "@'; then
    pass "glm review spawn is prefixed with LEADV2_WORKER_ROLE=critic (${line%%:*})"
  else
    fail "review-run glm arm does not set LEADV2_WORKER_ROLE=critic"
  fi
}

test_01_default_developer
test_02_role_critic
test_03_killswitch_off
test_04_missing_config_fails_open
test_05_bg_path
test_06_review_run_uses_critic
test_nc_mutation_kills_suite

printf -- '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
if [[ "${FAIL}" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]+"${ERRORS[@]}"}"
  exit 1
fi
exit 0
