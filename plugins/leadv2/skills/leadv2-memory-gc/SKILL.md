---
name: leadv2-memory-gc
description: "[internal] Finds stale paths, duplicate entries, and archive candidates in leadv2 memory stores. Triggers: memory index over its line cap, or an explicit GC request."
allowed-tools:
  - Read
  - Bash
---

# Lead v2 Memory GC — Dream Pass

## Purpose

Periodically prune and validate the four leadv2 memory stores:

- `docs/leadv2/immune-patterns.yaml`
- `docs/leadv2-negative-memory.yaml`
- `docs/leadv2-priors.yaml`
- `.claude/ref/lead-patterns.md`

## Checks performed

| Check | Action |
|---|---|
| **Stale paths** — path tokens in store content that no longer exist on disk | Report-only; founder decides deletions |
| **Duplicates** — identical `pattern/regex` (immune) or `failure_mode+pattern` (negative-memory) | Removed on `--apply`; oldest entry archived |
| **Archive candidates** — `hits/uses==0` (or absent) AND older than `--max-age-days` | Report-only; founder reviews before archiving |

## Flags

```
leadv2-memory-gc.sh --project-root <path>   # defaults to $PWD
                    --apply                  # dedupes only; stale+archive = report-only always
                    --max-age-days N         # default 90
```

## Memory-index mode

For a Claude-style project memory directory, use the same script explicitly:

```
leadv2-memory-gc.sh --memory-dir /path/to/memory --project-root /path/to/project
                    [--model haiku] [--apply]
leadv2-memory-gc.sh --memory-dir /path/to/memory --project-root /path/to/project
                    --audit archive/gc-...
leadv2-memory-gc.sh --memory-dir /path/to/memory --project-root /path/to/project
                    --restore archive/gc-...
```

This mode is dry-run by default and writes only `memory-gc-report.md`. Unless
`--verdicts-file` supplies an explicit offline/test override, it invokes
`${CLAUDE_BIN:-claude}` exactly once with every index entry in one prompt. The
per-entry verdict is `live` (still changes a future session) or `spent` (closed,
fixed, superseded, or a one-off already encoded elsewhere). `--model` is passed
to that invocation (default: `haiku`).
A missing CLI, timeout, non-zero exit, or malformed model response is reported as
an `llm: error`, exits non-zero, and never applies index/archive changes. When no
honest loader measurement can be found, the run is BLOCKED instead of using a
guessed cap; tests/offline callers may provide both `--byte-cap` and `--line-limit`
as explicit configuration.

The cap is derived from the actual read boundary in the installed Claude Code
2.1.220 session loader: its embedded `MEMORY.md` config was measured at 25,000
bytes and 200 lines, and it states that this index is loaded into every session.
The report measures the live index bytes and average bytes/line, then derives the
displayed line cap as `min(200, floor(25000 / measured_average_line_bytes))`; bytes
remain the authoritative alert bar because they are the configured read cost.

`--apply` is required to rewrite `MEMORY.md` and move spent entry files into
`archive/gc-<timestamp>/`. The run stores every removed index line verbatim in
`MEMORY.md.archived` and a non-empty one-line reason in `REASONS.md` and the
manifest. Restore refuses if the live index has changed since that run.

`STANDING:` entries, `metadata.type: user`, `metadata.memory_gc: keep`, ACTIVE entries
from the project leadv2 YAML stores, and orphan index lines are immune and can never be
archived. This is enforced after the model verdict. `--audit` independently re-queries
the archived files and exact index lines for immunity violations and missing reasons.
Composite `. Also:` index lines are also protected because removing one would silently
drop pointers whose files were not moved; explicit unresolved-work markers are protected
so the model cannot invent closure that contradicts the source. Index prose, blank lines,
and section headers are retained verbatim.
The legacy four-store mode above is unchanged and remains the weekly Phase-8 action.

## Weekly Phase-8 trigger

`leadv2-phase8-close.sh` runs this script in report-only mode if
`docs/leadv2/.memory-gc-last` is absent or older than 7 days.
Prints: `memory-gc: report refreshed (weekly)`. Never blocks close.

## Report path

`docs/leadv2/memory-gc-report.md` — sections: Stale Paths / Duplicates /
Archive Candidates / Summary counts.

## Apply policy

`--apply` only deduplicates (keeps newest entry per key; removed entries go to
`docs/leadv2/memory-gc-archive.yaml` with `archived_at`).
Stale paths and archive-candidates are **always report-only** — founder reviews
the report and deletes entries manually.

## Proof

This skill carries a runnable proof at [`PROOF.sh`](./PROOF.sh).
Run the gate: `bash plugins/leadv2/scripts/leadv2-skill-proof.sh --only leadv2-memory-gc`
