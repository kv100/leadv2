#!/usr/bin/env bash
# tests/test-hook-output-cap.sh — HOOK-OUTPUT-CAP-PLUGIN-01: pins the
# SessionStart output caps on leadv2-one-copy-drift.sh and
# leadv2-truth-card-inject.sh. Every ordinary session start pays these two
# hooks' stdout as re-sent context on every later turn, so a drifted tree
# (hundreds of REGRESSION lines) or a fully-populated truth card must not
# flood it — the fact + count + a path to the full detail on disk is enough.
#
# T1 one-copy-drift: many REGRESSION lines -> capped stdout, count correct,
#    full detail on disk with every line.
# T2 one-copy-drift: clean tree -> unchanged silent behaviour (no cap path).
# T3 truth-card-inject: large row -> capped stdout, full card on disk.
# T4 truth-card-inject: small/failure row -> unchanged direct emission (no
#    disk file, cap path not taken).
#
# Run: bash plugins/leadv2/scripts/tests/test-hook-output-cap.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_ONE_COPY="${SCRIPT_DIR}/../hooks/leadv2-one-copy-drift.sh"
HOOK_TRUTH_CARD="${SCRIPT_DIR}/../hooks/leadv2-truth-card-inject.sh"
source "${SCRIPT_DIR}/leadv2-temp.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); log "FAIL: $1"; }

CAP_BYTES=2048

bash -n "${HOOK_ONE_COPY}" 2>/dev/null && pass "bash -n one-copy-drift hook" || fail "bash -n one-copy-drift hook"
bash -n "${HOOK_TRUTH_CARD}" 2>/dev/null && pass "bash -n truth-card-inject hook" || fail "bash -n truth-card-inject hook"

# ── T1/T2 fixture: fake canonical root, stub convert script ────────────────
mk_one_copy_fixture() { # <regression-count>
  local n="$1" tmp root i
  tmp="$(lv2_mktemp_dir one-copy-cap-fixture)"
  root="${tmp}/canon"
  mkdir -p "${root}/.git" "${root}/plugins/leadv2/scripts"
  {
    printf '#!/usr/bin/env bash\n'
    if [[ "$n" -gt 0 ]]; then
      for ((i = 1; i <= n; i++)); do
        printf 'echo "[one-copy] REGRESSION: fixture-copy-%d.sh is a real file, identical to canonical, path=/some/long/fixture/path/to/make/the/line/realistic/copy-%d.sh" >&2\n' "$i" "$i"
      done
      printf 'echo "[one-copy] tally: linked=0 regression=%d badlink=0 expected_override=0 diverged=0 info=0" >&2\n' "$n"
      printf 'exit 1\n'
    else
      printf 'echo "[one-copy] tally: linked=5 regression=0 badlink=0 expected_override=0 diverged=0 info=0" >&2\n'
      printf 'exit 0\n'
    fi
  } > "${root}/plugins/leadv2/scripts/leadv2-one-copy-convert.sh"
  chmod +x "${root}/plugins/leadv2/scripts/leadv2-one-copy-convert.sh"
  printf '%s' "$root"
}

run_one_copy_hook() { # <root> <payload-json> <fake-home>
  local root="$1" payload="$2" home="$3" base
  base="$(lv2_mktemp_dir one-copy-cap-output)"
  printf '%s' "$payload" | \
    HOME="${home}" \
    CLAUDE_PLUGIN_ROOT="${root}/plugins/leadv2" \
    TMPDIR="${home}" \
    bash "${HOOK_ONE_COPY}" >"${base}/stdout" 2>"${base}/stderr"
  RC=$?
  STDOUT="$(<"${base}/stdout")"
  STDOUT_BYTES="$(wc -c < "${base}/stdout" | tr -d ' ')"
}

# T1: 100 regressions -> capped stdout, correct count, full detail on disk
FAKE_HOME="$(lv2_mktemp_dir one-copy-cap-home)"
ROOT1="$(mk_one_copy_fixture 100)"
run_one_copy_hook "$ROOT1" '{"source":"startup","cwd":"/tmp"}' "$FAKE_HOME"
DETAIL_LOG="${FAKE_HOME}/leadv2-one-copy-drift-detail.log"
if [[ "$RC" -eq 0 ]] \
   && [[ "$STDOUT_BYTES" -lt "$CAP_BYTES" ]] \
   && grep -q '^100 regression(s)/badlink(s)\.' <<<"$STDOUT" \
   && grep -q "Full list: ${DETAIL_LOG}" <<<"$STDOUT" \
   && [[ -f "$DETAIL_LOG" ]] \
   && [[ "$(grep -cE '^\[one-copy\] REGRESSION' "$DETAIL_LOG")" -eq 100 ]]; then
  pass "T1 one-copy-drift: 100 regressions capped to ${STDOUT_BYTES}B, full detail on disk"
else
  fail "T1 one-copy-drift: 100 regressions capped (rc=$RC bytes=$STDOUT_BYTES stdout=$STDOUT)"
fi

# T2: clean tree -> unchanged silent behaviour, no cap path taken, no detail file
FAKE_HOME2="$(lv2_mktemp_dir one-copy-cap-home2)"
ROOT2="$(mk_one_copy_fixture 0)"
run_one_copy_hook "$ROOT2" '{"source":"startup","cwd":"/tmp"}' "$FAKE_HOME2"
if [[ "$RC" -eq 0 ]] && [[ -z "$STDOUT" ]] && [[ ! -f "${FAKE_HOME2}/leadv2-one-copy-drift-detail.log" ]]; then
  pass "T2 one-copy-drift: clean tree stays silent, no cap path"
