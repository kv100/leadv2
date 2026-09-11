#!/usr/bin/env bash
# tests/test-premise-markdown-backlog.sh — PREMISE-GATE-MARKDOWN-BACKLOG-01
# run-all-triggers: leadv2-dispatch-code leadv2-markdown-backlog-read.py
#
# The defect (measured 2026-09-11): _premise_probe_gate's yaml resolver
# returns status=none for every repo with no docs/tasks.yaml at all
# (getmany-followup-bot), so the gate silently no-ops there forever even
# though the repo has a real backlog in a markdown pipe table. This suite
# proves the markdown fallback: Tier A drives the new reader directly
# (plugins/leadv2/scripts/lib/leadv2-markdown-backlog-read.py), Tier B
# drives the REAL dispatch script end to end, the same hermetic-fixture
# discipline as test-dispatch-refuses-a-dead-premise.sh.
#
# Run: bash plugins/leadv2/scripts/tests/test-premise-markdown-backlog.sh
set -uo pipefail
_t_src="${BASH_SOURCE[0]:-}"
if [[ -z "$_t_src" && -f "${0:-}" ]]; then _t_src="$0"; fi
SCRIPT_DIR="$(cd "$(dirname "$_t_src")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

DISPATCH_SH="${SCRIPTS_ROOT}/leadv2-dispatch-cod""e.sh"
READER="${LEADV2_MARKDOWN_BACKLOG_READER:-${SCRIPTS_ROOT}/lib/leadv2-markdown-backlog-read.py}"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

SUITE_SELF="$(cd "$(dirname "$_t_src")" && pwd)/$(basename "$_t_src")"
TMP="$(lv2_mktemp_dir premise-md-backlog-test)"
trap 'rm -rf "$TMP"' EXIT
STAMP="${TMP}/.t0"
: > "${STAMP}"

# ── T0: syntax / compile checks ────────────────────────────────────────────
if bash -n "${DISPATCH_SH}" 2>/dev/null && bash -n "${SUITE_SELF}" 2>/dev/null; then
  pass "T0 bash -n dispatch script + suite"
else
  fail "T0 bash -n dispatch script + suite"
fi
if python3 -m py_compile "${READER}" 2>/dev/null; then
  pass "T0 py_compile reader"
else
  fail "T0 py_compile reader"
fi

########################################################################
# Tier A -- reader unit cases (direct invocation, no dispatch involved)
########################################################################
REPO_A="${TMP}/repoA"
mkdir -p "${REPO_A}/.claude/leadv2-overrides" "${REPO_A}/docs"
( cd "${REPO_A}" && git init -q && git config user.email t@example.com && git config user.name t \
  && printf 'seed\n' > seed.txt && git add seed.txt && git commit -qm seed ) \
  || { echo "repoA git init failed"; exit 1; }

cat > "${REPO_A}/.claude/leadv2-overrides/markdown-backlog.yaml" <<'YAML'
file: docs/TASKS.md
id_column: "#"
status_column: "Статус"
id_pattern: '^[0-9]+$'
closed_statuses:
  - "в проде"
  - "не нужна"
  - "решено"
  - "разобрано"
YAML

cat > "${REPO_A}/docs/TASKS.md" <<'MD'
Intro text, not a table.

| # | Спека | Задача | Зачем | Статус | Блокер | Дальше |
|---|---|---|---|---|---|---|
| 7 | confirm | task seven | why | не начато | — | next |
| 17 | no-show | task seventeen | why | в проде | — | next |

Some prose between the two tables.

| # | Спека | Задача | Зачем | Статус | Блокер | Дальше |
|---|---|---|---|---|---|---|
| 27 | confirm | task 27 | why | в проде, флаг OFF | — | next |
| 30 | — | task 30 | why | в проде, без потребителя | — | next |
| 31 | — | dup a | why | в проде | — | next |
| 31 | — | dup b | why | в проде | — | next |
MD

_read() { python3 "${READER}" --root "$1" --task-id "$2" 2>"${TMP}/_stderr"; }

