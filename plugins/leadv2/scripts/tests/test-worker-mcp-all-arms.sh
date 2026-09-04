#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: codex-task.sh freepool-coder kimi-coder leadv2-codex-planner.sh leadv2-dispatch-code leadv2-worker-mcp.sh
# tests/test-worker-mcp-all-arms.sh — WORKER-MCP-ALL-ARMS-01.
#
# freepool-coder.sh and kimi-coder.sh must resolve+attach the SAME role-scoped
# --mcp-config glm-coder.sh uses (lib/leadv2-worker-mcp.sh, never a copy),
# gated by LEADV2_WORKER_MCP (default 1). Exact coverage, one case per claim:
#
#   - freepool `run` (v1) path: --mcp-config + resolved servers on the real
#     spawn (stub claude binary), LEADV2_WORKER_MCP=0 restores no-flag spawn.
#   - freepool `bg` path: the REAL bg -> __supervise -> __run_child chain,
#     invoked via `freepool-coder.sh bg` exactly as the dispatcher does, with
#     the transport faked one level lower (stub claude binary dumps argv+env;
#     no network). Asserts --mcp-config/--strict-mcp-config on the child argv,
#     the role-resolved server list, and the transport env.
#   - kimi `run` and `bg` paths: same coverage as freepool, PLUS the R3
#     journal-append case: the stream tee must APPEND to journal.jsonl so the
#     worker_mcp_attached record written before the spawn survives (round-2
#     reviewer H1: bare tee truncated it).
#   - R3 preamble gate (reviewer H2): the dispatcher injects the code-intel
#     preamble ONLY for arms whose MCP attach will succeed. lib's
#     worker_mcp_preamble_for_arm() is exercised behaviourally: attached ->
#     preamble text, LEADV2_WORKER_MCP=0 / fail-open / codex / sonnet default
#     -> nothing (R4 finding 1: every fail-open branch still spawns with the
#     FULL default MCP set, never zero, so a "code-intel MCP unavailable"
#     note there was an inverted claim -- deleted, not just reworded), sonnet
#     SLIM_MCP=1 -> preamble. dispatch-code.sh is asserted to call the gate,
#     to contain NO unconditional-injection marker, AND (R4 finding 2) the
#     dispatcher's real mission-building path is exercised end-to-end via
#     LEADV2_DISPATCH_SOURCE_ONLY=1 so a deleted `mission="${_ci_txt}"...`
#     line is caught, not just the presence of the gate call.
#   - NEGATIVE CONTROLS: scratch-copy mutations (a) freepool `run` wiring,
#     (b) freepool cmd_run_child (bg) wiring, (c) kimi cmd_run_child (bg)
#     wiring, (d) kimi bg tee -a dropped (round-2 H1), (e) dispatch preamble
#     gate replaced by unconditional injection (round-2 H2) — each proven to
#     be caught by this suite (reviewer round-1: the bg wiring could be
#     deleted with the suite staying green).
#
# codex-task.sh: live MCP wiring is NOT asserted because it is NOT possible
# in-repo — the real spawn goes through node codex-companion.mjs (openai-codex
# plugin cache, outside this repo and outside LANE_WRITES), which has no
# mcp_servers/-c passthrough (probed 2026-09-02: companion 1.0.4, 1027 lines,
# zero "mcp" occurrences; it spawns its own task-worker with fixed argv).
# This suite asserts only the documented allowlist toml + the doc-gap NOTE —
# no coverage claim beyond that.
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
  LEADV2_PROJECT_ROOT="${REPO}" KIMI_SKIP_LAUNCH_PROBE=1 \
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

# ── bg path helpers: REAL bg → __supervise → __run_child, transport faked ────
# The reviewer (round 1) proved the `run`-path-only suite stays green when the
# whole cmd_run_child MCP wiring is deleted — and bg is the ONLY path the
# dispatcher uses. These cases invoke `bg` itself and let the detached
# supervisor spawn the real __run_child, which execs a stub binary that dumps
# its argv + env to files. No network: the "provider" is the stub.

wait_finalized() { # <run_dir> — poll for the terminal sentinel, bounded
  local run_dir="$1" deadline=$(( $(date +%s) + 120 ))
  while (( $(date +%s) < deadline )); do
    [[ -f "${run_dir}/.finalized" ]] && return 0
    sleep 1
  done
  return 1
}

