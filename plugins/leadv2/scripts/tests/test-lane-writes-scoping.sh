#!/usr/bin/env bash
# tests/test-lane-writes-scoping.sh — LANDING-BLOCKER round 2 (lane-writes review scoping).
#
# Red-first harness (LANDING-BLOCKER-R2 §3): every case_X runs TWICE, once against a
# `git archive HEAD` extraction (PREFIX_SCRIPTS -- committed baseline, pre-round-1 AND
# pre-round-2) and once against this working tree (SCRIPT_DIR -- round-1 + round-2
# applied). case_X must FAIL against PREFIX_SCRIPTS and PASS against SCRIPT_DIR. A case
# that passes against BOTH is reported as GREEN-PRE-FIX, not silently counted as a pass --
# round 1 is uncommitted on disk, so HEAD is genuinely pre-fix; NEVER git stash/reset/clean.
#
# Round 1's own 14 assertions had 7 green-pre-fix (four `bash -n` checks, worker-spawned,
# launcher-exits-0, and the M3-c kill-switch check) and ZERO covering the two defects that
# mattered (C1: worker cwd vs diff root disagree; C2: untracked new files never diffed).
# This file replaces that suite; every assertion below is shown red against HEAD.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANE_WT_BIN="${SCRIPT_DIR}/leadv2-lane-worktree.sh"

PASS=0
FAIL=0
GREEN_PRE_FIX=0
COULD_NOT_RUN=0
ERRORS=()

log()  { printf -- '[TEST] %s\n' "$*"; }

# ── 0. syntax check on all four LANE_WRITES-declared scripts, both interpreters ────
for f in leadv2-dispatch-code.sh leadv2-dispatch-product-close.sh \
         leadv2-fanout-lane-launcher.sh; do
  if bash -n "${SCRIPT_DIR}/${f}" 2>/dev/null; then
    PASS=$((PASS + 1)); log "PASS: bash -n ${f}"
  else
    FAIL=$((FAIL + 1)); ERRORS+=("bash -n ${f}"); log "FAIL: bash -n ${f}"
  fi
done
# M9 (LANDING-BLOCKER-R2): standing guard -- product-close.sh must parse under bash 3.2
# (no `declare -A`, no `mapfile`, no `${var,,}`, no `&>>`) since dispatch-code.sh resolves
# `bash` from PATH to invoke it, and a PATH without homebrew hits /bin/bash 3.2 on macOS.
if /bin/bash -n "${SCRIPT_DIR}/leadv2-dispatch-product-close.sh" 2>/dev/null; then
  PASS=$((PASS + 1)); log "PASS: /bin/bash -n leadv2-dispatch-product-close.sh (bash 3.2 syntax)"
else
  FAIL=$((FAIL + 1)); ERRORS+=("/bin/bash -n product-close.sh"); log "FAIL: /bin/bash -n leadv2-dispatch-product-close.sh"
fi

# ── shared fixtures ─────────────────────────────────────────────────────────────
new_repo() { # -> repo path, git-init'd with a baseline commit
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-lwt.XXXXXX")"
  ( cd "${d}" && git init -q -b main && git config user.email test@example.com \
    && git config user.name test && mkdir -p agent \
    && printf 'seed\n' > agent/seed.py && git add agent/seed.py && git commit -qm seed ) >/dev/null 2>&1
  printf '%s' "${d}"
}

worktree_path() { # <repo> <task_id> -> ABS worktree path (may not exist)
  printf '%s/.claude/worktrees/%s' "$1" "$2"
}

ensure_worktree() { # <repo> <task_id> -> worktree path (real, out-of-scope binary)
  LEADV2_PROJECT_ROOT="$1" bash "${LANE_WT_BIN}" ensure "$2" standard >/dev/null 2>&1
  worktree_path "$1" "$2"
}

phys() { ( cd "$1" 2>/dev/null && pwd -P ) 2>/dev/null || printf '%s' "$1"; }

