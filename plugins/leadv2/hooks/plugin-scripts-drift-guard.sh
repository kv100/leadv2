#!/bin/bash
# .claude/hooks/plugin-scripts-drift-guard.sh — PreToolUse(Bash) hook.
#
# Single-source distribution. The plugin tree is canonical; projects retain
# only their overrides. Plugin-owned scripts in .claude/scripts/ must be
# symlinks, never vendored copies.
#
# Scope: only files under .claude/scripts/ that ALSO exist in canonical
# (plugins/leadv2/scripts/, .sh|.py only — mirrors leadv2-drift-guard.sh's
# comparison scope). A repo-local script with no canonical counterpart is not
# vendored and is never blocked here.
#
# Checks the STAGED (index) mode, not the working-tree file, so a real copy is
# rejected at the moment it would be committed. This file also exports the
# shared classifier used by the SessionStart warning hook.
#
# Bypass: `git commit --no-verify` (honored, same convention as the sibling
# pre-commit-python-lint / pre-commit-pnpm-build hooks in this dir).

plugin_script_classify() { # <repo-root> <relative-path> <staged|filesystem> -> NATIVE|LINKED|REGRESSION|DRIFT
  local repo_root="$1" relpath="$2" source="$3" canonical_root canonical_scripts canon_file mode sibling
  canonical_root="${LEADV2_CANONICAL_ROOT:-$HOME/Projects/leadv2}"
  canonical_scripts="${canonical_root}/plugins/leadv2/scripts"
  canon_file="${canonical_scripts}/${relpath}"
  # Installed dependencies are not plugin-owned source. Both trees carry the same
  # node_modules from the same lockfile, so every vendored .sh in there matched
  # canonical and reported as a REGRESSION — 10 false positives that drowned the
  # real ones on 2026-07-29.
  [[ "$relpath" == node_modules/* || "$relpath" == */node_modules/* ]] && { printf 'NATIVE\n'; return; }
  [[ -f "$canon_file" ]] || { printf 'NATIVE\n'; return; }
  if [[ "$source" == staged ]]; then
    mode="$(git -C "$repo_root" ls-files -s -- ".claude/scripts/${relpath}" 2>/dev/null | awk 'NR==1 {print $1}')"
    [[ "$mode" == 120000 ]] && { printf 'LINKED\n'; return; }
  else
    [[ -L "${repo_root}/.claude/scripts/${relpath}" ]] && { printf 'LINKED\n'; return; }
  fi
  sibling="$(find "${repo_root}/.claude/scripts" -type l -name '*.sh' -o -type l -name '*.py' 2>/dev/null | head -1)"
  [[ -n "$sibling" ]] && printf 'REGRESSION\n' || printf 'DRIFT\n'
}

plugin_script_guard_main() {
  local input cmd repo_root canonical_scripts staged fail blocked f relpath classification
  input=$(cat)
  cmd=$(echo "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)
  echo "$cmd" | grep -qE '(^|&&|;| )git commit' || return 0
  echo "$cmd" | grep -qE -- '--no-verify|(^|\s)-n(\s|$)|(^|\s)-[a-zA-Z]*n([a-zA-Z]|\s|$)' && return 0
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  [[ -n "$repo_root" ]] || return 0
  canonical_scripts="${LEADV2_CANONICAL_ROOT:-$HOME/Projects/leadv2}/plugins/leadv2/scripts"
  [[ -d "$canonical_scripts" ]] || return 0
  # ACMRT, not ACMR: a symlink-to-real-file conversion staged in the index is
  # recorded by git as T (typechange), never M. ACMR alone let that exact
  # scenario walk through the guard with rc=0 (round-1 review finding,
  # DRIFT-GUARDS-TO-CANON-01 fix-round 1) — the guard's own reason for
  # existing is the case ACMR silently excluded.
  staged=$(git -C "$repo_root" diff --cached --name-only --diff-filter=ACMRT -- '.claude/scripts/*.sh' '.claude/scripts/*.py' 2>/dev/null || true)
  [[ -n "$staged" ]] || return 0
  fail=0; blocked=""
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    relpath="${f#.claude/scripts/}"
    classification="$(plugin_script_classify "$repo_root" "$relpath" staged)"
    case "$classification" in
      REGRESSION|DRIFT)
        fail=1
        blocked="${blocked}  - ${f} (${classification}; canonical: plugins/leadv2/scripts/${relpath})\n"
        ;;
    esac
  done <<< "$staged"
  [[ "$fail" == 1 ]] || return 0
  cat >&2 <<EOF

❌ plugin-scripts-drift-guard blocked: staged real .claude/scripts/ file(s)
   replace plugin-owned symlinks:

$(printf '%b' "$blocked")
   Single-source rule: land intended script changes in canonical, then restore
   the project's symlink with leadv2-scripts-symlink-plan.sh. Never commit a
   real plugin-owned copy here.
   Bypass: git commit --no-verify (honored, use only for a deliberate
   emergency hotfix you will immediately upstream).

EOF
  return 2
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  plugin_script_guard_main
fi
