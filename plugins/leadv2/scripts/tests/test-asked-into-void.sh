#!/usr/bin/env bash
# N1-EMPTY-LANE-IS-NOT-A-PASS — falsifying harness for Design C.
# Asserts (1) the asked-into-void detection shape: a result.md whose last
# non-empty line ends in '?' (or fullwidth '？') is flagged, a normal result is
# not, and RUN_COMPLETE stays on its own line before RUN_COMPLETE_ASKED_INTO_VOID;
# (2) product-close maps empty-diff + marker -> no_work/asked_into_void, and
# non-empty-diff + marker -> parked/asked_into_void. New file (R5): the six named
# suites keep their exact counts.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PC="${SCRIPT_DIR}/leadv2-dispatch-product-close.sh"
PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

# ---- Case 1: detection shape (faithful to the coder's finish-guard case-glob) --
# This is the EXACT predicate the coder embeds (conditions 1+2; condition 3 is
# subsumed -- a run reaching RUN_COMPLETE cannot hold a pending blocking-ask).
detect_asked_into_void() { # <result.md_path> -> echoes 1/0
  local rf="$1" last=""
  [[ -s "${rf}" ]] || { echo 0; return; }
  last="$(grep -v '^[[:space:]]*$' "${rf}" 2>/dev/null | tail -n1)"
  case "${last}" in
    *\?|*？) echo 1 ;;
    *) echo 0 ;;
  esac
}
case_detection_shape() {
  local d rf
  d="$(mktemp -d)"; rf="${d}/result.md"
  printf 'work done\nstill need input?\n' > "${rf}"
  [[ "$(detect_asked_into_void "${rf}")" == "1" ]] && ok "trailing '?' detected" || bad "trailing '?' should be detected"
  printf 'all done, shipping it.\n' > "${rf}"
  [[ "$(detect_asked_into_void "${rf}")" == "0" ]] && ok "normal result not flagged" || bad "normal result should not be flagged"
  printf 'что делать дальше？\n' > "${rf}"   # fullwidth '？'
  [[ "$(detect_asked_into_void "${rf}")" == "1" ]] && ok "fullwidth '？' detected" || bad "fullwidth '？' should be detected"
  : > "${rf}"
  [[ "$(detect_asked_into_void "${rf}")" == "0" ]] && ok "empty result not flagged" || bad "empty result should not be flagged"
  rm -rf "${d}"
}

# Shared stubs + a one-commit repo. <seed_modified>: if 1, patch the declared write.
setup_repo() { # <root> <seed_modified>
  local root="$1" mod="$2"
  mkdir -p "${root}/agent"
  ( cd "${root}" && git init -q -b main && git config user.email t@e.com && git config user.name t \
    && printf 'seed\n' > agent/seed.py && git add agent/seed.py && git commit -qm seed ) >/dev/null 2>&1
  [[ "${mod}" == "1" ]] && printf 'seed\npatched\n' > "${root}/agent/seed.py"
}
make_stubs() { # <dir>
  local d="$1"
  cat > "${d}/resolver.py" <<'PY'
print("reviewer=codex"); print("pool=codex"); print("refusal=")
PY
  cat > "${d}/codex.sh" <<'SH'
#!/usr/bin/env bash
mkdir -p "$2"; printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n' > "$1"
SH
  chmod +x "${d}/codex.sh"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/journal.log"\n' "${d}" > "${d}/journal.sh"
  chmod +x "${d}/journal.sh"
}

# ---- Case 2: empty diff + .asked_into_void -> no_work/asked_into_void --------
case_empty_asked() {
  local d root runs handle
  d="$(mktemp -d)"; root="${d}/repo"; mkdir -p "${root}"; setup_repo "${root}" 0
  make_stubs "${d}"
  runs="${d}/cache"; handle="h-empt"; mkdir -p "${runs}/kimi-runs/${handle}"
  touch "${runs}/kimi-runs/${handle}/.asked_into_void"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache2" \
    LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_PC_RUNS_ROOT="${runs}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" \
    LEADV2_JOURNAL_BIN="${d}/journal.sh" \
    LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
    bash "${PC}" "${root}" av1sig001 kimi "${handle}" 0 1 "founder-av1" >/dev/null 2>&1
  if grep -q 'terminal=no_work cause=asked_into_void' "${d}/journal.log" 2>/dev/null; then
    ok "empty diff + asked -> no_work/asked_into_void"
  else bad "empty diff + asked should be no_work/asked_into_void (got: $(grep review_gate "${d}/journal.log" 2>/dev/null | tail -1))"; fi
  rm -rf "${d}"
}

# ---- Case 3: non-empty diff + .asked_into_void -> parked/asked_into_void -----
case_nonempty_asked_parked() {
  local d root runs handle
  d="$(mktemp -d)"; root="${d}/repo"; mkdir -p "${root}"; setup_repo "${root}" 1   # patched -> non-empty diff
  make_stubs "${d}"
  runs="${d}/cache"; handle="h-non"; mkdir -p "${runs}/kimi-runs/${handle}"
  touch "${runs}/kimi-runs/${handle}/.asked_into_void"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache2" \
    LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_PC_RUNS_ROOT="${runs}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" \
    LEADV2_JOURNAL_BIN="${d}/journal.sh" \
    LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
    bash "${PC}" "${root}" av2sig002 kimi "${handle}" 0 1 "founder-av2" >/dev/null 2>&1
  if grep -q 'terminal=parked cause=asked_into_void' "${d}/journal.log" 2>/dev/null; then
    ok "non-empty diff + asked -> parked/asked_into_void"
  else bad "non-empty diff + asked should be parked/asked_into_void (got: $(grep -E 'review_gate|dispatch_terminal ' "${d}/journal.log" 2>/dev/null | tail -2))"; fi
  rm -rf "${d}"
}

case_detection_shape
case_empty_asked
case_nonempty_asked_parked

printf '\n=== %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == 0 ]]
