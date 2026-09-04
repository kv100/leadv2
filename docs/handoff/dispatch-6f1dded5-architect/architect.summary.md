verdict: REVISE
next_action: escalate_to_founder

Mission premise false for 2 of 3 targets — delete only `leadv2-wiki-index.sh` (173 LOC), not 538.

- `leadv2-wiki-query.sh` LIVE-wired: `~/.claude/settings.json:269` UserPromptSubmit hook, all repos.
- `leadv2-cache-warm.sh` existence required by persona-engine `leadv2-preflight.sh` ×4 (:40,:73,:187,:205).
- All 3 are symlink targets from persona-engine + respiro-ios; `~/.claude/scripts` holds untracked real copies (one-copy drift).
- Test file needs 3 edits, not 1 (:11, :57, :175-182).

Full: architect.full.md
