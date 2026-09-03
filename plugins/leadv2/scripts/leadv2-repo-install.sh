#!/usr/bin/env bash
# leadv2-repo-install.sh — idempotent adoption of a repo into /leadv2.
#
# WHY THIS EXISTS (2026-08-25, founder: "каждый раз как сетапим новый репо вот эта
# проблема"): plugin enablement is only HALF the install. The plugin is user-level,
# so its command and skills appear in ANY project — but five repo-local things are
# not auto-created, and each fails silently and differently:
#   1. .claude/scripts/       per-file symlink farm to canonical (hooks and repo
#                             tooling call ${CLAUDE_PROJECT_DIR}/.claude/scripts/*)
#   2. .claude/agents/        shared architect / critic / security-auditor
#   3. .claude/settings.json  env block (LEADV2_MAIN_MODEL, PULSE_MODE, ...) —
#                             without it the lead runs the wrong model and the
#                             pulse never beats
#   4. state dir              ~/.claude/leadv2-state/<slug>/ with .repo-root and
#                             active.yaml. A MISSING active.yaml is the silent
#                             killer: leadv2-status-projects.sh drops the repo
#                             from the registry entirely, so cross-repo status,
#                             the SwiftBar plugin and lane reconciliation all
#                             behave as if the repo does not exist. `platform`
#                             hit exactly this — docs/leadv2/active.yaml was a
#                             symlink to a file nobody ever created.
#   5. docs/leadv2/{,tasks/}  journals, open-threads, per-task dirs
#
# It NEVER creates a real copy of a plugin-owned file (one-copy rule): every
# script and agent lands as a symlink to canonical. It never overwrites an
# existing path, and it only ADDS missing env keys — a repo that deliberately
# pins LEADV2_MAIN_MODEL keeps its value.
#
# Stack overrides (.claude/leadv2-overrides/stack.yaml) are NOT guessed here —
# that is the leadv2-init skill's job (it asks the founder when detection is
# ambiguous). This script only reports whether they are present.
#
# Normally you never type this: the /leadv2 command runs it (--quiet) as step 0,
# so a fresh repo adopts itself the first time the founder types /leadv2.
#
# Usage:
#   leadv2-repo-install.sh [--check|--check-all] [--quiet] [repo-root]
#     (no flag)  install/heal, print a per-item table
#     --check    report only, write nothing; exit 1 if anything is missing
#     --check-all  audit EVERY adopted repo (walks ~/.claude/leadv2-state/*/
#                  .repo-root): one command to answer "is every project fine?"
#     --quiet    print only when something actually changed
#
# Exit: 0 installed/complete · 1 --check found gaps or a gate-unfixable repo ·
#       2 bad repo root
set -uo pipefail

CANON="${LEADV2_CANONICAL_SCRIPTS:-$HOME/Projects/leadv2/plugins/leadv2/scripts}"
AGENTS_SRC="${LEADV2_SHARED_AGENTS:-$HOME/.claude/agents-shared}"
STATE_BASE="${LEADV2_STATE_BASE:-$HOME/.claude/leadv2-state}"
PLUGIN_ROOT_DEFAULT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/local/leadv2/plugins/leadv2}"
# LEAD-IS-OPUS-THINK-IS-FABLE-01 (2026-09-03, founder order): the lead's own
# main model and the think-role model are two SEPARATE axes. FABLE-THINK-TIER-01
# R4 had collapsed them — LEADV2_MAIN_MODEL was written FROM the think resolver,
# so every freshly-adopted repo got a lead running on Fable instead of Opus.
# THINK_MODEL_RESOLVED below still feeds ONLY LEADV2_THINK_MODEL (architect,
# plan synthesis, judge — fable by default). LEADV2_MAIN_MODEL gets its own
# independent default (opus) via MAIN_MODEL_DEFAULT, never derived from this.
THINK_MODEL_RESOLVED="$(bash "${CANON}/lib/leadv2-think-model.sh" 2>/dev/null || true)"
THINK_MODEL_RESOLVED="${THINK_MODEL_RESOLVED:-fable}"
MAIN_MODEL_DEFAULT="${LEADV2_MAIN_MODEL_DEFAULT:-opus}"

