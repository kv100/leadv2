#!/usr/bin/env bash
# test-dispatch-prepass-provider-fallback.sh — PREPASS-PROVIDER-FALLBACK-01-R5.
#
# Focused fixture suite for the four Codex High findings
# (docs/handoff/CODEX-LEAD-REPAIR-20260824/review-codex.md):
#   H1  fallback arms run inside a DISPOSABLE ISOLATED git worktree, never
#       --cwd the shared checkout; the workspace is removed on every terminal
#       path (arm success, arm failure, ladder exhaustion).
#   H2  slot release is OWNER-VERIFIED (registration session_id + durable PID +
#       pid_role): a foreign-session row, a foreign-pid row (the concurrent-retry
#       register-refresh shape) and a worker-owned row are never unregistered by
#       this dispatcher; our own row is.
#   H3  ONE disarmable EXIT trap (cleanup_pending_dispatch) releases the
#       pre-registered row on a proven no-worker terminal exit (unit: direct
#       trap-body call, armed vs disarmed; e2e: a full dispatch subprocess that
#       parks at prepass leaves NO active.yaml row behind).
#   H4  auth/rate/quota/opaque classification + precedence, and the Codex
#       (rc0 + non-empty stdout) / GLM (rc0 + non-empty --out file) launcher
#       result-parsing contracts are pinned to fixtures; the same prepass
#       mission is re-fed to the fallback launcher verbatim. Every external
#       assumption the dispatcher leans on is tagged UNVERIFIED in its comments
#       with the in-repo evidence/compensating control -- nothing here talks to
#       a live provider, and NO worker is spawned by anything in this suite:
#       every launcher seam is a printf stub.
#
# Technique: sources the REAL leadv2-dispatch-code.sh function bodies (never a
# hand-reimplemented copy) by truncating just before the trailing dispatch-case
# block -- the same shape test-dispatch-checkpoint-commit-cutoff.sh describes.
# The truncation lives beside its siblings in scripts/ (SCRIPT_DIR-relative
# `source` lines require this) as a private dotfile, removed on exit.
#
# Run: bash plugins/leadv2/scripts/tests/test-dispatch-prepass-provider-fallback.sh

set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH_SH="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-test-ppf-r5.XXXXXX")"
cleanup() { echo "KEEP: ${ROOT}"; }
trap cleanup EXIT

# ── fixture repo ────────────────────────────────────────────────────────────────
REPO="$ROOT/repo"
mkdir -p "$REPO/.claude/ref" "$REPO/docs/leadv2"
(cd "$REPO" && git init -q && git config user.email test@example.com && git config user.name test \
  && : > seed && git add seed && git commit -qm seed \
  && git add .claude/ref/leadv2-routing.yaml && git commit -qm routing)
printf 'router:\n  glm_policy:\n    sonnet_exceptions: []\n    opus_only_mission_kinds: []\n    codex_fitting_mission_kinds: []\n' \
  > "$REPO/.claude/ref/leadv2-routing.yaml"
(cd "$REPO" && git add .claude/ref/leadv2-routing.yaml && git commit -qm routing)
REPO_HEAD="$(git -C "$REPO" rev-parse HEAD)"

# ── launcher stubs (their own seams: LEADV2_DISPATCH_CODEX_BIN / _GLM_BIN) ─────
CODEX_STUB="$ROOT/codex-stub.sh"
GLM_STUB="$ROOT/glm-stub.sh"

# codex stub: records cwd/--cwd/head/prompt, proves the ws is a real git
# worktree at the repo commit, writes INSIDE the ws (writable-but-disposable),
# prints a design on stdout. Mode via $PPF_CODEX_MODE: ok | fail | silent.
cat > "$CODEX_STUB" <<'EOF'
#!/usr/bin/env bash
prev=""; cwd=""; prompt=""
for a in "$@"; do
  [[ "$prev" == "--cwd" ]] && cwd="$a"
  [[ -z "$prompt" && "$a" != -* && "$a" != task ]] && prompt="$a"
  prev="$a"
done
{ printf 'pwd=%s\ncwd=%s\n' "$PWD" "$cwd"
  git -C "$cwd" rev-parse HEAD 2>/dev/null || printf 'no-git\n'
  printf 'head_ok=%s\n' "$(git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 && printf yes || printf no)"
} > "${PPF_ROOT}/codex-probe"
printf '%s\n' "$prompt" > "${PPF_ROOT}/codex-prompt"
printf 'touched\n' > "${cwd}/codex-wrote-inside-ws.txt"
case "${PPF_CODEX_MODE:-ok}" in
  ok)      printf '%s\n' "codex stub design line"; exit 0 ;;
  fail)    exit 1 ;;
  silent)  exit 0 ;;
