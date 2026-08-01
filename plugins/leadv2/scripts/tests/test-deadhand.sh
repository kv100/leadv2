#!/usr/bin/env bash
# test-deadhand.sh — offline tests for DISPATCH-DEADHAND-01 (the dead-hand
# disease: a bg worker exits 0 / RUN_COMPLETE WITHOUT writing its named
# deliverable, and nothing on the dispatch path notices).
#
# Exercises both channel wrappers (glm-coder.sh, kimi-coder.sh). NO real
# network / no real z.ai / no real `claude`: every scenario stubs the `claude`
# binary via the GLM_CLAUDE_BIN / KIMI_CLAUDE_BIN seams (fake executables emit
# canned stream-json lines and selectively write the deliverable file). Run
# state (RUNS_DIR) and secrets (SECRETS_FILE) are seam-overridden into an
# isolated tmp dir so tests never touch prod.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLM_CODER="${SCRIPT_DIR}/../glm-coder.sh"
KIMI_CODER="${SCRIPT_DIR}/../kimi-coder.sh"
THIS_TEST="${SCRIPT_DIR}/test-deadhand.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

FAILURES=0
PASSES=0
pass() { printf 'PASS: %s\n' "$1"; PASSES=$((PASSES + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAILURES=$((FAILURES + 1)); }

# ---------------------------------------------------------------------------
# case_bash_n — syntax-clean on all three scripts.
# ---------------------------------------------------------------------------
if bash -n "${GLM_CODER}" && bash -n "${KIMI_CODER}" && bash -n "${THIS_TEST}"; then
  pass "case_bash_n"
else
  fail "case_bash_n" "bash -n reported a syntax error"
fi

# ---------------------------------------------------------------------------
# Shared fixtures — isolated secrets + run-state dirs. Prod
# ~/.claude/cache/{glm,kimi}-runs/ and ~/.claude/secrets/*.env are NEVER touched.
# ---------------------------------------------------------------------------
SECRETS_DIR="${TMP_ROOT}/secrets"
mkdir -p "${SECRETS_DIR}"
FAKE_GLM_SECRETS="${SECRETS_DIR}/zai.env"
printf 'ZAI_AUTH_TOKEN=test-token-not-real\n' > "${FAKE_GLM_SECRETS}"
chmod 600 "${FAKE_GLM_SECRETS}"
FAKE_KIMI_SECRETS="${SECRETS_DIR}/tokenrouter.env"
printf 'TOKENROUTER_AUTH_TOKEN=test-token-not-real\n' > "${FAKE_KIMI_SECRETS}"
chmod 600 "${FAKE_KIMI_SECRETS}"

GLM_RUNS_DIR="${TMP_ROOT}/glm-runs"
KIMI_RUNS_DIR="${TMP_ROOT}/kimi-runs"
mkdir -p "${GLM_RUNS_DIR}" "${KIMI_RUNS_DIR}"

STUBS_DIR="${TMP_ROOT}/stubs"
mkdir -p "${STUBS_DIR}"

HANDOFF_DIR="docs/handoff/b5e776559cb0"
DELIV_FILE="${HANDOFF_DIR}/build-report.md"

# Mission prompt that names a deliverable (auto-parse target). The
# FINISH_CONTRACT_TRAILER wrapping contains neither "deliverable" nor a
# docs/handoff path, so this is the only source of a contract.
DELIV_PROMPT="Implement the scoped change. Deliverable: docs/handoff/b5e776559cb0/build-report.md ending DELIVERABLE_COMPLETE. Done."
NO_DELIV_PROMPT="Run the self-test and report findings. No file artifact required."
# N2-DEADHAND-SUBSTANCE: a code-shaped mission carries a LANE_WRITES: line
# naming a non-docs/ path -- this is what makes mission_is_code_shaped()
# return 1 and turns G3 (work-delta) on for a scenario.
CODE_DELIV_PROMPT="$(printf '%s\nLANE_WRITES: scripts/foo.sh' "${DELIV_PROMPT}")"

# stub-success-no-deliv: coherent non-error result, exits 0, writes NOTHING.
cat > "${STUBS_DIR}/success-no-deliv.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"type":"system","subtype":"init","model":"glm-5.2"}\n'
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}],"usage":{"input_tokens":10,"output_tokens":5}}}\n'
printf '{"type":"result","result":"done","is_error":false}\n'
exit 0
EOF

