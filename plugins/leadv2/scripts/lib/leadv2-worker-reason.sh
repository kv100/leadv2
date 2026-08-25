#!/usr/bin/env bash
# leadv2-worker-reason.sh — LANE-OBSERVABILITY-02 change 1.
#
# Extracts the worker's OWN last words for a lane that stopped with nothing to
# show (no_work/dead), so a dispatch_terminal row can say WHY in the worker's
# voice instead of the dispatcher's taxonomy. Live incident (2026-08-25):
# three stops in a row journaled cause=arm_produced_nothing|empty_diff while
# the workers' final messages said "DELIVERABLE_BLOCKED: census falsified" /
# "Stopped at prepass" — the lead had to exhume rollout jsonl by hand.
#
# lv2_worker_reason <handoff_dir> <arm> <task_sig8> [<since_epoch>]
#   stdout: single line, <=120 bytes, sanitized; EMPTY on miss; rc always 0.
#   Pure read — never writes, never gates. Fail-open to empty on every error.
#
# Resolution order (first non-empty wins), every source guarded:
#   sonnet/claude  <handoff>/developer.stream.jsonl — last {"type":"result"}
#                  -> .result; else last type:assistant text block.
#   codex          newest rollout under the sessions ROOT (resolution below)
#                  whose body literally carries the task sig8, inside the
#                  mtime window >= since, AND (when LEADV2_LANE_WORK_ROOT is
#                  set) whose session_meta cwd matches — last
#                  task_complete.last_agent_message.
#                  Attribution rule (D2): a rollout is used only when
#                  something ties it to THIS lane. Empty/short sig8, missing/
#                  unreadable root, or zero survivors is a MISS -> empty.
#                  This is deliberate: the alternative is attributing a
#                  sibling lane's last words to this lane. Do NOT "fix" the
#                  empty case back to newest-global.
#   glm/kimi       <handoff>/developer.glm.out — last non-blank line; else
#                  <handoff>/<arm>.stream.jsonl when present.
#   unknown arm    tries the claude source, then codex, then glm.out.
#
# Env: LEADV2_WORKER_REASON=0 is the kill switch (callers check it, and the
# function also honours it directly for direct-sourced callers).
# Sessions ROOT resolution (first non-empty wins):
#   1. LEADV2_CODEX_SESSIONS_ROOT    (canonical)
#   2. LV2_CODEX_SESSIONS_ROOT       (brief-compat alias, see D1)
#   3. ${LEADV2_WORKER_REASON_CODEX_HOME}/sessions  (legacy knob, kept)
#   4. ${CODEX_HOME}/sessions
#   5. $HOME/.codex/sessions         (default)