esac
EOF

# glm stub: same probes; reads the @mission-file it was fed, writes the design
# to --out (the artifact-not-stdout contract). Modes: ok | noout | fail.
cat > "$GLM_STUB" <<'EOF'
#!/usr/bin/env bash
prev=""; cwd=""; out=""; mfile=""
for a in "$@"; do
  [[ "$prev" == "--out" ]] && out="$a"
  [[ "$prev" == "--cwd" ]] && cwd="$a"
  [[ "$a" == @* ]] && mfile="${a#@}"
  prev="$a"
done
{ printf 'cwd=%s\n' "$cwd"; } > "${PPF_ROOT}/glm-probe"
[[ -n "$mfile" ]] && cp "$mfile" "${PPF_ROOT}/glm-mission-fed"
printf 'touched\n' > "${cwd}/glm-wrote-inside-ws.txt"
case "${PPF_GLM_MODE:-ok}" in
  ok)    printf '%s\n' "glm stub design line" > "$out"; exit 0 ;;
  noout) : > "$out"; exit 0 ;;
  fail)  exit 1 ;;
esac
EOF
chmod +x "$CODEX_STUB" "$GLM_STUB"

# ── source the REAL function bodies (truncated before the dispatch case) ───────
FUNCS_SH="${SCRIPTS_DIR}/.test-dispatch-ppf-r5-funcs.$$.sh"
CUT_LINE="$(grep -n '^# ── dispatch ─' "${DISPATCH_SH}" | tail -1 | cut -d: -f1)"
if [[ -z "${CUT_LINE}" ]]; then
  echo "[TEST] SETUP FAILED: no trailing dispatch-case marker in ${DISPATCH_SH}" >&2
  exit 1
fi
head -n "$((CUT_LINE - 1))" "${DISPATCH_SH}" > "${FUNCS_SH}"

# cwd = non-git scratch dir so the env root guard accepts the fixture repo
cd "$ROOT"
CLAUDE_PROJECT_ROOT="$REPO" LEADV2_PROJECT_ROOT="$REPO" \
LEADV2_DISPATCH_CACHE_DIR="$ROOT/cache" \
LEADV2_DISPATCH_CODEX_BIN="$CODEX_STUB" LEADV2_DISPATCH_GLM_BIN="$GLM_STUB" \
  source "${FUNCS_SH}"
set +e   # SILENT-DEATH-01 guard: a sourced sibling re-enables -e; opt back out

# sourcing armed the script's own EXIT trap -- prove it, then chain our cleanup
if trap -p EXIT | grep -q cleanup_pending_dispatch; then
  ok "H3: EXIT trap is cleanup_pending_dispatch (single disarmable trap)"
else
  bad "H3: EXIT trap is not cleanup_pending_dispatch: $(trap -p EXIT)"
fi
trap 'cleanup_pending_dispatch; cleanup' EXIT

export PPF_ROOT="$ROOT"

# ── T1: _architect_failure_class matrix (H4) ───────────────────────────────────
mkdir -p "$ROOT/t1/adir"
cls() { _architect_failure_class "$1" "$2" "$3"; }
_c1="$(cls "$ROOT/t1/adir" 'x' 1)"
[[ "${_c1}" == "failed_rc_1" ]] \
  && ok "H4: empty evidence -> opaque failed_rc_1" \
  || bad "H4: empty evidence -> '${_c1}'"
printf '%s\n' '{"error":"authentication_failed","is_api_error_message":true}' > "$ROOT/t1/adir/architect.stream.jsonl"
_c2="$(cls "$ROOT/t1/adir" '' 1)"
[[ "${_c2}" == "authentication_failed"$'\t'* ]] \
  && ok "H4: stream.jsonl error=authentication_failed -> authentication_failed (live 17309830 shape)" \
  || bad "H4: auth stream class -> '${_c2}'"
_c3="$(cls "$ROOT/t1/empty2" 'Failed to authenticate: OAuth session expired and could not be refreshed' 1)"
[[ "${_c3}" == "authentication_failed"$'\t'* ]] \
  && ok "H4: captured stdout OAuth-expired text -> authentication_failed" \
  || bad "H4: auth stdout class -> '${_c3}'"