# stub-success-complete: exits 0 AND writes the deliverable ending in the
# terminal marker DELIVERABLE_COMPLETE. Satisfied contract -> NO flag.
cat > "${STUBS_DIR}/success-complete.sh" <<EOF
#!/usr/bin/env bash
printf '{"type":"system","subtype":"init","model":"glm-5.2"}\n'
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}],"usage":{"input_tokens":10,"output_tokens":5}}}\n'
mkdir -p "${HANDOFF_DIR}"
printf '# Build report\n\nWork shipped. This report describes the change in enough\ndetail to clear the N2-DEADHAND-SUBSTANCE byte floor (G2) on its own,\nindependent of any work-delta check.\n\nDELIVERABLE_COMPLETE\n' > "${DELIV_FILE}"
printf '{"type":"result","result":"done","is_error":false}\n'
exit 0
EOF

# stub-success-marker-missing: writes the deliverable file but its last
# non-empty line is prose (no terminal marker) -> flag (case_d).
cat > "${STUBS_DIR}/success-marker-missing.sh" <<EOF
#!/usr/bin/env bash
printf '{"type":"system","subtype":"init","model":"glm-5.2"}\n'
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}],"usage":{"input_tokens":10,"output_tokens":5}}}\n'
mkdir -p "${HANDOFF_DIR}"
printf '# Build report\n\nThis is my report, finished now.\n' > "${DELIV_FILE}"
printf '{"type":"result","result":"done","is_error":false}\n'
exit 0
EOF

# stub-tiny-deliv: writes ONLY the terminal marker (well under the 200-byte
# floor) -- the S-4 empty/near-empty prepass shape. Marker satisfies G1;
# byte floor (G2) must still catch it -> reason=too_small.
cat > "${STUBS_DIR}/tiny-deliv.sh" <<EOF
#!/usr/bin/env bash
printf '{"type":"system","subtype":"init","model":"glm-5.2"}\n'
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}],"usage":{"input_tokens":10,"output_tokens":5}}}\n'
mkdir -p "${HANDOFF_DIR}"
printf 'DELIVERABLE_COMPLETE\n' > "${DELIV_FILE}"
printf '{"type":"result","result":"done","is_error":false}\n'
exit 0
EOF

# stub-prose-no-diff: writes a large (>5KB) prose-only deliverable ending in
# the terminal marker, but touches NOTHING in the tracked tree -- the
# SWIFTBAR shape. G1+G2 both pass; G3 (work delta) must still catch it on a
# code-shaped mission -> reason=no_work_delta.
cat > "${STUBS_DIR}/prose-no-diff.sh" <<EOF
#!/usr/bin/env bash
printf '{"type":"system","subtype":"init","model":"glm-5.2"}\n'
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}],"usage":{"input_tokens":10,"output_tokens":5}}}\n'
mkdir -p "${HANDOFF_DIR}"
{
  printf '# Design doc\n\nNo implementation here.\n\n'
  for i in \$(seq 1 200); do printf 'This is filler prose line %d describing the design in detail.\n' "\${i}"; done
  printf '\nDELIVERABLE_COMPLETE\n'
} > "${DELIV_FILE}"
printf '{"type":"result","result":"done","is_error":false}\n'
exit 0
EOF

# stub-genuine: writes a substantive (>5KB) deliverable ending in the
# terminal marker AND modifies the tracked file scripts/foo.sh -- the
# anti-false-red control. All three gates must pass -> no flag.
cat > "${STUBS_DIR}/genuine.sh" <<EOF
#!/usr/bin/env bash
printf '{"type":"system","subtype":"init","model":"glm-5.2"}\n'
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}],"usage":{"input_tokens":10,"output_tokens":5}}}\n'
mkdir -p scripts
printf '#!/usr/bin/env bash\necho "implemented"\n' > scripts/foo.sh
mkdir -p "${HANDOFF_DIR}"
{
  printf '# Build report\n\nImplemented scripts/foo.sh.\n\n'
  for i in \$(seq 1 100); do printf 'Detail line %d of the implementation.\n' "\${i}"; done
  printf '\nDELIVERABLE_COMPLETE\n'
} > "${DELIV_FILE}"
printf '{"type":"result","result":"done","is_error":false}\n'
exit 0
EOF