make_bg_stub() { # <bin-name> <argv-file> <env-file> <resolved-capture>
  local bin_name="$1" argv_file="$2" env_file="$3" resolved_capture="$4"
  cat > "${STUB_BIN}/${bin_name}" <<STUBEOF
#!/usr/bin/env bash
_prev=""
for _a in "\$@"; do
  printf 'ARGV: %s\n' "\$_a" >> "${argv_file}"
  if [[ "\$_prev" == "--mcp-config" && -f "\$_a" ]]; then
    cp "\$_a" "${resolved_capture}" 2>/dev/null || true
  fi
  _prev="\$_a"
done
env | sort >> "${env_file}"
printf '%s\n' '{"type":"system","subtype":"init","model":"stub"}'
exit 0
STUBEOF
  chmod +x "${STUB_BIN}/${bin_name}"
}

make_bg_repo() { # <name> — fresh git repo with both servers in .mcp.json (unique per bg case: the launcher locks per-cwd)
  local r="${FIXTURE}/$1"
  mkdir -p "${r}"
  printf '%s\n' '{"mcpServers": {"repowise": {"command": "stub-repowise", "args": []}, "codebase-memory-mcp": {"command": "stub-cbm", "args": []}}}' > "${r}/.mcp.json"
  git -C "${r}" init -q 2>/dev/null || true
  git -C "${r}" -c user.email=wmaa@test -c user.name=wmaa commit -q --allow-empty -m init 2>/dev/null || true
  printf '%s' "${r}"
}

bg_mission() { # <prompt-file> — dispatcher-equivalent prompt: preamble + mission
  { cat "${PREAMBLE_FILE}"; printf '\nBG-PROBE mission: verify the bg child spawn wiring.\n'; } > "$1"
}

# ── freepool bg: bg → __supervise → cmd_run_child attaches --mcp-config ─────
FPBG_REPO="$(make_bg_repo fp-bg-repo)"
FPBG_RUNS="${FIXTURE}/fp-bg-runs"
FPBG_ARGV="${FIXTURE}/fp-bg-argv.txt"; : > "${FPBG_ARGV}"
FPBG_ENV="${FIXTURE}/fp-bg-env.txt";  : > "${FPBG_ENV}"
FPBG_RESOLVED="${FIXTURE}/fp-bg-resolved.json"
make_bg_stub "fp-bg-claude" "${FPBG_ARGV}" "${FPBG_ENV}" "${FPBG_RESOLVED}"
FPBG_PROMPT="${FIXTURE}/fp-bg-prompt.txt"; bg_mission "${FPBG_PROMPT}"

FPBG_SECRETS="${FIXTURE}/fp-bg-secrets"
printf '%s\n' 'FREEPOOL_AUTH_TOKEN=stub-token' > "${FPBG_SECRETS}"
chmod 600 "${FPBG_SECRETS}"

FPBG_RUN_ID="$(env FREEPOOL_CLAUDE_BIN="${STUB_BIN}/fp-bg-claude" \
  FREEPOOL_SECRETS_FILE="${FPBG_SECRETS}" FREEPOOL_RUNS_DIR="${FPBG_RUNS}" \
  FREEPOOL_PROXY_URL="http://stub" \
  LEADV2_PROJECT_ROOT="${FPBG_REPO}" FREEPOOL_SKIP_GATE=1 FREEPOOL_TEST_NO_REDACT=1 \
  bash "${FREEPOOL_SCRIPT}" bg "@${FPBG_PROMPT}" --cwd "${FPBG_REPO}" --timeout 60 2>/dev/null | tail -1)"
FPBG_RUN_DIR="${FPBG_RUNS}/${FPBG_RUN_ID}"

if [[ -n "${FPBG_RUN_ID}" ]] && wait_finalized "${FPBG_RUN_DIR}"; then
  pass "freepool bg: run finalized (run_id=${FPBG_RUN_ID})"
else
  fail "freepool bg: run finalized within 120s (run_id=${FPBG_RUN_ID:-none}; supervisor.log: $(tail -3 "${FPBG_RUN_DIR}/supervisor.log" 2>/dev/null | tr '\n' '|'))"
fi
if grep -qx -- "ARGV: --mcp-config" "${FPBG_ARGV}" 2>/dev/null && grep -qx -- "ARGV: --strict-mcp-config" "${FPBG_ARGV}" 2>/dev/null; then
  pass "freepool bg: cmd_run_child puts --strict-mcp-config --mcp-config on the child argv"
else
  fail "freepool bg: cmd_run_child puts --strict-mcp-config --mcp-config on the child argv"
fi
if [[ -f "${FPBG_RESOLVED}" ]] && grep -q "repowise" "${FPBG_RESOLVED}" && grep -q "codebase-memory-mcp" "${FPBG_RESOLVED}"; then
  pass "freepool bg: role-resolved config with both servers reaches the child (--mcp-config value)"