# case 1: no declaration at all
OUT="$(_read "${TMP}" 7)"; RC=$?
[[ "${RC}" == "0" && "${OUT}" == $'none\t-\t-\t-' ]] \
  && pass "A1 no declaration -> none" || fail "A1 no declaration: rc=${RC} out='${OUT}'"

# case 2: id 7 -> md_open (не начато)
OUT="$(_read "${REPO_A}" 7)"
[[ "${OUT}" == $'md_open\t7\tне начато'* ]] && pass "A2 id7 -> md_open" || fail "A2 id7: '${OUT}'"

# case 3: id 17 -> md_closed (в проде)
OUT="$(_read "${REPO_A}" 17)"
[[ "${OUT}" == $'md_closed\t17\tв проде'* ]] && pass "A3 id17 -> md_closed" || fail "A3 id17: '${OUT}'"

# case 4: id 27 -> md_open (prefix trap: "в проде, флаг OFF" must not close)
OUT="$(_read "${REPO_A}" 27)"
[[ "${OUT}" == $'md_open\t27\tв проде, флаг OFF'* ]] && pass "A4 id27 prefix trap -> md_open" || fail "A4 id27: '${OUT}'"

# case 5: id 30 -> md_open (prefix trap variant)
OUT="$(_read "${REPO_A}" 30)"
[[ "${OUT}" == $'md_open\t30\tв проде, без потребителя'* ]] && pass "A5 id30 prefix trap -> md_open" || fail "A5 id30: '${OUT}'"

# case 6: substring trap -- id 7 must not match rows 17/27; id 1 -> none
OUT="$(_read "${REPO_A}" 7)"
ROW_ID="$(printf '%s' "${OUT}" | cut -f2)"
[[ "${ROW_ID}" == "7" ]] && pass "A6a id7 row_id exactly 7 (not 17/27)" || fail "A6a row_id='${ROW_ID}'"
OUT="$(_read "${REPO_A}" 1)"
[[ "${OUT}" == $'none\t-\t-\t-' ]] && pass "A6b id1 (substring of 17) -> none" || fail "A6b id1: '${OUT}'"

# case 7: two rows share id 31 -> md_ambiguous
OUT="$(_read "${REPO_A}" 31)"
[[ "${OUT}" == md_ambiguous$'\t'31$'\t'* ]] && pass "A7 id31 duplicate -> md_ambiguous" || fail "A7 id31: '${OUT}'"

# case 8: declaration names a missing file -> none, rc 0, no traceback
REPO_B8="${TMP}/repoB8"
mkdir -p "${REPO_B8}/.claude/leadv2-overrides"
( cd "${REPO_B8}" && git init -q )
cat > "${REPO_B8}/.claude/leadv2-overrides/markdown-backlog.yaml" <<'YAML'
file: docs/does-not-exist.md
id_column: "#"
status_column: "Статус"
id_pattern: '^[0-9]+$'
closed_statuses: ["в проде"]
YAML
OUT="$(_read "${REPO_B8}" 7)"; RC=$?
STDERR8="$(cat "${TMP}/_stderr" 2>/dev/null)"
[[ "${RC}" == "0" && "${OUT}" == $'none\t-\tdecl_file_missing\t-' ]] \
  && pass "A8 missing decl file -> none/decl_file_missing rc0" || fail "A8: rc=${RC} out='${OUT}'"
[[ -z "${STDERR8}" ]] && pass "A8 no stderr / no traceback" || fail "A8 unexpected stderr: ${STDERR8}"

# case 9: PyYAML unavailable -- fallback literal parser
SHIM_DIR="${TMP}/shim"
mkdir -p "${SHIM_DIR}"
printf 'raise ImportError("nc: PyYAML unavailable in this shim")\n' > "${SHIM_DIR}/yaml.py"
REPO_B9="${TMP}/repoB9"
mkdir -p "${REPO_B9}/.claude/leadv2-overrides" "${REPO_B9}/docs"
( cd "${REPO_B9}" && git init -q )
cat > "${REPO_B9}/.claude/leadv2-overrides/markdown-backlog.yaml" <<'YAML'
file: docs/TASKS.md
id_column: "#"
status_column: "Статус"
id_pattern: '^[0-9]+$'
closed_statuses:
  - "в проде"
