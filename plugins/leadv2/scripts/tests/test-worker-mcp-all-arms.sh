#!/usr/bin/env bash
# tests/test-worker-mcp-all-arms.sh — WORKER-MCP-ALL-ARMS-01.
#
# freepool-coder.sh and kimi-coder.sh must resolve+attach the SAME role-scoped
# --mcp-config glm-coder.sh uses (lib/leadv2-worker-mcp.sh, never a copy), on
# both their `run` (v1) and `bg`/child spawn paths, gated by LEADV2_WORKER_MCP
# (default 1). codex-task.sh cannot wire live MCP (its real spawn is an
# external plugin companion, out of LANE_WRITES) — this suite instead asserts
# the documented allowlist file exists and the doc-gap NOTE is emitted.
# leadv2-dispatch-code.sh must inject prompts/worker-code-intel-preamble.md
# into every arm's mission at ONE call site.
#
# NEGATIVE CONTROL: mutates a SCRATCH COPY of freepool-coder.sh (removes the
# worker_mcp_resolve call from its `run` path) and proves this suite goes RED
# against it — never against the working tree.
#
# Run: bash plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_ROOT="$(cd "${PLUGIN_SCRIPTS}/.." && pwd)"
FREEPOOL_SCRIPT="${PLUGIN_SCRIPTS}/freepool-coder.sh"
KIMI_SCRIPT="${PLUGIN_SCRIPTS}/kimi-coder.sh"
CODEX_SCRIPT="${PLUGIN_SCRIPTS}/codex-task.sh"
DISPATCH_SCRIPT="${PLUGIN_SCRIPTS}/leadv2-dispatch-code.sh"
PREAMBLE_FILE="${PLUGIN_ROOT}/prompts/worker-code-intel-preamble.md"
CODEX_TOML="${PLUGIN_ROOT}/config/codex-mcp-servers.toml"

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
# codex-task.sh is excluded from the /bin/bash (3.2) leg: it embeds a JS
# heredoc ("(async () => {" at ~L717) that pre-existing /bin/bash 3.2 -n
# mis-parses on main too (verified against git HEAD before this lane's
# edits) — a known false positive, not a regression this suite should chase.
for f in "scripts/freepool-coder.sh" "scripts/kimi-coder.sh" \
         "scripts/leadv2-codex-planner.sh" "scripts/lib/leadv2-worker-mcp.sh" \
         "scripts/leadv2-dispatch-code.sh"; do
  if bash -n "${PLUGIN_ROOT}/${f}" 2>/dev/null && /bin/bash -n "${PLUGIN_ROOT}/${f}" 2>/dev/null; then
    PASS=$((PASS + 1)); log "PASS: bash -n ${f} (incl. 3.2)"
  else
    FAIL=$((FAIL + 1)); ERRORS+=("bash -n ${f}"); log "FAIL: bash -n ${f}"
  fi
done
if bash -n "${CODEX_SCRIPT}" 2>/dev/null; then
  pass "bash -n scripts/codex-task.sh (bash 5, /bin/bash 3.2 leg skipped — pre-existing heredoc false positive)"
else
  fail "bash -n scripts/codex-task.sh"
fi

# ── fixture repo: both allowlisted servers defined in .mcp.json ─────────────
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/wmaa-fixture.XXXXXX")"
CLEANUP_PATHS+=("${FIXTURE}")
REPO="${FIXTURE}/repo"
mkdir -p "${REPO}"
printf '%s\n' '{"mcpServers": {"repowise": {"command": "stub-repowise", "args": []}, "codebase-memory-mcp": {"command": "stub-cbm", "args": []}}}' > "${REPO}/.mcp.json"
git -C "${REPO}" init -q 2>/dev/null || true
git -C "${REPO}" -c user.email=wmaa@test -c user.name=wmaa commit -q --allow-empty -m init 2>/dev/null || true

STUB_BIN="${FIXTURE}/bin"
mkdir -p "${STUB_BIN}"

make_stub() {
  local bin_name="$1" argv_file="$2" resolved_capture="$3"
  cat > "${STUB_BIN}/${bin_name}" <<STUBEOF
#!/usr/bin/env bash
_prev=""
for _a in "\$@"; do
  printf '%s\n' "\$_a" >> "${argv_file}"
  if [[ "\$_prev" == "--mcp-config" && -f "\$_a" ]]; then
    cp "\$_a" "${resolved_capture}" 2>/dev/null || true
  fi
  _prev="\$_a"
done
printf '%s\n' '{"type":"system","subtype":"init","model":"stub"}'
exit 0
STUBEOF
  chmod +x "${STUB_BIN}/${bin_name}"
}