_c4="$(cls "$ROOT/t1/empty2" 'HTTP 429: too many requests, rate limit hit' 1)"
[[ "${_c4}" == "rate_limited"$'\t'* ]] \
  && ok "H4: 429/too-many-requests -> rate_limited" \
  || bad "H4: rate class -> '${_c4}'"
_c5="$(cls "$ROOT/t1/empty2" "You've hit your usage limit for today" 1)"
[[ "${_c5}" == "quota_exceeded"$'\t'* ]] \
  && ok "H4: usage-limit text -> quota_exceeded" \
  || bad "H4: quota class -> '${_c5}'"
_c6="$(cls "$ROOT/t1/empty2" 'HTTP 401 unauthorized AND usage limit reached' 1)"
[[ "${_c6}" == "authentication_failed"$'\t'* ]] \
  && ok "H4: auth outranks quota when both match" \
  || bad "H4: precedence -> '${_c6}'"
_c7="$(cls "$ROOT/t1/empty2" 'core dumped' 7)"
[[ "${_c7}" == "failed_rc_7" ]] \
  && ok "H4: unmatched text -> opaque failed_rc_<rc>" \
  || bad "H4: opaque -> '${_c7}'"

# ── T2: codex fallback runs isolated and parses stdout (H1+H4) ─────────────────
_LADDER_IDS=(codex); _LADDER_PROVIDERS=(codex)
mkdir -p "$ROOT/t2"; printf 'T2 mission body\n' > "$ROOT/t2/mission"
: > "$ROOT/t2/design"; rm -f "$ROOT/codex-probe" "$ROOT/codex-prompt"
ARCHITECT_FALLBACK_ARM_USED=""
if _architect_fallback_design "$ROOT/t2/mission" "t2sig8" "authentication_failed" "$ROOT/t2/design" "anthropic"; then
  ok "H1: codex fallback arm produced a design (rc0 + non-empty stdout)"
else
  bad "H1: codex fallback arm failed: design='$(cat "$ROOT/t2/design")'"
fi
[[ "$(cat "$ROOT/t2/design")" == "codex stub design line" ]] \
  && ok "H4: codex stdout parsed as the design text" \
  || bad "H4: codex design content: '$(cat "$ROOT/t2/design")'"
[[ "${ARCHITECT_FALLBACK_ARM_USED}" == "codex" ]] \
  && ok "H4: ARCHITECT_FALLBACK_ARM_USED=codex" || bad "H4: arm used '${ARCHITECT_FALLBACK_ARM_USED}'"
_ws="$(sed -n 's/^cwd=//p' "$ROOT/codex-probe" | head -1)"
_pwd="$(sed -n 's/^pwd=//p' "$ROOT/codex-probe" | head -1)"
[[ -n "${_ws}" && "${_ws}" != "$REPO" && "${_pwd}" != "$REPO" ]] \
  && ok "H1: launcher cwd was the disposable ws, NOT the shared checkout" \
  || bad "H1: launcher cwd pwd='${_pwd}' cwd='${_ws}' repo='${REPO}'"
if [[ "$(sed -n 's/^head_ok=//p' "$ROOT/codex-probe")" == "yes" ]] && grep -q "^${REPO_HEAD}$" "$ROOT/codex-probe"; then
  ok "H1: ws was a real git worktree at the repo HEAD commit"
else
  bad "H1: ws git probe: $(tr '\n' ' ' < "$ROOT/codex-probe")"
fi
[[ ! -e "${_ws}" ]] \
  && ok "H1: disposable ws removed after arm success" || bad "H1: ws leaked: ${_ws}"
_wtc="$(git -C "$REPO" worktree list --porcelain | grep -c '^worktree' || true)"
[[ "${_wtc}" == "1" ]] && ok "H1: repo has no leftover registered worktrees" \
  || bad "H1: leftover worktrees: ${_wtc} ($(git -C "$REPO" worktree list))"
[[ -z "$(git -C "$REPO" status --porcelain)" ]] \
  && ok "H1: shared checkout untouched by the fallback arm" \
  || bad "H1: shared checkout dirty: $(git -C "$REPO" status --porcelain)"
[[ "$(cat "$ROOT/codex-prompt")" == "T2 mission body" ]] \
  && ok "H4: same prepass mission re-fed to the codex launcher verbatim" \
  || bad "H4: mission re-fed as: '$(cat "$ROOT/codex-prompt")'"

