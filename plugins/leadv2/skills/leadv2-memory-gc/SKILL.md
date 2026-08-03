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
leadv2-memory-gc.sh --memory-dir /path/to/memory [--cap 100] [--sim 0.34]
                    [--model haiku] [--max-clusters 40] [--apply]
leadv2-memory-gc.sh --memory-dir /path/to/memory --restore archive/gc-...
```

This mode is dry-run by default and writes only `memory-gc-report.md`. Unless
`--verdicts-file` supplies an explicit offline/test override, it invokes
`${CLAUDE_BIN:-claude}` exactly once with every deterministic, same-section/type
cluster in one prompt. `--model` is passed to that invocation (default: `haiku`).
A missing CLI, timeout, non-zero exit, or malformed model response is reported as
an `llm: error`, exits non-zero, and never applies index/archive changes. When no
pair reaches `--sim`, the report shows the pair counts and maximum similarity and
skips the model call explicitly.

`--apply` is required to rewrite `MEMORY.md` and move absorbed entry files into
`archive/gc-<timestamp>/`. Restore refuses if the live index has changed since that run.

`STANDING:` entries, `metadata.type: user`, `metadata.memory_gc: keep`, ACTIVE entries
from optional leadv2 YAML stores, and orphan index lines are immune: they can be anchors,
but cannot be absorbed. Index prose, blank lines, and section headers are retained verbatim.
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
