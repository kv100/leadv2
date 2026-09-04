# M-6 fix round 1 — acceptance criterion 1 FAILS as shipped

Work in the existing worktree `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/cffc2f86`
(branch `worktree-cffc2f86`, on top of commit `355fc9c`). Do not create a new worktree, do not
re-architect what is there — the clustering, immunity rules, archive/restore and apply-gating are
fine and stay.

## What the lead actually ran, and what came back
```
leadv2-memory-gc.sh --memory-dir ~/.claude/projects/-Users-...-persona-engine/memory --cap 100
```
Report:
```
llm: unavailable
current total lines: 149; current entry lines: 141
projected post-GC index size: 149 (cap: 100)
deferred_clusters: 0
## Per-cluster verdicts      <- empty
```
Acceptance criterion 1 requires a projected post-GC size **≤100 with a per-cluster verdict list**.
149 with an empty list is a FAIL. The index is not compacted by one line.

## F1 — the batched LLM call does not exist
`leadv2-memory-index-gc.py:85` returns `"unavailable"` whenever `--verdicts-file` is absent, and
there is no subprocess/API call anywhere in the file. So the single most important thing in the
mission — "ONE batched LLM call per run over ALL clusters returning merge/archive/keep" — was not
built; the tool only emits a request and waits for someone to hand it verdicts.
Worse, `SKILL.md` documents a `--model haiku` flag and states the tool "makes one batched verdict
request". The flag is accepted and ignored. **A documented capability with no implementation is
exactly the lying-green disease** — and it is the disease M-8 exists to kill, so shipping it here
is not acceptable.
Fix: actually make the batched call, one call for all clusters, using a real model invocation.
Keep `--verdicts-file` as an override for tests and offline runs; it must not be the only path.
If the call fails, say so loudly in the report and change nothing — never silently no-op.

## F2 — zero clusters on a 141-entry index
Even before the LLM step the run produced `deferred_clusters: 0` and an empty request, so there
was nothing to send. Either the similarity threshold, the same-section/type constraint, or the
`seen`-fingerprint filter is eliminating every candidate. Diagnose which, and report the honest
number: if this index genuinely has no mergeable clusters at a sane threshold, say that
explicitly rather than tuning the threshold until something appears.

## The bar
Re-run the exact command above and paste the raw report. Criterion 1 is met only when the
projected size is ≤100 **and** the per-cluster verdict list is non-empty. Then run the remaining
three from the original mission (`docs/handoff/M6-MEMORY-GC-BATCHED-VERDICTS-01/mission.md`, in
the persona-engine repo): apply with zero orphan `absorbed_by` pointers, idempotent re-run, and a
byte-exact restore (`diff` empty). Paste raw output for all four.

If a real model call cannot be made from this environment, mark F1 BLOCKED and say why. An honest
BLOCKED is acceptable; a `--verdicts-file` fixture presented as a passing acceptance run is not.

## Return
`PASS|FAIL|BLOCKED` per item, changed paths, commit SHA, raw output of all four acceptance checks.