# ── T3: codex failure contracts (H4) + cleanup on failure paths (H1) ───────────
for mode in fail silent; do
  rm -f "$ROOT/codex-probe"; : > "$ROOT/t2/design"
  export PPF_CODEX_MODE="$mode"
  _architect_fallback_design "$ROOT/t2/mission" "t3sig8" "rate_limited" "$ROOT/t2/design" "anthropic"
  rc=$?
  unset PPF_CODEX_MODE
  [[ $rc -eq 1 && ! -s "$ROOT/t2/design" ]] \
    && ok "H4: codex mode=${mode} (rc!=0 / empty stdout) rejected as a design" \
    || bad "H4: codex mode=${mode} rc=${rc} design='$(cat "$ROOT/t2/design")'"
  _ws3="$(sed -n 's/^cwd=//p' "$ROOT/codex-probe" 2>/dev/null | head -1)"
  [[ -z "${_ws3}" || ! -e "${_ws3}" ]] \
    && ok "H1: ws removed after codex mode=${mode} failure" || bad "H1: ws leaked after ${mode}: ${_ws3}"
done
_wtc="$(git -C "$REPO" worktree list --porcelain | grep -c '^worktree' || true)"
[[ "${_wtc}" == "1" ]] || bad "H1: leftover worktrees after failures: ${_wtc}"

# ── T4: glm fallback isolation + --out parsing (H1+H4) ─────────────────────────
_LADDER_IDS=(glm); _LADDER_PROVIDERS=(glm)
: > "$ROOT/t2/design"; rm -f "$ROOT/glm-probe" "$ROOT/glm-mission-fed"
ARCHITECT_FALLBACK_ARM_USED=""
if _architect_fallback_design "$ROOT/t2/mission" "t4sig8" "quota_exceeded" "$ROOT/t2/design" "anthropic"; then
  ok "H1: glm fallback arm produced a design (rc0 + non-empty --out file)"
else
  bad "H1: glm fallback arm failed: design='$(cat "$ROOT/t2/design")'"
fi
[[ "$(cat "$ROOT/t2/design")" == "glm stub design line" ]] \
  && ok "H4: glm design read from the --out FILE, not stdout" \
  || bad "H4: glm design content: '$(cat "$ROOT/t2/design")'"
[[ "${ARCHITECT_FALLBACK_ARM_USED}" == "glm" ]] || bad "H4: glm arm used '${ARCHITECT_FALLBACK_ARM_USED}'"
_ws4="$(sed -n 's/^cwd=//p' "$ROOT/glm-probe")"
[[ -n "${_ws4}" && "${_ws4}" != "$REPO" ]] \
  && ok "H1: glm launcher cwd was the disposable ws" || bad "H1: glm cwd '${_ws4}'"
[[ ! -e "${_ws4}" ]] && ok "H1: glm ws removed after success" || bad "H1: glm ws leaked: ${_ws4}"
[[ "$(cat "$ROOT/glm-mission-fed" 2>/dev/null)" == "T2 mission body" ]] \
  && ok "H4: same prepass mission re-fed via @file to the glm launcher" \
  || bad "H4: glm mission fed: '$(cat "$ROOT/glm-mission-fed" 2>/dev/null)'"
for mode in noout fail; do
  rm -f "$ROOT/glm-probe"; : > "$ROOT/t2/design"
  export PPF_GLM_MODE="$mode"
  _architect_fallback_design "$ROOT/t2/mission" "t4sig8" "quota_exceeded" "$ROOT/t2/design" "anthropic"
  rc=$?
  unset PPF_GLM_MODE
  [[ $rc -eq 1 && ! -s "$ROOT/t2/design" ]] \
    && ok "H4: glm mode=${mode} (empty --out / rc!=0) rejected" \
    || bad "H4: glm mode=${mode} rc=${rc} design='$(cat "$ROOT/t2/design")'"
  _ws5="$(sed -n 's/^cwd=//p' "$ROOT/glm-probe" 2>/dev/null)"
  [[ -z "${_ws5}" || ! -e "${_ws5}" ]] || bad "H1: glm ws leaked after ${mode}: ${_ws5}"
done
_wtc="$(git -C "$REPO" worktree list --porcelain | grep -c '^worktree' || true)"
[[ "${_wtc}" == "1" ]] && ok "H1: repo clean of fallback worktrees after all T2-T4 cases" \
  || bad "H1: leftover worktrees after T4: ${_wtc}"

