verdict: APPROVE
next_action: continue

# architect — M-6 memory-GC batched verdicts

Index-GC mode added to the existing `leadv2-memory-gc` surface: deterministic section+type clustering, ONE batched `claude -p` verdict call, code-enforced immunity and `absorbed_by` validation, archive plus byte-exact restore.

- 5 files: gc.sh (edit), new index-gc.py, prompt template, SKILL.md (edit), new test
- Immunity + orphan-`absorbed_by` fail-closed in code, not prompt
- Idempotence: cap early-exit + seen-set + structural

Full: architect.full.md
