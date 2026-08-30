#!/usr/bin/env bash
# FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01 — the worker output gate must reject any
# changed *.sh/*.py that does not parse, for EVERY arm, not just freepool.
# Two of the three unusable free-arm results measured 2026-08-30 were a
# syntactically broken hook line (literal \n, unclosed quote) and a
# bash -n-failing test suite committed four times -- both are exactly what
# this gate exists to catch before the result is recorded as done.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GATE="${SCRIPTS_ROOT}/lib/leadv2-worker-output-gate.sh"
CODER="${SCRIPTS_ROOT}/freepool-coder.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/wog-test.XXXXXX")"
trap '[[ "${WOG_KEEP:-0}" == "1" ]] || rm -rf "$TMP"' EXIT

bash -n "$GATE" || { fail "bash syntax: gate"; exit 1; }
pass "bash syntax: gate"

REPO="$TMP/repo"
mkdir -p "$REPO"

# ── clean *.sh and *.py: gate passes ───────────────────────────────────────
printf '#!/usr/bin/env bash\necho ok\n' > "$REPO/good.sh"
printf 'x = 1\nprint(x)\n' > "$REPO/good.py"
out="$(bash "$GATE" "$REPO" good.sh good.py 2>&1)"; rc=$?
if [[ $rc -eq 0 && -z "$out" ]]; then
  pass "clean sh+py: gate exits 0 with no reject lines"
else
  fail "clean sh+py: expected rc0/no output, got rc=$rc out=$out"
fi

# ── broken *.sh (exact shape of the 2026-08-30 incident: unclosed quote) ──
printf '#!/usr/bin/env bash\necho "unclosed\n' > "$REPO/broken.sh"
out="$(bash "$GATE" "$REPO" broken.sh 2>&1)"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q 'worker_output_gate_reject file=broken.sh tool=bash-n'; then
  pass "broken sh: gate rejects with bash-n error attached (behavioural, real bash -n run)"
else
  fail "broken sh: expected reject, got rc=$rc out=$out"
fi

# ── broken *.py (empty function body -- exact shape of the other incident) ─
printf 'def f():\n    pass\n\ndef g():\n' > "$REPO/broken.py"
out="$(bash "$GATE" "$REPO" broken.py 2>&1)"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q 'worker_output_gate_reject file=broken.py tool=py_compile'; then
  pass "broken py: gate rejects with py_compile error attached"
else
  fail "broken py: expected reject, got rc=$rc out=$out"
fi

# ── non-code file (e.g. *.md) is never checked ─────────────────────────────
printf '# not shell, not python, has "quotes and (parens\n' > "$REPO/notes.md"
out="$(bash "$GATE" "$REPO" notes.md 2>&1)"; rc=$?
if [[ $rc -eq 0 && -z "$out" ]]; then
  pass "non-code file: ignored, gate exits 0"
else
  fail "non-code file: expected pass-through, got rc=$rc out=$out"
fi

# ── --from-git-diff mode: real git repo, staged broken file ───────────────
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@e.com; git -C "$REPO" config user.name t
: > "$REPO/seed"; git -C "$REPO" add seed; git -C "$REPO" commit -qm seed
git -C "$REPO" update-ref refs/remotes/origin/main HEAD

# A good committed worker has an empty working diff. This must pass on the
# macOS Bash 3.2 runtime rather than expanding an unbound empty array.
out="$(bash "$GATE" "$REPO" --from-git-diff HEAD 2>&1)"; rc=$?
if [[ $rc -eq 0 && -z "$out" ]]; then
  pass "empty git diff: gate passes under bash 3.2 with no unbound-array crash"
else
  fail "empty git diff: expected rc0/no output, got rc=$rc out=$out"
fi

cp "$REPO/broken.sh" "$REPO/worker-change.sh"
git -C "$REPO" add worker-change.sh
out="$(bash "$GATE" "$REPO" --from-git-diff --cached 2>&1)"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q 'worker_output_gate_reject file=worker-change.sh tool=bash-n'; then
  pass "--from-git-diff: staged broken .sh caught from real git diff output"
