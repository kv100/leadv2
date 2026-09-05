# ANTI-SILENCE-STATUSLINE-01 — closing round (Standard)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01`
All edits go there. Never edit files under `/Users/kostiantyn.vlasenko/Projects/leadv2`
directly — a previous round did exactly that and its work had to be rescued by hand
(`DISPATCH-PIN-VIOLATED-LIVE-20260830`). Two commits already exist in the lane; build on them.

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-status-line.sh,plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh,plugins/leadv2/scripts/leadv2-status-surface.sh,plugins/leadv2/scripts/tests/test-statusline-readable.sh,plugins/leadv2/scripts/tests/test-status-surface.sh,plugins/leadv2/scripts/tests/run-all.sh


Write set (files this round may modify, all lane-local):
- `plugins/leadv2/scripts/leadv2-lane-status-line.sh`
- `plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh`
- `plugins/leadv2/scripts/leadv2-status-surface.sh`
- `plugins/leadv2/scripts/tests/test-statusline-readable.sh`
- `plugins/leadv2/scripts/tests/test-status-surface.sh`
- `plugins/leadv2/scripts/tests/run-all.sh` (EXTRA_SUITE_MAP row only)

## Measured state of the lane RIGHT NOW (do not re-derive, verify)

Rendered from the lane at three widths, 2026-08-30T08:09Z:

```
COLUMNS=80  → ? in ? | cc 87%·7d/5d17h · cx 93%·wk/6d17h · glm 19%·wk/20h53m
COLUMNS=120 → (identical)
COLUMNS=200 → (identical)
```

So: `sup:OFF(retired)` is gone — that part landed. **Everything else in the brief is unmet.**
Quotas still lead the line, the output does not change with `COLUMNS` at all, and the lane
section is absent. The founder's complaint is verbatim that three lanes were running and he
could see none of them; that is still true today.

## Build this, and nothing else

Primary file: `plugins/leadv2/scripts/leadv2-lane-status-line.sh` (+ its tail helper
`leadv2-lane-status-line-tail.sh`, already partly reworked in `7f3d98e`).

1. **Lanes FIRST.** The line begins with lane state. Everything else follows it. If there are
   zero lanes, say so in one short token — never render an empty leading field.
2. **A silent or dead lane is the most prominent field on the line**, ahead of every quota.
3. **Budget to terminal width**: `COLUMNS` → `tput cols` → 80. Reserve the budget for lanes
   first. Never truncate mid-word: cut on a field boundary and append a dropped-count marker.
   The three renders above must differ by width; today they do not, which means whatever width
   logic exists is not reached on the live path. Find out why before you write new code.
4. **Quotas shrink or vanish when lanes are live.** Abbreviate to what fits the remainder.
5. Do not add a hook, a loop, a notifier, or any send door. All cancelled — see
   `docs/handoff/ANTI-SILENCE-DELIVERY-01/channel-verdict.md` (in the persona-engine repo).

## Also in scope — separately proven, carried over unmet

6. **Hook JSON schema.** `/Users/kostiantyn.vlasenko/Projects/persona-engine/.claude/hooks/anti-silence-pulse-arm-inject.sh`
   and `…-detector.sh` must emit
   `{"hookSpecificOutput":{"hookEventName":"<ev>","additionalContext":"…"}}` and DROP the
   top-level `additionalContext`, which the harness discards. Amend
   `tests/unit/test-anti-silence-pulse-hooks.sh:46,51` — it asserts the broken shape, which is
   exactly why this shipped green. Amend, never delete. **These two files live in
   persona-engine**, so they belong to that repo's lane
   (`/Users/kostiantyn.vlasenko/Projects/persona-engine/.claude/worktrees/ANTI-SILENCE-DELIVERY-01`),
   not this one. Keep the two repos' changes in their own lanes.
7. **Session key.** `session_id` → `basename(transcript_path .jsonl)` → **HARD FAIL** (KEYFAIL
   marker, no keyed artifact). Replace `read -r -N 8192 -t 2` with `_stdin="$(cat)"`: `-N` is
   bash 4.1+, macOS `/bin/bash` is 3.2.57 and rejects it, `|| true` swallows the error, and the
   key silently rotates. `$PPID` must never be used as a key.

## Tests — negative controls you RUN

| Fix | Mutation (INSIDE the function body) | Suite |
|---|---|---|
| order | move the lane field back behind the quota block | `tests/test-statusline-readable.sh`: lane field start index < 40 in a 3-lane fixture |
| width | remove the width budget | same: an 80-col fixture emits no truncated word and names the dropped count |
| silence | render a stale lane as a plain suffix | same: a lane silent past threshold precedes every quota field |
| schema | restore the top-level `additionalContext` in `_emit` | `tests/contract/anti-silence-hook-schema.sh` (persona-engine) |
| key | restore `_SESSION_KEY="${_sid:-${PPID:-}}"` | `tests/unit/test-anti-silence-pulse-hooks.sh` amended (persona-engine) |

Name each mutation in the suite header, apply it inside the function body in a scratch worktree,
show RED, revert, show GREEN, paste the runs. A grep-for-a-string assertion is not a control —
the suite must execute the renderer. Wire the suites into CI and prove selection with
`--scope changed`.

## Done means

Lane clean of source changes (control-plane residue only), commit shas reported, all five
mutations red-then-green, and **a before/after render at 80, 120 and 200 columns with three live
lanes** — the after must show the lanes at every width. Commit your work: a round that ends with
uncommitted edits in the lane counts as producing nothing.
