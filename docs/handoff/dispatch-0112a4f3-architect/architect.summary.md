verdict: APPROVE
next_action: continue

Codex 0.145.0-alpha.1 DOES support blocking PreToolUse hooks — lv2guard becomes enforced, not prose.

- Binary schema: PreToolUse may emit ONLY `permissionDecision:deny` + non-empty reason; `allow`/`ask`/`approve` are runtime-rejected. Allow = empty stdout.
- Manifest is `.codex-plugin/plugin.json`, index `.agents/plugins/marketplace.json` — mission paths were one level off.
- Probe first: the bypass alias may skip hooks; `test-codex-install.sh` has no `codex` stub and would mutate the real host.

Full: architect.full.md
