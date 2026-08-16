#!/usr/bin/env bash
# leadv2-fork-session.sh — FORK-RUNS-A-SESSION-01: lead-side pre/post ops for
# a fork-owned /leadv2 session (Phase 0..8 carried by a fork, not a lead).
#
# WHY THIS EXISTS: a fork was only ever used for fragments (a review, a
# judgement, a synthesis) because three phases looked lead-only: Gate 1 needs
# founder input, Phase 6 needs ExitWorktree, Phase 8 reaps the worktree. All
# three already have bash answers for headless lanes — leadv2-ask.sh's
# control-plane questions/ dir, leadv2-lane-worktree.sh's bash lane (the same
# path/branch EnterWorktree uses), leadv2-deploy-merge.sh's worktree-<id>
# branch resolution. This script is the thin lead-side wrapper around those
# EXISTING pieces; it never enters a tool worktree and never reimplements a
# gate. The fork itself addresses every file by absolute path under the lane
# root — it shares the session CWD with the lead and never calls `cd`.
#
# Carve-outs this script enforces (design §2, "The honest boundary"):
#   A — worktree lifecycle: `preflight` (lead, before spawn) creates the lane;
#        the fork never calls EnterWorktree/ExitWorktree/cd.
#   B — worktree reaping: `postflight` (lead, after the fork reports done)
#        removes the lane — deleting a dir a session may hold a path under is
#        the same ENOENT class the ExitWorktree delegation ban guards.
#   C — daemon self-spawn: `postflight --self-spawn` only; a fork spawning
#        the next session would spawn it inside the lead's session.
#
# Ops:
#   preflight <task-id> [class]
#       ensure lane (leadv2-lane-worktree.sh ensure), register active.yaml,
#       write <lane>/docs/handoff/<task-id>/fork-lane.env
#       (TASK_ID/LANE_ROOT/CONTROL_PLANE), print the ABS lane root to stdout.
#       Idempotent: re-running returns the same lane.
#       REFUSES (exit 1) when an isolated lane is unavailable — kill-switch
#       LEADV2_LANE_WORKTREE=off, ensure's shared-root fallback, an
#       unregistered worktree, or the wrong branch. A fork sharing the lead's
#       session CWD in the shared checkout is the 2026-07-28 mutual-clobber
#       incident by construction; preflight never degrades (ensure's own
#       never-block contract stays untouched for ordinary lanes).
#   ask <task-id> "<question>" --option "label|desc" [--option ...]
#       [--default-option <label>] [--phase <p>] [--timeout-poll <sec=540>]
#       Fork-side Gate 1. Wraps leadv2-ask.sh --no-block (question lands in
#       the control-plane questions/ dir — the founder answers via
#       /leadv2 reply, same surface as every lane), then polls BOUNDED so the
#       Bash call stays under the 600s tool ceiling.
#       The pending question SURVIVES a retry: identity is persisted in
#       <control-plane>/fork-ask/<task-id>.yaml (qid + fingerprint + question,
#       sibling of questions/ so /leadv2 questions never sees it), and a
#       re-invoke with the same question polls THAT qid — one question, N
#       bounded polls. A degraded ask (label where a qid belongs) is refused:
#       a failed control-plane write must not manufacture the founder's
#       consent.
#         exit 0  answered — chosen option label on stdout
#         exit 3  still pending after the poll cap — gate NOT passed; the fork
#                 re-invokes later and resumes polling THIS question
#         exit 1  usage error / question write failed / a DIFFERENT question
#                 is still pending for this task (answer it or --cancel-pending)
#   ask <task-id> --cancel-pending
#       Withdraw this task's fork-ask record (operator escape after a refused
#       duplicate ask). Does not touch the question record itself.
#   commit <task-id> -m "<msg>" (--all | --paths <p> …)
#       Fork-side Phase 6 commit INTO THE LANE: every git call carries
#       `-C <lane-root>`, never a bare `git` on the shared session CWD.
#       Re-runs the isolation assertion — the same predicate that gates spawn
#       gates the commit. Empty index => exit 0 "nothing to commit"
#       (idempotent Phase 6 retry).
#   postflight <task-id> [--self-spawn] [--force]
#       Carve-outs B (+C with --self-spawn). REFUSES a dirty lane (exit 1,
#       worktree left on disk for inspection — mirrors the Phase 6
#       circuit-break). No-op-safe when no worktree exists.
#
# Untouched by design (reused, never modified): leadv2-ask.sh, leadv2-answer.sh,
# leadv2-lane-worktree.sh, leadv2-deploy-merge.sh, leadv2-phase8-close.sh,
# leadv2-state-atomic-write.sh.
#
# Env:
#   LEADV2_PROJECT_ROOT   main checkout the lane forks from (default: derived
#                         from git-common-dir so a lead running inside its own
#                         worktree still creates the lane under the MAIN root,
#                         matching EnterWorktree's .claude/worktrees convention)
#   LEADV2_FORK_ASK_POLL_SEC   ask-op poll cap (default 540)
#   LEADV2_ASK_POLL_INTERVAL   seconds between polls (default 3, shared with
#                              leadv2-ask.sh)
#
# Exit codes: 0 ok / 1 error / 3 ask-still-pending. `ensure`-style never-block
# semantics do NOT apply here: preflight failure means the lead must not spawn
# the fork, so preflight fails loud.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()       { printf '[fork-session] %s\n' "$*" >&2; }
log_error() { printf '[fork-session] ERROR: %s\n' "$*" >&2; }

