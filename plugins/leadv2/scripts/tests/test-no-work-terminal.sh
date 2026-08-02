#!/usr/bin/env bash
# N1-EMPTY-LANE-IS-NOT-A-PASS — falsifying harness for Design A.
# Asserts an empty lane diff closes as terminal=no_work (cause empty_diff),
# never passed; e2e-gate-passed.flag is absent; review-gate.md reason=no_work;
# exit 5; partial_diff stays refused; and a no_work ledger row renders RED
# (no-work(...), cls dead) and is NOT laundered into green done(...) even when
# old (R1). New file (R5): the six named suites keep their exact counts.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PC="${SCRIPT_DIR}/leadv2-dispatch-product-close.sh"
SURFACE="${SCRIPT_DIR}/leadv2-status-surface.sh"
PASS=0; FAIL=0
ok()   { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }
assert_eq() { if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

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

new_repo() {
  local root="$1"
  mkdir -p "${root}/agent"
  ( cd "${root}" && git init -q -b main && git config user.email t@e.com && git config user.name t \
    && printf 'seed\n' > agent/seed.py && git add agent/seed.py && git commit -qm seed ) >/dev/null 2>&1
}

# ---- Case 1: empty diff -> no_work / empty_diff, no e2e flag, exit 5 ---------
case_empty_no_work() {
  local d root
  d="$(mktemp -d)"; root="${d}/repo"; mkdir -p "${root}"
  new_repo "${root}"; make_stubs "${d}"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" \
    LEADV2_JOURNAL_BIN="${d}/journal.sh" \
    LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
    bash "${PC}" "${root}" nw1sig001 sonnet "" 1 1 "founder-nw1" >/dev/null 2>&1
  local rc=$?
  local handoff="${root}/docs/handoff/dispatch-nw1sig001"
  assert_eq "${rc}" "5" "empty-diff exits 5"
  if [[ -f "${handoff}/review-gate.md" ]] && grep -q '^reason: no_work$' "${handoff}/review-gate.md"; then
    ok "review-gate.md reason=no_work"
  else bad "review-gate.md reason=no_work (got: $(cat "${handoff}/review-gate.md" 2>/dev/null))"
  fi
  if [[ ! -f "${handoff}/e2e-gate-passed.flag" ]]; then ok "e2e-gate-passed.flag absent"; else bad "e2e-gate-passed.flag present"; fi
  if grep -q 'terminal=no_work cause=empty_diff' "${d}/journal.log" 2>/dev/null; then
    ok "ledger decision line terminal=no_work cause=empty_diff"
  else bad "ledger decision line missing (got: $(grep review_gate "${d}/journal.log" 2>/dev/null | tail -1))"
  fi
  rm -rf "${d}"
}

# ---- Case 2: partial_diff (mixed group) stays refused -----------------------
case_partial_stays_refused() {
  local d plugin target
  d="$(mktemp -d)"; plugin="${d}/plugin-repo"; target="${d}/target-repo"
  mkdir -p "${plugin}/scripts" "${target}/.claude/scripts" "${target}/agent"
  ( cd "${plugin}" && git init -q -b main && git config user.email t@e.com && git config user.name t \
    && printf 'orig\n' > scripts/foo.sh && git add scripts/foo.sh && git commit -qm seed ) >/dev/null 2>&1
  printf 'orig\npatched\n' > "${plugin}/scripts/foo.sh"
  ( cd "${target}" && git init -q -b main && git config user.email t@e.com && git config user.name t \
    && printf 'seed\n' > agent/seed.py && ln -s "${plugin}/scripts/foo.sh" .claude/scripts/foo.sh \
    && git add agent/seed.py .claude/scripts/foo.sh && git commit -qm seed ) >/dev/null 2>&1
  make_stubs "${d}"
  CLAUDE_PROJECT_ROOT="${target}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    LEADV2_LANE_WORK_ROOT="${target}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py,.claude/scripts/foo.sh" \
    LEADV2_JOURNAL_BIN="${d}/journal.sh" \
    LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
    bash "${PC}" "${target}" nw2sig002 sonnet "" 0 1 "founder-nw2" >/dev/null 2>&1
  local gate="${target}/docs/handoff/dispatch-nw2sig002/review-gate.md"
  if [[ -f "${gate}" ]] && grep -q '^reason: partial_diff$' "${gate}"; then
    ok "partial_diff stays refused (reason=partial_diff, not no_work)"
  else bad "partial_diff should stay refused (got: $(cat "${gate}" 2>/dev/null))"
  fi
  rm -rf "${d}"
}

# ---- Case 3 (R1): a no_work terminal row renders RED, never done(...) --------
case_surface_no_work_not_done() {
  local SB NOW LEDGER DIR
  SB="$(mktemp -d)"; DIR="${SB}/state"; LEDGER="${SB}/ledger"; mkdir -p "${DIR}" "${LEDGER}"
  NOW=$(( $(date +%s) ))
  # 30min old: lands on stale(...) for lack of any live signal, but inside the
  # DEAD_TTL window so it is NOT age-dropped before render. task_sig is the 8-char
  # sig the surface keys on; the row lives at ${LEDGER_DIR}/${REPO}.jsonl.
  local old=$(( NOW - 1800 ))
  printf '{"task_sig":"nw3sig00","founder_task_id":"founder-nw3","terminal":"no_work","cause":"empty_diff","created_epoch":%s,"task_id":"founder-nw3"}\n' "${old}" \
    > "${LEDGER}/testrepo.jsonl"
  : > "${DIR}/active.yaml"
  local out
  out="$(LEADV2_STATUS_STATE_DIR="${DIR}" \
         LEADV2_STATUS_LEDGER_DIR="${LEDGER}" \
         LEADV2_STATUS_RUNS_ROOT="${SB}/cache" \
         LEADV2_STATUS_REPO="testrepo" \
         LEADV2_STATUS_REPO_ROOT="${SB}" \
         LEADV2_STATUS_NOW="${NOW}" \
         LEADV2_STATUS_TASKS_YAML="${SB}/tasks.yaml" \
         bash "${SURFACE}" 2>/dev/null || true)"
  if printf '%s' "${out}" | grep -q 'no-work(empty-diff)'; then
    ok "surface renders no-work(empty-diff)"
  else bad "surface should render no-work(empty-diff) (got: $(printf '%s' "${out}" | grep -i nw3 || echo '<row absent>'))"
  fi
  if printf '%s' "${out}" | grep -qE 'done\(no_work|done\(terminal\)'; then
    bad "R1: no_work row laundered into done(...)"
  else ok "R1: no_work row NOT laundered into done(...)"
  fi
  rm -rf "${SB}"
}

case_empty_no_work
case_partial_stays_refused
case_surface_no_work_not_done

printf '\n=== %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == 0 ]]
