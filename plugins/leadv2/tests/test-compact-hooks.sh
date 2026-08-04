#!/usr/bin/env bash
# tests/test-compact-hooks.sh — smoke tests for leadv2-pre-compact-checkpoint.sh and
# leadv2-postcompact-goal-reinject.sh (multi-task / journal-aware rewrite, LONG-SESSION-01).
# Usage: bash tests/test-compact-hooks.sh
# Exit 0 = all pass; non-zero = failure count
set -euo pipefail

# Absolutise this file's dir ONCE (see test-open-threads-prune.sh for the full
# rationale): a relative "${BASH_SOURCE[0]%/*}" breaks under a sandbox `cd` and
# under a slashless invocation. `cd … && pwd`, not `realpath` (macOS-safe).
_src="${BASH_SOURCE[0]}"
case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir="." ;; esac
TESTS_DIR="$(cd "$_dir" && pwd)"
HOOKS_DIR="${TESTS_DIR}/../hooks"
PRE_HOOK="${HOOKS_DIR}/leadv2-pre-compact-checkpoint.sh"
POST_HOOK="${HOOKS_DIR}/leadv2-postcompact-goal-reinject.sh"
ACTIVE_CACHE_SRC="${HOOKS_DIR}/leadv2-active-cache.sh"
FREEZE_HOOK="${HOOKS_DIR}/pre-compact-task-freeze.sh"

PASS=0
FAIL=0
pass() { printf -- 'PASS: %s\n' "$1"; PASS=$(( PASS + 1 )); }
fail() { printf -- 'FAIL: %s\n' "$1"; FAIL=$(( FAIL + 1 )); }

# Some machines install PyYAML into the real $HOME's user site-packages (not the
# interpreter's global site-packages). Overriding $HOME for sandbox isolation would
# otherwise silently break `import yaml` in the sourced hooks. Preserve access to it.
REAL_USER_SITE="$(python3 -c 'import site; print(site.getusersitepackages())' 2>/dev/null || true)"

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# ---------------------------------------------------------------------------
# Sandbox project: leadv2_dir=docs/leadv2, 2 sessions (T-ALPHA build, T-BETA review),
# journal.md for both, STATE.md with goal for T-ALPHA, open-threads.md with 3 lines.
# ---------------------------------------------------------------------------
setup_sandbox() {
  local proj="$1"
  mkdir -p "${proj}/.claude/leadv2-overrides"
  mkdir -p "${proj}/docs/leadv2/tasks/T-ALPHA"
  mkdir -p "${proj}/docs/leadv2/tasks/T-BETA"
  # HOME override so leadv2-active-cache.sh resolves at ~/.claude/hooks/... in tests
  mkdir -p "${proj}/home/.claude/hooks" "${proj}/home/.claude/state/leadv2"
  cp "$ACTIVE_CACHE_SRC" "${proj}/home/.claude/hooks/leadv2-active-cache.sh"

  cat > "${proj}/docs/leadv2/active.yaml" <<'YAML'
sessions:
  - task_id: T-ALPHA
    phase: build
  - task_id: T-BETA
    phase: review
YAML

  cat > "${proj}/docs/leadv2/tasks/T-ALPHA/STATE.md" <<'MD'
phase: build
goal: ship the compact hooks rewrite
MD
  printf -- '- 2026-07-02T10:00:00Z [progress] scaffolded pre-compact loop\n- 2026-07-02T10:05:00Z [progress] added composed resume path\n' \
    > "${proj}/docs/leadv2/tasks/T-ALPHA/journal.md"

  printf -- '- 2026-07-02T09:00:00Z [progress] review pass 1 started\n- 2026-07-02T09:30:00Z [progress] review pass 1 done\n' \
    > "${proj}/docs/leadv2/tasks/T-BETA/journal.md"

  printf -- '- thread: confirm dedupe order\n- thread: confirm 60-line cap\n- thread: no-active-task case\n' \
    > "${proj}/docs/leadv2/open-threads.md"
}

PROJ="${TMPDIR_BASE}/proj"
mkdir -p "$PROJ"
setup_sandbox "$PROJ"

# ---------------------------------------------------------------------------
# (1) pre-compact hook writes BOTH tasks/T-ALPHA and tasks/T-BETA pre-compact-resume.md
#     (no checkpoint.md present -> composed path for both)
# ---------------------------------------------------------------------------
INPUT_JSON=$(printf '{"cwd":"%s"}' "$PROJ")
PRE_RC=0
set +e; printf '%s' "$INPUT_JSON" | bash "$PRE_HOOK" >/dev/null 2>&1; PRE_RC=$?; set -e
if [[ $PRE_RC -eq 0 ]]; then
  pass "(0a) pre-compact hook exits 0"