else
  fail "freepool bg: role-resolved config with both servers reaches the child (--mcp-config value)"
fi
if grep -q "^ANTHROPIC_BASE_URL=http://stub$" "${FPBG_ENV}" 2>/dev/null && grep -q "^ANTHROPIC_AUTH_TOKEN=stub-token$" "${FPBG_ENV}" 2>/dev/null && grep -q "^FREEPOOL_ROLE=" "${FPBG_ENV}" 2>/dev/null; then
  pass "freepool bg: child env carries the transport (BASE_URL/AUTH_TOKEN) + FREEPOOL_ROLE"
else
  fail "freepool bg: child env carries the transport (BASE_URL/AUTH_TOKEN) + FREEPOOL_ROLE"
fi
if grep -q "CODE-INTEL ROUTING" "${FPBG_ARGV}" 2>/dev/null && grep -q "BG-PROBE mission" "${FPBG_ARGV}" 2>/dev/null; then
  pass "freepool bg: code-intel preamble + mission both inside the child -p prompt"
else
  fail "freepool bg: code-intel preamble + mission both inside the child -p prompt"
fi

# ── kimi bg: bg → __supervise → cmd_run_child attaches --mcp-config ─────────
KMBG_REPO="$(make_bg_repo kimi-bg-repo)"
KMBG_RUNS="${FIXTURE}/kimi-bg-runs"
KMBG_ARGV="${FIXTURE}/kimi-bg-argv.txt"; : > "${KMBG_ARGV}"
KMBG_ENV="${FIXTURE}/kimi-bg-env.txt";  : > "${KMBG_ENV}"
KMBG_RESOLVED="${FIXTURE}/kimi-bg-resolved.json"
make_bg_stub "kimi-bg-claude" "${KMBG_ARGV}" "${KMBG_ENV}" "${KMBG_RESOLVED}"
KMBG_PROMPT="${FIXTURE}/kimi-bg-prompt.txt"; bg_mission "${KMBG_PROMPT}"

KMBG_RUN_ID="$(KIMI_CLAUDE_BIN="${STUB_BIN}/kimi-bg-claude" \
  KIMI_SECRETS_FILE="${KIMI_SECRETS}" KIMI_RUNS_DIR="${KMBG_RUNS}" \
  LEADV2_PROJECT_ROOT="${KMBG_REPO}" KIMI_SKIP_LAUNCH_PROBE=1 \
  bash "${KIMI_SCRIPT}" bg "@${KMBG_PROMPT}" --cwd "${KMBG_REPO}" --timeout 60 2>/dev/null | tail -1)"
KMBG_RUN_DIR="${KMBG_RUNS}/${KMBG_RUN_ID}"

if [[ -n "${KMBG_RUN_ID}" ]] && wait_finalized "${KMBG_RUN_DIR}"; then
  pass "kimi bg: run finalized (run_id=${KMBG_RUN_ID})"
else
  fail "kimi bg: run finalized within 120s (run_id=${KMBG_RUN_ID:-none}; supervisor.log: $(tail -3 "${KMBG_RUN_DIR}/supervisor.log" 2>/dev/null | tr '\n' '|'))"
fi
if grep -qx -- "ARGV: --mcp-config" "${KMBG_ARGV}" 2>/dev/null && grep -qx -- "ARGV: --strict-mcp-config" "${KMBG_ARGV}" 2>/dev/null; then
  pass "kimi bg: cmd_run_child puts --strict-mcp-config --mcp-config on the child argv"
else
  fail "kimi bg: cmd_run_child puts --strict-mcp-config --mcp-config on the child argv"
fi
if [[ -f "${KMBG_RESOLVED}" ]] && grep -q "repowise" "${KMBG_RESOLVED}" && grep -q "codebase-memory-mcp" "${KMBG_RESOLVED}"; then
  pass "kimi bg: role-resolved config with both servers reaches the child (--mcp-config value)"
else
  fail "kimi bg: role-resolved config with both servers reaches the child (--mcp-config value)"
fi
if grep -q "^ANTHROPIC_BASE_URL=http://stub$" "${KMBG_ENV}" 2>/dev/null && grep -q "^ANTHROPIC_AUTH_TOKEN=stub-token$" "${KMBG_ENV}" 2>/dev/null; then
  pass "kimi bg: child env carries the transport (BASE_URL/AUTH_TOKEN)"
else
  fail "kimi bg: child env carries the transport (BASE_URL/AUTH_TOKEN)"