# ── T5: owner-safe release (H2) ─────────────────────────────────────────────────
# LEADV2_PROJECT_ROOT must be EXPORTED before the registry's register/unregister
# calls (a `VAR=x source` prefix does not persist past the source command -- the
# same robustness reason the dispatcher now passes it per-call).
export LEADV2_PROJECT_ROOT="$REPO"
source "${SCRIPTS_DIR}/leadv2-active-registry.sh" 2>/dev/null
set +e   # the registry re-enables -e for standalone use
ACTIVE_YAML="$REPO/docs/leadv2/active.yaml"
row_count() {  # <task_id>
  python3 -c 'import sys,os,yaml
p, tid = sys.argv[1], sys.argv[2]
d = (yaml.safe_load(open(p)) or {}) if os.path.exists(p) else {}
print(len([s for s in (d.get("sessions") or []) if s.get("task_id") == tid]))' "$ACTIVE_YAML" "$1"
}
edit_row() {  # <task_id> <python-stmt on row>
  python3 -c 'import sys,yaml
p, tid, stmt = sys.argv[1], sys.argv[2], sys.argv[3]
d = yaml.safe_load(open(p)) or {}
for s in d.get("sessions") or []:
    if s.get("task_id") == tid: exec(stmt)
yaml.safe_dump(d, open(p, "w"), sort_keys=False)' "$ACTIVE_YAML" "$1" "$2"
}
arm_slot() {  # <task_id>
  DISPATCH_SLOT_REG_ID="$1"; DISPATCH_SLOT_SIG8="${1#dispatch-}"
  DISPATCH_SLOT_PID="$(_lv2_durable_pid)"
}
# register's stdout also carries render_index's "[registry] rendered ..." line
# (observed live 2026-08-24) -- keep only the s-<ts>-<pid>-<pid> session_id.
reg_session() {
  leadv2_active_register "$@" 2>/dev/null \
    | grep -E '^s-[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]+$' | tail -1
}

# a) our own row -> released
S="$(reg_session "dispatch-t5own" Standard "$REPO" t5branch)"
[[ -n "${S}" ]] || bad "H2: t5own register produced no session_id"
DISPATCH_SLOT_SESSION="$S"; arm_slot "dispatch-t5own"
_release_registered_lane "dispatch-t5own" "t5own" "unit_owned"
[[ "$(row_count dispatch-t5own)" == "0" ]] \
  && ok "H2: own row (session+pid match) is released" || bad "H2: own row NOT released"

# b) foreign session_id -> kept (another registration attempt owns it)
S="$(reg_session "dispatch-t5fs" Standard "$REPO" t5branch)"
[[ -n "${S}" ]] || bad "H2: t5fs register produced no session_id"
DISPATCH_SLOT_SESSION="s-FOREIGN-attempt"; arm_slot "dispatch-t5fs"
_release_registered_lane "dispatch-t5fs" "t5fs" "unit_foreign_session"
[[ "$(row_count dispatch-t5fs)" == "1" ]] \
  && ok "H2: foreign-session row kept (not our registration)" || bad "H2: foreign-session row deleted"

# c) foreign durable pid -> kept (the concurrent-retry register-refresh shape)
S="$(reg_session "dispatch-t5fp" Standard "$REPO" t5branch)"
[[ -n "${S}" ]] || bad "H2: t5fp register produced no session_id"
DISPATCH_SLOT_SESSION="$S"; arm_slot "dispatch-t5fp"; DISPATCH_SLOT_PID="999999"
_release_registered_lane "dispatch-t5fp" "t5fp" "unit_foreign_pid"
[[ "$(row_count dispatch-t5fp)" == "1" ]] \
  && ok "H2: foreign-pid row kept (another live dispatcher's refresh)" || bad "H2: foreign-pid row deleted"

# d) worker-owned row -> kept (post-spawn handoff)
S="$(reg_session "dispatch-t5wk" Standard "$REPO" t5branch)"
[[ -n "${S}" ]] || bad "H2: t5wk register produced no session_id"
DISPATCH_SLOT_SESSION="$S"; arm_slot "dispatch-t5wk"
edit_row "dispatch-t5wk" 's["pid_role"] = "worker"'
_release_registered_lane "dispatch-t5wk" "t5wk" "unit_worker_owned"
[[ "$(row_count dispatch-t5wk)" == "1" ]] \
  && ok "H2: worker-owned row kept (spawn handoff, never released here)" || bad "H2: worker row deleted"