else
  fail "T2 one-copy-drift: clean tree stays silent (rc=$RC stdout=$STDOUT)"
fi

# ── T3/T4 fixture: fake CWD with .env + state-paths.yaml + stubbed curl ────
mk_truth_card_fixture() { # <big|small|fail>
  local mode="$1" tmp cwd binroot
  tmp="$(lv2_mktemp_dir truth-card-cap-fixture)"
  cwd="${tmp}/repo"
  mkdir -p "${cwd}/.claude/leadv2-overrides"
  cat > "${cwd}/.claude/leadv2-overrides/state-paths.yaml" <<'YAML'
persona_id: "fixture-persona"
YAML
  cat > "${cwd}/.env" <<'ENV'
SUPABASE_URL=https://fixture.example.invalid
SUPABASE_SERVICE_ROLE_KEY=fixture-key
ENV
  binroot="${tmp}/bin"
  mkdir -p "$binroot"
  case "$mode" in
    big)
      # working_hours_json padded well past CAP_BYTES so the assembled card
      # crosses the truncation threshold.
      python3 - "$binroot/curl" <<'PY'
import sys
path = sys.argv[1]
big = "x" * 3000
row = {
    "as_of": "2026-08-30T00:00:00Z",
    "run_mode": "live",
    "control_mode": "auto",
    "v4_deterministic": True,
    "llm_backend": "claude",
    "active_flags": {},
    "working_hours_json": big,
}
import json
script = "#!/usr/bin/env bash\ncat <<'JSON'\n" + json.dumps([row]) + "\nJSON\n"
with open(path, "w") as fh:
    fh.write(script)
PY
      ;;
    small)
      cat > "${binroot}/curl" <<'CURL'
#!/usr/bin/env bash
cat <<'JSON'
[{"as_of":"2026-08-30T00:00:00Z","run_mode":"live","control_mode":"auto","v4_deterministic":true,"llm_backend":"claude","active_flags":{}}]
JSON
CURL
      ;;
    fail)
      cat > "${binroot}/curl" <<'CURL'
#!/usr/bin/env bash
printf ''
CURL
      ;;
  esac
  chmod +x "${binroot}/curl"
  printf '%s|%s' "$cwd" "$binroot"
}

run_truth_card_hook() { # <cwd> <binroot> <tmpdir>
  local cwd="$1" binroot="$2" tmp="$3" base
  base="$(lv2_mktemp_dir truth-card-cap-output)"
  printf '{"cwd":"%s"}' "$cwd" | \
    PATH="${binroot}:${PATH}" \
    TMPDIR="$tmp" \
    bash "${HOOK_TRUTH_CARD}" >"${base}/stdout" 2>"${base}/stderr"
  RC=$?
  STDOUT="$(<"${base}/stdout")"
  STDOUT_BYTES="$(wc -c < "${base}/stdout" | tr -d ' ')"
}

# T3: large truth card -> capped stdout, full card on disk
FIX3="$(mk_truth_card_fixture big)"
CWD3="${FIX3%%|*}"; BIN3="${FIX3##*|}"
TMP3="$(lv2_mktemp_dir truth-card-cap-tmp3)"
run_truth_card_hook "$CWD3" "$BIN3" "$TMP3"
# Extract the pointed-to path from stdout rather than re-deriving it (TMPDIR
# may carry a trailing slash bash preserves and python normalizes away).
FULL_CARD="$(sed -n 's/.*Full card: \([^"]*\)".*/\1/p' <<<"$STDOUT")"
if [[ "$RC" -eq 0 ]] \
   && [[ "$STDOUT_BYTES" -lt "$CAP_BYTES" ]] \
   && grep -q 'capped,' <<<"$STDOUT" \
   && [[ -n "$FULL_CARD" ]] \
   && [[ -f "$FULL_CARD" ]] \
   && grep -q 'PIPELINE HEALTH' "$FULL_CARD"; then
  pass "T3 truth-card-inject: large card capped to ${STDOUT_BYTES}B, full card on disk"
else
  fail "T3 truth-card-inject: large card capped (rc=$RC bytes=$STDOUT_BYTES stdout=$STDOUT)"
fi

# T4: small card -> unchanged direct emission, no disk file, cap path not taken
FIX4="$(mk_truth_card_fixture small)"
CWD4="${FIX4%%|*}"; BIN4="${FIX4##*|}"
TMP4="$(lv2_mktemp_dir truth-card-cap-tmp4)"
run_truth_card_hook "$CWD4" "$BIN4" "$TMP4"
SMALL_FULL_CARD="${TMP4}/leadv2-truth-card-full-fixture-persona.txt"
if [[ "$RC" -eq 0 ]] \
   && grep -q 'PIPELINE HEALTH' <<<"$STDOUT" \
   && ! grep -q 'capped,' <<<"$STDOUT" \
   && [[ ! -f "$SMALL_FULL_CARD" ]]; then
  pass "T4 truth-card-inject: small card emitted directly, no cap path"
else
  fail "T4 truth-card-inject: small card emitted directly (rc=$RC stdout=$STDOUT)"
fi

printf -- '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