fi
if grep -q "CODE-INTEL ROUTING" "${KMBG_ARGV}" 2>/dev/null && grep -q "BG-PROBE mission" "${KMBG_ARGV}" 2>/dev/null; then
  pass "kimi bg: code-intel preamble + mission both inside the child -p prompt"
else
  fail "kimi bg: code-intel preamble + mission both inside the child -p prompt"
fi

# ── R3 (reviewer H1): journal.jsonl must APPEND — two consecutive writes ────
# Write #1: worker_mcp_resolve() journals worker_mcp_attached BEFORE the spawn
# (kimi-coder.sh cmd_run_child). Write #2: the stream tee starts writing AFTER
# it. A bare tee truncates the file and destroys write #1 — both records must
# be present after the run for the append to be proven.
if grep -q "worker_mcp_attached" "${KMBG_RUN_DIR}/journal.jsonl" 2>/dev/null \
   && grep -q '"type":"system"' "${KMBG_RUN_DIR}/journal.jsonl" 2>/dev/null; then
  pass "kimi bg: journal keeps BOTH the pre-spawn worker_mcp_attached record and the stream (tee -a)"
else
  fail "kimi bg: journal keeps BOTH the pre-spawn worker_mcp_attached record and the stream (tee -a); got: $(head -3 "${KMBG_RUN_DIR}/journal.jsonl" 2>/dev/null | tr '\n' '|')"
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

# ── R3 (reviewer H2): the preamble gate — behavioural, lib level ────────────
# worker_mcp_preamble_for_arm() is the dispatcher's ONLY injection decision.
# It is exercised here from behaviour: what it prints and what rc it returns.
PREAMBLE_LIB="${PLUGIN_SCRIPTS}/lib/leadv2-worker-mcp.sh"
GATE_REPO="$(make_bg_repo wmaa-gate-repo)"   # .mcp.json carries both servers
NO_MCP_DIR="${FIXTURE}/wmaa-no-mcp-home"; mkdir -p "${NO_MCP_DIR}"

# gate_case_run <label> <expected-rc> <expect-preamble|expect-empty> <arm> <root> [env...]
gate_case_run() {
  local label="$1" want_rc="$2" want_kind="$3" arm="$4" root="$5"
  shift 5
  local res rc out
  res="$(env "$@" bash -c '
    source "$1"; shift
    out="$(worker_mcp_preamble_for_arm "$@")"; rc=$?
    printf "%s" "${out}"; printf "\n--RC=%s" "${rc}"
  ' _ "${PREAMBLE_LIB}" "${arm}" "${root}" 2>/dev/null)"
  rc="${res##*--RC=}"
  out="${res%"--RC=${rc}"}"
  case "${want_kind}" in
    expect-preamble)
      if [[ "${rc}" == "${want_rc}" ]] && printf '%s' "${out}" | grep -q "CODE-INTEL ROUTING"; then
        pass "preamble gate: ${label} -> rc=${rc} + preamble text"
      else
        fail "preamble gate: ${label} -> rc=${rc} (want ${want_rc}) + preamble text (got: $(printf '%s' "${out}" | head -1))"
      fi ;;
    expect-empty)
      if [[ "${rc}" == "${want_rc}" ]] && [[ -z "${out//[$'\n']/}" ]]; then
        pass "preamble gate: ${label} -> rc=${rc} + empty output"
      else
        fail "preamble gate: ${label} -> rc=${rc} (want ${want_rc}) + empty output (got: $(printf '%s' "${out}" | head -1))"
      fi ;;
  esac
}

gate_case_run "kimi attached (default gate)"            0 expect-preamble kimi    "${GATE_REPO}"
gate_case_run "freepool attached (default gate)"        0 expect-preamble freepool "${GATE_REPO}"
gate_case_run "glm attached (default gate)"             0 expect-preamble glm     "${GATE_REPO}"
gate_case_run "kimi LEADV2_WORKER_MCP=0"                3 expect-empty    kimi    "${GATE_REPO}" "LEADV2_WORKER_MCP=0"
gate_case_run "kimi fail-open (nothing resolvable)"     3 expect-empty    kimi    "${NO_MCP_DIR}" "HOME=${NO_MCP_DIR}"
gate_case_run "codex unwired"                           4 expect-empty    codex   "${GATE_REPO}"
gate_case_run "sonnet default (no SLIM_MCP)"            3 expect-empty    sonnet  "${GATE_REPO}"
gate_case_run "sonnet LEADV2_SUBSESSION_SLIM_MCP=1"     0 expect-preamble sonnet  "${GATE_REPO}" "LEADV2_SUBSESSION_SLIM_MCP=1"