usage() {
  sed -n '2,60p' "${BASH_SOURCE[0]}" | grep '^#   \|^# Ops:' | sed 's/^# \{0,1\}//' >&2
  exit 1
}

# Main checkout the lane should live under. Explicit env wins; otherwise a
# linked worktree derives the MAIN root from git-common-dir (the same trick
# leadv2-state-path.sh uses to resolve one root from every worktree).
resolve_project_root() {
  if [[ -n "${LEADV2_PROJECT_ROOT:-}" ]]; then
    printf '%s\n' "$LEADV2_PROJECT_ROOT"
    return 0
  fi
  local common toplevel
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  common="$(git -C "${toplevel:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [[ -n "$common" && -d "$common" && "$common" == */.git ]]; then
    (cd "$(dirname "$common")" && pwd)
  elif [[ -n "$toplevel" ]]; then
    printf '%s\n' "$toplevel"
  else
    return 1
  fi
}

# ── isolation assertion (H1) ────────────────────────────────────────────────
# Resolve a path to its PHYSICAL form — macOS symlinks /tmp -> /private/tmp,
# and git's `worktree list --porcelain` reports the physical path. Mirrors
# phys() in leadv2-lane-worktree.sh (the reference predicate).
phys() { ( cd "$1" 2>/dev/null && pwd -P ) 2>/dev/null || printf '%s' "$1"; }

# assert_isolated_lane <task_id> <project_root> <lane_root>
# Four conjunctive checks; first failure names the check and both values, then
# exits 1. Runs AFTER ensure and BEFORE any registry row or fork-lane.env is
# written, so a refusal leaves no state behind to mislead a later reader.
assert_isolated_lane() {
  local task_id="$1" project_root="$2" lane_root="$3"
  local errf="${LEADV2_LANE_WORKTREE_ERRF:-/tmp/pe-lane-worktree.err}"

  # 2. Expected path — ensure degrades to the SHARED root on any git failure;
  #    a fork-owned session must never accept it.
  local wt_dir expected phys_expected phys_got
  wt_dir="${LEADV2_WORKTREE_DIR:-${project_root}/.claude/worktrees}"
  expected="${wt_dir}/${task_id}"
  phys_expected="$(phys "$expected")"
  phys_got="$(phys "$lane_root")"
  if [[ "$phys_got" != "$phys_expected" ]]; then
    log_error "task=${task_id}: fork requires an isolated lane — expected ${phys_expected}, got ${phys_got} (ensure diagnostics: ${errf}); refusing, no fork spawned"
    exit 1
  fi

  # 3. Registered worktree — rejects a stale directory git no longer tracks
  #    (the main checkout IS listed by worktree list, so check 2 is what
  #    rejects the shared root; this check rejects the other failure mode).
  if ! git -C "$project_root" worktree list --porcelain 2>/dev/null | grep -q "^worktree ${phys_expected}\$"; then
    log_error "task=${task_id}: lane ${phys_expected} exists but is not a registered git worktree (ensure diagnostics: ${errf}); refusing, no fork spawned"
    exit 1
  fi

  # 4. Branch identity — deploy-merge resolves worktree-<id> later; a lane on
  #    any other branch would strand the Phase 6 land step.
  local branch
  branch="$(git -C "$lane_root" symbolic-ref --short HEAD 2>/dev/null || true)"
  if [[ "$branch" != "worktree-${task_id}" ]]; then
    log_error "task=${task_id}: lane branch is '${branch:-<unborn/none>}', expected 'worktree-${task_id}' — refusing, no fork spawned"
    exit 1
  fi
}

# ── preflight ───────────────────────────────────────────────────────────────
cmd_preflight() {
  local task_id="${1:?preflight: <task-id> required}"
  local cls="${2:-Standard}"

  local project_root
  project_root="$(resolve_project_root)" || { log_error "cannot resolve project root (set LEADV2_PROJECT_ROOT or run inside a repo)"; exit 1; }
  export LEADV2_PROJECT_ROOT="$project_root"

  # 1. Kill-switch is fatal HERE (fatal for a fork, mere legacy for a lane):
  #    with isolation off, ensure would print the shared root and the fork
  #    would run in the lead's checkout.
  if [[ "${LEADV2_LANE_WORKTREE:-on}" == "off" ]]; then
    log_error "task=${task_id}: lane isolation disabled (LEADV2_LANE_WORKTREE=off) — a fork-owned session requires an isolated lane; refusing, no fork spawned"
    exit 1
  fi

  # Carve-out A — the lead, not the fork, creates the lane. Same path/branch
  # convention EnterWorktree uses; leadv2-deploy-merge.sh already resolves
  # worktree-<id> for landing, so nothing downstream changes.
  local lane_root
  lane_root="$(bash "${SCRIPT_DIR}/leadv2-lane-worktree.sh" ensure "$task_id" "$cls")"
  if [[ ! -d "$lane_root" ]]; then
    log_error "lane-worktree ensure did not return a usable lane root: ${lane_root}"
    exit 1
  fi
  # H1: never accept ensure's shared-root degrade. See assert_isolated_lane.
  assert_isolated_lane "$task_id" "$project_root" "$lane_root"

  # Register the lane in the shared control-plane registry (same locked write
  # N parallel lanes use — no new lock, no new surface).
  # shellcheck source=leadv2-active-registry.sh
  source "${SCRIPT_DIR}/leadv2-active-registry.sh"
  # LEADV2-SYMLINK-CLOBBER (found in the live pass): the registry resolves its
  # state-path helper at <project_root>/scripts/leadv2-state-path.sh — a layout
  # this repo does not have (plugin lives at plugins/leadv2/). The fallback
  # then writes <root>/docs/leadv2/active.yaml directly, and its atomic
  # os.replace(tmp, path) REPLACES the control-plane symlink with a private
  # regular file — forking the shared registry. Point the helper at THIS
  # plugin's real resolver so register/unregister hit the control plane from
  # any repo layout.
  _leadv2_state_path_sh() { printf '%s' "${SCRIPT_DIR}/leadv2-state-path.sh"; }
  # register's helpers print bookkeeping lines to stdout (session id, render
  # note) — keep stdout clean: preflight's contract is ONE line, the lane root.
  if ! leadv2_active_register "$task_id" "$cls" "$lane_root" "worktree-${task_id}" "false" >/dev/null; then
    log_error "active.yaml register failed for ${task_id}"
    exit 1
  fi

  # Handoff envelope for the fork: everything it must NOT guess.
  local control_plane handoff_dir
  control_plane="$(bash "${SCRIPT_DIR}/leadv2-state-path.sh" --no-link root)"
  handoff_dir="${lane_root}/docs/handoff/${task_id}"
  mkdir -p "$handoff_dir"
  cat > "${handoff_dir}/fork-lane.env" <<EOF
TASK_ID=${task_id}
LANE_ROOT=${lane_root}
CONTROL_PLANE=${control_plane}
EOF

  printf '%s\n' "$lane_root"
}

# ── ask (H2: the pending Gate-1 question survives a retry) ─────────────────
# Record layout: <control-plane>/fork-ask/<task_id>.yaml
#   qid / fingerprint / asked_at / question   (sibling of questions/ so
#   /leadv2 questions and any questions/*.yaml glob never see it)

# fa_read <record> -> "qid<TAB>fingerprint<TAB>question" on stdout, or nothing.
fa_read() {
  python3 - "$1" <<'PYEOF'
import sys, yaml
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        d = yaml.safe_load(f) or {}
except Exception:
    sys.exit(0)
if d.get("qid"):
    print("\t".join(str(d.get(k) or "") for k in ("qid", "fingerprint", "question")))
PYEOF
}

# fa_write <record> <qid> <fingerprint> <question> — atomic (tmp+replace).
fa_write() {
  python3 - "$1" "$2" "$3" "$4" <<'PYEOF'
import sys, os, yaml, datetime
path, qid, fp, question = sys.argv[1:5]
doc = {
    "qid": qid,
    "fingerprint": fp,
    "asked_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "question": question,
}
tmp = path + ".tmp.%d" % os.getpid()
with open(tmp, "w", encoding="utf-8") as f:
    yaml.safe_dump(doc, f, sort_keys=False, allow_unicode=True)
os.replace(tmp, path)
PYEOF
}

# q_status <qfile> -> "missing|" | "pending|" | "answered|<selected>"
q_status() {
  python3 - "$1" <<'PYEOF'
import sys, yaml
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        d = yaml.safe_load(f) or {}
except Exception:
    print("missing|"); sys.exit(0)
if d.get("status") == "answered":
    ans = d.get("answer")
    selected = (ans or {}).get("selected") if isinstance(ans, dict) else ans
    print("answered|%s" % (selected or ""))
else:
    print("pending|")
PYEOF
}

cmd_ask() {
  local task_id="${1:?ask: <task-id> required}"

  # Operator escape: withdraw this task's fork-ask record without touching the
  # question record (the refused-duplicate path names this command).
  if [[ "${2:-}" == "--cancel-pending" ]]; then
    local cp rec
    cp="$(bash "${SCRIPT_DIR}/leadv2-state-path.sh" --no-link root)"
    rec="${cp}/fork-ask/${task_id}.yaml"
    if [[ -f "$rec" ]]; then
      rm -f "$rec"
      log "ask: cancelled pending fork-ask record for ${task_id}"
    else
      log "ask: no pending fork-ask record for ${task_id}"
    fi
    exit 0
  fi

  local question="${2:?ask: <question> required}"
  shift 2

  local options=() default_option="" phase="" poll_cap="${LEADV2_FORK_ASK_POLL_SEC:-540}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --option)        options+=("$2"); shift 2 ;;
      --default-option) default_option="$2"; shift 2 ;;
      --phase)         phase="$2"; shift 2 ;;
      --timeout-poll)  poll_cap="$2"; shift 2 ;;
      *) log_error "ask: unknown arg: $1"; usage ;;
    esac
  done
  [[ ${#options[@]} -ge 1 ]] || { log_error "ask: at least one --option required"; usage; }

  local qdir cp_root fa_dir rec_path lock_dir
  qdir="$(bash "${SCRIPT_DIR}/leadv2-state-path.sh" --no-link questions)"
  cp_root="$(bash "${SCRIPT_DIR}/leadv2-state-path.sh" --no-link root)"
  fa_dir="${cp_root}/fork-ask"
  rec_path="${fa_dir}/${task_id}.yaml"
  lock_dir="${fa_dir}/${task_id}.lock"
  mkdir -p "$fa_dir"

  # mkdir-lock across the read-modify-write only — NEVER across the poll.
  # A single fork serialises its own calls; this is insurance against a lead
  # re-running ask for the same task concurrently. Stale (>120s) is broken.
  if ! mkdir "$lock_dir" 2>/dev/null; then
    local lock_mtime lock_age
    lock_mtime="$(stat -f %m "$lock_dir" 2>/dev/null || stat -c %Y "$lock_dir" 2>/dev/null || date +%s)"
    lock_age=$(( $(date +%s) - lock_mtime ))
    if [[ "$lock_age" -gt 120 ]]; then
      log "ask: breaking stale fork-ask lock (${lock_age}s old): ${lock_dir}"
      rm -rf "$lock_dir" && mkdir "$lock_dir"
    else
      log_error "ask: another ask for ${task_id} is in flight (${lock_dir}) — retry shortly"
      exit 1
    fi
  fi

  # Fingerprint identifies "the same question" across retries.
  local fingerprint
  fingerprint="$(python3 - "$question" "${options[@]}" "$default_option" "$phase" <<'PYEOF'
import hashlib, sys
q = sys.argv[1]
opts, default_opt, phase = sys.argv[2:-2], sys.argv[-2], sys.argv[-1]
h = hashlib.sha256()
h.update(q.encode()); h.update(b"\n")
for o in sorted(opts):
    h.update(o.encode()); h.update(b"\n")
h.update((default_opt or "").encode()); h.update(b"\n")
h.update((phase or "").encode())
print(h.hexdigest())
PYEOF
)"

  local qid="" rec_line rec_qid rec_fp rec_q st rec_status rec_ans
  if [[ -f "$rec_path" ]]; then
    rec_line="$(fa_read "$rec_path")"
    rec_qid="$(printf '%s' "$rec_line" | cut -d$'\t' -f1)"
    rec_fp="$(printf '%s' "$rec_line" | cut -d$'\t' -f2)"
    rec_q="$(printf '%s' "$rec_line" | cut -d$'\t' -f3)"
    st="$(q_status "${qdir}/${rec_qid}.yaml")"
    rec_status="${st%%|*}"
    rec_ans="${st#*|}"
    if [[ "$rec_status" == "missing" ]]; then
      log "ask: stale pending record for qid=${rec_qid} — question file gone, re-asking"
      rm -f "$rec_path"
    elif [[ "$rec_status" == "answered" && "$rec_fp" == "$fingerprint" && -n "$rec_ans" ]]; then
      # Race closed: the founder answered between a poll deadline and this
      # retry — the retry is not a new question, it is the same one concluded.
      rmdir "$lock_dir" 2>/dev/null || true
      rm -f "$rec_path"
      printf '%s\n' "$rec_ans"
      exit 0
    elif [[ "$rec_status" == "answered" ]]; then
      # Prior question concluded; a genuinely new Gate-1 question is free.
      rm -f "$rec_path"
    elif [[ "$rec_fp" != "$fingerprint" ]]; then
      rmdir "$lock_dir" 2>/dev/null || true
      log_error "ask: a DIFFERENT Gate-1 question is still pending for ${task_id} (qid=${rec_qid}): \"${rec_q}\" — answer it via /leadv2 reply, or run 'leadv2-fork-session.sh ask ${task_id} --cancel-pending' to withdraw it"
      exit 1
    else
      # Same question still pending: poll THAT qid, ask NOTHING. One
      # question, N bounded polls — the fix H2 asked for.
      qid="$rec_qid"
    fi
  fi

  if [[ -z "$qid" ]]; then
    local ask_args=(--no-block)
    [[ -n "$default_option" ]] && ask_args+=(--default-option "$default_option")
    [[ -n "$phase" ]] && ask_args+=(--phase "$phase")
    local opt
    for opt in "${options[@]}"; do ask_args+=(--option "$opt"); done

    # --no-block: the V2 record is written to the control-plane questions/ dir
    # (founder answers via /leadv2 reply — the existing surface, nothing new)
    # and the qid comes back on stdout.
    qid="$(bash "${SCRIPT_DIR}/leadv2-ask.sh" "$task_id" "$question" "${ask_args[@]}")" \
      || { rmdir "$lock_dir" 2>/dev/null || true; log_error "leadv2-ask.sh --no-block failed"; exit 1; }

    # --no-block is contracted to print a QID; leadv2-ask.sh's degrade path
    # prints a chosen LABEL instead when the control-plane write fails.
    # Accepting it would let a failed write manufacture the founder's consent.
    if [[ ! "$qid" =~ ^q-[0-9a-f]{8}$ ]]; then
      rmdir "$lock_dir" 2>/dev/null || true
      log_error "ask degraded to a default without a control-plane record (stdout='${qid}') — refusing to treat a degraded write as an answered gate"
      exit 1
    fi

    fa_write "$rec_path" "$qid" "$fingerprint" "$question"
  fi
  rmdir "$lock_dir" 2>/dev/null || true

  local qfile legacy_answered
  qfile="${qdir}/${qid}.yaml"
  legacy_answered="${LEADV2_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/docs/handoff/${task_id}/questions-async/${qid}-answered.yaml"

  local deadline status_and_answer status answer
  deadline=$(( $(date +%s) + poll_cap ))
  while :; do
    status_and_answer="$(python3 - "$qfile" "$legacy_answered" <<'PYEOF'
import sys, os, yaml

def _load(p):
    try:
        with open(p, encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}

# V2 control-plane record (primary). answer.selected, pre-V2 flat scalar tolerated.
doc = _load(sys.argv[1])
if doc.get("status") == "answered":
    ans = doc.get("answer")
    selected = (ans or {}).get("selected") if isinstance(ans, dict) else ans
    if selected:
        print(f"answered|{selected}")
        sys.exit(0)

# Legacy fallback store (only reached when the control-plane write degraded).
leg = _load(sys.argv[2])
if leg.get("chosen"):
    print(f"answered|{leg['chosen']}")
    sys.exit(0)

print("pending|")
PYEOF
)" || status_and_answer="pending|"
    status="${status_and_answer%%|*}"
    answer="${status_and_answer#*|}"
    if [[ "$status" == "answered" && -n "$answer" ]]; then
      # Answered: the record's job is done — the next genuine Gate-1 question
      # in this task starts from a clean slate.
      rm -f "$rec_path"
      printf '%s\n' "$answer"
      exit 0
    fi
    [[ "$(date +%s)" -lt "$deadline" ]] || break
    sleep "${LEADV2_ASK_POLL_INTERVAL:-3}"
  done

  # Keep the record: the next invocation must resume polling THIS question.
  log "ask: qid=${qid} still pending after ${poll_cap}s — exit 3 (gate NOT passed), re-invoke to resume polling THIS question"
  exit 3
}

