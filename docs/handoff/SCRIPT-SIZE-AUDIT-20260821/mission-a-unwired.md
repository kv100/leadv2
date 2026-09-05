# Mission A — retire 3 statically-unwired scripts (538 lines)

Repo: ~/Projects/leadv2 (the plugin source). Source of truth: this repo only.
Basis: docs/handoff/SCRIPT-SIZE-AUDIT-20260821/codex-findings.md §Q5 (Codex audit,
measured 2026-08-21). Premise re-verified 2026-08-23: all three files still exist,
still have zero production callers.

## Targets
- plugins/leadv2/scripts/leadv2-cache-warm.sh (193 lines) — self-declared deprecated
  shim, disabled unless LEADV2_LEGACY_API_CACHE_WARM=1. Only external reference:
  plugins/leadv2/scripts/tests/test-hook-token-mode-isolation.sh:175-182 (tests the
  disabled no-op).
- plugins/leadv2/scripts/leadv2-wiki-index.sh (173 lines)
- plugins/leadv2/scripts/leadv2-wiki-query.sh (172 lines)
  Both claim PostToolUse / UserPromptSubmit wiring in their headers, but
  plugins/leadv2/hooks/hooks.json contains neither (UserPromptSubmit manifest is
  hooks.json:86-133). Arrived in d709d65 (2026-06-16) already unwired.

## Do
1. Re-run the callsite census yourself before deleting anything. Search the WHOLE repo
   (including hooks.json, docs, marketplace manifests, the plugin-sync curated lists in
   leadv2-plugin-sync.sh) and the .claude/ trees of ~/Projects/persona-engine and
   ~/Projects/respiro-ios. Record the exact commands + output in the deliverable.
   If ANY live caller turns up, STOP and report it — do not delete.
2. Deletion, not deprecation-notice theatre. The audit's "versioned deprecation" is
   satisfied by: git rm + a one-line entry in
   docs/handoff/SCRIPT-SIZE-AUDIT-20260821/removed-scripts.md recording path, LOC, last
   commit touching it, and the census output that proved zero callers — so a revert is
   one `git revert`.
3. leadv2-cache-warm.sh: also remove or repoint the test that asserts its no-op
   behaviour (tests/test-hook-token-mode-isolation.sh:175-182). Do not leave a test
   referencing a deleted file. If that test also covers unrelated behaviour, keep the
   file and delete only the cache-warm block.
4. Grep the plugin-sync curated file lists (leadv2-plugin-sync.sh) for these three names
   and remove them if present.
5. Run the plugin test suite (plugins/leadv2/scripts/tests/) and report pass/fail counts
   verbatim. `bash -n` every file you touched.

## Off-limits
- Do not touch any other script. No "while I was there" refactors.
- Do not touch the semantic-recall, eval-harness, or memory-backup mechanisms — the
  audit explicitly says default-off is NOT reachability evidence and those have live
  callers.
- Do not create real copies of plugin files in any project repo.

## Deliverable
docs/handoff/SCRIPT-SIZE-AUDIT-20260821/mission-a-report.md — census commands + output,
files deleted with LOC, test results verbatim, git diff --stat. End with
DELIVERABLE_COMPLETE.