# WORKER-MCP-ALL-ARMS-01 R4 (reviewer finding 1): every rc=3 fail-open branch
# actually describes a spawn that still gets no --strict-mcp-config, so the
# child inherits the FULL default MCP set (never zero) -- a "code-intel MCP
# unavailable" note there was backwards. The fix is silence (rc=3 + empty
# stdout, asserted by the expect-empty rows above); this is the negative
# control proving the false claim cannot silently come back.
_regression_note="$(env HOME="${NO_MCP_DIR}" bash -c '
  source "$1"; shift
  worker_mcp_preamble_for_arm kimi "$2" ""
' _ "${PREAMBLE_LIB}" kimi "${NO_MCP_DIR}" 2>/dev/null)"
if [[ -z "${_regression_note//[$'\n']/}" ]]; then
  pass "preamble gate: fail-open branch stays silent (no inverted 'MCP unavailable' claim)"
else
  fail "preamble gate: fail-open branch printed non-empty text (regression of R4 finding 1: ${_regression_note})"
fi

# ── dispatch-code.sh: gated injection call site, no unconditional marker ────
# Structural by necessity (a real dispatch spawns a live worker); the gate
# FUNCTION itself is behaviour-proven above. Regression marker: the round-2
# unconditional global `_LEADV2_CODE_INTEL_PREAMBLE` must never reappear.
dispatch_gate_check() { # <script-path> -> 0 when the gated call site is present
  grep -q 'worker_mcp_preamble_for_arm "${arm}" "${WORK_ROOT}"' "$1" 2>/dev/null \
    && ! grep -q '_LEADV2_CODE_INTEL_PREAMBLE' "$1" 2>/dev/null
}
if dispatch_gate_check "${DISPATCH_SCRIPT}"; then
  pass "leadv2-dispatch-code.sh: preamble injection is gated by worker_mcp_preamble_for_arm(arm)"
else
  fail "leadv2-dispatch-code.sh: preamble injection is gated by worker_mcp_preamble_for_arm(arm)"
fi
if grep -q '_LEADV2_CODE_INTEL_PREAMBLE' "${DISPATCH_SCRIPT}" 2>/dev/null; then
  fail "leadv2-dispatch-code.sh: unconditional-injection marker _LEADV2_CODE_INTEL_PREAMBLE must stay deleted (round-2 H2 regression)"
else
  pass "leadv2-dispatch-code.sh: unconditional-injection marker _LEADV2_CODE_INTEL_PREAMBLE stays deleted (round-2 H2 regression)"
fi
if grep -q 'worker_mcp_preamble_for_arm' "${DISPATCH_SCRIPT}" 2>/dev/null \
   && grep -q 'lib/leadv2-worker-mcp.sh' "${DISPATCH_SCRIPT}" 2>/dev/null; then
  pass "leadv2-dispatch-code.sh: sources the shared worker-MCP lib (no second resolver)"
else
  fail "leadv2-dispatch-code.sh: sources the shared worker-MCP lib (no second resolver)"
fi

# ── dispatch-code.sh: _spawn_worker_body actually PUTS the preamble text in ──
# the mission the child receives -- not just "calls the gate function". R4
# finding 2: the two greps above pass even if the ONE line that folds
# `_ci_txt` into `mission` (`[[ -z "${_ci_txt}" ]] || mission="${_ci_txt}"...`)
# is deleted, because that line names neither `worker_mcp_preamble_for_arm`
# nor `_LEADV2_CODE_INTEL_PREAMBLE`. This drives `_spawn_worker_body` itself
# (LEADV2_DISPATCH_SOURCE_ONLY=1 sources the real dispatcher, same technique
# test-mission-writeset.sh uses for architect_prepass) with a stub kimi
# launcher that captures the exact `mission` argv `bg` receives, so the
# assertion is on what the child would actually be handed, not on grep hits.
WMB_STUB="${STUB_BIN}/wmb-kimi"
cat > "${WMB_STUB}" <<'STUBEOF'
#!/usr/bin/env bash
case "$1" in
  bg)
    printf '%s' "$2" > "${WMB_MISSION_CAPTURE}"
    printf '%s\n' "${WMB_HANDLE}${WMB_HANDLE}"
    exit 0
    ;;
  status) exit 0 ;;
  *) exit 1 ;;
esac
STUBEOF
chmod +x "${WMB_STUB}"

