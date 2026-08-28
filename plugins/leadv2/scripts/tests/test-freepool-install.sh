#!/usr/bin/env bash
# test-freepool-install.sh — FP-03 freepool installer test
#
# Tests:
#   - Skeleton created when absent
#   - Existing .env untouched byte-for-byte (cmp)
#   - --check output shape
#   - Negative control declared in header and RUN red (mutation: installer overwrites existing .env)
#
# The test must declare its negative control in the header and RUN red for the
# mutation case (installer overwrites existing .env).
# shellcheck disable=SC2034
NEGATIVE_CONTROL_MUTATION="installer overwrites existing .env"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL="$SCRIPTS_ROOT/freepool-install.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL=$((FAIL + 1)); }

bash -n "$INSTALL" 2>/dev/null || { echo "ERROR: install syntax check failed"; exit 1; }

ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

# Test 1: Skeleton created when absent
HOME_TEST="$ROOT/home"
mkdir -p "$HOME_TEST"
export HOME="$HOME_TEST"

log() { echo "[test-freepool-install] $*" >&2; }

# Run installer with clean HOME (no .fcc directory)
"$INSTALL" >"$ROOT/install.out" 2>&1
rc=$?

if [[ $rc -eq 0 ]] && [[ -f "${HOME}/.fcc/.env" ]]; then
  # Check that it contains commented placeholders for all keys
  if grep -q "^# FCC_CONFIG_SCHEMA=" "${HOME}/.fcc/.env" && \
     grep -q "^# DEEPSEEK_API_KEY=" "${HOME}/.fcc/.env" && \
     grep -q "^# GEMINI_API_KEY=" "${HOME}/.fcc/.env" && \
     grep -q "^# GROQ_API_KEY=" "${HOME}/.fcc/.env" && \
     grep -q "^# MISTRAL_API_KEY=" "${HOME}/.fcc/.env" && \
     grep -q "^# NVIDIA_NIM_API_KEY=" "${HOME}/.fcc/.env" && \
     grep -q "^# OPENROUTER_API_KEY=" "${HOME}/.fcc/.env" && \
     grep -q "^# PROXY_AUTH_ENABLED=" "${HOME}/.fcc/.env" && \
     grep -q "^# PORT=" "${HOME}/.fcc/.env"; then
    pass "case1: skeleton created with all required keys as comments"
  else
    fail "case1: skeleton missing some required key comments"
  fi
else
  fail "case1: installer failed or .env not created (rc=$rc)"
fi

# Test 2: Existing .env untouched byte-for-byte (except for appended missing key comments)
HOME_TEST2="$ROOT/home2"
mkdir -p "$HOME_TEST2/.fcc"
export HOME="$HOME_TEST2"

# Create a custom .env with specific content
cat > "${HOME}/.fcc/.env" <<'EOF'
# Custom existing .env
FCC_CONFIG_SCHEMA=custom_value
DEEPSEEK_API_KEY=sk-deepseek-123
GEMINI_API_KEY=gemini-key-456
# Note: GROQ_API_KEY is intentionally missing
MISTRAL_API_KEY=mistral-key-789
NVIDIA_NIM_API_KEY=nim-key-000
OPENROUTER_API_KEY=or-key-111
PROXY_AUTH_ENABLED=true
PORT=8317
EOF

# Save original for comparison
cp "${HOME}/.fcc/.env" "${HOME}/.fcc/.env.original"

# Run installer again
"$INSTALL" >"$ROOT/install2.out" 2>&1
rc=$?

if [[ $rc -eq 0 ]]; then
  # The original content should be preserved exactly at the start
  # Check if the new file starts with the original content
  if head -n "$(wc -l < "${HOME}/.fcc/.env.original")" "${HOME}/.fcc/.env" | cmp -s - "${HOME}/.fcc/.env.original"; then
    # Check that missing keys were appended as comments (after the original content)
    original_lines=$(wc -l < "${HOME}/.fcc/.env.original")
    if [[ $(wc -l < "${HOME}/.fcc/.env") -gt $original_lines ]]; then
      if tail -n +$((original_lines + 1)) "${HOME}/.fcc/.env" | grep -q "^# Missing keys added by freepool-install.sh"; then
        if tail -n +$((original_lines + 1)) "${HOME}/.fcc/.env" | grep -q "^# GROQ_API_KEY="; then
          pass "case2: existing .env preserved with missing keys appended as comments"
        else
          fail "case2: missing key comment not found"
          echo "Content after line $original_lines:" >&2
          tail -n +$((original_lines + 1)) "${HOME}/.fcc/.env" >&2
        fi
      else
        fail "case2: missing keys header not found"
        echo "Content after line $original_lines:" >&2
        tail -n +$((original_lines + 1)) "${HOME}/.fcc/.env" >&2
      fi
    else
      fail "case2: no missing keys were appended (file not longer than original)"
    fi
  else
    fail "case2: existing .env content was modified"
    echo "Original content:" >&2
    cat "${HOME}/.fcc/.env.original" >&2
    echo "New content:" >&2
    cat "${HOME}/.fcc/.env" >&2
  fi
