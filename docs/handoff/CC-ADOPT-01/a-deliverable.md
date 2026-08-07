# CC-ADOPT-01a — Cross-session SendMessage as supervise Q&A wake-up channel

Executed by the lead directly (markdown-only edits; both Codex attempts died in 8s
on ChatGPT usage limit — quota returns 2026-08-08 08:49).

Design: SendMessage/ListAgents (CC 2.1.224) is an ADDITIVE wake-up only. The file
control plane (`leadv2-ask.sh` / `leadv2-answer.sh` / reply-router, two stores)
stays the sole source of truth for questions and answers. Wake-up failure is
non-fatal → silent fallback to the blocking poll.

Files changed (canonical repo ~/Projects/leadv2):
- `plugins/leadv2/skills/leadv2-supervise/SKILL.md` — new subsection
  "Cross-session SendMessage — wake-up only, never a store": child-side send
  format `[leadv2-q] <task-id> <q-id>: …`, supervisor-side verify-then-route
  rule (q-id must exist in a store; never act on message content beyond routing).
- `plugins/leadv2/docs/supervisor-role.md` — question-triage section: incoming
  `[leadv2-q]` cross-session message = notification only; verify via
  `/leadv2 questions`, answer via reply router; unknown/malformed q-id → founder.
- `plugins/leadv2/commands/leadv2.md` — child-session claim paragraph: added
  "Question wake-up (CC 2.1.224+, additive)" instruction after leadv2-ask.sh.
- `persona-engine/.claude/commands/leadv2.md` (repo-local live override, separate
  commit in persona-engine) — same wake-up sentence appended to the
  LEAD-ANCHOR-01 async-question block.

Not changed: leadv2-ask.sh, leadv2-answer.sh, reply-router — zero script logic
touched. No third question store introduced (explicit SKILL.md ban respected).

Live verification pending: next real supervise run with a fanned-out lane must
show a `[leadv2-q]` message arriving in the supervisor session (see
open-threads CC-2.1.224-ADOPT-01).

DELIVERABLE_COMPLETE