_run_spawn_worker_mission() { # <dispatch_script> <work_root> <mission_capture_file> -> stdout unused; rc=_spawn_worker_body's rc
  local dsh="$1" root="$2" capture="$3" errf
  errf="$(mktemp "${TMPDIR:-/tmp}/wmaa-wmb-err.XXXXXX")"
  : > "${capture}"
  ( cd "${root}" && \
    LEADV2_DISPATCH_SOURCE_ONLY=1 PROJECT_ROOT="${root}" CLAUDE_PROJECT_ROOT="${root}" \
    LEADV2_DISPATCH_KIMI_BIN="${WMB_STUB}" WMB_MISSION_CAPTURE="${capture}" WMB_HANDLE="wmbh8" \
    bash -c '
      set -uo pipefail
      source "$1"
      _spawn_worker_body kimi "WMB-MISSION-BODY-MARKER" "wiretest8" "$2"
    ' _ "${dsh}" "${errf}" )
  local rc=$?
  rm -f "${errf}" 2>/dev/null || true
  return ${rc}
}

WMB_REPO="$(make_bg_repo wmaa-wmb-repo)"
WMB_CAPTURE="${FIXTURE}/wmb-mission-capture.txt"
_run_spawn_worker_mission "${DISPATCH_SCRIPT}" "${WMB_REPO}" "${WMB_CAPTURE}"
WMB_RC=$?
if [[ ${WMB_RC} -eq 0 ]] && grep -q "CODE-INTEL ROUTING" "${WMB_CAPTURE}" 2>/dev/null \
   && grep -q "WMB-MISSION-BODY-MARKER" "${WMB_CAPTURE}" 2>/dev/null; then
  pass "leadv2-dispatch-code.sh: _spawn_worker_body puts the resolved preamble text INSIDE the mission the child bg call receives"
else
  fail "leadv2-dispatch-code.sh: _spawn_worker_body puts the resolved preamble text INSIDE the mission the child bg call receives (rc=${WMB_RC}, captured: $(head -c 200 "${WMB_CAPTURE}" 2>/dev/null))"
fi

# ── NEGATIVE CONTROL (f): delete the `mission="${_ci_txt}"...` fold line ────
# in a scratch dispatch-code.sh copy and prove the case above goes RED. This
# is the exact R4 finding 2 regression: the structural dispatch_gate_check
# above stays green on this mutant (neither grep target is touched), but the
# real mission text now never carries the preamble.
WMB_NC_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wmaa-wmbnc.XXXXXX")"
CLEANUP_PATHS+=("${WMB_NC_DIR}")
# Copy the WHOLE scripts tree (not just the one file) so the mutant still
# finds its own lib/leadv2-worker-mcp.sh sibling -- otherwise a missing-lib
# side effect could mask whether the deleted line is really what breaks it.
cp -pR "${PLUGIN_SCRIPTS}" "${WMB_NC_DIR}/scripts"
WMB_NC_SCRIPT="${WMB_NC_DIR}/scripts/leadv2-dispatch-code.sh"
python3 - "${WMB_NC_SCRIPT}" <<'PYMUT'
import sys
path = sys.argv[1]
text = open(path).read()
needle = '  [[ -z "${_ci_txt}" ]] || mission="${_ci_txt}"$\'\\n\\n\'"${mission}"\n'
if needle not in text:
    print("MUTATION_TARGET_NOT_FOUND", file=sys.stderr)
    sys.exit(1)
open(path, "w").write(text.replace(needle, '', 1))
PYMUT
if [[ $? -ne 0 ]]; then
  fail "negative control (mission fold): mutation target found in scratch copy"
else
  if dispatch_gate_check "${WMB_NC_SCRIPT}"; then
    log "negative control (mission fold): structural dispatch_gate_check still PASSES on the mutant, as predicted (R4 finding 2) -- the behavioural case below must be the one that catches it"
  else
    fail "negative control (mission fold): structural dispatch_gate_check unexpectedly went red on this mutant -- test setup drifted from the finding's exact shape"
  fi
  WMB_NC_CAPTURE="${FIXTURE}/wmb-nc-mission-capture.txt"
  _run_spawn_worker_mission "${WMB_NC_SCRIPT}" "${WMB_REPO}" "${WMB_NC_CAPTURE}"
  WMB_NC_RC=$?
  if [[ ${WMB_NC_RC} -eq 0 ]] && grep -q "CODE-INTEL ROUTING" "${WMB_NC_CAPTURE}" 2>/dev/null; then
    fail "negative control (mission fold): mutated dispatcher still put the preamble in the mission -- suite would be blind to the R4 finding 2 regression"
  else
    pass "negative control (mission fold): mutated dispatcher goes RED -- preamble text absent from the mission the child receives (mutation caught)"
  fi
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

# ── NEGATIVE CONTROL (bg): mutate cmd_run_child in scratch copies ────────────
# Reviewer's exact round-1 mutation, now applied to the path that actually
# runs: empty out mcp_cfg in cmd_run_child (the resolve + argv-append wiring)
# and prove the bg cases above would catch it — the mutated copy must spawn
# with NO --mcp-config.
bg_negative_control() { # <script-path> <needle> <label> <stub-bin> <secrets> <runs-var-name>
  local script="$1" needle="$2" label="$3" stub_bin="$4" secrets="$5" runs_env="$6"
  local nc_dir argv_f env_f resolved_f repo prompt_f run_id run_dir
  nc_dir="$(mktemp -d "${TMPDIR:-/tmp}/wmaa-ncbg.XXXXXX")"
  CLEANUP_PATHS+=("${nc_dir}")
  cp -pR "${PLUGIN_SCRIPTS}" "${nc_dir}/scripts"
  local script_copy="${nc_dir}/scripts/$(basename "${script}")"
  python3 - "$script_copy" "$needle" <<'PYMUT'
import sys
path, needle = sys.argv[1], sys.argv[2]
text = open(path).read()
if needle not in text:
    print("MUTATION_TARGET_NOT_FOUND", file=sys.stderr)
    sys.exit(1)
open(path, "w").write(text.replace(needle, 'mcp_cfg=""', 1))
PYMUT
  if [[ $? -ne 0 ]]; then
    fail "negative control (${label}): mutation target found"
    return 1
  fi
  argv_f="${FIXTURE}/ncbg-${label}-argv.txt"; : > "${argv_f}"
  env_f="${FIXTURE}/ncbg-${label}-env.txt";  : > "${env_f}"
  resolved_f="${FIXTURE}/ncbg-${label}-resolved.json"
  make_bg_stub "ncbg-${label}" "${argv_f}" "${env_f}" "${resolved_f}"
  repo="$(make_bg_repo "ncbg-${label}-repo")"
  prompt_f="${FIXTURE}/ncbg-${label}-prompt.txt"; bg_mission "${prompt_f}"
  if [[ "${runs_env}" == FREEPOOL_RUNS_DIR ]]; then
    run_id="$(env FREEPOOL_CLAUDE_BIN="${STUB_BIN}/ncbg-${label}" FREEPOOL_SECRETS_FILE="${secrets}" \
      "${runs_env}=${FIXTURE}/ncbg-${label}-runs" FREEPOOL_PROXY_URL="http://stub" \
      LEADV2_PROJECT_ROOT="${repo}" FREEPOOL_SKIP_GATE=1 FREEPOOL_TEST_NO_REDACT=1 \
      bash "${nc_dir}/scripts/$(basename "${script}")" bg "@${prompt_f}" --cwd "${repo}" --timeout 60 2>/dev/null | tail -1)"
  else
    run_id="$(env KIMI_CLAUDE_BIN="${STUB_BIN}/ncbg-${label}" KIMI_SECRETS_FILE="${secrets}" \
      "${runs_env}=${FIXTURE}/ncbg-${label}-runs" LEADV2_PROJECT_ROOT="${repo}" \
      KIMI_SKIP_LAUNCH_PROBE=1 \
      bash "${nc_dir}/scripts/$(basename "${script}")" bg "@${prompt_f}" --cwd "${repo}" --timeout 60 2>/dev/null | tail -1)"
  fi
  run_dir="${FIXTURE}/ncbg-${label}-runs/${run_id}"
  if [[ -n "${run_id}" ]] && wait_finalized "${run_dir}"; then
    pass "negative control (${label}): mutated bg run finalized"
  else
    fail "negative control (${label}): mutated bg run finalized"
  fi
  if grep -qx -- "ARGV: --mcp-config" "${argv_f}" 2>/dev/null; then
    fail "negative control (${label}): mutated cmd_run_child must NOT attach --mcp-config (suite would be blind to the exact round-1 regression)"
  else
    pass "negative control (${label}): mutated cmd_run_child goes RED (no --mcp-config reaches the child)"
  fi
}