lv2_worker_reason() {  # <handoff_dir> <arm> <task_sig8> [<since_epoch>]
  local handoff="${1:-}" arm="${2:-}" sig8="${3:-}" since="${4:-0}"
  [[ "${LEADV2_WORKER_REASON:-1}" == "1" ]] || return 0
  # NOTE: no -d handoff guard here — the CODEX source is global (rollout files
  # under ~/.codex), so a codex arm with a missing/empty handoff dir must still
  # resolve; the handoff-backed sources guard themselves on isdir/open-fail.
  local sessions_root="${LEADV2_CODEX_SESSIONS_ROOT:-${LV2_CODEX_SESSIONS_ROOT:-}}"
  [[ -n "$sessions_root" ]] || sessions_root="${LEADV2_WORKER_REASON_CODEX_HOME:+${LEADV2_WORKER_REASON_CODEX_HOME}/sessions}"
  [[ -n "$sessions_root" ]] || sessions_root="${CODEX_HOME:+${CODEX_HOME}/sessions}"
  [[ -n "$sessions_root" ]] || sessions_root="$HOME/.codex/sessions"
  python3 - "${handoff}" "${arm}" "${sig8}" "${since}" \
    "${sessions_root}" \
    "${LEADV2_LANE_WORK_ROOT:-}" <<'PY' 2>/dev/null || true
import glob, json, os, re, sys

handoff, arm_raw, sig8, since_raw, sessions_root, expected_cwd = sys.argv[1:7]
try:
    since = int(since_raw)
except ValueError:
    since = 0

def sanitize(s):
    if not s:
        return ""
    s = re.sub(r"\s+", " ", str(s))
    s = s.replace('"', "").replace("\\", "")
    s = re.sub(r"[\x00-\x1f\x7f]", "", s)
    return s.strip()[:120]

def from_claude_stream():
    if not (handoff and os.path.isdir(handoff)):
        return ""
    p = os.path.join(handoff, "developer.stream.jsonl")
    try:
        with open(p, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return ""
    # last {"type":"result"} -> .result (the worker's own final text)
    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if isinstance(d, dict) and d.get("type") == "result":
            r = d.get("result")
            if isinstance(r, str) and r.strip():
                return r
    # else last type:assistant text block
    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if not (isinstance(d, dict) and d.get("type") == "assistant"):
            continue
        msg = d.get("message")
        if not isinstance(msg, dict):
            continue
        for blk in reversed(msg.get("content") or []):
            if isinstance(blk, dict) and blk.get("type") == "text" \
               and str(blk.get("text") or "").strip():
                return str(blk["text"])
    return ""

def from_codex_rollout():
    # D2: a rollout is used only when something ties it to THIS lane. No
    # attributing key -> miss; never fall through to "newest global".
    if not sig8 or len(sig8) < 8:
        return ""
    candidates = []
    for p in glob.glob(os.path.join(sessions_root, "**", "rollout-*.jsonl"), recursive=True):
        try:
            m = os.path.getmtime(p)
        except OSError:
            continue
        if m < since:
            continue
        cwd = None
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                first = fh.readline()
            d = json.loads(first)
            if d.get("type") == "session_meta":
                cwd = d.get("payload", {}).get("cwd")
        except (OSError, ValueError):
            cwd = None
        candidates.append((m, p, cwd))
    candidates.sort(key=lambda t: t[0])
    pool = candidates
    # cwd hard filter stays as an AND-guard (same rule as dispatch-code.sh's
    # rollout discovery): with a known expected cwd and zero matches, "no
    # candidate" -- never guess a sibling dispatch's rollout.
    if expected_cwd:
        pool = [c for c in candidates if c[2] == expected_cwd]
    if not pool:
        return ""
    # task attribution: the rollout's own bytes must carry this dispatch's
    # sig8 (the codex mission text always names dispatch-<sig8>). Bounded
    # read: first 512 KB, case-sensitive raw substring. Newest survivor wins.
    needle = sig8.encode("utf-8")
    p = None
    for _m, cand, _cwd in reversed(pool):
        try:
            with open(cand, "rb") as fh:
                head = fh.read(512 * 1024)
        except OSError:
            continue
        if needle in head:
            p = cand
            break
    if p is None:
        return ""
    try:
        with open(p, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return ""
    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("type") != "event_msg":
            continue
        payload = d.get("payload")
        if not (isinstance(payload, dict) and payload.get("type") == "task_complete"):
            continue
        msg = payload.get("last_agent_message")
        if isinstance(msg, str) and msg.strip():
            return msg
        return ""  # terminal task_complete with null message = dead shape
    return ""

def from_glm_out():
    if not (handoff and os.path.isdir(handoff)):
        return ""
    for name in ("developer.glm.out", "developer.kimi.out"):
        p = os.path.join(handoff, name)
        if os.path.isfile(p):
            try:
                with open(p, encoding="utf-8", errors="replace") as fh:
                    lines = [l for l in fh.read().splitlines() if l.strip()]
            except OSError:
                continue
            if lines:
                return lines[-1]
    for p in sorted(glob.glob(os.path.join(handoff, "*.stream.jsonl"))):
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                lines = [l for l in fh.read().splitlines() if l.strip()]
        except OSError:
            continue
        if lines:
            return lines[-1]
    return ""

arm = (arm_raw or "").lower()
out = ""
try:
    if any(k in arm for k in ("sonnet", "claude", "opus", "haiku")):
        out = from_claude_stream() or from_codex_rollout() or from_glm_out()
    elif "codex" in arm:
        out = from_codex_rollout() or from_claude_stream() or from_glm_out()
    elif any(k in arm for k in ("glm", "kimi")):
        out = from_glm_out() or from_claude_stream()
    else:
        out = from_claude_stream() or from_codex_rollout() or from_glm_out()
except Exception:
    out = ""
print(sanitize(out))
PY
  return 0
}

# Direct-execution guard: this file is a library; a caller who runs it
# directly WITH args (leadv2-broad-status.sh's renderer does — `bash lib
# <handoff> <arm> <sig8>`) gets the extraction on stdout; bare execution gets
# usage, not a silent no-op.
if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  if [[ $# -ge 1 ]]; then
    lv2_worker_reason "$1" "${2:-}" "${3:-}" "${4:-0}"
    exit 0
  fi
  printf 'usage: %s <handoff_dir> <arm> <task_sig8> [since_epoch]  (or: source this file)\n' "$0" >&2
  exit 2
fi
