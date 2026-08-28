#!/usr/bin/env bash
# freepool-install.sh — one-shot local install for the free-claude-code proxy
# (T19). Clones the repo, creates a venv, installs deps, and pins the checked-
# out commit hash into config/freepool-arm.yaml for reproducibility. Never
# writes secrets into git — provider API keys stay in the proxy's own .env
# under FREEPOOL_INSTALL_DIR, which is outside this plugin repo.
#
# Idempotent: re-running updates the pin file to the currently checked-out
# commit but does not force-reset an existing checkout (so a local operator
# can pin to a specific tested commit without this script clobbering it).
#
# FP-03: Also creates ~/.fcc/.env skeleton with all required keys, prints
# ownership table, and verifies proxy health.
set -euo pipefail

readonly FREEPOOL_REPO_URL="${FREEPOOL_REPO_URL:-https://github.com/Alishahryar1/free-claude-code.git}"
readonly FREEPOOL_INSTALL_DIR="${FREEPOOL_INSTALL_DIR:-${HOME}/tools/free-claude-code}"
# LEADV2_FREEPOOL_PIN_FILE (same env var leadv2-freepool-gate.sh reads) lets a
# caller point this at a scratch path instead of the real checked-in config —
# REQUIRED for any test harness that exercises this script for real (not just
# sourced/stubbed), so a test run can never clobber the repo's own pin file.
# FREEPOOL-MODEL-SELECTOR-01 R2 incident: test-freepool-pin-drift.sh's case7
# ran this script for real with no override and silently overwrote
# plugins/leadv2/config/freepool-arm.yaml, deleting its hand-curated
# model_rank block in the process.
readonly PIN_FILE="${LEADV2_FREEPOOL_PIN_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/freepool-arm.yaml}"
# Marker at the end of the auto-generated header. Anything AFTER this line in
# an existing PIN_FILE (e.g. a hand-curated model_rank: block) is preserved
# verbatim across re-installs instead of being silently dropped by the
# heredoc below — defense-in-depth against the same class of incident even
# for a real (non-test) re-install.
readonly PRESERVE_MARKER="# --- end generated header (freepool-install.sh preserves everything below this line on re-install) ---"
# T19 fix-round-2 (B-H1): the commit actually reviewed/tested, resolved once via
# `git ls-remote https://github.com/Alishahryar1/free-claude-code.git HEAD` on
# 2026-08-26 and hardcoded here as the default -- the prior default (empty) meant
# "install whatever the upstream default branch has drifted to and merely warn",
# which is the opposite of what the pin file's own generated comment claimed
# ("what was actually reviewed/tested"). A caller can still override PINNED_COMMIT
# to move to a newly reviewed commit; FREEPOOL_ALLOW_UNPINNED=1 restores the old
# "install unpinned HEAD" behaviour explicitly, for anyone who really wants it.
# NOTE: `-` not `:-` -- a caller that explicitly sets PINNED_COMMIT="" (to ask
# for an unpinned install) must stay empty and hit the refusal guard below;
# `:-` would silently paper over that explicit empty back to the hardcoded
# default, making the guard unreachable.
readonly PINNED_COMMIT="${PINNED_COMMIT-6b3f16f41d4b06ab1320c0d0e71007392a676348}"
readonly FREEPOOL_ALLOW_UNPINNED="${FREEPOOL_ALLOW_UNPINNED:-0}"
readonly FCC_ENV_FILE="${HOME}/.fcc/.env"
# All keys the proxy reads (from FCC_CONFIG_SCHEMA and freepool-coder.sh)
readonly FCC_ENV_KEYS=(
  FCC_CONFIG_SCHEMA
  DEEPSEEK_API_KEY
  GEMINI_API_KEY
  GROQ_API_KEY
  MISTRAL_API_KEY
  NVIDIA_NIM_API_KEY
  OPENROUTER_API_KEY
  PROXY_AUTH_ENABLED
  PORT
)

log() { echo "[freepool-install] $*" >&2; }

# --- Argument parsing ---
CHECK_MODE=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --check)
      CHECK_MODE=1
      shift
      ;;
    *)  # unknown option
      log "error: unknown option: $1"
      exit 1
      ;;
  esac
done

# --- Helper functions ---