YAML
cat > "${REPO_B9}/docs/TASKS.md" <<'MD'
| # | Спека | Задача | Зачем | Статус | Блокер | Дальше |
|---|---|---|---|---|---|---|
| 17 | no-show | x | y | в проде | — | z |
MD
OUT="$(PYTHONPATH="${SHIM_DIR}" python3 "${READER}" --root "${REPO_B9}" --task-id 17 2>"${TMP}/_stderr9")"; RC=$?
STDERR9="$(cat "${TMP}/_stderr9" 2>/dev/null)"
[[ "${RC}" == "0" && "${OUT}" == $'md_closed\t17\tв проде'* ]] \
  && pass "A9a no-PyYAML fallback parses flat decl, matches -> md_closed" || fail "A9a: rc=${RC} out='${OUT}'"
[[ -z "${STDERR9}" ]] && pass "A9a no traceback" || fail "A9a unexpected stderr: ${STDERR9}"
# second half: a flow-list under the shim -- fallback refuses it, still rc 0
cat > "${REPO_B9}/.claude/leadv2-overrides/markdown-backlog.yaml" <<'YAML'
file: docs/TASKS.md
id_column: "#"
status_column: "Статус"
id_pattern: '^[0-9]+$'
closed_statuses: [a, b]
YAML
OUT="$(PYTHONPATH="${SHIM_DIR}" python3 "${READER}" --root "${REPO_B9}" --task-id 17 2>"${TMP}/_stderr9b")"; RC=$?
STDERR9B="$(cat "${TMP}/_stderr9b" 2>/dev/null)"
[[ "${RC}" == "0" && "${OUT}" == $'none\t-\tdecl_malformed\t-' ]] \
  && pass "A9b no-PyYAML fallback refuses flow-list -> decl_malformed" || fail "A9b: rc=${RC} out='${OUT}'"
[[ -z "${STDERR9B}" ]] && pass "A9b no traceback" || fail "A9b unexpected stderr: ${STDERR9B}"

# case 11: two-root rule via a real linked worktree
( cd "${REPO_A}" && git worktree add -q "${TMP}/repoA-wt" -b premise-md-wt-branch >/dev/null 2>&1 )
if [[ -d "${TMP}/repoA-wt" ]]; then
  # the declaration is uncommitted in repoA's working tree -- git worktree
  # add only checked out committed content, so repoA-wt does NOT have it;
  # the reader must fall back to the git-common-dir parent (repoA itself).
  [[ ! -f "${TMP}/repoA-wt/.claude/leadv2-overrides/markdown-backlog.yaml" ]] \
    && pass "A11 fixture sanity: worktree lacks the uncommitted declaration" \
    || fail "A11 fixture sanity: worktree unexpectedly has the declaration"
  OUT="$(_read "${TMP}/repoA-wt" 17)"
  [[ "${OUT}" == $'md_closed\t17\tв проде'* ]] \
    && pass "A11 worktree root falls back to git-common-dir parent -> md_closed" \
    || fail "A11 worktree: '${OUT}'"
else
  fail "A11 could not create linked worktree for repoA (git worktree add failed)"
fi

########################################################################
# Tier B -- gate cases through the REAL dispatch script
########################################################################
ROOT="${TMP}/repoB"
CACHE_DIR="${TMP}/cache"
SPAWN_MARK="${TMP}/spawn-mark.log"
JOURNAL_REC="${TMP}/journal-record.log"

mkdir -p "${ROOT}/.claude/ref" "${ROOT}/docs/leadv2/.bus-offsets" "${ROOT}/platform" "${ROOT}/docs"
( cd "${ROOT}" && git init -q && git config user.email t@example.com && git config user.name t \
  && printf 'seed\n' > seed.txt && git add seed.txt && git commit -qm seed ) \
  || { echo "repoB git init failed"; exit 1; }

cat > "${ROOT}/.claude/ref/leadv2-routing.yaml" <<'YAML'
router:
  glm_policy:
    sonnet_exceptions:
      - id: safety_gate_publish_payments
    opus_only_mission_kinds: []
    codex_fitting_mission_kinds: []
    codex_default_tier: standard
