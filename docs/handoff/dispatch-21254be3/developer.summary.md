verdict: APPROVE
next_action: review_round_2

Both drift guards lifted into canon, wired, and proven with a live-fire mktemp harness; persona-engine's symlink conversion deliberately deferred.

- plugin-scripts-drift-guard.sh (git-commit blocker) + plugin-scripts-drift-session-warn.sh (SessionStart report) now in plugins/leadv2/hooks/, wired into leadv2-bash-pre-dispatch.sh's MANIFEST and hooks.json's SessionStart list.
- leadv2-repo-install.sh --check and leadv2-link-tree-heal.sh both now detect/report a real file sitting where a symlink belongs, reusing plugin_script_classify (no reimplementation).
- Not done: persona-engine's real copies are NOT symlinked yet (would dangle pre-merge, breaking live sessions) — post-merge follow-up. Cache not synced — hook needs leadv2-plugin-cache-sync.sh + session restart to load anywhere.

Full: full.md