# Single recorder binary for glm/codex/sonnet: honors --cwd if present in argv, else
# records $PWD. Branches on $1 to speak each arm's expected handle/status contract.
make_cwd_recorder() { # <path>
  cat > "$1" <<'STUBEOF'
#!/usr/bin/env bash
if [[ "$1" == "status" ]]; then exit 0; fi
prev=""
cwd="$PWD"
for a in "$@"; do
  [[ "$prev" == "--cwd" ]] && cwd="$a"
  prev="$a"
done
printf '%s' "$cwd" > "${STUB_CWD_FILE}"
case "$1" in
  bg)   printf 'handle-glm-stub\n' ;;
  task) printf 'task-stub1a-abcdef\n' ;;
  *)
    nohup sleep 30 >/dev/null 2>&1 &
    printf 'PID=%s LABEL=test SESSION_ID=test\n' "$!"
    ;;
esac
STUBEOF
  chmod +x "$1"
}

make_resolver_stub() { # <path> <reviewer-arm>
  cat > "$1" <<PYEOF
#!/usr/bin/env python3
print("reviewer=$2")
print("pool=$2")
print("refusal=")
PYEOF
  chmod +x "$1"
}

make_review_pass_stub() { # <path> -- speaks both codex-task.sh and claude-subsession.sh's
  # positional-arg contract (ignores argv, writes the verdict lines to stdout).
  cat > "$1" <<'EOF'
#!/usr/bin/env bash
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
exit 0
EOF
  chmod +x "$1"
}

# ── C1 -- worker cwd vs diff root: prove the recorder actually lands where dispatch
# claims (WORK_ROOT), for each of the three spawn arms. ────────────────────────────
case_c1() { # <scripts_dir> <arm> -> 0 pass, 1 fail(red), 2 could-not-run
  local scripts_dir="$1" arm="$2"
  local dc="${scripts_dir}/leadv2-dispatch-code.sh" launcher="${scripts_dir}/leadv2-fanout-lane-launcher.sh"
  [[ -f "${dc}" && -f "${launcher}" ]] || return 2
  local root tid stubdir cwd_file rel excl
  root="$(new_repo)"
  tid="c1-${arm}-$$"
  stubdir="$(mktemp -d)"
  cwd_file="${stubdir}/cwd.txt"
  rel="agent/new_${arm}.py"
  make_cwd_recorder "${stubdir}/bin.sh"
  case "${arm}" in
    glm)    excl="" ;;
    codex)  excl="glm" ;;
    sonnet) excl="glm,codex" ;;
  esac
  mkdir -p "${root}/.claude/ref" "${root}/docs/leadv2/.bus-offsets"
  printf 'router:\n  glm_policy:\n    sonnet_exceptions: []\n    opus_only_mission_kinds: []\n    codex_fitting_mission_kinds: []\n' \
    > "${root}/.claude/ref/leadv2-routing.yaml"
  local mission_file="${stubdir}/mission.md" sig_dir="${stubdir}/sig"
  printf 'C1 %s throwaway lane mission\n' "${arm}" > "${mission_file}"
  mkdir -p "${sig_dir}"

  STUB_CWD_FILE="${cwd_file}" \
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_PROJECT_ROOT="${root}" \
  LEADV2_DISPATCH_CACHE_DIR="${stubdir}/cache" LEADV2_JOURNAL_BIN=/bin/true \
  LEADV2_DISPATCH_GLM_BIN="${stubdir}/bin.sh" LEADV2_DISPATCH_CODEX_BIN="${stubdir}/bin.sh" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${stubdir}/bin.sh" \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
  LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS="${excl}" LEADV2_LANE_SHAPE=off \
  LEADV2_REQUIRE_LANE_WRITES=1 \
  bash "${launcher}" --task-id "${tid}" --class standard --mission-file "${mission_file}" \
    --project-root "${root}" --sig-dir "${sig_dir}" --dispatch-bin "${dc}" --writes "${rel}" \
    >/dev/null 2>&1

  local ok=1
  if [[ -s "${cwd_file}" ]]; then
    local got wt got_p wt_p
    got="$(cat "${cwd_file}")"
    wt="$(worktree_path "${root}" "${tid}")"
    got_p="$(phys "${got}")"
    wt_p="$(phys "${wt}")"
    [[ -d "${wt}" && "${got_p}" == "${wt_p}" ]] && ok=0
  fi
  rm -rf "${root}" "${stubdir}"
  return "${ok}"
}

