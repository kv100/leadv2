# M-6 fix round 1 result

Overall: **FAIL** — F1 is implemented and a real model call works, but the live
index has zero candidate pairs at the configured similarity, so acceptance 1
cannot honestly reach the 100-line cap. No `--verdicts-file` was used for any
acceptance check.

## Defects

- **F1 PASS** — `leadv2-memory-index-gc.py` now makes one `claude` subprocess
  invocation containing all clusters when `--verdicts-file` is absent. `--model`
  is forwarded. Missing CLI, timeout, non-zero exit, malformed JSON, duplicate
  IDs, or incomplete IDs produce `llm: error`, exit 7, and stop before index or
  archive changes. The shell wrapper delegates to this implementation instead
  of maintaining a second model-call path.
- **F2 PASS (diagnosis), acceptance remains FAIL** — the seen state contains zero
  fingerprints. At `--sim 0.34`, 0 of 2,239 same-section/type pairs qualify, and
  0 of all 9,870 pairs qualify even if the section/type constraint is removed.
  The maximum score is 0.267647. Therefore the similarity threshold eliminates
  every candidate; neither the constraint nor the seen filter does. Lowering the
  threshold produces related-but-not-redundant groups and was not used to force a
  green result.

## Acceptance status

1. **FAIL** — projected size 149 > 100 and the per-cluster list is empty.
2. **FAIL** — apply correctly changed no index/archive data because there was no
   verdict plan; the index remains 149 lines and no GC manifest exists on which
   to run the orphan query.
3. **FAIL** — the rerun is operationally a no-op, but the required precondition
   (an already-compacted index <=100) was never achieved; it remains 149 lines.
4. **BLOCKED** — no `gc-*` run directory was created, so there is nothing to
   restore and no restored index to diff.

## Changed paths

- `plugins/leadv2/scripts/leadv2-memory-index-gc.py`
- `plugins/leadv2/scripts/leadv2-memory-gc.sh`
- `plugins/leadv2/skills/leadv2-memory-gc/SKILL.md`
- `plugins/leadv2/tests/test-memory-index-gc.sh`
- `FIXROUND-RESULT.md` (this evidence file, written after the implementation commit)

Implementation commit: `7e5afe180e650f1f33a13e0804b8c92829b3349f`

The repository script is mode 0644 and no `leadv2-memory-gc.sh` command is on this
shell's PATH, so the same repository implementation was invoked explicitly with
`bash` below.

## Real model-call evidence (not a verdict fixture)

Command: direct call to `call_model(plan, "haiku")` with one synthetic duplicate
cluster, `LEADV2_MEMGC_TIMEOUT=90`.

```text
{
  "c01": {
    "cluster_id": "c01",
    "into": "alpha",
    "members": [
      {
        "action": "keep",
        "slug": "alpha"
      },
      {
        "absorbed_by": "alpha",
        "action": "absorb",
        "merged_hook": "Alpha is deployed and live",
        "slug": "alpha_copy"
      }
    ],
    "rationale": "Identical semantic content (Alpha production deployment state). alpha_copy is redundant duplicate. Merge hooks convey unified status.",
    "verdict": "merge"
  }
}
EXIT_CODE=0
```

## Raw acceptance output

### 1. Live dry-run

Command:

```text
bash plugins/leadv2/scripts/leadv2-memory-gc.sh --memory-dir "$HOME/.claude/projects/-Users-kostiantyn-vlasenko-Projects-persona-engine/memory" --cap 100
```

Output plus raw report:

```text
memory-index-gc: no-op (no candidate clusters at sim 0.34; report /Users/kostiantyn.vlasenko/.claude/projects/-Users-kostiantyn-vlasenko-Projects-persona-engine/memory/memory-gc-report.md)
exit_code=0
--- memory-gc-report.md ---
# Memory index GC plan

llm: skipped (no candidate clusters)
current total lines: 149; current entry lines: 141
projected post-GC index size: 149 (cap: 100)
candidate_clusters: 0
deferred_clusters: 0
clustering: 0/2239 same-section/type pairs met sim 0.34; max=0.267647; all-pair eligible=0/9870 max=0.267647; seen-filtered clusters=0

## Per-cluster verdicts
```

### 2. Apply and orphan check

Command:

```text
bash plugins/leadv2/scripts/leadv2-memory-gc.sh --memory-dir "$HOME/.claude/projects/-Users-kostiantyn-vlasenko-Projects-persona-engine/memory" --cap 100 --apply
```

Output:

```text
before_lines=149
before_sha256=abd3e02122fa98b47049d7268b5e0955f9fe3b6d0966b982b8103fc4315fe929
before_gc_runs=0
memory-index-gc: no-op (no candidate clusters at sim 0.34; report /Users/kostiantyn.vlasenko/.claude/projects/-Users-kostiantyn-vlasenko-Projects-persona-engine/memory/memory-gc-report.md)
exit_code=0
after_lines=149
after_sha256=abd3e02122fa98b47049d7268b5e0955f9fe3b6d0966b982b8103fc4315fe929
after_gc_runs=0
orphan_absorbed_by=not_run (no gc manifest)
```

### 3. Idempotent rerun

Command:

```text
bash plugins/leadv2/scripts/leadv2-memory-gc.sh --memory-dir "$HOME/.claude/projects/-Users-kostiantyn-vlasenko-Projects-persona-engine/memory" --cap 100
```

Output:

```text
memory-index-gc: no-op (no candidate clusters at sim 0.34; report /Users/kostiantyn.vlasenko/.claude/projects/-Users-kostiantyn-vlasenko-Projects-persona-engine/memory/memory-gc-report.md)
exit_code=0
index_lines=149
gc_runs=0
```

### 4. Byte-exact restore

Restore precondition/output:

```text
restore_not_run: no gc-* run directory exists
diff_not_run: restore produced no MEMORY.md to compare
```

## Regression checks

```text
$ python3 -m py_compile plugins/leadv2/scripts/leadv2-memory-index-gc.py
$ bash -n plugins/leadv2/scripts/leadv2-memory-gc.sh
$ bash plugins/leadv2/tests/test-memory-index-gc.sh
PASS test-memory-index-gc
$ git diff --check
exit_code=0
```