# ── commit (H3: lane-scoped Phase 6 commit) ────────────────────────────────
cmd_commit() {
  local task_id="${1:?commit: <task-id> required}"
  shift

  local msg="" mode="" paths=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m)     msg="$2"; shift 2 ;;
      --all)  mode="all"; shift ;;
      --paths) mode="paths"; shift
               while [[ $# -gt 0 && "$1" != --* ]]; do paths+=("$1"); shift; done ;;
      *) log_error "commit: unknown arg: $1"; usage ;;
    esac
  done
  [[ -n "$msg" ]] || { log_error "commit: -m <message> required"; usage; }
  [[ "$mode" == "all" || ${#paths[@]} -ge 1 ]] \
    || { log_error "commit: --all or --paths <p> … required (a lane commit must never sweep the shared index)"; usage; }

  local project_root
  project_root="$(resolve_project_root)" || { log_error "cannot resolve project root"; exit 1; }
  export LEADV2_PROJECT_ROOT="$project_root"

  local lane_root
  lane_root="$(LEADV2_PROJECT_ROOT="$project_root" bash "${SCRIPT_DIR}/leadv2-lane-worktree.sh" path-of "$task_id")"
  if [[ -z "$lane_root" || ! -d "$lane_root" ]]; then
    log_error "commit: no lane worktree for ${task_id} — nothing legitimate to commit into"
    exit 1
  fi
  # Same predicate that gates spawn gates the commit: a lane that lost its
  # registration between preflight and Phase 6 must not receive one either.
  assert_isolated_lane "$task_id" "$project_root" "$lane_root"
  # Belt-and-braces against a future path-of regression.
  if [[ "$(phys "$lane_root")" == "$(phys "$project_root")" ]]; then
    log_error "commit: resolved lane root IS the project root — refusing"
    exit 1
  fi

  if [[ "$mode" == "all" ]]; then
    git -C "$lane_root" add -A --
  else
    git -C "$lane_root" add -- "${paths[@]}"
  fi
  if git -C "$lane_root" diff --cached --quiet; then
    log "commit: nothing to commit in lane ${task_id} (idempotent Phase 6 retry)"
    exit 0
  fi
  git -C "$lane_root" commit -m "$msg"
}

# ── postflight ──────────────────────────────────────────────────────────────
cmd_postflight() {
  local task_id="${1:?postflight: <task-id> required}"
  shift
  local self_spawn=0 force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --self-spawn) self_spawn=1; shift ;;
      --force)      force=1; shift ;;
      *) log_error "postflight: unknown arg: $1"; usage ;;
    esac
  done

  local project_root
  project_root="$(resolve_project_root)" || { log_error "cannot resolve project root"; exit 1; }
  export LEADV2_PROJECT_ROOT="$project_root"

  local lane_root
  lane_root="$(LEADV2_PROJECT_ROOT="$project_root" bash "${SCRIPT_DIR}/leadv2-lane-worktree.sh" path-of "$task_id")"
  if [[ -z "$lane_root" || ! -d "$lane_root" ]]; then
    log "postflight: no worktree for ${task_id} — nothing to reap (no-op)"
    return 0
  fi

  # preflight's own envelope is lead bookkeeping, not fork work — drop it
  # before the dirty check so an otherwise-clean lane is not refused for
  # carrying its own address label (if the fork committed it, rm is a no-op
  # against the committed copy and git status stays clean either way).
  rm -f "${lane_root}/docs/handoff/${task_id}/fork-lane.env" 2>/dev/null || true

  # Carve-out B guard: a dirty lane means the fork left work behind — removing
  # the worktree would discard it silently. Refuse and leave it on disk.
  local dirty
  dirty="$(git -C "$lane_root" status --porcelain 2>/dev/null || true)"
  if [[ -n "$dirty" && "$force" -eq 0 ]]; then
    log_error "lane ${task_id} has uncommitted/untracked changes — refusing to reap:"
    printf '%s\n' "$dirty" >&2
    log_error "inspect ${lane_root}, commit or land the work, then re-run postflight (or --force)"
    exit 1
  fi

  # Carve-out C — lead-only, BEFORE the reap (Phase 8 ordering): a fork
  # spawning the next session would spawn it inside the lead's session.
  if [[ "$self_spawn" -eq 1 || "${LEADV2_DAEMON:-0}" == "1" ]]; then
    LEADV2_TASK_ID="$task_id" CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}" \
      bash "${SCRIPT_DIR}/leadv2-self-spawn.sh" || log "self-spawn failed (non-fatal to reap)"
  fi

  local cleanup_args=(--name "$task_id")
  [[ "$force" -eq 1 ]] && cleanup_args+=(--force)
  bash "${SCRIPT_DIR}/leadv2-worktree-cleanup.sh" "${cleanup_args[@]}"
}

# ── dispatch ────────────────────────────────────────────────────────────────
[[ $# -ge 1 ]] || usage
op="$1"; shift
case "$op" in
  preflight)  cmd_preflight "$@" ;;
  ask)        cmd_ask "$@" ;;
  commit)     cmd_commit "$@" ;;
  postflight) cmd_postflight "$@" ;;
  *)          log_error "unknown op: ${op}"; usage ;;
esac