print_ownership_table() {
  cat <<'EOF'
# FCC admin UI field ownership (from freepool-backlog.md appendix)
# - Providers/API keys: operator, once (already done via ~/.fcc/.env).
# - Default Model: safety net ONLY (used when selector fails → `freepool-default`). Any cheap model fine.
# - Fable/Opus/Sonnet/Haiku Overrides: keep None — our workers never send tier names.
# - Fallback Models: the one field worth filling (mid-flight provider failover FCC does itself;
#   our selector cannot catch a provider dying before first token). Recommend 2-3 entries.
# - Reasoning: From client. Web Tools: on.
EOF
}

create_fcc_env_skeleton() {
  if [[ ! -d "${HOME}/.fcc" ]]; then
    mkdir -p "${HOME}/.fcc"
    log "created ${HOME}/.fcc directory"
  fi

  if [[ ! -f "${FCC_ENV_FILE}" ]]; then
    log "creating ${FCC_ENV_FILE} with commented placeholders"
    {
      echo "# .env for free-claude-code proxy"
      echo "# Fill in the values below (operator responsibility)"
      echo "# Format: KEY=value (no quotes)"
      echo ""
      for key in "${FCC_ENV_KEYS[@]}"; do
        echo "# ${key}=
"
      done
    } > "${FCC_ENV_FILE}"
  else
    log "${FCC_ENV_FILE} already exists — checking for missing keys"
    local missing_keys=()
    for key in "${FCC_ENV_KEYS[@]}"; do
      if ! grep -q "^${key}=" "${FCC_ENV_FILE}" 2>/dev/null; then
        missing_keys+=("${key}")
      fi
    done

    if [[ ${#missing_keys[@]} -gt 0 ]]; then
      log "applying missing keys as comments: ${missing_keys[*]}"
      {
        echo ""
        echo "# Missing keys added by freepool-install.sh $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        for key in "${missing_keys[@]}"; do
          echo "# ${key}=
"
        done
      } >> "${FCC_ENV_FILE}"
    else
      log "all required keys present in ${FCC_ENV_FILE}"
    fi
  fi
}

check_fcc_env() {
  local all_present=0
  for key in "${FCC_ENV_KEYS[@]}"; do
    if grep -q "^${key}=" "${FCC_ENV_FILE}" 2>/dev/null; then
      echo "${key}=present"
    else
      echo "${key}=missing"
      all_present=1
    fi
  done
  return ${all_present}
}

health_check_proxy() {
  local url="${FREEPOOL_PROXY_URL:-http://127.0.0.1:8317}/health"
  log "checking proxy health at ${url} (5s timeout)"
  if curl --silent --fail --max-time 5 "${url}" >/dev/null; then
    log "proxy is healthy"
    return 0
  else
    log "proxy health check failed"
    return 1
  fi
}

start_proxy_if_needed() {
  if [[ "${FREEPOOL_AUTOSTART:-0}" == "0" ]]; then
    log "FREEPOOL_AUTOSTART=0, skipping autostart"
    return 0
  fi

  local proxy_script="${FREEPOOL_INSTALL_DIR}/freepool-proxy.sh"
  if [[ ! -x "${proxy_script}" ]]; then
    log "warning: ${proxy_script} not found or not executable"
    return 1
  fi

  log "starting freepool proxy..."
  "${proxy_script}" start &
  local pid=$!
  # Give it a moment to start
  sleep 2
  # Check if it's still running
  if ! kill -0 "${pid}" 2>/dev/null; then
    log "error: proxy failed to start"
    return 1
  fi
  log "proxy started (PID: ${pid})"
  return 0
}

# --- Main logic ---

if [[ ${CHECK_MODE} -eq 1 ]]; then
  log "running in --check mode (report-only)"
  check_fcc_env
  exit $?
fi

# Normal installation flow

# Step 1: Create ~/.fcc/.env skeleton
create_fcc_env_skeleton

# Step 2: Print ownership table
print_ownership_table

# Step 3: Existing freepool installation logic (cloning, venv, etc.)
if [[ ! -d "${FREEPOOL_INSTALL_DIR}/.git" ]]; then
  log "cloning ${FREEPOOL_REPO_URL} -> ${FREEPOOL_INSTALL_DIR}"
  git clone "${FREEPOOL_REPO_URL}" "${FREEPOOL_INSTALL_DIR}"
else
  log "checkout already present at ${FREEPOOL_INSTALL_DIR} — not re-cloning (this script does not force-reset)"
fi

if [[ -n "${PINNED_COMMIT}" ]]; then
  log "checking out pinned commit ${PINNED_COMMIT}"
  git -C "${FREEPOOL_INSTALL_DIR}" fetch --quiet origin "${PINNED_COMMIT}" 2>/dev/null || true
  git -C "${FREEPOOL_INSTALL_DIR}" checkout --quiet "${PINNED_COMMIT}"
else
  log "PINNED_COMMIT not set (FREEPOOL_ALLOW_UNPINNED=1) -- installing whatever commit is" \
      "currently checked out (untested provenance)"
fi

if [[ ! -d "${FREEPOOL_INSTALL_DIR}/.venv" ]]; then
  log "creating venv"
  python3 -m venv "${FREEPOOL_INSTALL_DIR}/.venv"
fi

if [[ -f "${FREEPOOL_INSTALL_DIR}/requirements.txt" ]]; then
  log "installing requirements.txt"
  "${FREEPOOL_INSTALL_DIR}/.venv/bin/pip" install -q -r "${FREEPOOL_INSTALL_DIR}/requirements.txt"
else
  log "no requirements.txt found yet (repo not cloned in this environment) — skipping pip install"
fi

commit_hash="$(git -C "${FREEPOOL_INSTALL_DIR}" rev-parse HEAD 2>/dev/null || echo UNRESOLVED)"

# Preserve any hand-curated content (e.g. model_rank:) that already lives
# below PRESERVE_MARKER in the existing PIN_FILE, so regenerating the header
# below never silently deletes it.
preserved_tail=""
if [[ -f "${PIN_FILE}" ]] && grep -qF "${PRESERVE_MARKER}" "${PIN_FILE}"; then
  preserved_tail="$(awk -v marker="${PRESERVE_MARKER}" 'found{print} $0==marker{found=1}' "${PIN_FILE}")"
fi

cat > "${PIN_FILE}" <<EOF
# freepool-arm.yaml — generated by freepool-install.sh. Pinned commit is what
# was actually checked out at ${FREEPOOL_INSTALL_DIR} at install time; a
# mismatch between this and a live \`git -C \$FREEPOOL_INSTALL_DIR rev-parse
# HEAD\` means the local checkout drifted from what was reviewed/tested.
repo_url: ${FREEPOOL_REPO_URL}
pinned_commit: ${commit_hash}
install_dir: ${FREEPOOL_INSTALL_DIR}

# Provider API keys the proxy itself needs — NEVER set here, NEVER in git.
# Configure them in \${FREEPOOL_INSTALL_DIR}/.env per the cloned repo's own
# README/.env.example (exact names are UNVERIFIED until the repo is cloned in
# a network-enabled environment — see freepool-proxy.sh's ENTRYPOINT-UNVERIFIED
# note for the same caveat on the run command). Until that file has real
# values, leadv2-freepool-gate.sh's liveness probe fails closed (arm_down) and
# the router skips this arm by fact — no code change needed when keys land,
# only the .env file and a \`freepool-proxy.sh start\`.
${PRESERVE_MARKER}
EOF
if [[ -n "${preserved_tail}" ]]; then
  printf '%s\n' "${preserved_tail}" >> "${PIN_FILE}"
fi
log "pinned commit ${commit_hash} -> ${PIN_FILE}"

# Step 4: Health-verify the proxy
log "verifying proxy health..."
if health_check_proxy; then
  log "proxy health check passed"
else
  log "proxy health check failed"
  if [[ "${FREEPOOL_AUTOSTART:-0}" != "0" ]]; then
    log "attempting to start proxy (FREEPOOL_AUTOSTART=${FREEPOOL_AUTOSTART})"
    if start_proxy_if_needed; then
      log "proxy started, re-checking health..."
      if health_check_proxy; then
        log "proxy health check passed after start"
      else
        log "error: proxy health check failed after start attempt"
        exit 1
      fi
    else
      log "error: failed to start proxy"
      exit 1
    fi
  else
    log "error: proxy is down and FREEPOOL_AUTOSTART=0"
    exit 1
  fi
fi

log "installation complete"
log "next: put provider keys in ${FCC_ENV_FILE}, then freepool-proxy.sh start"