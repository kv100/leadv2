# LANE-WRITES-IS-EMPTY-98-PERCENT-01 — the BEFORE number

**98% is not what is happening, and the three diseases the row asks me to
separate are not the three that exist.** Measured 2026-09-05, one procedure,
re-runnable: `lane-writes-census.sh` in this directory.

## The instrument

The census does not re-implement the parse. It **extracts `_prepass_file` and
`_prepass_writes` verbatim** from `leadv2-dispatch-code.sh` and runs them over
every dispatch handoff directory, so the count cannot drift from what the
dispatcher sees. Non-zero answers exist in the corpus (148), so the instrument is
not stuck at zero.

## The count

918 dispatch handoff dirs in `~/Projects/leadv2`:

| outcome | n | share |
|---|---|---|
| A `no_artifact` — the architect prepass file does not exist | 757 | 82.5% |
| B `no_line` — artifact exists, no `LANE_WRITES:` line | 13 | 1.4% |
| C `empty_value` — line present, value blank | **0** | 0.0% |
| D `all_rejected` — entries declared, all dropped by the L12 over-broad filter | **0** | 0.0% |
| E `kept` — a usable CSV survives | 148 | 16.1% |

**C and D are zero.** The "empty field" disease — a declared-but-blank scope that
reads as permission to write anywhere — does not occur even once. Neither does
the subtler one where a scope is declared and silently discarded for being
over-broad (`*`, `**`, `.`, `/`, a bare top-level directory).

Where the prepass artifact does exist, **148 of 161 (92%) carry a usable write
set**. The 82.5% is not a field left empty; it is a *source document that was
never written*.

## Why the headline number cannot be 98% either way

The guard has **four independent satisfiers** (`_lane_writes_guard`), and the
census above measures exactly one of them:

1. a row-declared writes CSV (`row_writes`)
2. a validated `report:<path>` deliverable (report lanes have no write set by contract)
3. the prepass artifact's `LANE_WRITES:` line ← the only one this census sees
4. an existing lane worktree — isolation substituting for a declaration

So "83.9% effectively empty" is a statement about source 3 alone. Reported as
"84% of lanes have no write set" it would be a false zero of exactly the kind
this repo keeps producing.

## What the journals actually recorded

1000 lane journals:

| event | n |
|---|---|
| routed dispatches (`route_resolved`) | 1458 |
| parked, `reason=no_lane_writes` | 94 |
| `lane_writes … source=prepass` | 186 |
| `lane_writes … source=report_deliverable` | 0 |
| `dispatch_refused reason=writeset_overlap` | 36 |

## The actual defect

**Three of the four satisfiers were silent.** Only the prepass branch and the
report-deliverable branch emitted anything; a row-declared CSV and a lane
worktree each `return 0` with no journal line. So for the overwhelming majority
of routed dispatches nothing on disk says *how* the write set was satisfied — and
"declared nothing, ran isolated in a worktree" and "no declared write set at all"
were the same row, though only the first is safe.

That is not a missing write set. It is a missing sentence about the write set,
and it is the whole reason the field reads as empty from the outside.

**Fixed here:** both silent satisfiers now name themselves —
`lane_writes task=<sig> source=row writes=<csv>` and
`lane_writes task=<sig> source=worktree substitutes_for=declaration`. Nothing
about *whether* a lane passes changes; only whether the reason is legible. The
next census can therefore attribute all four sources instead of one.