# ── C2 -- untracked new file must still be diffed (throwaway-index add -N). ────────
case_c2() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt d
  root="$(new_repo)"
  tid="c2-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  mkdir -p "${wt}/agent"
  printf 'brand new, never git add-ed\n' > "${wt}/agent/newmod.py"
  d="$(mktemp -d)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
  LEADV2_DISPATCH_LANE_WRITES="agent/newmod.py" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
  bash "${pc}" "${root}" c2sig001 sonnet "" 0 1 "${tid}" >/dev/null 2>&1
  local diff="${root}/docs/handoff/dispatch-c2sig001/review.diff"
  local ok=1
  [[ -s "${diff}" ]] && grep -q 'newmod' "${diff}" && ok=0
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── C2-b -- the throwaway-index trick must never touch the real index. ─────────────
case_c2b() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt d before after cached
  root="$(new_repo)"
  tid="c2b-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  mkdir -p "${wt}/agent"
  printf 'brand new\n' > "${wt}/agent/newmod2.py"
  before="$(git -C "${wt}" status --porcelain)"
  d="$(mktemp -d)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
  LEADV2_DISPATCH_LANE_WRITES="agent/newmod2.py" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
  bash "${pc}" "${root}" c2bsig01 sonnet "" 0 1 "${tid}" >/dev/null 2>&1
  after="$(git -C "${wt}" status --porcelain)"
  cached="$(git -C "${wt}" diff --cached)"
  local ok=1
  [[ "${before}" == "${after}" && -z "${cached}" ]] && ok=0
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── C3 -- LEADV2_REVIEW_DIFF_CROSS_REPO=0 is a genuine one-flip rollback: diff_root
# stays ${ROOT} even though a lane worktree exists and LEADV2_LANE_WORK_ROOT is set. ──
case_c3() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt d
  root="$(new_repo)"
  tid="c3-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  # edited in the SHARED ROOT itself -- with the flag off, review must find it there,
  # not come up empty because diff_root silently stayed pinned to the worktree.
  printf 'seed\nedited-in-root\n' > "${root}/agent/seed.py"
  d="$(mktemp -d)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
  LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_REVIEW_DIFF_CROSS_REPO=0 \
  LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
  bash "${pc}" "${root}" c3sig001 sonnet "" 0 1 "${tid}" >/dev/null 2>&1
  local diff="${root}/docs/handoff/dispatch-c3sig001/review.diff"
  local gate="${root}/docs/handoff/dispatch-c3sig001/review-gate.md"
  local ok=1
  if [[ -s "${diff}" ]] && grep -q 'edited-in-root' "${diff}" && grep -q '^status: pass' "${gate}" 2>/dev/null; then
    ok=0
  fi
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── H4 -- cache hit on a row with no declared writes and an artifact with no
# LANE_WRITES: line must be treated as a cache MISS, not served blind. ─────────────
case_h4() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local dc="${scripts_dir}/leadv2-dispatch-code.sh"
  [[ -f "${dc}" ]] || return 2
  local root d mission_hash sig8="deadbeefh4" adir f
  root="$(new_repo)"
  d="$(mktemp -d)"
  mkdir -p "${root}/.claude/ref"
  printf 'router:\n  glm_policy:\n    sonnet_exceptions: []\n    opus_only_mission_kinds: []\n    codex_fitting_mission_kinds: []\n' \
    > "${root}/.claude/ref/leadv2-routing.yaml"
  adir="${root}/docs/handoff/dispatch-${sig8}"
  mkdir -p "${adir}"
  f="${adir}/architect-prepass.md"
  printf 'Stale scoped design (predates the LANE_WRITES prompt).\n' > "${f}"
  local mission="H4 cache-hit stale artifact test"
  mission_hash="$(printf '%s' "${mission}" | shasum -a 256 2>/dev/null | awk '{print $1}')"
  printf '%s' "${mission_hash}" > "${f}.sig"

  local architect="${d}/architect.sh"
  cat > "${architect}" <<'ARCHEOF'