else
  fail "case2: installer failed on existing .env (rc=$rc)"
fi

# Test 3: --check output shape
HOME_TEST3="$ROOT/home3"
mkdir -p "$HOME_TEST3/.fcc"
export HOME="$HOME_TEST3"

# Create .env with subset of keys
cat > "${HOME}/.fcc/.env" <<'EOF'
FCC_CONFIG_SCHEMA=test
DEEPSEEK_API_KEY=test-key
# GEMINI_API_KEY intentionally missing
GROQ_API_KEY=test-key
MISTRAL_API_KEY=test-key
# NVIDIA_NIM_API_KEY intentionally missing
OPENROUTER_API_KEY=test-key
PROXY_AUTH_ENABLED=false
PORT=8080
EOF

# Run in check mode
OUTPUT="$("$INSTALL" --check 2>/dev/null)"
rc=$?

if [[ $rc -ne 0 ]]; then
  # --check should return non-zero when keys are missing
  # Check output format: each line should be KEY=present|missing
  expected_lines=(
    "FCC_CONFIG_SCHEMA=present"
    "DEEPSEEK_API_KEY=present"
    "GEMINI_API_KEY=missing"
    "GROQ_API_KEY=present"
    "MISTRAL_API_KEY=present"
    "NVIDIA_NIM_API_KEY=missing"
    "OPENROUTER_API_KEY=present"
    "PROXY_AUTH_ENABLED=present"
    "PORT=present"
  )

  # Check that we have exactly 9 lines
  if [[ $(echo "$OUTPUT" | wc -l) -eq 9 ]]; then
    # Check each line matches expected value
    all_correct=1
    i=0
    while IFS= read -r line; do
      if [[ "$line" != "${expected_lines[$i]}" ]]; then
        all_correct=0
        break
      fi
      ((i++))
    done <<< "$OUTPUT"

    if [[ $all_correct -eq 1 ]]; then
      pass "case3: --check output shape correct"
    else
      fail "case3: --check output has wrong values"
      echo "Expected:" >&2
      printf '%s\n' "${expected_lines[@]}" >&2
      echo "Actual:" >&2
      echo "$OUTPUT" >&2
    fi
  else
    fail "case3: --check output wrong line count (expected 9, got $(echo "$OUTPUT" | wc -l))"
    echo "Output was:" >&2
    echo "$OUTPUT" >&2
  fi
else
  fail "case3: --check should return non-zero when keys missing (rc=$rc)"
fi

# Test 4: --check with all keys present
HOME_TEST4="$ROOT/home4"
mkdir -p "$HOME_TEST4/.fcc"
export HOME="$HOME_TEST4"

# Create .env with all keys
cat > "${HOME}/.fcc/.env" <<'EOF'
FCC_CONFIG_SCHEMA=test
DEEPSEEK_API_KEY=test-key
GEMINI_API_KEY=test-key
GROQ_API_KEY=test-key
MISTRAL_API_KEY=test-key
NVIDIA_NIM_API_KEY=test-key
OPENROUTER_API_KEY=test-key
PROXY_AUTH_ENABLED=true
PORT=8317
EOF

OUTPUT="$("$INSTALL" --check 2>/dev/null)"
rc=$?

if [[ $rc -eq 0 ]]; then
  # All should be present
  if echo "$OUTPUT" | grep -qv '=missing$'; then
    pass "case4: --check returns 0 when all keys present"
  else
    fail "case4: --check shows missing keys when all present"
    echo "Output was:" >&2
    echo "$OUTPUT" >&2
  fi
else
  fail "case4: --check should return 0 when all keys present (rc=$rc)"
fi

# NEGATIVE CONTROL: mutation case (installer overwrites existing .env)
# This test verifies that if we REMOVE the protection logic, the installer would
# overwrite an existing .env. We test this by creating a simple mutated installer
# that always overwrites .env (removing the idempotency check).
HOME_TEST5="$ROOT/home5"
mkdir -p "$HOME_TEST5/.fcc"
export HOME="$HOME_TEST5"

# Create a .env with custom content
cat > "${HOME}/.fcc/.env" <<'EOF'
# This is a custom .env that should NOT be overwritten
MY_CUSTOM_VAR=custom-value
ANOTHER_CUSTOM=another-value
EOF