chmod +x "${STUBS_DIR}"/*.sh

# run_scenario <tag> <wrapper> <stub> <prompt> [env_var_expr...]
# Prints the resulting run_dir path on stdout; isolates a fresh cwd repo per
# tag so deliverable files from one case never leak into another. Polls
# meta.yaml until it leaves "running", then echoes run_dir.
run_scenario() {
  local tag="$1" wrapper="$2" stub="$3" prompt="$4"
  shift 4
  local runs_dir secret_file claude_bin
  if [[ "${wrapper}" == "${GLM_CODER}" ]]; then
    runs_dir="${GLM_RUNS_DIR}"; secret_file="${FAKE_GLM_SECRETS}"; claude_bin_var="GLM_CLAUDE_BIN"
  else
    runs_dir="${KIMI_RUNS_DIR}"; secret_file="${FAKE_KIMI_SECRETS}"; claude_bin_var="KIMI_CLAUDE_BIN"
  fi
  local cwd_dir="${TMP_ROOT}/repo-${tag}"
  rm -rf "${cwd_dir}"
  mkdir -p "${cwd_dir}"
  # N2-DEADHAND-SUBSTANCE: every scenario repo is a real git work tree with a
  # committed baseline (scripts/foo.sh tracked) BEFORE `bg` dispatches, so
  # work_baseline() captures a clean starting point and G3 (work-delta) is
  # exercisable/skippable deterministically per scenario.
  ( cd "${cwd_dir}" \
      && git init -q \
      && git config user.email 'test@example.com' \
      && git config user.name 'test' \
      && mkdir -p scripts docs \
      && printf '#!/usr/bin/env bash\necho baseline\n' > scripts/foo.sh \
      && git add -A \
      && git commit -q -m baseline )

  local run_id raw
  if [[ "${wrapper}" == "${GLM_CODER}" ]]; then
    raw="$(
      cd "${cwd_dir}" && \
      GLM_SECRETS_FILE="${secret_file}" \
      GLM_RUNS_DIR="${runs_dir}" \
      GLM_CLAUDE_BIN="${stub}" \
      GLM_TIMEOUT=30 \
      "$@" bash "${wrapper}" bg "${prompt}"
    )"
  else
    raw="$(
      cd "${cwd_dir}" && \
      KIMI_SECRETS_FILE="${secret_file}" \
      KIMI_RUNS_DIR="${runs_dir}" \
      KIMI_CLAUDE_BIN="${stub}" \
      KIMI_SKIP_LAUNCH_PROBE=1 \
      "$@" bash "${wrapper}" bg "${prompt}"
    )"
  fi
  # The run_id is the final echoed line of `bg`; gates/probes may print other
  # lines to stdout first, so match the run-id shape (yymmdd-HHMMSS-...) only.
  run_id="$(printf '%s\n' "${raw}" | grep -E '^[0-9]{6}-[0-9]{6}-' | tail -1)"
  [[ -n "${run_id}" ]] || { fail "$TAG" "could not parse run_id from bg output"; printf 'none\n'; return; }

  local run_dir="${runs_dir}/${run_id}"
  local waited=0
  # N2-DEADHAND-SUBSTANCE r2: poll for the `.finalized` sentinel, not
  # meta.yaml's status field. finalize_meta (which flips status away from
  # "running") runs BEFORE deadhand_check, so a status-based barrier can
  # release while .no-deliverable is still milliseconds from being written
  # -- that race, not a kimi-mirror divergence, was the source of case_j's
  # flakiness. `.finalized` is written only after both have completed.
  while [[ "${waited}" -lt 30 ]]; do
    [[ -f "${run_dir}/.finalized" ]] && break
    sleep 1
    waited=$((waited + 1))
  done
  printf '%s\n' "${run_dir}"
}

# wait/assert helpers operating on a run_dir.
assert_flagged() { # <run_dir> <abs_deliverable_path>
  # <run_dir> <abs_deliverable_path> <expected_reason>
  local run_dir="$1" path="$2" want_reason="${3:?assert_flagged requires an expected reason}"
  local nd="${run_dir}/.no-deliverable"
  local want="LEADV2_WORKER_NO_DELIVERABLE path=${path} exit=0 reason=${want_reason}"
  if [[ ! -f "${nd}" ]]; then
    fail "$TAG" ".no-deliverable missing"; return; fi
  if ! grep -Fxq "${want}" "${run_dir}/progress.log"; then
    fail "$TAG" "progress.log lacks exact line: ${want}"; return; fi
  if ! grep -Fxq "${want}" "${run_dir}/meta.yaml"; then
    fail "$TAG" "meta.yaml lacks exact line: ${want}"; return; fi
  # .no-deliverable content must name the path (R: assert file exists, then content).
  if ! grep -Fxq "path=${path}" "${nd}"; then
    fail "$TAG" ".no-deliverable path line wrong"; return; fi
  if ! grep -Fxq "reason=${want_reason}" "${nd}"; then
    fail "$TAG" ".no-deliverable reason line wrong (want reason=${want_reason})"; return; fi
  pass "$TAG (flagged: .no-deliverable + progress.log + meta.yaml exact line, reason=${want_reason})"
}

assert_clean() { # <run_dir> <abs_deliverable_path>
  local run_dir="$1" path="$2"
  if [[ -f "${run_dir}/.no-deliverable" ]]; then
    fail "$TAG" "unexpected .no-deliverable"; return; fi
  if grep -q 'LEADV2_WORKER_NO_DELIVERABLE' "${run_dir}/progress.log"; then
    fail "$TAG" "unexpected flag in progress.log"; return; fi
  if grep -q 'LEADV2_WORKER_NO_DELIVERABLE' "${run_dir}/meta.yaml"; then
    fail "$TAG" "unexpected flag in meta.yaml"; return; fi
  pass "$TAG (no flag artifacts)"
}

# ---------------------------------------------------------------------------
# case_a_missing_file: deliverable named, worker exits 0 writing nothing ->
# flagged.
# ---------------------------------------------------------------------------
TAG="case_a_missing_file"
RD="$(run_scenario "${TAG}" "${GLM_CODER}" "${STUBS_DIR}/success-no-deliv.sh" "${DELIV_PROMPT}")"
EXPECTED_PATH="${TMP_ROOT}/repo-${TAG}/${DELIV_FILE}"
assert_flagged "${RD}" "${EXPECTED_PATH}" "missing"

# ---------------------------------------------------------------------------
# case_b_complete: worker writes deliverable ending DELIVERABLE_COMPLETE ->
# no flag.
# ---------------------------------------------------------------------------
TAG="case_b_complete"
RD="$(run_scenario "${TAG}" "${GLM_CODER}" "${STUBS_DIR}/success-complete.sh" "${DELIV_PROMPT}")"
EXPECTED_PATH="${TMP_ROOT}/repo-${TAG}/${DELIV_FILE}"
assert_clean "${RD}" "${EXPECTED_PATH}"

# ---------------------------------------------------------------------------
# case_c_no_contract: mission mentions no deliverable path -> feature inert,
# no .deliverable, no flag.
# ---------------------------------------------------------------------------
TAG="case_c_no_contract"
RD="$(run_scenario "${TAG}" "${GLM_CODER}" "${STUBS_DIR}/success-no-deliv.sh" "${NO_DELIV_PROMPT}")"
EXPECTED_PATH="${TMP_ROOT}/repo-${TAG}/${DELIV_FILE}"
if [[ -f "${RD}/.deliverable" ]]; then
  fail "$TAG" ".deliverable should not exist when no contract derivable"
else
  assert_clean "${RD}" "${EXPECTED_PATH}"
fi

# ---------------------------------------------------------------------------
# case_d_marker_missing: deliverable written, last line is prose -> flag.
# ---------------------------------------------------------------------------
TAG="case_d_marker_missing"
RD="$(run_scenario "${TAG}" "${GLM_CODER}" "${STUBS_DIR}/success-marker-missing.sh" "${DELIV_PROMPT}")"
EXPECTED_PATH="${TMP_ROOT}/repo-${TAG}/${DELIV_FILE}"
assert_flagged "${RD}" "${EXPECTED_PATH}" "marker"

# ---------------------------------------------------------------------------
# case_e_env_override: LEADV2_DELIVERABLE set explicitly, mission silent ->
# contract captured from env; missing file -> flag.
# ---------------------------------------------------------------------------
TAG="case_e_env_override"
ENV_DELIV="${TMP_ROOT}/repo-${TAG}/${DELIV_FILE}"
# Pre-export LEADV2_DELIVERABLE so it is inherited by the bg'd supervisor.
export LEADV2_DELIVERABLE="${ENV_DELIV}"
RD="$(run_scenario "${TAG}" "${GLM_CODER}" "${STUBS_DIR}/success-no-deliv.sh" "${NO_DELIV_PROMPT}")"
unset LEADV2_DELIVERABLE
assert_flagged "${RD}" "${ENV_DELIV}" "missing"

# ---------------------------------------------------------------------------
# case_f_kimi_mirror: case_a repeated through kimi-coder.sh -> identical flag.
# ---------------------------------------------------------------------------
TAG="case_f_kimi_mirror"
RD="$(run_scenario "${TAG}" "${KIMI_CODER}" "${STUBS_DIR}/success-no-deliv.sh" "${DELIV_PROMPT}")"
EXPECTED_PATH="${TMP_ROOT}/repo-${TAG}/${DELIV_FILE}"
assert_flagged "${RD}" "${EXPECTED_PATH}" "missing"

# ---------------------------------------------------------------------------
# case_g_empty_deliverable (N2-DEADHAND-SUBSTANCE, S-4 shape): deliverable
# holds ONLY the terminal marker (well under the byte floor) -> G1 passes,
# G2 (substance floor) catches it. The marker must NOT be able to rescue an
# empty/near-empty file.
# ---------------------------------------------------------------------------
TAG="case_g_empty_deliverable"
RD="$(run_scenario "${TAG}" "${GLM_CODER}" "${STUBS_DIR}/tiny-deliv.sh" "${DELIV_PROMPT}")"
EXPECTED_PATH="${TMP_ROOT}/repo-${TAG}/${DELIV_FILE}"
assert_flagged "${RD}" "${EXPECTED_PATH}" "too_small"

# ---------------------------------------------------------------------------
# case_h_prose_only_no_diff (N2-DEADHAND-SUBSTANCE, SWIFTBAR shape): mission
# is code-shaped (LANE_WRITES: scripts/foo.sh), stub writes a >5KB prose
# deliverable ending DELIVERABLE_COMPLETE but leaves the tracked tree
# untouched -> G1+G2 pass, G3 (work delta) catches it. The marker must NOT
# be able to rescue a prose-only "deliverable" that did no code work.
# ---------------------------------------------------------------------------
TAG="case_h_prose_only_no_diff"
RD="$(run_scenario "${TAG}" "${GLM_CODER}" "${STUBS_DIR}/prose-no-diff.sh" "${CODE_DELIV_PROMPT}")"
EXPECTED_PATH="${TMP_ROOT}/repo-${TAG}/${DELIV_FILE}"
assert_flagged "${RD}" "${EXPECTED_PATH}" "no_work_delta"

# ---------------------------------------------------------------------------
# case_i_genuine_run (anti-false-red): same code-shaped mission, stub edits
# the tracked scripts/foo.sh AND writes a substantive (>5KB) deliverable
# ending DELIVERABLE_COMPLETE -> all three gates pass, no flag. Proves G3
# does not trade a false-green for a false-red on a genuine run.
# ---------------------------------------------------------------------------
TAG="case_i_genuine_run"
RD="$(run_scenario "${TAG}" "${GLM_CODER}" "${STUBS_DIR}/genuine.sh" "${CODE_DELIV_PROMPT}")"
EXPECTED_PATH="${TMP_ROOT}/repo-${TAG}/${DELIV_FILE}"
assert_clean "${RD}" "${EXPECTED_PATH}"

# ---------------------------------------------------------------------------
# case_j_kimi_mirror: case_h repeated through kimi-coder.sh -> identical
# sentinel + reason (twin-drift guard for the G1-G3 conjunction, not just
# the original single-marker check).
# ---------------------------------------------------------------------------
TAG="case_j_kimi_mirror"
RD="$(run_scenario "${TAG}" "${KIMI_CODER}" "${STUBS_DIR}/prose-no-diff.sh" "${CODE_DELIV_PROMPT}")"
EXPECTED_PATH="${TMP_ROOT}/repo-${TAG}/${DELIV_FILE}"
assert_flagged "${RD}" "${EXPECTED_PATH}" "no_work_delta"

echo "---"
echo "PASS=${PASSES} FAIL=${FAILURES}"
if [[ "${FAILURES}" -eq 0 ]]; then
  exit 0
else
  exit 1
fi
