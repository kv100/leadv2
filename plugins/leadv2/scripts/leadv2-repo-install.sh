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
#   leadv2-repo-install.sh [--check] [--quiet] [repo-root]
#     (no flag)  install/heal, print a per-item table
#     --check    report only, write nothing; exit 1 if anything is missing
#     --quiet    print only when something actually changed
#
# Exit: 0 installed/complete · 1 --check found gaps · 2 bad repo root
set -uo pipefail

CANON="${LEADV2_CANONICAL_SCRIPTS:-$HOME/Projects/leadv2/plugins/leadv2/scripts}"
AGENTS_SRC="${LEADV2_SHARED_AGENTS:-$HOME/.claude/agents-shared}"
STATE_BASE="${LEADV2_STATE_BASE:-$HOME/.claude/leadv2-state}"
PLUGIN_ROOT_DEFAULT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/local/leadv2/plugins/leadv2}"

CHECK=0; QUIET=0; REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) REPO="$1" ;;
  esac
  shift
done

[ -n "$REPO" ] || REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
[ -d "$REPO" ] || { echo "[repo-install] ERROR: not a directory: $REPO" >&2; exit 2; }
REPO="$(cd "$REPO" && pwd)"
SLUG="$(basename "$REPO")"
STATE="${STATE_BASE}/${SLUG}"

BUF=""; changed=0; gaps=0
say() { BUF="${BUF}$1"$'\n'; }
row() { say "$(printf '  %-24s %s' "$1" "$2")"; }
flush() {
  # --quiet suppresses the table when the repo was already complete; a heal is
  # never silent (a repo that was broken until this second is not routine).
  if [ "$QUIET" -eq 1 ] && [ "$changed" -eq 0 ] && [ "$CHECK" -eq 0 ]; then return 0; fi
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

# ---- 3. docs/leadv2 ---------------------------------------------------------
if [ -d "${REPO}/docs/leadv2/tasks" ]; then
  row "docs/leadv2/tasks" "ok"
elif [ "$CHECK" -eq 1 ]; then
  row "docs/leadv2/tasks" "MISSING"; gaps=$((gaps+1))
else
  mkdir -p "${REPO}/docs/leadv2/tasks"
  row "docs/leadv2/tasks" "created"; changed=$((changed+1))
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
  LV2_REPO="$REPO" LV2_PR="$PLUGIN_ROOT_DEFAULT" LV2_MODE="$1" python3 -c '
import json,os,pathlib
repo=os.environ["LV2_REPO"]; mode=os.environ["LV2_MODE"]
want={
 "ENABLE_TOOL_SEARCH":"auto:50",
 "LEADV2_PULSE_MODE":"1",
 "LEADV2_MAIN_MODEL":"opus",
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
flush
exit 0
