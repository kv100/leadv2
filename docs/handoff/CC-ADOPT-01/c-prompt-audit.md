# CC-ADOPT-01c — Prompt/mission template audit (manual, no claude-api skill)

Scope: `plugins/leadv2/{skills,docs,commands,templates}`. Grep-first, bounded reads only.

## Findings

- `skills/leadv2-review/ref/workflow-review-reference.md:14` — hardcoded model id
  `"claude-opus-4-8"` for the safety-touched critic branch. Per memory
  `reference_opus5_live_drop_in_for_opus48.md`, opus-5 is the live drop-in replacement for
  opus-4-8. Suggested: `"claude-opus-5"` (or whatever alias the repo's model-routing skill
  resolves "opus" to today — confirm against `docs/model-effort-matrix.md` before editing).
  NOTE: this is a reference/illustrative file, not the executing script
  (`scripts/leadv2-review-run.sh` is canonical per the file's own header) — low urgency but
  still misleading to a reader.

- `commands/leadv2.md:23,29,36,92` + `docs/model-effort-matrix.md:42` — **internal
  contradiction**, not just staleness. `model-effort-matrix.md:42` states "FABLE-RETIRE-01
  2026-07-06: fable sunset, opus absorbs its slots" (Fable retired), while `commands/leadv2.md`
  still routes Heavy-tier planning/architect work to `Fable/xhigh` in four places (lines 23, 29,
  92) as if Fable is live. Per task brief, Fable 5 is available again (5-family) but the lead
  default stays Opus — so leadv2.md's Fable routing may be closer to current truth than the
  matrix's "sunset" framing, or both may be stale relative to today's actual routing decision.
  Needs a founder/architect call on which doc is authoritative before either is edited.

- `commands/leadv2.md:239` — heading "Post-Fable Opus-lead compensations" assumes Fable is
  gone; contradicts the same file's own Fable/xhigh routing rows above it (lines 23-92). Same
  root cause as the item above — one doc, self-inconsistent.

- `commands/leadv2.md:36` — Codex pinned as `GPT-5.6`. Task brief states current Codex =
  gpt-5.5. Flag for confirmation (could be the brief that's stale, not the doc) — do not
  overwrite without checking `docs/model-effort-matrix.md` or a live `codex --version`/session
  check first.

## Not found (checked, clean)
- No hits for `claude-3`, `sonnet-3`, `glm-5.1`, `haiku-3`, `gpt-5.[0-3]` anywhere in scope.
- No hits for generic-assistant boilerplate patterns ("you are a helpful AI assistant", "think
  step by step", "XML tags are preferred", stale `max_tokens 4096`) anywhere in scope.
- `docs/phases.md` and `skills/leadv2-diverge/PHASES.md` — no stale model-id patterns.
- No `*mission*.md` files matched the stale-model grep.

DELIVERABLE_COMPLETE
