#!/usr/bin/env bash
# scripts/leadv2-reply-router.sh — single entry point for `/leadv2 reply
# <q-id> <option>`. LANE-QUESTION-DELIVERY-01.
#
# THE GAP this closes: the question channel has always had TWO stores (see
# leadv2-ask.sh / leadv2-answer.sh header comments, and the leadv2-supervise
# SKILL.md "Async question channel" section):
#   - control-plane  <state-root>/questions/<qid>.yaml   — canonical for
#     fanned-out/adopted lanes (leadv2-ask.sh writes, leadv2-answer.sh answers)
#   - legacy-handoff docs/handoff/<task_id>/questions-async/<qid>-pending.yaml
#     — worktree-local, embedded same-session subagents (leadv2-reply.sh)
# But the documented `/leadv2 reply` PROCEDURE (docs/phases.md §Invocation)
# only ever looked in the legacy-handoff store. A control-plane q-id — which
# is what every fanned-out lane actually uses — had no path to an answer at
# all: the lead would grep docs/handoff/*/questions-async/*-pending.yaml,
# find nothing, and hard-fail "not found", even though the question was
# sitting right there in the control-plane store waiting. This script
# resolves BOTH stores and dispatches to whichever one actually holds the
# qid, so `/leadv2 reply` works regardless of which store asked the question.
#
# Usage:
#   leadv2-reply-router.sh <q-id> <option> [--task-id <id>]
#
# --task-id is optional: only needed as a disambiguation hint for the
# legacy-handoff store if the same qid string were ever found under more
# than one task-id directory (should not happen — qids are random per
# leadv2_ask_async, but this keeps the caller's existing --task-id knowledge
# useful instead of discarding it).
#
# Exit codes (mirrors the underlying scripts so callers need no new cases):
#   0 — answer recorded successfully
#   3 — invalid option (not in the question's options[] list)
#   4 — question already answered
#   5 — question id not found in either store
#   1 — usage / unexpected error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  printf -- 'Usage: leadv2-reply-router.sh <q-id> <option> [--task-id <id>] [--force]\n' >&2
  exit 1
}

# QUESTION-DELIVERY-OWNERSHIP-01 — returns 0 to allow the answer, non-zero
# (exit 6) to refuse a too-young foreign question. Old rows without
# owner_session always pass. --force always passes (and is logged).
_foreign_check() { # $1 = control-plane yaml path
  local qfile="$1"
  local min_age="${LEADV2_Q_FOREIGN_MIN_AGE_S:-1200}"
  local caller_session="${CLAUDE_SESSION_ID:-}"

  # Read owner_session and asked_at from the question yaml.
  local owner_session asked_at
  owner_session="$(python3 -c '
import sys, yaml
try:
    d = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
except Exception:
    d = {}
v = d.get("owner_session")
print(v if v else "")
' "$qfile" 2>/dev/null || true)"

  # No owner_session → old row (pre-OWNERSHIP) → always allow.
  [[ -z "$owner_session" ]] && return 0

  # Own question → always allow.
  [[ "$owner_session" == "$caller_session" ]] && return 0

  # Foreign question. --force overrides (logged).
  if [[ "$FORCE_FOREIGN" -eq 1 ]]; then
    printf '[leadv2-reply-router] FORCE_FOREIGN qid=%s owner=%s caller=%s\n' \
      "$QID" "$owner_session" "${caller_session:-<none>}" >&2
    return 0
  fi

  # Compute age from asked_at (ISO-8601 UTC). If we cannot parse it, err on
  # the side of allowing (fail-open, same as old rows).
  asked_at="$(python3 -c '
import sys, yaml, datetime
try:
    d = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
except Exception:
    d = {}
ts = d.get("asked_at", "") or ""
if not ts:
    print("")
    sys.exit(0)
try:
    dt = datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ")
    now = datetime.datetime.utcnow()
    print(int((now - dt).total_seconds()))
except Exception:
    print("")
' "$qfile" 2>/dev/null || true)"

  if [[ -z "$asked_at" ]]; then
    # Cannot determine age — fail-open (allow, like old rows).
    return 0
  fi

  if [[ "$asked_at" -ge "$min_age" ]]; then
    return 0
  fi

  printf -- 'Ошибка: вопрос %s принадлежит сессии %s (возраст %ss < порога %ss). Ответ может дать только владелец или подождите истечения порога. Используйте --force для принудительного ответа.\n' \
    "$QID" "$owner_session" "$asked_at" "$min_age" >&2
  return 6
}

