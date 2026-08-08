#!/usr/bin/env bash
# leadv2-link-tree-heal.sh — SessionStart guard against silent plugin link-tree drift.
#
# WHY THIS EXISTS (2026-08-08, persona-engine): the shared script tree
# ~/.claude/leadv2-shared/scripts is a per-file symlink farm pointing at canonical
# ~/Projects/leadv2/plugins/leadv2/scripts. A file ADDED to canonical after the last linking
# pass simply never appears in the tree, and nothing reports it. That day 59 files were missing,
# including lib/leadv2-codex-circuit.sh (so the codex arm could not spawn AT ALL) and
# leadv2-phase-record.sh (so phase recording died with exit 127 in warn mode). The visible
# symptom was a lane that "failed on GLM quota" — a routine refusal that is SUPPOSED to fall
# through to the next arm, except the fallback binary did not exist. Silent drift turns a
# recoverable event into a dead lane, and reads like bad luck.
#
# WHAT IT DOES: for every *.sh under canonical, ensure the same relative path exists in the
# shared tree; create the missing ones as symlinks to canonical. Never overwrites, never
# deletes, never touches a path that already exists — the tree legitimately holds ~196 REAL
# repo-owned files (glm-coder.sh and friends) mixed in with the links, and clobbering one of
# those is the failure mode this script must not become.
set -uo pipefail

CANON="${LEADV2_CANONICAL_SCRIPTS:-$HOME/Projects/leadv2/plugins/leadv2/scripts}"
TREE="${LEADV2_SHARED_SCRIPTS:-$HOME/.claude/leadv2-shared/scripts}"

[ -d "$CANON" ] || exit 0   # no canonical checkout on this machine — nothing to compare against
[ -d "$TREE" ]  || exit 0   # no shared tree — repo may not use the link farm

healed=0
missing_list=""
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  target="$TREE/$rel"
  [ -e "$target" ] && continue          # -e follows links: an existing link OR a real file both count
  mkdir -p "$(dirname "$target")" 2>/dev/null || continue
  if ln -s "$CANON/$rel" "$target" 2>/dev/null; then
    healed=$((healed + 1))
    missing_list="${missing_list}${missing_list:+, }${rel}"
  fi
done < <(cd "$CANON" && find . -type f -name '*.sh' 2>/dev/null | sed 's|^\./||')

[ "$healed" -eq 0 ] && exit 0

# Report loudly. A heal is not routine: it means the tree was broken until this moment, and any
# lane that ran before it may have failed for reasons that no longer apply.
printf 'LINK-TREE-HEAL: linked %d missing plugin script(s) into %s\n' "$healed" "$TREE"
if [ "$healed" -le 12 ]; then
  printf 'LINK-TREE-HEAL: %s\n' "$missing_list"
else
  printf 'LINK-TREE-HEAL: %s, ... (+%d more)\n' \
    "$(printf '%s' "$missing_list" | cut -d, -f1-8)" "$((healed - 8))"
fi
printf 'LINK-TREE-HEAL: a lane that failed to spawn before now may simply have been missing its arm.\n'
exit 0
