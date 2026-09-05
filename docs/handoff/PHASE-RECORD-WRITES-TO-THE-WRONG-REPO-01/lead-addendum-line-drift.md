# Lead addendum — line drift + partial prior edit (verified 2026-09-06)

The brief stands, including its central instruction **"do not reorder resolution to prefer
cwd"** and its prescribed fix (a permitted-root existence gate inside `cmd_record`).
Two facts have moved since it was written. Re-read the file; do not trust the brief's
line numbers.

## 1. `leadv2-phase-record.sh` has grown ~9 lines

| Thing | Brief says | Actually now |
|---|---|---|
| root resolution block | :152-164 | **:156-171** (`PHASES_DIR_BASE` set at :170) |
| env-var conflict guard | :155-159 | **:158-166** |
| `_phases_d()` | :189 | **:198** |
| `mkdir -p "$phases_d"` in `cmd_record` | :746 | still the first write, but re-derive the line |

**Root cause 1 is NOT fixed.** `cmd_record` still runs
`mkdir -p "$phases_d" || { _log_err "record: cannot mkdir $phases_d"; exit 4; }`
with no preceding check that `docs/handoff/dispatch-<sig8>/` already exists under the
resolved root. The gate the brief prescribes is still absent. Premise confirmed.

## 2. Root cause 2's regex has ALREADY been partially widened by someone else

The brief prescribes replacing the two-name alternation at `:510`. That alternation is
gone. Current state, at **:536**:

```
'^(.*/)?docs/handoff/[^/]+/(brief|brief-[^/]+|fix-round-[0-9]+)\.md$'
```

So `brief-*.md` was added, but the brief's prescription was **generic leaf-name**
(`[^/]+\.md`) **plus a substance floor of ≥120 non-whitespace characters and ≥2 non-blank
lines**. Neither the generic form nor the substance floor is present — the bare `-s`
non-empty check the brief calls out is still what gates content, so a placeholder still
passes.

Commit 2 must therefore start from the file as it is, decide whether the remaining gap is
still worth closing as specified, and **say so explicitly in the close** — do not apply the
brief's diff blind against a line that no longer reads what it read. The stale rationale
comments the brief flags (its :28-30 / :498-503) also need re-locating; :28-30 still
describes the old two-name rule.

## 3. Unchanged

The off-limits list, the files allowlist, the WAVE4 shared constraints, the negative-control
discipline, and the two-commit split all bind as written.