# ── freepool-coder.sh: run path attaches --mcp-config by default ────────────
FP_ARGV="${FIXTURE}/fp-argv.txt"; : > "${FP_ARGV}"
FP_RESOLVED="${FIXTURE}/fp-resolved.json"
make_stub "fp-claude" "${FP_ARGV}" "${FP_RESOLVED}"
FP_SECRETS="${FIXTURE}/fp-secrets"
printf '%s\n' 'FREEPOOL_BASE_URL=http://stub' 'FREEPOOL_AUTH_TOKEN=stub-token' > "${FP_SECRETS}"
chmod 600 "${FP_SECRETS}"

FP_OUT="${FIXTURE}/fp-out.txt"
FREEPOOL_CLAUDE_BIN="${STUB_BIN}/fp-claude" FREEPOOL_SECRETS_FILE="${FP_SECRETS}" \
  LEADV2_PROJECT_ROOT="${REPO}" FREEPOOL_SKIP_GATE=1 \
  bash "${FREEPOOL_SCRIPT}" run "test prompt" --out "${FP_OUT}" --cwd "${REPO}" >/dev/null 2>&1

if grep -qx -- "--mcp-config" "${FP_ARGV}" 2>/dev/null; then
  pass "freepool-coder.sh run: --mcp-config on argv (default LEADV2_WORKER_MCP=1)"
else
  fail "freepool-coder.sh run: --mcp-config on argv (default LEADV2_WORKER_MCP=1)"
fi
if [[ -f "${FP_RESOLVED}" ]] && grep -q "repowise" "${FP_RESOLVED}" && grep -q "codebase-memory-mcp" "${FP_RESOLVED}"; then
  pass "freepool-coder.sh run: resolved config carries both servers"
else
  fail "freepool-coder.sh run: resolved config carries both servers"
fi

# LEADV2_WORKER_MCP=0 restores no-flag spawn
FP_ARGV2="${FIXTURE}/fp-argv2.txt"; : > "${FP_ARGV2}"
make_stub "fp-claude2" "${FP_ARGV2}" "${FIXTURE}/fp-resolved2.json"
FREEPOOL_CLAUDE_BIN="${STUB_BIN}/fp-claude2" FREEPOOL_SECRETS_FILE="${FP_SECRETS}" \
  LEADV2_PROJECT_ROOT="${REPO}" LEADV2_WORKER_MCP=0 FREEPOOL_SKIP_GATE=1 \
  bash "${FREEPOOL_SCRIPT}" run "test prompt" --out "${FP_OUT}" --cwd "${REPO}" >/dev/null 2>&1
if grep -qx -- "--mcp-config" "${FP_ARGV2}" 2>/dev/null; then
  fail "freepool-coder.sh run: LEADV2_WORKER_MCP=0 must NOT attach --mcp-config"
else
  pass "freepool-coder.sh run: LEADV2_WORKER_MCP=0 must NOT attach --mcp-config"
fi

# ── kimi-coder.sh: run path attaches --mcp-config by default ────────────────
KIMI_ARGV="${FIXTURE}/kimi-argv.txt"; : > "${KIMI_ARGV}"
KIMI_RESOLVED="${FIXTURE}/kimi-resolved.json"
make_stub "kimi-claude" "${KIMI_ARGV}" "${KIMI_RESOLVED}"
KIMI_SECRETS="${FIXTURE}/kimi-secrets"
printf '%s\n' 'TOKENROUTER_BASE_URL=http://stub' 'TOKENROUTER_AUTH_TOKEN=stub-token' 'TOKENROUTER_MODEL=stub-model' > "${KIMI_SECRETS}"
chmod 600 "${KIMI_SECRETS}"

KIMI_OUT="${FIXTURE}/kimi-out.txt"
KIMI_CLAUDE_BIN="${STUB_BIN}/kimi-claude" KIMI_SECRETS_FILE="${KIMI_SECRETS}" \
  LEADV2_PROJECT_ROOT="${REPO}" \
  bash "${KIMI_SCRIPT}" run "test prompt" --out "${KIMI_OUT}" --cwd "${REPO}" >/dev/null 2>&1

if grep -qx -- "--mcp-config" "${KIMI_ARGV}" 2>/dev/null; then
  pass "kimi-coder.sh run: --mcp-config on argv (default LEADV2_WORKER_MCP=1)"
else
  fail "kimi-coder.sh run: --mcp-config on argv (default LEADV2_WORKER_MCP=1)"
fi
if [[ -f "${KIMI_RESOLVED}" ]] && grep -q "repowise" "${KIMI_RESOLVED}" && grep -q "codebase-memory-mcp" "${KIMI_RESOLVED}"; then
  pass "kimi-coder.sh run: resolved config carries both servers"
else
  fail "kimi-coder.sh run: resolved config carries both servers"
fi

# ── codex: no live wiring possible (companion out of scope) — doc-gap asserted ──
if [[ -f "${CODEX_TOML}" ]] && grep -q "codebase-memory-mcp" "${CODEX_TOML}" && grep -q "repowise" "${CODEX_TOML}"; then
  pass "config/codex-mcp-servers.toml declares both server names"