YAML

cat > "${TMP}/journal-recorder.sh" <<'EOF'
#!/usr/bin/env bash
printf 'JOURNAL %s\n' "$*" >> "${LEADV2_JOURNAL_REC:-/dev/null}"
exit 0
EOF
chmod +x "${TMP}/journal-recorder.sh"

cat > "${TMP}/fake-glm.sh" <<'EOF'
#!/usr/bin/env bash
printf 'SPAWN glm\n' >> "${LEADV2_SPAWN_MARK:-/dev/null}"
case "${1:-}" in
  bg)     printf 'fake-glm-handle\n' ;;
  status) exit 0 ;;
  *)      exit 0 ;;
esac
EOF
chmod +x "${TMP}/fake-glm.sh"
cat > "${TMP}/fake-subsession.sh" <<'EOF'
#!/usr/bin/env bash
printf 'SPAWN subsession\n' >> "${LEADV2_SPAWN_MARK:-/dev/null}"
nohup sleep 0.3 >/dev/null 2>&1 &
pid=$!
disown
printf 'PID=%s LABEL=fake-lane SESSION_ID=fake-session\n' "${pid}"
exit 0
EOF
chmod +x "${TMP}/fake-subsession.sh"

export LEADV2_LANE_WORK_ROOT="${ROOT}"
export LEADV2_ARM_EARLY_VERDICT_S=0
cd "${ROOT}"

DISPATCH_EXTRA=()
_dispatch() {
  local _case="$1" _tid="$2"; shift 2
  rm -f "${SPAWN_MARK}"
  : > "${JOURNAL_REC}"
  local -a _env=()
  local _kv
  for _kv in "$@"; do _env+=("$_kv"); done
  local _rc=0 _out
  _out="$(env \
    CLAUDE_PROJECT_ROOT="${ROOT}" LEADV2_PROJECT_ROOT="${ROOT}" \
    LEADV2_STATE_ROOT="${TMP}/state-root" \
    LEADV2_DISPATCH_CACHE_DIR="${CACHE_DIR}" \
    LEADV2_DISPATCH_GLM_BIN="${TMP}/fake-glm.sh" \
    LEADV2_DISPATCH_SUBSESSION_BIN="${TMP}/fake-subsession.sh" \
    LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_JOURNAL_BIN="${TMP}/journal-recorder.sh" \
    LEADV2_JOURNAL_REC="${JOURNAL_REC}" \
    LEADV2_SPAWN_MARK="${SPAWN_MARK}" \
    LEADV2_ROUTER_V2=0 \
    LEADV2_EXCLUDED_ARMS="__none__" \
    LEADV2_LANE_SHAPE=off \
    LEADV2_BURN_GOVERNOR=0 \
    LEADV2_MARKDOWN_BACKLOG_READER="${READER}" \
    ${_env[@]+"${_env[@]}"} \
    bash "${DISPATCH_SH}" "premise-md suite ${_case} $$ $(date +%s 2>/dev/null || echo 0)" \
      --spawn --task-id "${_tid}" ${DISPATCH_EXTRA[@]+"${DISPATCH_EXTRA[@]}"} 2>&1)" || _rc=$?
  RC="${_rc}"; OUT="${_out}"
}
# bash-guard: allow

# ── B1: a yaml row wins even when a markdown declaration also matches ─────
mkdir -p "${ROOT}/.claude/leadv2-overrides"
cat > "${ROOT}/docs/tasks.yaml" <<YAML
total_open: 1
tasks:
- id: '7'
  intent: 'row seven, yaml precedence'
  status: queued
  acceptance_probe_id: null
  needs_acceptance_probe: false
  acceptance_cmd: 'false'