#!/usr/bin/env bash
tid=""
while [[ $# -gt 0 ]]; do case "$1" in --task-id) tid="$2"; shift 2;; *) shift;; esac; done
root="${CLAUDE_PROJECT_ROOT:-${PROJECT_ROOT:-.}}"
adir="${root}/docs/handoff/${tid}"
mkdir -p "${adir}"
printf 'Fresh scoped design.\n\nLANE_WRITES: agent/newh4.py\n' > "${adir}/architect.full.md"
ARCHEOF
  chmod +x "${architect}"
  local subsession="${d}/subsession.sh"
  printf '#!/usr/bin/env bash\nnohup sleep 30 >/dev/null 2>&1 &\nprintf "PID=%%s LABEL=test SESSION_ID=test\\n" "$!"\n' > "${subsession}"
  chmod +x "${subsession}"

  local out
  out="$(CLAUDE_PROJECT_ROOT="${root}" LEADV2_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    LEADV2_DISPATCH_SUBSESSION_BIN="${subsession}" LEADV2_DISPATCH_ARCHITECT_BIN="${architect}" \
    LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC=5 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=glm,codex LEADV2_LANE_SHAPE=off LEADV2_JOURNAL_BIN=/bin/true \
    bash "${dc}" "${mission}" --kind product --protected --task-id "dispatch-${sig8}" 2>&1)"
  local ok=1
  # Must NOT dispatch straight off the stale cached artifact (no LANE_WRITES line, no
  # row writes) -- either it re-runs and picks up the fresh LANE_WRITES (worker_spawned)
  # or it parks; either is acceptable, but "status=cached" served blind is the regression.
  if [[ "${out}" != *"status=cached reason=sig_match"* ]]; then
    ok=0
  fi
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── H5 -- a two-repo declaration with one repo contributing zero bytes must BLOCK
# as partial_diff, with a per-repo byte-count journal line, not silently PASS. ─────
case_h5() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local plugin target d
  d="$(mktemp -d)"
  plugin="${d}/plugin-repo"
  target="${d}/target-repo"
  mkdir -p "${plugin}/scripts" "${target}/.claude/scripts" "${target}/agent"
  ( cd "${plugin}" && git init -q -b main && git config user.email t@e.com && git config user.name t \
    && printf 'orig\n' > scripts/foo.sh && git add scripts/foo.sh && git commit -qm seed ) >/dev/null 2>&1
  printf 'orig\npatched\n' > "${plugin}/scripts/foo.sh"
  ( cd "${target}" && git init -q -b main && git config user.email t@e.com && git config user.name t \
    && printf 'seed\n' > agent/seed.py && ln -s "${plugin}/scripts/foo.sh" .claude/scripts/foo.sh \
    && git add agent/seed.py .claude/scripts/foo.sh && git commit -qm seed ) >/dev/null 2>&1
  # agent/seed.py is DECLARED but left untouched (zero bytes) -- the plugin repo's
  # foo.sh is the only real edit. A correct gate BLOCKS this as partial_diff.
  local journal="${d}/journal.log"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  cat > "${d}/journal.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${journal}"
EOF
  chmod +x "${d}/journal.sh"
  CLAUDE_PROJECT_ROOT="${target}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
  LEADV2_DISPATCH_LANE_WRITES="agent/seed.py,.claude/scripts/foo.sh" \
  LEADV2_JOURNAL_BIN="${d}/journal.sh" \
  LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
  bash "${pc}" "${target}" h5sig001 sonnet "" 0 1 "" >/dev/null 2>&1
  local gate="${target}/docs/handoff/dispatch-h5sig001/review-gate.md"
  local ok=1
  if [[ -f "${gate}" ]] && grep -q 'reason: partial_diff' "${gate}" \
     && grep -q 'bytes=0' "${journal}" 2>/dev/null; then
    ok=0
  fi
  rm -rf "${d}"
  return "${ok}"
}

# ── H6 -- ARCHITECT_GATE=0 (kill switch) must not dispatch an undeclared, unisolated
# lane -- it can no longer bypass the writes guard entirely. ──────────────────────
case_h6() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local dc="${scripts_dir}/leadv2-dispatch-code.sh"
  [[ -f "${dc}" ]] || return 2
  local root d
  root="$(new_repo)"
  d="$(mktemp -d)"
  mkdir -p "${root}/.claude/ref"
  printf 'router:\n  glm_policy:\n    sonnet_exceptions: []\n    opus_only_mission_kinds: []\n    codex_fitting_mission_kinds: []\n' \
    > "${root}/.claude/ref/leadv2-routing.yaml"
  local subsession="${d}/subsession.sh"
  printf '#!/usr/bin/env bash\nnohup sleep 30 >/dev/null 2>&1 &\nprintf "PID=%%s LABEL=test SESSION_ID=test\\n" "$!"\n' > "${subsession}"
  chmod +x "${subsession}"
  local out
  out="$(CLAUDE_PROJECT_ROOT="${root}" LEADV2_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    LEADV2_DISPATCH_SUBSESSION_BIN="${subsession}" LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_REQUIRE_LANE_WRITES=1 \
    LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=glm,codex LEADV2_LANE_SHAPE=off LEADV2_JOURNAL_BIN=/bin/true \
    bash "${dc}" "H6 no writes at all, gate disabled" --kind product --protected 2>&1)"
  local ok=1
  [[ "${out}" != *worker_spawned* ]] && ok=0
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── M7 -- tolerant LANE_WRITES match (markdown emphasis / indentation). ────────────
case_m7() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local dc="${scripts_dir}/leadv2-dispatch-code.sh"
  [[ -f "${dc}" ]] || return 2
  local root d sig8="deadbeefm7" adir
  root="$(new_repo)"
  d="$(mktemp -d)"
  mkdir -p "${root}/.claude/ref"
  printf 'router:\n  glm_policy:\n    sonnet_exceptions: []\n    opus_only_mission_kinds: []\n    codex_fitting_mission_kinds: []\n' \
    > "${root}/.claude/ref/leadv2-routing.yaml"
  local architect="${d}/architect.sh"
  cat > "${architect}" <<'ARCHEOF'
#!/usr/bin/env bash
tid=""
while [[ $# -gt 0 ]]; do case "$1" in --task-id) tid="$2"; shift 2;; *) shift;; esac; done
root="${CLAUDE_PROJECT_ROOT:-${PROJECT_ROOT:-.}}"
adir="${root}/docs/handoff/${tid}"
mkdir -p "${adir}"
printf 'Design.\n\n**LANE_WRITES:** agent/m7.py\n' > "${adir}/architect.full.md"
ARCHEOF
  chmod +x "${architect}"
  local subsession="${d}/subsession.sh"
  printf '#!/usr/bin/env bash\nnohup sleep 30 >/dev/null 2>&1 &\nprintf "PID=%%s LABEL=test SESSION_ID=test\\n" "$!"\n' > "${subsession}"
  chmod +x "${subsession}"
  local out
  out="$(CLAUDE_PROJECT_ROOT="${root}" LEADV2_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    LEADV2_DISPATCH_SUBSESSION_BIN="${subsession}" LEADV2_DISPATCH_ARCHITECT_BIN="${architect}" \
    LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC=5 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=glm,codex LEADV2_LANE_SHAPE=off LEADV2_JOURNAL_BIN=/bin/true \
    bash "${dc}" "M7 markdown-emphasis LANE_WRITES" --kind product --protected --task-id "dispatch-${sig8}" 2>&1)"
  local ok=1
  [[ "${out}" == *worker_spawned* ]] && ok=0
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── M8 -- a declared path containing a space must be diffed as ONE path. ───────────
case_m8() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt d
  root="$(new_repo)"
  tid="m8-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  mkdir -p "${wt}/agent/has space"
  printf 'edit\n' > "${wt}/agent/has space/file.py"
  d="$(mktemp -d)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
  LEADV2_DISPATCH_LANE_WRITES="agent/has space/file.py" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
  bash "${pc}" "${root}" m8sig001 sonnet "" 0 1 "${tid}" >/dev/null 2>&1
  local diff="${root}/docs/handoff/dispatch-m8sig001/review.diff"
  local ok=1
  [[ -s "${diff}" ]] && grep -q 'has space/file.py' "${diff}" && ok=0
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── L11 -- review.diff has no `# repo:` marker and is `git apply --check`-able;
# per-repo attribution moves to a sidecar. ─────────────────────────────────────────
case_l11() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt d
  root="$(new_repo)"
  tid="l11-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  printf 'seed\nl11-edit\n' > "${wt}/agent/seed.py"
  d="$(mktemp -d)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
  LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
  bash "${pc}" "${root}" l11sig01 sonnet "" 0 1 "${tid}" >/dev/null 2>&1
  local diff="${root}/docs/handoff/dispatch-l11sig01/review.diff"
  local ok=1
  # Check apply-ability against a CLEAN checkout of HEAD (the diff's own "before" state),
  # never the dirty worktree it was generated from -- the worktree already contains the
  # edit, so re-applying the same diff there fails on context mismatch, not because the
  # diff itself is malformed.
  local clean_check
  clean_check="$(mktemp -d)"
  git -C "${wt}" archive HEAD | tar -x -C "${clean_check}" 2>/dev/null
  if [[ -s "${diff}" ]] && ! grep -q '^# repo:' "${diff}" \
     && ( cd "${clean_check}" && git apply --check "${diff}" ) >/dev/null 2>&1; then
    ok=0
  fi
  rm -rf "${root}" "${d}" "${clean_check}"
  return "${ok}"
}

# ── L12 -- an over-broad LANE_WRITES entry (**/*, ./, or a bare top-level dir name)
# must be rejected, not trusted. ───────────────────────────────────────────────────
case_l12() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local dc="${scripts_dir}/leadv2-dispatch-code.sh"
  [[ -f "${dc}" ]] || return 2
  local root d sig8="deadbeefl12" adir
  root="$(new_repo)"
  mkdir -p "${root}/agent"
  d="$(mktemp -d)"
  mkdir -p "${root}/.claude/ref"
  printf 'router:\n  glm_policy:\n    sonnet_exceptions: []\n    opus_only_mission_kinds: []\n    codex_fitting_mission_kinds: []\n' \
    > "${root}/.claude/ref/leadv2-routing.yaml"
  local architect="${d}/architect.sh"
  cat > "${architect}" <<'ARCHEOF'
#!/usr/bin/env bash
tid=""
while [[ $# -gt 0 ]]; do case "$1" in --task-id) tid="$2"; shift 2;; *) shift;; esac; done
root="${CLAUDE_PROJECT_ROOT:-${PROJECT_ROOT:-.}}"
adir="${root}/docs/handoff/${tid}"
mkdir -p "${adir}"
printf 'Design.\n\nLANE_WRITES: **/*, ./, agent\n' > "${adir}/architect.full.md"
ARCHEOF
  chmod +x "${architect}"
  local subsession="${d}/subsession.sh"
  printf '#!/usr/bin/env bash\nnohup sleep 30 >/dev/null 2>&1 &\nprintf "PID=%%s LABEL=test SESSION_ID=test\\n" "$!"\n' > "${subsession}"
  chmod +x "${subsession}"
  local out
  out="$(CLAUDE_PROJECT_ROOT="${root}" LEADV2_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    LEADV2_DISPATCH_SUBSESSION_BIN="${subsession}" LEADV2_DISPATCH_ARCHITECT_BIN="${architect}" \
    LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC=5 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=glm,codex LEADV2_LANE_SHAPE=off LEADV2_JOURNAL_BIN=/bin/true \
    bash "${dc}" "L12 over-broad LANE_WRITES only" --kind product --protected --task-id "dispatch-${sig8}" 2>&1)"
  local ok=1
  # every entry over-broad -> reads as absent -> no row writes, no valid prepass writes,
  # no worktree -> parked, never dispatched unrefined.
  [[ "${out}" != *worker_spawned* ]] && ok=0
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── harness runner ──────────────────────────────────────────────────────────────
PREFIX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-prefix.XXXXXX")"
LEADV2_REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
git -C "${LEADV2_REPO}" archive HEAD plugins/leadv2/scripts 2>/dev/null | tar -x -C "${PREFIX_DIR}" 2>/dev/null
PREFIX_SCRIPTS="${PREFIX_DIR}/plugins/leadv2/scripts"
if [[ ! -f "${PREFIX_SCRIPTS}/leadv2-dispatch-code.sh" ]]; then
  log "FATAL: git archive HEAD extraction failed -- cannot run red-first harness"
  exit 1
fi

run_case() { # <name> <fn> [args...]
  local name="$1" fn="$2"; shift 2
  local pre_rc post_rc
  "${fn}" "${PREFIX_SCRIPTS}" "$@" >/dev/null 2>&1; pre_rc=$?
  "${fn}" "${SCRIPT_DIR}" "$@" >/dev/null 2>&1; post_rc=$?

  if [[ ${pre_rc} -eq 2 || ${post_rc} -eq 2 ]]; then
    COULD_NOT_RUN=$((COULD_NOT_RUN + 1))
    log "COULD-NOT-RUN: ${name} (pre_rc=${pre_rc} post_rc=${post_rc})"
    return
  fi
  if [[ ${post_rc} -ne 0 ]]; then
    FAIL=$((FAIL + 1)); ERRORS+=("${name}: post-fix did not pass (rc=${post_rc})")
    log "FAIL: ${name} -- post-fix rc=${post_rc}, expected 0"
    return
  fi
  if [[ ${pre_rc} -eq 0 ]]; then
    GREEN_PRE_FIX=$((GREEN_PRE_FIX + 1))
    log "GREEN-PRE-FIX: ${name} -- passed against HEAD too (pre_rc=0)"
    return
  fi
  PASS=$((PASS + 1))
  log "RED-then-GREEN: ${name} (pre_rc=${pre_rc} -> post_rc=0)"
}

run_case "C1-glm"    case_c1 glm
run_case "C1-codex"  case_c1 codex
run_case "C1-sonnet" case_c1 sonnet
run_case "C2"        case_c2
run_case "C2-b"      case_c2b
run_case "C3"        case_c3
run_case "H4"        case_h4
run_case "H5"        case_h5
run_case "H6"        case_h6
run_case "M7"        case_m7
run_case "M8"        case_m8
run_case "L11"       case_l11
run_case "L12"       case_l12

rm -rf "${PREFIX_DIR}"

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix, ${COULD_NOT_RUN} could-not-run"
echo "red=${PASS} green-pre-fix=${GREEN_PRE_FIX} could-not-run=${COULD_NOT_RUN}"
if [[ "${FAIL}" -gt 0 ]]; then
  printf -- 'FAIL: %s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