# ── T6: the single disarmable EXIT trap body (H3) ──────────────────────────────
S="$(reg_session "dispatch-t6a" Standard "$REPO" t6branch)"
[[ -n "${S}" ]] || bad "H3: t6a register produced no session_id"
DISPATCH_SLOT_SESSION="$S"; arm_slot "dispatch-t6a"; ACTIVE_DISPATCH_TOKEN=""
cleanup_pending_dispatch
[[ "$(row_count dispatch-t6a)" == "0" ]] \
  && ok "H3: armed trap body releases the registered row" || bad "H3: armed trap left the row"
S="$(reg_session "dispatch-t6b" Standard "$REPO" t6branch)"
[[ -n "${S}" ]] || bad "H3: t6b register produced no session_id"
DISPATCH_SLOT_SESSION="$S"; arm_slot "dispatch-t6b"
DISPATCH_SLOT_REG_ID=""   # the worker-spawn handoff / ambiguity disarm
cleanup_pending_dispatch
[[ "$(row_count dispatch-t6b)" == "1" ]] \
  && ok "H3: disarmed trap does NOT release the row" || bad "H3: disarmed trap released the row"

# ── T7: e2e -- a full dispatch that parks at prepass leaves no active row (H3) ─
ARCH_FAIL="$ROOT/arch-auth-fail.sh"
cat > "$ARCH_FAIL" <<EOF
#!/usr/bin/env bash
prev=""; tid=""
for a in "\$@"; do
  [[ "\$prev" == "--task-id" ]] && tid="\$a"
  prev="\$a"
done
mkdir -p "\$PWD/docs/handoff/\${tid}"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Failed to authenticate: OAuth session expired and could not be refreshed"}]},"error":"authentication_failed","is_api_error_message":true}' \\
  > "\$PWD/docs/handoff/\${tid}/architect.stream.jsonl"
exit 1
EOF
chmod +x "$ARCH_FAIL"
_dispatch_rows() {
  python3 -c 'import sys,os,yaml
p = sys.argv[1]
d = (yaml.safe_load(open(p)) or {}) if os.path.exists(p) else {}
print(sum(1 for s in (d.get("sessions") or []) if str(s.get("task_id","")).startswith("dispatch-")))' "$ACTIVE_YAML"
}
_rows_before="$(_dispatch_rows)"
rc_e2e=0
( cd "$REPO" && LEADV2_DISPATCH_ARCHITECT_GATE=1 \
  CLAUDE_PROJECT_ROOT="$REPO" LEADV2_PROJECT_ROOT="$REPO" LEADV2_DISPATCH_CACHE_DIR="$ROOT/cache-e2e" \
  LEADV2_DISPATCH_SUBSESSION_BIN="$CODEX_STUB" LEADV2_DISPATCH_ARCHITECT_BIN="$ARCH_FAIL" \
  LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC=10 LEADV2_DISPATCH_ARCHITECT_FALLBACK=0 \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
  LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
  bash "$DISPATCH_SH" 'e2e park must release the registered slot' --kind product --protected \
  --writes "a.txt,b.txt,c.txt" > "$ROOT/e2e-out.log" 2>&1 ) || rc_e2e=$?
[[ $rc_e2e -eq 3 ]] && ok "H3: e2e prepass-park dispatch exits 3 (rc=${rc_e2e})" \
  || bad "H3: e2e exit rc=${rc_e2e} (expected 3)"
grep -q 'architect_prepass task=.* status=failed reason=authentication_failed' "$ROOT/e2e-out.log" \
  && ok "H4: e2e journal names authentication_failed from the stream artifact" \
  || bad "H4: no auth-classified prepass failure line: $(grep -o 'architect_prepass[^ ]* [^ ]* [^ ]* [^ ]* [^ ]*' "$ROOT/e2e-out.log" | head -2)"
grep -q 'active_lane_released task=.* where=exit_trap' "$ROOT/e2e-out.log" \
  && ok "H3: e2e journal shows active_lane_released where=exit_trap" \
  || bad "H3: no exit_trap release line in e2e log"
_rows_after="$(_dispatch_rows)"
[[ "${_rows_after}" == "${_rows_before}" ]] \
  && ok "H3: e2e parked lane left NO new active.yaml dispatch row behind (before=${_rows_before} after=${_rows_after})" \
  || bad "H3: dispatch rows before=${_rows_before} after=${_rows_after} -- the parked lane leaked a row"

# ── verdict ─────────────────────────────────────────────────────────────────────
printf '\n[SUITE] %s: %d passed, %d failed\n' \
  "$([[ $FAIL -eq 0 ]] && printf PASS || printf FAIL)" "$PASS" "$FAIL"
exit $([[ $FAIL -eq 0 ]] && printf 0 || printf 1)