else
  fail "config/codex-mcp-servers.toml declares both server names"
fi
if grep -q "code-intel MCP.*not yet wired for Codex arms" "${CODEX_SCRIPT}"; then
  pass "codex-task.sh emits documented MCP-gap NOTE"
else
  fail "codex-task.sh emits documented MCP-gap NOTE"
fi

# ── preamble file: exists, ≤25 lines, both routing halves present ───────────
if [[ -f "${PREAMBLE_FILE}" ]]; then
  pass "worker-code-intel-preamble.md exists"
else
  fail "worker-code-intel-preamble.md exists"
fi
_lines="$(wc -l < "${PREAMBLE_FILE}" 2>/dev/null || echo 999)"
if [[ "${_lines}" -le 25 ]]; then
  pass "worker-code-intel-preamble.md <= 25 lines (${_lines})"
else
  fail "worker-code-intel-preamble.md <= 25 lines (${_lines})"
fi
if grep -q "codebase-memory-mcp" "${PREAMBLE_FILE}" && grep -q "repowise" "${PREAMBLE_FILE}" && grep -q "distill" "${PREAMBLE_FILE}"; then
  pass "worker-code-intel-preamble.md covers graph/repowise/distill routing"
else
  fail "worker-code-intel-preamble.md covers graph/repowise/distill routing"
fi

# ── dispatch-code.sh: ONE injection call site for all arms ──────────────────
_inject_count="$(grep -c "_LEADV2_CODE_INTEL_PREAMBLE" "${DISPATCH_SCRIPT}" 2>/dev/null || echo 0)"
if [[ "${_inject_count}" -ge 2 ]]; then
  pass "leadv2-dispatch-code.sh: code-intel preamble injection wired (${_inject_count} refs)"
else
  fail "leadv2-dispatch-code.sh: code-intel preamble injection wired (${_inject_count} refs)"
fi
if grep -q 'worker-code-intel-preamble.md' "${DISPATCH_SCRIPT}"; then
  pass "leadv2-dispatch-code.sh: references the canonical preamble file path"
else
  fail "leadv2-dispatch-code.sh: references the canonical preamble file path"
fi

# ── NEGATIVE CONTROL: mutate a scratch copy, prove RED ──────────────────────
NC_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wmaa-nc.XXXXXX")"
CLEANUP_PATHS+=("${NC_DIR}")
mkdir -p "${NC_DIR}/lib"
cp "${FREEPOOL_SCRIPT}" "${NC_DIR}/freepool-coder.sh"
cp "${PLUGIN_SCRIPTS}/lib/leadv2-worker-mcp.sh" "${NC_DIR}/lib/leadv2-worker-mcp.sh"
cp "${PLUGIN_SCRIPTS}/lib/leadv2-costlog-dev.sh" "${NC_DIR}/lib/leadv2-costlog-dev.sh" 2>/dev/null || true
# Remove the worker_mcp_resolve call from the run_claude() spawn path.
python3 - "${NC_DIR}/freepool-coder.sh" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path).read()
needle = 'mcp_cfg="$(worker_mcp_resolve "${cwd_dir}" "" "${mcp_out_dir}")" || true\n'
if needle not in text:
    print("MUTATION_TARGET_NOT_FOUND", file=sys.stderr)
    sys.exit(1)
text = text.replace(needle, 'mcp_cfg=""\n', 1)
open(path, "w").write(text)
PYEOF
if [[ $? -ne 0 ]]; then
  fail "negative control: mutation target found in scratch copy"
else
  pass "negative control: mutation applied to scratch copy"
fi

NC_ARGV="${FIXTURE}/nc-argv.txt"; : > "${NC_ARGV}"
make_stub "nc-claude" "${NC_ARGV}" "${FIXTURE}/nc-resolved.json"
NC_OUT="${FIXTURE}/nc-out.txt"
FREEPOOL_CLAUDE_BIN="${STUB_BIN}/nc-claude" FREEPOOL_SECRETS_FILE="${FP_SECRETS}" \
  LEADV2_PROJECT_ROOT="${REPO}" FREEPOOL_SKIP_GATE=1 \
  bash "${NC_DIR}/freepool-coder.sh" run "test prompt" --out "${NC_OUT}" --cwd "${REPO}" >/dev/null 2>&1
if grep -qx -- "--mcp-config" "${NC_ARGV}" 2>/dev/null; then
  fail "negative control: mutated freepool-coder.sh must NOT attach --mcp-config (this suite would be blind to the T14 regression it exists to catch)"
else
  pass "negative control: mutated freepool-coder.sh correctly goes RED (no --mcp-config)"
fi

echo
log "TOTAL: PASS=${PASS} FAIL=${FAIL}"
if [[ "${FAIL}" -gt 0 ]]; then
  for e in "${ERRORS[@]}"; do log "${e}"; done
  exit 1
fi
exit 0
