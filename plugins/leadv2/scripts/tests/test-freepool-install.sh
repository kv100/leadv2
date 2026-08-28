#!/usr/bin/env bash
# test-freepool-install.sh — FP-03 installer regression tests
#
# Negative control: mutate create_fcc_env_skeleton in a temporary copy of the
# real freepool-install.sh so it overwrites an existing .env.  That run must
# go red; the unmodified installer must preserve the same input.
NEGATIVE_CONTROL_MUTATION="real create_fcc_env_skeleton overwrites existing .env"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL="$SCRIPTS_ROOT/freepool-install.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL=$((FAIL + 1)); }

bash -n "$INSTALL" 2>/dev/null || { echo "ERROR: install syntax check failed"; exit 1; }

ROOT="$(mktemp -d)"
cleanup() {
  if [[ -f "$ROOT/proxy.pid" ]]; then
    proxy_pid="$(<"$ROOT/proxy.pid")"
    kill "$proxy_pid" 2>/dev/null || true
  fi
  rm -rf "$ROOT"
}
trap cleanup EXIT

# The fake curl is intentionally first on PATH.  It records each health probe
# and returns the requested up/down sequence without opening a network socket.
mkdir -p "$ROOT/bin" "$ROOT/install/.git" "$ROOT/install/.venv/bin"
cat > "$ROOT/bin/curl" <<'EOF'
#!/usr/bin/env bash
count=0
[[ -f "${CURL_COUNT_FILE:?}" ]] && count="$(<"$CURL_COUNT_FILE")"
count=$((count + 1))
printf '%s\n' "$count" > "$CURL_COUNT_FILE"
IFS=, read -r -a responses <<< "${FAKE_CURL_SEQUENCE:-up}"
state="${responses[$((count - 1))]:-${responses[${#responses[@]} - 1]}}"
[[ "$state" == up ]]
EOF
chmod +x "$ROOT/bin/curl"

# No real repository commands are needed once the fixture has .git/.venv.
cat > "$ROOT/bin/git" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *" rev-parse HEAD "*) printf '%s\n' '0123456789abcdef0123456789abcdef01234567' ;;
esac
EOF
chmod +x "$ROOT/bin/git"

# The autostart fixture stays alive until cleanup so start_proxy_if_needed's
# liveness check succeeds, but it launches no real proxy or child process.
cat > "$ROOT/install/freepool-proxy.sh" <<'EOF'
#!/usr/bin/env bash
printf 'start\n' >> "${START_LOG:?}"
printf '%s\n' "$$" > "${START_PID_FILE:?}"
trap 'exit 0' TERM INT
while :; do read -r -t 1 _ || :; done
EOF
chmod +x "$ROOT/install/freepool-proxy.sh"

PIN_FILE="$ROOT/freepool-arm.yaml"
START_LOG="$ROOT/start.log"
START_PID_FILE="$ROOT/proxy.pid"

run_install() {
  local script="$1" home="$2" label="$3" sequence="$4" autostart="$5"
  local count_file="$ROOT/${label}.curl-count"
  : > "$count_file"
  env -u FREEPOOL_PROXY_URL \
    PATH="$ROOT/bin:$PATH" \
    HOME="$home" \
    FREEPOOL_INSTALL_DIR="$ROOT/install" \
    LEADV2_FREEPOOL_PIN_FILE="$PIN_FILE" \
    FREEPOOL_AUTOSTART="$autostart" \
    FAKE_CURL_SEQUENCE="$sequence" \
    CURL_COUNT_FILE="$count_file" \
    START_LOG="$START_LOG" \
    START_PID_FILE="$START_PID_FILE" \
    "$script" >"$ROOT/${label}.out" 2>&1
  RUN_RC=$?
  RUN_CURL_COUNT="$(<"$count_file")"
}

has_skeleton_keys() {
  local file="$1" key
  for key in FCC_CONFIG_SCHEMA DEEPSEEK_API_KEY GEMINI_API_KEY GROQ_API_KEY \
      MISTRAL_API_KEY NVIDIA_NIM_API_KEY OPENROUTER_API_KEY PROXY_AUTH_ENABLED PORT; do
    grep -q "^# ${key}=" "$file" || return 1
  done
}

