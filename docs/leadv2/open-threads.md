## Drifted `.claude/scripts/tests/` tree — 100-file stale fork (2026-08-03)

**Source:** GATE-WRONG-ROOT-FALSE-DEAD-01 (C3 note)
**State:** open — hygiene cleanup, not a blocker

The `.claude/scripts/tests/` directory is a 100-file REAL COPY (not symlinks) of
`plugins/leadv2/scripts/tests/`. It drifted 5+ days behind canonical as of
2026-07-29, missing 11 suites including every suite recent lanes registered.

GATE-WRONG-ROOT-FALSE-DEAD-01 C3 makes the gate stop READING this tree (plugin-preferred
always-on path via `plugins/leadv2/` probe). But the files remain on disk and may still
be referenced by other tooling. Full de-duplication/delete is a separate task with its own
blast radius assessment.

**Action:** Audit what still references `.claude/scripts/tests/` paths; convert to symlinks
or delete. Do NOT leave as copies (global CLAUDE.md shared-trees policy).

## Captured asks (auto)
- [ ] 2026-08-04T16:17:46Z [s:19465815] — NOTE: the Agent/Task/sub-agent tool is disabled for this session. Do all work directly in this one context -- never attempt to spawn a sub-a