QID=""
OPTION=""
TASK_ID_HINT=""
FORCE_FOREIGN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id)
      [[ $# -ge 2 ]] || { printf -- 'Ошибка: --task-id требует значение\n' >&2; exit 1; }
      TASK_ID_HINT="$2"
      shift 2
      ;;
    --force)
      # QUESTION-DELIVERY-OWNERSHIP-01: override the foreign-answer age gate
      # so an operator may answer another session's question on demand.
      FORCE_FOREIGN=1
      shift
      ;;
    --*)
      printf -- 'Ошибка: неизвестный флаг %s\n' "$1" >&2
      usage
      ;;
    *)
      if [[ -z "$QID" ]]; then
        QID="$1"
      elif [[ -z "$OPTION" ]]; then
        OPTION="$1"
      else
        printf -- 'Ошибка: лишний аргумент %s\n' "$1" >&2
        usage
      fi
      shift
      ;;
  esac
done

[[ -n "$QID" && -n "$OPTION" ]] || usage

PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${PROJECT_ROOT:-$(pwd)}}"

# ── Try control-plane store first (canonical for fanned-out/adopted lanes) ──
CP_QUESTIONS_DIR="$(bash "${SCRIPT_DIR}/leadv2-state-path.sh" questions 2>/dev/null || true)"
CP_FILE=""
if [[ -n "$CP_QUESTIONS_DIR" && -f "${CP_QUESTIONS_DIR}/${QID}.yaml" ]]; then
  CP_FILE="${CP_QUESTIONS_DIR}/${QID}.yaml"
fi

# ── Try legacy-handoff store (worktree-local, embedded same-session subagents) ──
LEGACY_MATCHES=()
if [[ -n "$TASK_ID_HINT" ]]; then
  cand="${PROJECT_ROOT}/docs/handoff/${TASK_ID_HINT}/questions-async/${QID}-pending.yaml"
  [[ -f "$cand" ]] && LEGACY_MATCHES+=("$cand")
else
  while IFS= read -r -d '' f; do
    LEGACY_MATCHES+=("$f")
  done < <(find "${PROJECT_ROOT}/docs/handoff" -maxdepth 3 -type f \
              -path "*/questions-async/${QID}-pending.yaml" -print0 2>/dev/null)
fi

if [[ -n "$CP_FILE" && ${#LEGACY_MATCHES[@]} -gt 0 ]]; then
  printf -- 'Ошибка: qid %s найден в ОБОИХ хранилищах (control-plane: %s; legacy: %s) — это не должно происходить, коллизия id. Прекращаю без ответа.\n' \
    "$QID" "$CP_FILE" "${LEGACY_MATCHES[0]}" >&2
  exit 1
fi

if [[ -n "$CP_FILE" ]]; then
  # QUESTION-DELIVERY-OWNERSHIP-01: foreign-answer gate. If the question has
  # an owner_session that differs from THIS session's id, only allow the
  # answer once the question is older than LEADV2_Q_FOREIGN_MIN_AGE_S (default
  # 1200s). --force overrides (logged). Old rows without owner_session are
  # always allowed (backward-compatible).
  _foreign_check "$CP_FILE" || exit $?
  exec bash "${SCRIPT_DIR}/leadv2-answer.sh" "$QID" "$OPTION"
fi

if [[ ${#LEGACY_MATCHES[@]} -eq 1 ]]; then
  legacy_file="${LEGACY_MATCHES[0]}"
  # .../docs/handoff/<task_id>/questions-async/<qid>-pending.yaml
  task_id="$(basename "$(dirname "$(dirname "$legacy_file")")")"
  # Critic r1 MEDIUM: legacy rows are never stamped with owner_session today
  # (leadv2-ask.sh writes control-plane only), so this call always takes the
  # old-row allow branch -- it exists so the gate holds automatically if the
  # legacy writer ever starts stamping ownership.
  _foreign_check "$legacy_file" || exit $?
  exec bash "${SCRIPT_DIR}/leadv2-reply.sh" --task-id "$task_id" "$QID" "$OPTION"
fi

if [[ ${#LEGACY_MATCHES[@]} -gt 1 ]]; then
  printf -- 'Ошибка: qid %s найден в НЕСКОЛЬКИХ legacy-задачах (%s) — укажите --task-id.\n' \
    "$QID" "$(IFS=,; echo "${LEGACY_MATCHES[*]}")" >&2
  exit 1
fi

printf -- 'Ошибка: вопрос %s не найден ни в control-plane хранилище (%s/%s.yaml), ни в legacy-хранилище (docs/handoff/*/questions-async/%s-pending.yaml). Возможно, id указан неверно, вопрос уже отвечен и архивирован, или его задающая сессия давно завершилась и он был поглощён при абсорбции orphan-состояния.\n' \
  "$QID" "${CP_QUESTIONS_DIR:-<control-plane unresolved>}" "$QID" "$QID" >&2
exit 5