# Case 1: absent .env creates a complete commented skeleton.  curl=up is a
# hermetic fake response, not a connection to 127.0.0.1:8317.
HOME1="$ROOT/home1"; mkdir -p "$HOME1"
run_install "$INSTALL" "$HOME1" case1 up 0
if [[ $RUN_RC -eq 0 && $RUN_CURL_COUNT -eq 1 && -f "$HOME1/.fcc/.env" ]] && has_skeleton_keys "$HOME1/.fcc/.env"; then
  pass "case1: hermetic health-up install creates all skeleton comments"
else
  fail "case1: expected rc=0, one fake health check, and skeleton (rc=$RUN_RC checks=$RUN_CURL_COUNT)"
fi

# Case 2: an existing partial file retains its original bytes and gains only
# the missing-key comments.
HOME2="$ROOT/home2"; mkdir -p "$HOME2/.fcc"
cat > "$HOME2/.fcc/.env" <<'EOF'
# Custom existing .env
FCC_CONFIG_SCHEMA=custom_value
DEEPSEEK_API_KEY=sk-deepseek-123
GEMINI_API_KEY=gemini-key-456
MISTRAL_API_KEY=mistral-key-789
NVIDIA_NIM_API_KEY=nim-key-000
OPENROUTER_API_KEY=or-key-111
PROXY_AUTH_ENABLED=true
PORT=8317
EOF
cp "$HOME2/.fcc/.env" "$HOME2/.fcc/.env.original"
run_install "$INSTALL" "$HOME2" case2 up 0
original_lines="$(wc -l < "$HOME2/.fcc/.env.original")"
if [[ $RUN_RC -eq 0 && $RUN_CURL_COUNT -eq 1 ]] && \
   head -n "$original_lines" "$HOME2/.fcc/.env" | cmp -s - "$HOME2/.fcc/.env.original" && \
   tail -n +$((original_lines + 1)) "$HOME2/.fcc/.env" | grep -q '^# GROQ_API_KEY='; then
  pass "case2: existing .env bytes preserved; missing key appended as comment"
else
  fail "case2: existing .env was changed incorrectly (rc=$RUN_RC checks=$RUN_CURL_COUNT)"
fi

# Cases 3/4: --check is report-only and does not invoke the health path.
HOME3="$ROOT/home3"; mkdir -p "$HOME3/.fcc"
cat > "$HOME3/.fcc/.env" <<'EOF'
FCC_CONFIG_SCHEMA=test
DEEPSEEK_API_KEY=test
GROQ_API_KEY=test
MISTRAL_API_KEY=test
OPENROUTER_API_KEY=test
PROXY_AUTH_ENABLED=false
PORT=8080
EOF
CHECK_OUTPUT="$(env -u FREEPOOL_PROXY_URL HOME="$HOME3" "$INSTALL" --check 2>/dev/null)"; CHECK_RC=$?
if [[ $CHECK_RC -ne 0 && "$(printf '%s\n' "$CHECK_OUTPUT" | wc -l)" -eq 9 ]] && \
   printf '%s\n' "$CHECK_OUTPUT" | grep -qx 'GEMINI_API_KEY=missing' && \
   printf '%s\n' "$CHECK_OUTPUT" | grep -qx 'NVIDIA_NIM_API_KEY=missing'; then
  pass "case3: --check reports missing keys without installation"
else
  fail "case3: --check output/rc wrong (rc=$CHECK_RC)"
fi

HOME4="$ROOT/home4"; mkdir -p "$HOME4/.fcc"
for key in FCC_CONFIG_SCHEMA DEEPSEEK_API_KEY GEMINI_API_KEY GROQ_API_KEY MISTRAL_API_KEY NVIDIA_NIM_API_KEY OPENROUTER_API_KEY PROXY_AUTH_ENABLED PORT; do
  printf '%s=test\n' "$key" >> "$HOME4/.fcc/.env"