else
  fail "(0a) pre-compact hook must exit 0 (got rc=$PRE_RC)"
fi

ALPHA_RESUME="${PROJ}/docs/leadv2/tasks/T-ALPHA/pre-compact-resume.md"
BETA_RESUME="${PROJ}/docs/leadv2/tasks/T-BETA/pre-compact-resume.md"

if [[ -f "$ALPHA_RESUME" && -f "$BETA_RESUME" ]]; then
  pass "(1) pre-compact hook writes resume.md for BOTH T-ALPHA and T-BETA"
else
  fail "(1) expected both resume files (alpha=$([[ -f "$ALPHA_RESUME" ]] && echo yes || echo no) beta=$([[ -f "$BETA_RESUME" ]] && echo yes || echo no))"
fi

# ---------------------------------------------------------------------------
# (2) T-ALPHA resume contains the goal line and a journal line
# ---------------------------------------------------------------------------
if [[ -f "$ALPHA_RESUME" ]] \
  && grep -q "ship the compact hooks rewrite" "$ALPHA_RESUME" \
  && grep -q "scaffolded pre-compact loop" "$ALPHA_RESUME"; then
  pass "(2) T-ALPHA resume contains goal line and journal line"
else
  fail "(2) T-ALPHA resume missing goal and/or journal line"
fi

# ---------------------------------------------------------------------------
# (3) postcompact stdout contains T-ALPHA block, journal tail, T-BETA line,
#     open-threads line, and total lines <= 60
# ---------------------------------------------------------------------------
POST_RC=0
set +e; POST_OUT=$(HOME="${PROJ}/home" PYTHONPATH="$REAL_USER_SITE" CLAUDE_PROJECT_DIR="$PROJ" bash "$POST_HOOK" 2>/dev/null); POST_RC=$?; set -e
if [[ $POST_RC -eq 0 ]]; then
  pass "(0b) postcompact hook exits 0"
else
  fail "(0b) postcompact hook must exit 0 (got rc=$POST_RC)"
fi
# COMPACT-DEDUP-01 (2026-07-23): postcompact STDOUT was silenced — the canonical
# context now lands in <leadv2_dir>/.compact-freeze.md (written pre-compact by
# pre-compact-task-freeze.sh, reinjected by post-compact-reground.sh). Assert
# THAT sink, not the old stdout. The freeze hook picks the single newest journal
# by mtime (here T-BETA, written last), so accept either task's journal line.
_FZ3_LOCK="$(mktemp -d "${TMPDIR_BASE}/fz3XXXX")"
_FZ3_JSON=$(python3 -c "import json,sys; print(json.dumps({'cwd': sys.argv[1]}))" "$PROJ")
TMPDIR="$_FZ3_LOCK" CLAUDE_PLUGIN_ROOT="/fake/plugin/root" \
  bash -c "printf '%s' '$_FZ3_JSON' | bash '$FREEZE_HOOK'" >/dev/null 2>&1 || true
FREEZE_FILE="${PROJ}/docs/leadv2/.compact-freeze.md"
if [[ -f "$FREEZE_FILE" ]] \
  && grep -q "confirm dedupe order" "$FREEZE_FILE" \
  && grep -qE "scaffolded pre-compact loop|review pass 1 started" "$FREEZE_FILE"; then
  pass "(3) freeze file carries an active journal tail + open thread (postcompact stdout silenced by DEDUP-01)"
else
  fail "(3) freeze file missing journal tail / open thread:"$'\n'"$(cat "$FREEZE_FILE" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# (4) No-active-task case: empty sessions + non-empty open-threads.md -> stdout
#     contains threads block only
# ---------------------------------------------------------------------------
PROJ2="${TMPDIR_BASE}/proj2"
mkdir -p "${PROJ2}/.claude/leadv2-overrides" "${PROJ2}/docs/leadv2"
mkdir -p "${PROJ2}/home/.claude/hooks" "${PROJ2}/home/.claude/state/leadv2"
cp "$ACTIVE_CACHE_SRC" "${PROJ2}/home/.claude/hooks/leadv2-active-cache.sh"
cat > "${PROJ2}/docs/leadv2/active.yaml" <<'YAML'
sessions: []
YAML
printf -- '- thread: lone open thread\n' > "${PROJ2}/docs/leadv2/open-threads.md"