CHECK=0; QUIET=0; CHECK_ALL=0; REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    --check-all) CHECK_ALL=1 ;;
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) REPO="$1" ;;
  esac
  shift
done

[ -n "$REPO" ] || REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# ---- 0. fleet audit: every adopted repo at once ------------------------------
# ADOPTION-GUARANTEES-A-PASSABLE-GATE-01: the founder answers "is every project
# fine?" with one command, not by opening seven repos. The registry of adopted
# repos IS the state dir (each adoption writes .repo-root).
if [ "$CHECK_ALL" -eq 1 ]; then
  rc=0; seen=0
  for root_file in "$STATE_BASE"/*/.repo-root; do
    [ -e "$root_file" ] || break
    audit_repo="$(cat "$root_file" 2>/dev/null)"
    [ -d "$audit_repo" ] || { printf '[ADOPTED-BROKEN] %s (missing dir)\n' "$root_file"; rc=1; continue; }
    seen=$((seen+1))
    if bash "${BASH_SOURCE[0]}" --check "$audit_repo"; then
      printf '[ADOPTED-OK] %s\n' "$audit_repo"
    else
      printf '[ADOPTED-BROKEN] %s\n' "$audit_repo"; rc=1
    fi
  done
  if [ "$seen" -eq 0 ]; then
    echo "[repo-install] no adopted repos under ${STATE_BASE}" >&2
    exit 1
  fi
  exit "$rc"
fi

[ -d "$REPO" ] || { echo "[repo-install] ERROR: not a directory: $REPO" >&2; exit 2; }
REPO="$(cd "$REPO" && pwd)"
SLUG="$(basename "$REPO")"
STATE="${STATE_BASE}/${SLUG}"

BUF=""; changed=0; gaps=0; gate_unfixable=0
say() { BUF="${BUF}$1"$'\n'; }
row() { say "$(printf '  %-24s %s' "$1" "$2")"; }
flush() {
  # --quiet suppresses the table when the repo was already complete; a heal is
  # never silent (a repo that was broken until this second is not routine), and
  # an UNFIXABLE repo is never silent either — it must not look adopted.
  if [ "$QUIET" -eq 1 ] && [ "$changed" -eq 0 ] && [ "$CHECK" -eq 0 ] && [ "$gate_unfixable" -eq 0 ]; then return 0; fi
  printf '%s' "$BUF"
}

say "leadv2 repo install — ${SLUG}  (${REPO})"

# The link SET is derived FROM canonical, never hardcoded — but scoped to what a
# repo actually calls: top-level executables plus lib/. node_modules/ (vendored
# playwright, thousands of files) and tests/ (canonical runs its own suite; a repo
# does not need per-test links) are pruned deliberately.
canon_files() {
  cd "$CANON" 2>/dev/null || return 0
  find . \( -name node_modules -o -name tests -o -name fixtures \) -prune -o \
       -type f \( -name '*.sh' -o -name '*.py' -o -name '*.js' -o -name '*.mjs' \) -print 2>/dev/null \
    | sed 's|^\./||'
}

# ---- 1. .claude/scripts per-file symlink farm -------------------------------
missing_scripts=0
if [ -d "$CANON" ]; then
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [ -e "${REPO}/.claude/scripts/${rel}" ] || missing_scripts=$((missing_scripts+1))
  done < <(canon_files)
fi
if [ ! -d "$CANON" ]; then
  row ".claude/scripts" "SKIPPED — no canonical checkout at ${CANON}"
elif [ "$missing_scripts" -eq 0 ]; then
  row ".claude/scripts" "ok"
elif [ "$CHECK" -eq 1 ]; then
  row ".claude/scripts" "MISSING — ${missing_scripts} link(s)"; gaps=$((gaps+1))
else
  mkdir -p "${REPO}/.claude/scripts"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    t="${REPO}/.claude/scripts/${rel}"
    [ -e "$t" ] && continue
    mkdir -p "$(dirname "$t")" 2>/dev/null || continue
    ln -s "${CANON}/${rel}" "$t" 2>/dev/null || true
  done < <(canon_files)
  row ".claude/scripts" "linked ${missing_scripts}"; changed=$((changed+1))
fi

# ---- 1b. .claude/scripts drift — a real file sitting where a symlink belongs
# DRIFT-GUARDS-TO-CANON-01: "linked N" / "ok" above only counts PRESENCE — a
# vendored real copy that has since drifted behind canonical still counts as
# present and reported clean. Reuse plugin_script_classify from the canonical
# drift-guard hook (never a second implementation of the same classification)
# to catch that case and fail --check loudly, naming each file with its line
# delta. Never auto-heals: a drifted copy may hold unmerged work that has to
# go UP into canonical first (one-copy rule, leadv2-repo-install.sh header).
drifted_scripts=0
drift_report=""
GUARD_LIB="$(dirname "$CANON")/hooks/plugin-scripts-drift-guard.sh"
if [ -d "$CANON" ] && [ -f "$GUARD_LIB" ]; then
  # shellcheck source=/dev/null
  . "$GUARD_LIB"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    case "$rel" in *.sh|*.py) ;; *) continue ;; esac
    t="${REPO}/.claude/scripts/${rel}"
    [ -e "$t" ] || continue
    classification="$(plugin_script_classify "$REPO" "$rel" filesystem)"
    case "$classification" in
      REGRESSION|DRIFT)
        drifted_scripts=$((drifted_scripts+1))
        local_lines="$(wc -l < "$t" 2>/dev/null | tr -d ' ')"
        canon_lines="$(wc -l < "${CANON}/${rel}" 2>/dev/null | tr -d ' ')"
        case "${local_lines:-}" in ''|*[!0-9]*) local_lines=0 ;; esac
        case "${canon_lines:-}" in ''|*[!0-9]*) canon_lines=0 ;; esac
        delta=$((canon_lines - local_lines))
        drift_report="${drift_report}  - .claude/scripts/${rel} (${classification}; ${delta} line(s) behind canonical)\n"
        ;;
    esac
  done < <(canon_files)
fi
if [ "$drifted_scripts" -gt 0 ]; then
  if [ "$CHECK" -eq 1 ]; then
    row ".claude/scripts drift" "DRIFTED — ${drifted_scripts} real copy(ies) where symlink(s) belong"; gaps=$((gaps+1))
  else
    row ".claude/scripts drift" "DRIFTED — ${drifted_scripts} real copy(ies) left untouched (one-copy rule: never auto-overwritten; land in canonical first)"
  fi
  say "$(printf '%b' "$drift_report")"
fi

# ---- 2. shared agents -------------------------------------------------------
missing_agents=0
if [ -d "$AGENTS_SRC" ]; then
  for f in "$AGENTS_SRC"/*.md; do
    [ -e "$f" ] || continue
    [ -e "${REPO}/.claude/agents/$(basename "$f")" ] || missing_agents=$((missing_agents+1))
  done
fi
if [ ! -d "$AGENTS_SRC" ]; then
  row ".claude/agents" "SKIPPED — no ${AGENTS_SRC}"
elif [ "$missing_agents" -eq 0 ]; then
  row ".claude/agents" "ok"
elif [ "$CHECK" -eq 1 ]; then
  row ".claude/agents" "MISSING — ${missing_agents}"; gaps=$((gaps+1))
else
  mkdir -p "${REPO}/.claude/agents"
  for f in "$AGENTS_SRC"/*.md; do
    [ -e "$f" ] || continue
    t="${REPO}/.claude/agents/$(basename "$f")"
    [ -e "$t" ] || ln -s "$f" "$t" 2>/dev/null || true
  done
  row ".claude/agents" "linked ${missing_agents}"; changed=$((changed+1))
fi

# ---- 2b. the bare /leadv2 command ------------------------------------------
# THE actual reason a fresh repo has no /leadv2 (founder screenshot, 2026-08-25):
# the plugin's own command is namespaced (it offers /leadv2-audit, /leadv2-learn
# and friends), while the bare `/leadv2` every repo actually uses comes from a
# PROJECT command file. persona-engine and respiro-ios each carry a real copy —
# and persona-engine's had silently rotted into a months-old fork ("Fable main",
# gpt-5.5, a retired fanout async-question mode, no GLM/Kimi row). platform had
# none at all, so /leadv2 simply did not exist there.
#
# Fix per one-copy rule: link, never copy. An EXISTING real file is left alone
# and reported — respiro-ios's copy is a legitimate iOS-specific fork (Swift
# agents, bot mode) and must not be clobbered; a stale fork is a reconcile
# decision for the founder, never a silent overwrite by this script.
CMD_SRC="${CANON%/scripts}/commands/leadv2.md"
CMD_DST="${REPO}/.claude/commands/leadv2.md"
if [ ! -f "$CMD_SRC" ]; then
  row ".claude/commands/leadv2" "SKIPPED — no canonical command file"
elif [ -L "$CMD_DST" ]; then
  row ".claude/commands/leadv2" "ok  (linked to canonical)"
elif [ -f "$CMD_DST" ]; then
  row ".claude/commands/leadv2" "LOCAL FORK — real file, left untouched (reconcile by hand if stale)"
elif [ "$CHECK" -eq 1 ]; then
  row ".claude/commands/leadv2" "MISSING — no bare /leadv2 in this repo"; gaps=$((gaps+1))
else
  mkdir -p "${REPO}/.claude/commands"
  ln -s "$CMD_SRC" "$CMD_DST" 2>/dev/null || true
  row ".claude/commands/leadv2" "linked to canonical"; changed=$((changed+1))
fi

# ---- 3. docs/leadv2 ---------------------------------------------------------
if [ -d "${REPO}/docs/leadv2/tasks" ]; then
  row "docs/leadv2/tasks" "ok"
elif [ "$CHECK" -eq 1 ]; then
  row "docs/leadv2/tasks" "MISSING"; gaps=$((gaps+1))
else
  mkdir -p "${REPO}/docs/leadv2/tasks"
  row "docs/leadv2/tasks" "created"; changed=$((changed+1))
fi

# ---- 3b. phase-gate artifacts must stay committable -------------------------
# ADOPTION-GUARANTEES-A-PASSABLE-GATE-01 (2026-08-31): the phase gate
# (leadv2-phase-record.sh) and the dispatcher accept only COMMITTED plan and
# gate artifacts — docs/handoff/dispatch-<sig8>/{context.yaml,
# architect-prepass.md,.gate1-passed} plus the lead-authored plan notes
# docs/handoff/<task>/{brief.md,fix-round-N.md}. A lane worktree contains only
# what is committed, so a .gitignore that blankets docs/handoff makes an honest
# gate passage physically impossible and trains the lead to bypass the gate
# (a full day of dispatches did exactly that on 2026-08-31 in a repo with
# `docs/handoff/*/*` ignored).
#
# The check is `git check-ignore` on concrete paths — never a grep of
# .gitignore: only git knows which of layered rules wins, and a negation that
# is present but overridden by a later rule must read as BROKEN, not fixed.
# The fix is additive (append negations, never rewrite a repo's own lines) and
# is re-verified against git; if the paths are STILL ignored (excluded parent
# dir, global excludes layering), the repo must NOT look adopted — fail loudly.
GATE_SAMPLES="docs/handoff/dispatch-1d76cf8a/context.yaml
docs/handoff/dispatch-1d76cf8a/architect-prepass.md
docs/handoff/dispatch-1d76cf8a/.gate1-passed
docs/handoff/some-task/brief.md
docs/handoff/some-task/fix-round-2.md"
GATE_MARKER="# leadv2: phase-gate artifacts must stay committable (leadv2-repo-install.sh)"

gate_ignored() { # rc 0 iff at least one guarded shape is git-ignored
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if git -C "$REPO" check-ignore -q "$p" 2>/dev/null; then return 0; fi
  done <<EOF
${GATE_SAMPLES}
EOF
  return 1
}

if ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  row "phase-gate committable" "SKIPPED — not a git repo"
elif ! gate_ignored; then
  row "phase-gate committable" "ok"
elif [ "$CHECK" -eq 1 ]; then
  row "phase-gate committable" "IGNORED — gate artifacts git-ignored; heal required"; gaps=$((gaps+1))
else
  gate_block="${GATE_MARKER}
!docs/handoff/*/context.yaml
!docs/handoff/*/architect-prepass.md
!docs/handoff/*/.gate1-passed
!docs/handoff/*/brief.md
!docs/handoff/*/fix-round-*.md"
  printf '%s\n' "$gate_block" >> "${REPO}/.gitignore"
  if gate_ignored; then
    # Appended negations did not win — a parent directory is excluded or a
    # higher-precedence ignore source still blocks. Do not leave this looking
    # adopted: report loudly and exit nonzero.
    gate_unfixable=1
    row "phase-gate committable" "UNFIXABLE — still git-ignored after negations (excluded parent dir or global excludes); phase gate UNPASSABLE — resolve the ignore layering by hand"
    gaps=$((gaps+1))
    echo "[repo-install] ERROR: ${SLUG}: docs/handoff gate artifacts remain git-ignored after appending negations — the phase gate is UNPASSABLE in this repo. Inspect .gitignore layering, .git/info/exclude and core.excludesFile by hand." >&2
  else
    row "phase-gate committable" "negations appended to .gitignore"; changed=$((changed+1))
  fi
fi

# ---- 4. control-plane state dir + registry key ------------------------------
# active.yaml must exist as a REAL file under the state dir. A repo-side symlink
# whose target was never created reads as "present" in the repo and still drops
# the repo out of leadv2-status-projects.sh.
state_gap=0
[ -d "$STATE" ] || state_gap=1
[ -s "${STATE}/.repo-root" ] || state_gap=1
[ -f "${STATE}/active.yaml" ] || state_gap=1
if [ "$state_gap" -eq 0 ]; then
  row "control-plane state" "ok  (${STATE})"
elif [ "$CHECK" -eq 1 ]; then
  row "control-plane state" "MISSING  (${STATE})"; gaps=$((gaps+1))
else
  mkdir -p "$STATE"
  [ -s "${STATE}/.repo-root" ] || printf '%s' "$REPO" > "${STATE}/.repo-root"
  [ -f "${STATE}/active.yaml" ] || printf 'sessions: []\n' > "${STATE}/active.yaml"
  row "control-plane state" "created  (${STATE})"; changed=$((changed+1))
fi

# ---- 5. settings.json env ---------------------------------------------------
env_py() {
  LV2_REPO="$REPO" LV2_PR="$PLUGIN_ROOT_DEFAULT" LV2_MODE="$1" \
    LV2_THINK_MODEL="$THINK_MODEL_RESOLVED" LV2_MAIN_MODEL="$MAIN_MODEL_DEFAULT" python3 -c '
import json,os,pathlib
repo=os.environ["LV2_REPO"]; mode=os.environ["LV2_MODE"]
want={
 "ENABLE_TOOL_SEARCH":"auto:50",
 "LEADV2_PULSE_MODE":"1",
 # LEAD-IS-OPUS-THINK-IS-FABLE-01 (2026-09-03): own axis, own default — opus,
 # independent of LV2_THINK_MODEL. Never re-derive this from the think resolver.
 "LEADV2_MAIN_MODEL": os.environ.get("LV2_MAIN_MODEL", "opus"),
 # FABLE-THINK-TIER-01 R5: the think-model kill-switch channel. The four
 # workflows (diverge/learn/diagnose/po-feedback-loop) resolve THINK_MODEL
 # from process.env.LEADV2_THINK_MODEL — the JS sandbox cannot read
 # model-capability.yaml. Writing the resolver answer here makes the
 # unavailable-true fallback reach every session in the installed repo,
 # at the same install-time freshness as the LEADV2_THINK_MODEL axis.
 "LEADV2_THINK_MODEL": os.environ.get("LV2_THINK_MODEL", "fable"),
 "LEADV2_FORCE_OPUS_LEAD":"0",
 "LEADV2_WORKFLOW_ENABLED":"1",
 "LEADV2_WIKI_INJECT":"0",
 "LEADV2_LOOP_DETECT":"1",
 "LEADV2_CORRECTION_DETECT":"1",
 "LEADV2_LOOP_WARN_AT":"3",
 "LEADV2_LOOP_HARD_AT":"5",
 "LEADV2_SCORECARD_ON_CLOSE":"1",
 "LEADV2_PARALLEL_DISPATCH":"1",
 "LEADV2_DISPATCH_ARCHITECT_GATE":"1",
 "MAX_MCP_OUTPUT_TOKENS":"15000",
 "CLAUDE_PLUGIN_ROOT":os.environ["LV2_PR"],
 "LEADV2_PROJECT_ROOT":repo,
}
p=pathlib.Path(repo)/".claude/settings.json"
try:
    d=json.loads(p.read_text()) if p.exists() else {}
except Exception:
    print("-1"); raise SystemExit(0)
env=d.get("env",{})
missing=[k for k in want if k not in env]
if mode=="write" and missing:
    d.setdefault("env",{}).update({k:want[k] for k in missing})
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(json.dumps(d,indent=2,ensure_ascii=False)+"\n")
print(len(missing))
'
}
missing_env="$(env_py check 2>/dev/null || echo -1)"
if [ "${missing_env}" = "-1" ]; then
  row ".claude/settings.json env" "UNREADABLE — settings.json is not valid JSON; fix it by hand"
  gaps=$((gaps+1))
elif [ "${missing_env:-0}" -eq 0 ]; then
  row ".claude/settings.json env" "ok"
elif [ "$CHECK" -eq 1 ]; then
  row ".claude/settings.json env" "MISSING — ${missing_env} key(s)"; gaps=$((gaps+1))
else
  env_py write >/dev/null 2>&1
  row ".claude/settings.json env" "added ${missing_env} key(s)"; changed=$((changed+1))
fi

# ---- 6. stack overrides (reported, never guessed) ---------------------------
if [ -f "${REPO}/.claude/leadv2-overrides/stack.yaml" ]; then
  row "leadv2-overrides" "ok"
else
  row "leadv2-overrides" "ABSENT — leadv2-init will scaffold it (it asks about the stack)"
fi

say ""
if [ "$CHECK" -eq 1 ]; then
  if [ "$gaps" -gt 0 ]; then
    say "INCOMPLETE — ${gaps} item(s). Heal with: bash \"\${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-repo-install.sh\""
    flush; exit 1
  fi
  say "COMPLETE — repo is adopted."
  flush; exit 0
fi
if [ "$changed" -gt 0 ]; then
  say "installed ${changed} item(s)."
  say "NOTE: the env block is read at SESSION START — the model/pulse settings above"
  say "take effect in the NEXT claude session opened from ${REPO}."
else
  say "nothing to do — repo already adopted."
fi
if [ "$gate_unfixable" -eq 1 ]; then
  say "UNFIXABLE — this repo looks adopted but CANNOT pass its phase gate honestly."
  say "Resolve the docs/handoff ignore layering by hand, then re-run this script."
  flush
  exit 1
fi
flush
exit 0