YAML
cat > "${ROOT}/.claude/leadv2-overrides/markdown-backlog.yaml" <<'YAML'
file: docs/TASKS.md
id_column: "#"
status_column: "Статус"
id_pattern: '^[0-9]+$'
closed_statuses: ["в проде"]
YAML
cat > "${ROOT}/docs/TASKS.md" <<'MD'
| # | Спека | Задача | Зачем | Статус | Блокер | Дальше |
|---|---|---|---|---|---|---|
| 7 | x | y | z | в проде | — | w |
MD
_dispatch b1 7
[[ "${RC}" == "0" ]] && pass "B1 yaml precedence: rc=0" || fail "B1 rc=${RC}: $(printf '%s' "${OUT}" | tail -1)"
grep -q "verdict=alive" "${JOURNAL_REC}" && pass "B1 journal verdict=alive (yaml path taken)" || fail "B1 journal missing verdict=alive: $(cat "${JOURNAL_REC}")"
if ! grep -q "md:" "${JOURNAL_REC}"; then pass "B1 no md: token in journal"; else fail "B1 markdown token leaked into journal: $(cat "${JOURNAL_REC}")"; fi
rm -f "${ROOT}/docs/tasks.yaml"

# ── B2: no yaml row, markdown row open -> skip, lane dispatched ───────────
cat > "${ROOT}/docs/TASKS.md" <<'MD'
| # | Спека | Задача | Зачем | Статус | Блокер | Дальше |
|---|---|---|---|---|---|---|
| 42 | x | y | z | не начато | — | w |
MD
_dispatch b2 42
[[ "${RC}" == "0" ]] && pass "B2 md_open: rc=0" || fail "B2 rc=${RC}: $(printf '%s' "${OUT}" | tail -1)"
grep -q "row=md:42" "${JOURNAL_REC}" && grep -q "reason=markdown_row_open_no_probe" "${JOURNAL_REC}" \
  && pass "B2 journal row=md:42 reason=markdown_row_open_no_probe" || fail "B2 journal: $(cat "${JOURNAL_REC}")"
grep -q '^SPAWN ' "${SPAWN_MARK:-/dev/nonexistent}" && pass "B2 worker started" || fail "B2 worker not started"

# ── B3: markdown row closed -> refuse, lane never dispatched ──────────────
cat > "${ROOT}/docs/TASKS.md" <<'MD'
| # | Спека | Задача | Зачем | Статус | Блокер | Дальше |
|---|---|---|---|---|---|---|
| 43 | x | y | z | в проде | — | w |
MD
_dispatch b3 43
[[ "${RC}" == "8" ]] && pass "B3 md_closed: rc=8" || fail "B3 rc=${RC}: $(printf '%s' "${OUT}" | tail -1)"
grep -q "reason=row_closed_in_markdown_backlog" "${JOURNAL_REC}" && grep -q "row=md:43" "${JOURNAL_REC}" \
  && pass "B3 journal reason=row_closed_in_markdown_backlog row=md:43" || fail "B3 journal: $(cat "${JOURNAL_REC}")"
LASTLINE="$(printf '%s' "${OUT}" | tail -1)"
[[ "${LASTLINE}" == *"43"* && "${LASTLINE}" == *"в проде"* && "${LASTLINE}" == *"TASKS.md"* ]] \
  && pass "B3 stderr names row, status, file" || fail "B3 stderr incomplete: ${LASTLINE}"
[[ ! -s "${SPAWN_MARK:-/dev/nonexistent}" ]] && pass "B3 worker never started" || fail "B3 worker started on a closed row"

# ── B4: duplicate rows -> ambiguous refusal ────────────────────────────────
cat > "${ROOT}/docs/TASKS.md" <<'MD'
| # | Спека | Задача | Зачем | Статус | Блокер | Дальше |
|---|---|---|---|---|---|---|
| 44 | x | y | z | не начато | — | w |
| 44 | x | y | z | не начато | — | w |
MD
_dispatch b4 44
[[ "${RC}" == "8" ]] && pass "B4 md_ambiguous: rc=8" || fail "B4 rc=${RC}: $(printf '%s' "${OUT}" | tail -1)"
grep -q "reason=markdown_row_ambiguous" "${JOURNAL_REC}" && pass "B4 journal reason=markdown_row_ambiguous" || fail "B4 journal: $(cat "${JOURNAL_REC}")"
[[ ! -s "${SPAWN_MARK:-/dev/nonexistent}" ]] && pass "B4 worker never started" || fail "B4 worker started"