POST_RC2=0
set +e; POST_OUT2=$(HOME="${PROJ2}/home" PYTHONPATH="$REAL_USER_SITE" CLAUDE_PROJECT_DIR="$PROJ2" bash "$POST_HOOK" 2>/dev/null); POST_RC2=$?; set -e
if [[ $POST_RC2 -eq 0 ]]; then
  pass "(0c) postcompact hook (no-active-task) exits 0"
else
  fail "(0c) postcompact hook must exit 0 (got rc=$POST_RC2)"
fi

# COMPACT-DEDUP-01: re-pointed from postcompact stdout to the freeze sink. With
# no active task there is no journal -> the freeze file must carry the open
# thread and NO ACTIVE JOURNAL TAIL section.
_FZ4_LOCK="$(mktemp -d "${TMPDIR_BASE}/fz4XXXX")"
_FZ4_JSON=$(python3 -c "import json,sys; print(json.dumps({'cwd': sys.argv[1]}))" "$PROJ2")
TMPDIR="$_FZ4_LOCK" CLAUDE_PLUGIN_ROOT="/fake/plugin/root" \
  bash -c "printf '%s' '$_FZ4_JSON' | bash '$FREEZE_HOOK'" >/dev/null 2>&1 || true
FREEZE_FILE2="${PROJ2}/docs/leadv2/.compact-freeze.md"
if [[ -f "$FREEZE_FILE2" ]] \
  && grep -q "lone open thread" "$FREEZE_FILE2" \
  && ! grep -q "ACTIVE JOURNAL TAIL" "$FREEZE_FILE2"; then
  pass "(4) no-active-task + open threads -> freeze file carries threads only (no journal tail)"
else
  fail "(4) freeze file threads-only contract broken:"$'\n'"$(cat "$FREEZE_FILE2" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# (5) Active task with journal.md but NO STATE.md -> postcompact still emits
#     the task id and a journal line (regression test for Codex finding 1)
# ---------------------------------------------------------------------------
PROJ3="${TMPDIR_BASE}/proj3"
mkdir -p "${PROJ3}/.claude/leadv2-overrides" "${PROJ3}/docs/leadv2/tasks/T-GAMMA"
mkdir -p "${PROJ3}/home/.claude/hooks" "${PROJ3}/home/.claude/state/leadv2"
cp "$ACTIVE_CACHE_SRC" "${PROJ3}/home/.claude/hooks/leadv2-active-cache.sh"
cat > "${PROJ3}/docs/leadv2/active.yaml" <<'YAML'
sessions:
  - task_id: T-GAMMA
    phase: ship
YAML
# journal.md present, STATE.md intentionally absent
printf -- '- 2026-07-02T11:00:00Z [progress] gamma work in progress\n' \
  > "${PROJ3}/docs/leadv2/tasks/T-GAMMA/journal.md"

POST_RC3=0
set +e; POST_OUT3=$(HOME="${PROJ3}/home" PYTHONPATH="$REAL_USER_SITE" CLAUDE_PROJECT_DIR="$PROJ3" bash "$POST_HOOK" 2>/dev/null); POST_RC3=$?; set -e
if [[ $POST_RC3 -eq 0 ]]; then
  pass "(0d) postcompact hook (no-STATE.md) exits 0"
else
  fail "(0d) postcompact hook must exit 0 with no STATE.md (got rc=$POST_RC3)"
fi

# COMPACT-DEDUP-01: re-pointed from postcompact stdout to the freeze sink. With
# only T-GAMMA's journal present, the freeze file's ACTIVE JOURNAL TAIL section
# carries both the task id (in the heading) and the journal line — the
# regression this case guards (context survives even with no STATE.md).
_FZ5_LOCK="$(mktemp -d "${TMPDIR_BASE}/fz5XXXX")"
_FZ5_JSON=$(python3 -c "import json,sys; print(json.dumps({'cwd': sys.argv[1]}))" "$PROJ3")
TMPDIR="$_FZ5_LOCK" CLAUDE_PLUGIN_ROOT="/fake/plugin/root" \
  bash -c "printf '%s' '$_FZ5_JSON' | bash '$FREEZE_HOOK'" >/dev/null 2>&1 || true