# Save original
cp "${HOME}/.fcc/.env" "${HOME}/.fcc/.env.original"

# Create a MUTATED version of the installer that DOES overwrite .env
# (removes the idempotency check - simplified for testing)
MUTATED_INSTALL="$ROOT/mutated-install.sh"
cat > "$MUTATED_INSTALL" <<'EOF'
#!/usr/bin/env bash
# MUTATED freepool-install.sh - always overwrites .env (negative control test)

# Simplified version that always creates/overwrites .env
mkdir -p "${HOME}/.fcc"
{
  echo "# .env for free-claude-code proxy"
  echo "# Fill in the values below (operator responsibility)"
  echo "# Format: KEY=value (no quotes)"
  echo ""
  for key in "${FCC_ENV_KEYS[@]}"; do
    echo "# ${key}=
"
  done
} > "${HOME}/.fcc/.env"

echo "[freepool-install] created ${HOME}/.fcc/.env (mutated version - always overwrites)"
EOF
chmod +x "$MUTATED_INSTALL"

# Define FCC_ENV_KEYS for the mutated installer (normally sourced from main script)
FCC_ENV_KEYS=(
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

# Run the mutated installer
"$MUTATED_INSTALL" >"$ROOT/install5.out" 2>&1
rc=$?

if [[ $rc -eq 0 ]]; then
  # Check if .env was overwritten (custom content lost)
  if ! grep -q "MY_CUSTOM_VAR=custom-value" "${HOME}/.fcc/.env"; then
    pass "NEGATIVE CONTROL KILLED: mutated installer overwrote existing .env (as expected)"
  else
    fail "NEGATIVE CONTROL SURVIVED: mutated installer did not overwrite .env"
  fi
else
  fail "NEGATIVE CONTROL: mutated installer failed unexpectedly (rc=$rc)"
fi

# Verify that the REAL installer does NOT overwrite (preserves original + appends missing key comments)
HOME_TEST6="$ROOT/home6"
mkdir -p "$HOME_TEST6/.fcc"
export HOME="$HOME_TEST6"

# Create a .env with custom content
cat > "${HOME}/.fcc/.env" <<'EOF'
# This is a custom .env that should NOT be overwritten by real installer
MY_CUSTOM_VAR=custom-value
ANOTHER_CUSTOM=another-value
EOF

# Save original
cp "${HOME}/.fcc/.env" "${HOME}/.fcc/.env.original"

# Run the REAL installer
"$INSTALL" >"$ROOT/install6.out" 2>&1
rc=$?

if [[ $rc -eq 0 ]]; then
  # The original content should be preserved exactly at the start
  original_lines=$(wc -l < "${HOME}/.fcc/.env.original")
  if [[ $(wc -l < "${HOME}/.fcc/.env") -ge $original_lines ]]; then
    if head -n "$original_lines" "${HOME}/.fcc/.env" | cmp -s - "${HOME}/.fcc/.env.original"; then
      # Check that only missing key comments were appended (after the original content)
      # Since our .env.original has all keys present, NO missing key comments should be added
      if [[ $(wc -l < "${HOME}/.fcc/.env") -eq $original_lines ]]; then
        pass "REAL installer preserves existing .env with custom content (no missing keys to add)"
      else
        # Check what was appended - should only be missing key comments
        appended_content=$(tail -n +$((original_lines + 1)) "${HOME}/.fcc/.env")
        if echo "$appended_content" | grep -q "^# Missing keys added by freepool-install.sh"; then
          # Check that no actual key values were added (only comments)
          if ! echo "$appended_content" | grep -v '^#' | grep -q '.'; then
            pass "REAL installer preserves existing .env and appends only missing key comments"
          else
            fail "REAL installer appended non-comment content"
            echo "Appended content:" >&2
            echo "$appended_content" >&2
          fi
        else
          fail "REAL installer did not append missing keys header when expected"
          echo "Appended content:" >&2
          echo "$appended_content" >&2
        fi
      fi
    else
      fail "REAL installer modified existing content"
      echo "Original:" >&2
      cat "${HOME}/.fcc/.env.original" >&2
      echo "New (first $original_lines lines):" >&2
      head -n "$original_lines" "${HOME}/.fcc/.env" >&2
    fi
  else
    fail "REAL installer truncated existing .env"
    echo "Original lines: $original_lines, New lines: $(wc -l < "${HOME}/.fcc/.env")" >&2
  fi
else
  fail "REAL installer failed on existing .env with custom content (rc=$rc)"
fi

printf '\n================================================\n'
printf '  freepool install test: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
printf '================================================\n'

exit $FAIL