FP_CHILD_NEEDLE='mcp_cfg="$(worker_mcp_resolve "${cwd_dir}" "${run_dir}/journal.jsonl" "${run_dir}")" || true'
bg_negative_control "${FREEPOOL_SCRIPT}" "${FP_CHILD_NEEDLE}" "freepool-bg" "fp" "${FPBG_SECRETS}" "FREEPOOL_RUNS_DIR" || true
bg_negative_control "${KIMI_SCRIPT}" "${FP_CHILD_NEEDLE}" "kimi-bg" "kimi" "${KIMI_SECRETS}" "KIMI_RUNS_DIR" || true

# ── NEGATIVE CONTROL (d): drop tee -a in a scratch kimi copy (round-2 H1) ────
# Reviewer's exact regression: bare tee truncates journal.jsonl and destroys
# the worker_mcp_attached record written before the spawn. The mutated copy
# must LOSE that record — i.e. the positive journal case above must go red.
ncd_dir="$(mktemp -d "${TMPDIR:-/tmp}/wmaa-ncd.XXXXXX")"
CLEANUP_PATHS+=("${ncd_dir}")
cp -pR "${PLUGIN_SCRIPTS}" "${ncd_dir}/scripts"
python3 - "${ncd_dir}/scripts/kimi-coder.sh" <<'PYMUT'
import sys
path = sys.argv[1]
text = open(path).read()
needle = '| tee -a "${run_dir}/journal.jsonl" |'
if needle not in text:
    print("MUTATION_TARGET_NOT_FOUND", file=sys.stderr)
    sys.exit(1)