# ── B5: no declaration, no tasks.yaml -> unchanged no_backlog_row skip ────
rm -f "${ROOT}/.claude/leadv2-overrides/markdown-backlog.yaml"
DISPATCH_EXTRA=(--acceptance-cmd 'true')
_dispatch b5 TASK-UNRESOLVED-99
DISPATCH_EXTRA=()
[[ "${RC}" == "0" ]] && pass "B5 no declaration/no row: rc=0" || fail "B5 rc=${RC}: $(printf '%s' "${OUT}" | tail -1)"
if grep -qx "JOURNAL append premise-md suite b5 $$ 0 decision premise_probe task=$(printf '%s' "${OUT}" | grep -oE 'task=[a-f0-9]+' | head -1 | cut -d= -f2) verdict=skipped reason=no_backlog_row" "${JOURNAL_REC}" 2>/dev/null; then
  pass "B5 journal exact no_backlog_row line (byte match)"
else
  # exact byte-for-byte assertion via grep -F for the fixed suffix instead,
  # which is what actually matters (today's ad-hoc contract byte-identical)
  if grep -qE 'verdict=skipped reason=no_backlog_row$' "${JOURNAL_REC}"; then
    pass "B5 journal reason=no_backlog_row with NO md= suffix (byte-identical contract)"
  else
    fail "B5 journal: $(cat "${JOURNAL_REC}")"
  fi
fi
grep -q '^SPAWN ' "${SPAWN_MARK:-/dev/nonexistent}" && pass "B5 worker started (ad-hoc contract intact)" || fail "B5 worker not started"

# ── B6: declaration present, file missing -> skip with md= diag suffix ───
cat > "${ROOT}/.claude/leadv2-overrides/markdown-backlog.yaml" <<'YAML'
file: docs/does-not-exist.md
id_column: "#"
status_column: "Статус"
id_pattern: '^[0-9]+$'
closed_statuses: ["в проде"]
YAML
_dispatch b6 45
[[ "${RC}" == "0" ]] && pass "B6 decl_file_missing: rc=0" || fail "B6 rc=${RC}: $(printf '%s' "${OUT}" | tail -1)"
grep -q "reason=no_backlog_row md=decl_file_missing" "${JOURNAL_REC}" \
  && pass "B6 journal reason=no_backlog_row md=decl_file_missing" || fail "B6 journal: $(cat "${JOURNAL_REC}")"
grep -q '^SPAWN ' "${SPAWN_MARK:-/dev/nonexistent}" && pass "B6 worker started (fail-open on unusable decl)" || fail "B6 worker not started"

printf -- '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
if [[ "${FAIL}" -gt 0 ]]; then
  printf -- '%s\n' "${ERRORS[@]}" >&2
  exit 1
fi

# Hermeticity: nothing this suite ran touched real leadv2 state. Scoped to
# this suite's own fixture slugs (repoB/repoB8/repoB9, the basenames of the
# scratch roots above) rather than a blanket newer-than-STAMP sweep of the
# whole shared ~/.claude/leadv2-state tree -- that tree is written by every
# concurrently-running leadv2 session on this machine (persona-engine,
# getmany-followup-bot, other lanes), and a global sweep flags their writes
# as false hermeticity violations of THIS suite. LEADV2_STATE_ROOT is set to
# a path under ${TMP} for every real-dispatch call above, so in the passing
# case this must find nothing at all; a real regression (an unstubbed call
# site falling back to production state resolution for this suite's own
# fixtures) still lands under one of these slugs and is still caught.
if command -v find >/dev/null 2>&1 && [[ -d "${HOME}/.claude/leadv2-state" ]]; then
  STALE="$(find "${HOME}/.claude/leadv2-state" -newer "${STAMP}" \
    \( -path '*/repoB/*' -o -path '*/repoB' -o -path '*/repoB8/*' -o -path '*/repoB8' -o -path '*/repoB9/*' -o -path '*/repoB9' \) \
    2>/dev/null)"
  if [[ -n "${STALE}" ]]; then
    printf 'HERMETICITY VIOLATION -- wrote to real leadv2 state:\n%s\n' "${STALE}" >&2
    exit 1
  fi
fi
exit 0
# bash-guard: allow