FREEZE_FILE3="${PROJ3}/docs/leadv2/.compact-freeze.md"
if [[ -f "$FREEZE_FILE3" ]] \
  && grep -q "T-GAMMA" "$FREEZE_FILE3" \
  && grep -q "gamma work in progress" "$FREEZE_FILE3"; then
  pass "(5) active task with journal but no STATE.md -> freeze file carries task id + journal line"
else
  fail "(5) freeze file missing task id / journal line:"$'\n'"$(cat "$FREEZE_FILE3" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# (6) OT-SESSION-SCOPE-01: pre-compact-task-freeze.sh scopes its OPEN THREADS
#     section by session_id. Mixed file (A-tagged + B-tagged + untagged):
#     freeze with session A keeps untagged + A, hides B, reports the count.
# ---------------------------------------------------------------------------
PROJ_FZ="${TMPDIR_BASE}/proj_freeze"
mkdir -p "${PROJ_FZ}/docs/leadv2" "${PROJ_FZ}/.claude/leadv2-overrides"
git -C "$PROJ_FZ" init -q
git -C "$PROJ_FZ" config user.email test@test.local
git -C "$PROJ_FZ" config user.name test
cat > "${PROJ_FZ}/docs/leadv2/open-threads.md" <<'MD'
## Captured asks (auto)
- [ ] 2026-08-04T11:00:00Z — freeze legacy untagged line
- [ ] 2026-08-04T11:01:00Z [s:aaaaaaaa] — freeze alpha for session A
- [ ] 2026-08-04T11:02:00Z [s:bbbbbbbb] — freeze beta for session B
MD
FZA_JSON=$(python3 -c "import json,sys; print(json.dumps({'cwd': sys.argv[1], 'session_id': 'aaaaaaaa-1111-2222-3333-444455556666'}))" "$PROJ_FZ")
# COMPACT-DEDUP-02: isolate the run-once lock (see test-open-threads-prune.sh).
# Without this, case (6)'s stdout is suppressed by (6) of a prior suite run
# within the same 60 s window — the reported cwd-dependent non-determinism.
_FZ6_LOCK="$(mktemp -d "${TMPDIR_BASE}/fz6XXXX")"
FZA_OUT="$(TMPDIR="$_FZ6_LOCK" CLAUDE_PLUGIN_ROOT="/fake/plugin/root" bash -c "printf '%s' '$FZA_JSON' | bash '$FREEZE_HOOK'")"
if printf '%s\n' "$FZA_OUT" | grep -q "OPEN THREADS" \
  && printf '%s\n' "$FZA_OUT" | grep -q "freeze legacy untagged line" \
  && printf '%s\n' "$FZA_OUT" | grep -q "freeze alpha for session A" \
  && ! printf '%s\n' "$FZA_OUT" | grep -q "freeze beta for session B" \
  && printf '%s\n' "$FZA_OUT" | grep -q "thread(s) from other sessions hidden"; then
  pass "(6) freeze with session A keeps untagged + A, hides B, reports hidden"
else
  fail "(6) freeze session scoping failed:"$'\n'"${FZA_OUT}"
fi

# ---------------------------------------------------------------------------
# (7) OT-SESSION-SCOPE-01 (backward-compat guard): freeze with NO session_id
#     sees every entry (legacy + both tags) and never hides — byte-equivalent
#     to the pre-change hook.
# ---------------------------------------------------------------------------
FZN_JSON=$(python3 -c "import json,sys; print(json.dumps({'cwd': sys.argv[1]}))" "$PROJ_FZ")
# COMPACT-DEDUP-02: isolate the lock. Case (7) has no session_id -> the lock
# falls back to a shared "nosession" key, which collides with itself across
# back-to-back runs without an isolated TMPDIR.
_FZ7_LOCK="$(mktemp -d "${TMPDIR_BASE}/fz7XXXX")"
FZN_OUT="$(TMPDIR="$_FZ7_LOCK" CLAUDE_PLUGIN_ROOT="/fake/plugin/root" bash -c "printf '%s' '$FZN_JSON' | bash '$FREEZE_HOOK'")"
if printf '%s\n' "$FZN_OUT" | grep -q "freeze legacy untagged line" \
  && printf '%s\n' "$FZN_OUT" | grep -q "freeze alpha for session A" \
  && printf '%s\n' "$FZN_OUT" | grep -q "freeze beta for session B" \
  && ! printf '%s\n' "$FZN_OUT" | grep -q "thread(s) from other sessions hidden"; then
  pass "(7) freeze with no session_id keeps all entries (backward compat)"
else
  fail "(7) freeze backward-compat failed:"$'\n'"${FZN_OUT}"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
