verdict: APPROVE
next_action: continue

Mechanism-closed design for `plugins/leadv2/codex-lead/` (guard, 5 prompts, status line, installer, tests, 2 doc edits).

- Census mismatch, not a halt: canonical yaml has 9 rules, only 7 catastrophic; reset/clean/stash are SOFT. Design keeps the yaml's tiering, adds 3 new rules in a codex-lead extras file.
- lv2guard is advisory — the sandbox flag is the real floor; optional PATH shim ships off by default.
- Fail-CLOSED inverts the canonical hook, deliberately; `LEADV2_DENY_FLOOR=0` not honoured.

Full: architect.full.md