open(path, "w").write(text.replace(needle, '| tee "${run_dir}/journal.jsonl" |', 1))
PYMUT
if [[ $? -ne 0 ]]; then
  fail "negative control (tee -a): mutation target found"
else
  NCD_ARGV="${FIXTURE}/ncd-argv.txt"; : > "${NCD_ARGV}"
  make_bg_stub "ncd-kimi" "${NCD_ARGV}" "${FIXTURE}/ncd-env.txt" "${FIXTURE}/ncd-resolved.json"
  NCD_REPO="$(make_bg_repo ncd-repo)"
  NCD_RUN_ID="$(env KIMI_CLAUDE_BIN="${STUB_BIN}/ncd-kimi" KIMI_SECRETS_FILE="${KIMI_SECRETS}" \
    KIMI_RUNS_DIR="${FIXTURE}/ncd-runs" LEADV2_PROJECT_ROOT="${NCD_REPO}" KIMI_SKIP_LAUNCH_PROBE=1 \
    bash "${ncd_dir}/scripts/kimi-coder.sh" bg "@${KMBG_PROMPT}" --cwd "${NCD_REPO}" --timeout 60 2>/dev/null | tail -1)"
  if [[ -n "${NCD_RUN_ID}" ]] && wait_finalized "${FIXTURE}/ncd-runs/${NCD_RUN_ID}" \
     && ! grep -q "worker_mcp_attached" "${FIXTURE}/ncd-runs/${NCD_RUN_ID}/journal.jsonl" 2>/dev/null; then
    pass "negative control (tee -a): mutated kimi goes RED — attached record destroyed by truncation, journal case catches it"
  else
    fail "negative control (tee -a): mutated kimi still keeps worker_mcp_attached — suite would be blind to the round-2 H1 regression"
  fi
fi

# ── NEGATIVE CONTROL (e): unconditional injection in a scratch dispatch copy ─
# Reviewer's exact regression (round-2 H2): replace the gated call with an
# unconditional prepend. The structural dispatch check must go red on the
# mutated copy (the gate call site is gone).
nce_dir="$(mktemp -d "${TMPDIR:-/tmp}/wmaa-nce.XXXXXX")"
CLEANUP_PATHS+=("${nce_dir}")
cp "${DISPATCH_SCRIPT}" "${nce_dir}/leadv2-dispatch-code.sh"
python3 - "${nce_dir}/leadv2-dispatch-code.sh" <<'PYMUT'
import sys
path = sys.argv[1]
text = open(path).read()
needle = '_ci_txt="$(worker_mcp_preamble_for_arm "${arm}" "${WORK_ROOT}" "")" || _ci_rc=$?'
if needle not in text:
    print("MUTATION_TARGET_NOT_FOUND", file=sys.stderr)
    sys.exit(1)
open(path, "w").write(text.replace(needle, '_ci_txt="UNCONDITIONAL-PROMISE"', 1))
PYMUT
if [[ $? -ne 0 ]]; then
  fail "negative control (dispatch gate): mutation target found"
elif dispatch_gate_check "${nce_dir}/leadv2-dispatch-code.sh"; then
  fail "negative control (dispatch gate): unconditional injection still passes — suite would be blind to the round-2 H2 regression"
else
  pass "negative control (dispatch gate): unconditional injection goes RED — dispatch gate check catches it"
fi

echo
log "TOTAL: PASS=${PASS} FAIL=${FAIL}"
if [[ "${FAIL}" -gt 0 ]]; then
  for e in "${ERRORS[@]}"; do log "${e}"; done
  exit 1
fi
exit 0
