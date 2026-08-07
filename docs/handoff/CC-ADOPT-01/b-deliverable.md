# CC-ADOPT-01b — nested-spawn depth truth update + platform env pin

Executed by the lead directly (comment/markdown-only edits; Codex quota-dead).

Platform truth adopted: CC default spawn depth = 3 (v2.1.219), 200-agent session
cap removed (v2.1.224), 20 concurrent (v2.1.217). leadv2 policy stays the
governing limit (max_depth: 1, max_nested_per_task: 3).

Changes:
- `plugins/leadv2/config/nested-spawn-policy.yaml` — header comment block:
  PLATFORM TRUTH paragraph added; values untouched.
- `plugins/leadv2/skills/leadv2-subagent-protocol/NESTED-SPAWNS.md` — §2.5
  rewritten: removed the stale "5-LEVEL HARD CAP (2.1.172)" claim; states
  platform defaults vs governing leadv2 policy vs env backstop.
- User settings `~/.claude/settings.json` — pinned
  `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=2` (platform backstop one level below
  what a hook bypass could otherwise reach). Done by lead, config change.
- NOT touched: `plugins/leadv2/hooks/leadv2-routing-guard.sh` — its header
  comments (lines 15-30) describe the hook's own contract, not platform
  defaults; and .sh files are lead-banned. If a doc-truth pass on that header
  is wanted, route it to a code worker when quota returns.

Also in this batch (C-audit fixes, docs/handoff/CC-ADOPT-01/c-prompt-audit.md):
- `skills/leadv2-review/ref/workflow-review-reference.md:14` —
  claude-opus-4-8 → claude-opus-5 (reference doc; executing script unaffected).
- `docs/model-effort-matrix.md:42` — FABLE-RETIRE-01 scoped to Fable 4.x;
  Fable 5 live since 2026-08; per-repo `ref/leadv2-main-model.yaml` decides.
- `commands/leadv2.md:241` heading — marked historical, same reconciliation.
- Codex "GPT-5.6" claim verified LIVE correct (~/.codex/config.toml
  model=gpt-5.6-sol) — audit brief's gpt-5.5 was the stale side, no edit.

DELIVERABLE_COMPLETE