else
  fail "--from-git-diff: expected reject, got rc=$rc out=$out"
fi

# A worker that commits leaves no working diff. The gate must still inspect
# origin/main...HEAD and reject a committed bad shell file.
git -C "$REPO" commit -qm 'worker committed broken shell'
out="$(bash "$GATE" "$REPO" --from-git-diff HEAD 2>&1)"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q 'worker_output_gate_reject file=worker-change.sh tool=bash-n'; then
  pass "committed range: clean tree still rejects broken origin/main...HEAD file"
else
  fail "committed range: expected reject from origin/main...HEAD, got rc=$rc out=$out"
fi

# ── mutation control: disable the *.sh branch in a scratch gate copy ───────
# Never mutate a plugin file in place: an interrupted test must leave
# production bytes untouched.
MUT_MARK='*.sh)'
if ! grep -qF "$MUT_MARK" "$GATE"; then
  fail "mutation anchor not found in production gate -- cannot prove the control" "zero-match"
else
  MUTATED_GATE="$TMP/leadv2-worker-output-gate.mutated.sh"
  cp "$GATE" "$MUTATED_GATE"
  # Replace the *.sh case arm with a no-op arm so a broken .sh is never
  # checked -- the exact regression this gate exists to prevent.
python3 - "$MUTATED_GATE" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
anchor = '''      *.sh)
        if ! err="$(bash -n "$abspath" 2>&1 1>/dev/null)"; then
          printf 'worker_output_gate_reject file=%s tool=bash-n\\n' "$f"
          printf '%s\\n' "$err"
          rc=1
        fi
        ;;'''
replacement = '''      *.sh)
        :  # MUTATED: sh check disabled
        ;;'''
if anchor not in src:
    sys.exit("mutation anchor not found -- zero-match, hard failure")
open(path, 'w').write(src.replace(anchor, replacement, 1))
PY
  if [[ $? -ne 0 ]]; then
    fail "mutation replace failed -- anchor text drifted" "zero-match"
  else
    bash -n "$MUTATED_GATE" || fail "mutated gate fails its own bash -n"
    out_red="$(bash "$MUTATED_GATE" "$REPO" broken.sh 2>&1)"; rc_red=$?
    if [[ $rc_red -eq 0 ]]; then
      pass "(red) mutated gate silently accepts the broken .sh -- control is falsifiable"
    else
      fail "(red) mutation did not flip the outcome" "rc=$rc_red out=$out_red"
    fi
    out_green="$(bash "$GATE" "$REPO" broken.sh 2>&1)"; rc_green=$?
    if [[ $rc_green -ne 0 ]] && printf '%s' "$out_green" | grep -q 'worker_output_gate_reject file=broken.sh tool=bash-n'; then
      pass "(green) restored gate rejects the broken .sh again"
    else
      fail "(green) restore did not bring back the reject" "rc=$rc_green out=$out_green"
    fi
  fi
fi

# ── production call path: freepool-coder invokes the gate after finalizing ─
# A fake worker commits a bash-n-broken file and returns a coherent result.
# The real coder must mark the run parse_error; a throwaway copy with the
# call site removed must reproduce the false pass. The supervisor is polled
# to .finalized before this test ends.
CALL_REPO="$TMP/call-repo"
mkdir -p "$CALL_REPO"
git -C "$CALL_REPO" init -q -b main
git -C "$CALL_REPO" config user.email t@e.com; git -C "$CALL_REPO" config user.name t
printf '#!/usr/bin/env bash\necho baseline\n' > "$CALL_REPO/worker.sh"
git -C "$CALL_REPO" add worker.sh; git -C "$CALL_REPO" commit -qm baseline
git -C "$CALL_REPO" update-ref refs/remotes/origin/main HEAD