done
CHECK_OUTPUT="$(env -u FREEPOOL_PROXY_URL HOME="$HOME4" "$INSTALL" --check 2>/dev/null)"; CHECK_RC=$?
if [[ $CHECK_RC -eq 0 ]] && ! printf '%s\n' "$CHECK_OUTPUT" | grep -q '=missing$'; then
  pass "case4: --check returns 0 when all keys are present"
else
  fail "case4: --check should return 0 with no missing keys (rc=$CHECK_RC)"
fi

# Case 5: mutate the actual production function in a temporary copy.  This
# changes its existing-file guard to true, so its normal skeleton writer must
# overwrite our custom input and make the control go red.
MUTATED_INSTALL="$ROOT/freepool-install-mutated.sh"
cp "$INSTALL" "$MUTATED_INSTALL"
perl -0pi -e 's/if \[\[ ! -f "\$\{FCC_ENV_FILE\}" \]\]; then/if true; then/' "$MUTATED_INSTALL"
chmod +x "$MUTATED_INSTALL"
if ! rg -q 'if true; then' "$MUTATED_INSTALL"; then
  fail "case5: failed to apply mutation inside real create_fcc_env_skeleton"
else
  HOME5="$ROOT/home5"; mkdir -p "$HOME5/.fcc"
  printf 'MY_CUSTOM_VAR=custom-value\n' > "$HOME5/.fcc/.env"
  run_install "$MUTATED_INSTALL" "$HOME5" case5 up 0
  if [[ $RUN_RC -eq 0 ]] && ! grep -q 'MY_CUSTOM_VAR=custom-value' "$HOME5/.fcc/.env"; then
    pass "case5: NEGATIVE CONTROL KILLED by mutation in real installer function"
  else
    fail "case5: real-function mutation did not overwrite existing .env (rc=$RUN_RC)"
  fi
fi

# Case 6: unmodified real installer preserves the same custom input.
HOME6="$ROOT/home6"; mkdir -p "$HOME6/.fcc"
printf 'MY_CUSTOM_VAR=custom-value\n' > "$HOME6/.fcc/.env"
cp "$HOME6/.fcc/.env" "$HOME6/.fcc/.env.original"
run_install "$INSTALL" "$HOME6" case6 up 0
if [[ $RUN_RC -eq 0 ]] && head -n 1 "$HOME6/.fcc/.env" | cmp -s - "$HOME6/.fcc/.env.original"; then
  pass "case6: real installer preserves untouched existing .env"
else
  fail "case6: real installer did not preserve custom content (rc=$RUN_RC)"
fi

# Case 7: no fake health success + autostart disabled must fail cleanly.
HOME7="$ROOT/home7"; mkdir -p "$HOME7"
run_install "$INSTALL" "$HOME7" case7 down 0
if [[ $RUN_RC -ne 0 && $RUN_CURL_COUNT -eq 1 ]] && grep -q 'proxy is down and FREEPOOL_AUTOSTART=0' "$ROOT/case7.out"; then
  pass "case7: health-down with autostart disabled exits non-zero"
else
  fail "case7: expected health-down failure with one check (rc=$RUN_RC checks=$RUN_CURL_COUNT)"
fi

# Case 8: exercise freepool-install.sh's autostart branch.  The sequence
# down,up proves exactly one initial check and exactly one re-check; the start
# fixture log proves exactly one start attempt.
: > "$START_LOG"
HOME8="$ROOT/home8"; mkdir -p "$HOME8"
run_install "$INSTALL" "$HOME8" case8 down,up 1
start_count="$(wc -l < "$START_LOG")"
if [[ $RUN_RC -eq 0 && $RUN_CURL_COUNT -eq 2 && $start_count -eq 1 ]]; then
  pass "case8: autostart attempts once and health re-checks once"
else
  fail "case8: expected rc=0, one start, two checks (rc=$RUN_RC starts=$start_count checks=$RUN_CURL_COUNT)"
fi

printf '\n================================================\n'
printf '  freepool install test: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
printf '================================================\n'
exit "$FAIL"