FAKE_CLAUDE="$TMP/fake-claude.sh"
cat > "$FAKE_CLAUDE" <<'EOF'
#!/usr/bin/env bash
printf '#!/usr/bin/env bash\necho "unclosed\n' > worker.sh
git add worker.sh && git commit -qm 'broken worker output'
mkdir -p docs/handoff/test
{ printf '# Report\n\n'; i=0; while [[ $i -lt 60 ]]; do printf 'completed worker output evidence line %s\n' "$i"; i=$((i + 1)); done; printf 'DELIVERABLE_COMPLETE\n'; } > docs/handoff/test/report.md
printf '{"type":"result","result":"done","is_error":false}\n'
EOF
chmod +x "$FAKE_CLAUDE"
printf 'FREEPOOL_AUTH_TOKEN=test\n' > "$TMP/freepool.env"
chmod 600 "$TMP/freepool.env"

run_coder_path() { # <coder-bin> <runs-dir>
  local coder_bin="$1" runs_dir="$2" raw run_id run_dir waited=0
  raw="$(cd "$CALL_REPO" && FREEPOOL_SECRETS_FILE="$TMP/freepool.env" FREEPOOL_RUNS_DIR="$runs_dir" \
    FREEPOOL_CLAUDE_BIN="$FAKE_CLAUDE" FREEPOOL_SKIP_GATE=1 FREEPOOL_SKIP_MODEL_SELECT=1 FREEPOOL_TEST_NO_REDACT=1 \
    FREEPOOL_TIMEOUT=20 FREEPOOL_STALL_S=20 FREEPOOL_TURN_LIMIT=20 FREEPOOL_NO_PROGRESS_S=20 \
    bash "$coder_bin" bg 'Deliverable: docs/handoff/test/report.md ending DELIVERABLE_COMPLETE.')"
  run_id="$(printf '%s\n' "$raw" | grep -E '^[0-9]{6}-[0-9]{6}-' | tail -1)"
  [[ -n "$run_id" ]] || return 1
  run_dir="$runs_dir/$run_id"
  while [[ $waited -lt 20 && ! -f "$run_dir/.finalized" ]]; do sleep 1; waited=$((waited + 1)); done
  [[ -f "$run_dir/.finalized" ]] || return 1
  printf '%s\n' "$run_dir"
}

RUNS_GREEN="$TMP/runs-green"; mkdir -p "$RUNS_GREEN"
CALL_GREEN="$(run_coder_path "$CODER" "$RUNS_GREEN")"; call_rc=$?
if [[ $call_rc -eq 0 && -f "$CALL_GREEN/.no-deliverable" ]] && grep -q 'reason=parse_error' "$CALL_GREEN/.no-deliverable"; then
  pass "production call path: freepool-coder rejects committed bash-n failure as parse_error"
else
  fail "production call path: expected parse_error from real coder call (rc=$call_rc run=${CALL_GREEN:-none})"
fi

MUT_ROOT="$TMP/mutated-scripts"
cp -R "$SCRIPTS_ROOT" "$MUT_ROOT"
MUT_CODER="$MUT_ROOT/freepool-coder.sh"
python3 - "$MUT_CODER" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
anchor = '''if gate_out="$(bash "${gate_lib}" "${cwd_dir}" --from-git-diff HEAD 2>&1)"; then
              gate_rc=0
            else
              gate_rc=$?
            fi'''
if anchor not in src:
    sys.exit("mutation anchor not found -- zero-match, hard failure")
open(path, "w").write(src.replace(anchor, 'gate_out=""; gate_rc=0  # MUTATED: output gate call removed', 1))
PY
if [[ $? -ne 0 ]]; then
  fail "production-call mutation: call-site anchor missing" "zero-match"
else
  git -C "$CALL_REPO" reset --hard -q origin/main
  RUNS_RED="$TMP/runs-red"; mkdir -p "$RUNS_RED"
  CALL_RED="$(run_coder_path "$MUT_CODER" "$RUNS_RED")"; call_red_rc=$?
  if [[ $call_red_rc -eq 0 && ! -f "$CALL_RED/.no-deliverable" ]]; then
    pass "MUTATION KILLED: removing freepool-coder gate call falsely accepts committed broken output"
  else
    fail "MUTATION KILLED: call-site mutation did not reproduce false pass (rc=$call_red_rc run=${CALL_RED:-none})"
  fi
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
