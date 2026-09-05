# ANTI-SILENCE-DELIVERY-01 round 2 — the beat is the STATUSLINE (Standard)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/persona-engine/.claude/worktrees/ANTI-SILENCE-DELIVERY-01`
Round 1 correctly stopped at the channel gate and wrote `channel-proof.md`. Read
`docs/handoff/ANTI-SILENCE-DELIVERY-01/channel-verdict.md` FIRST — it supersedes the design.

## The finding, in one line

The beat channel already exists, is already configured, is already lead-independent and
always-visible, and is already lane-aware: `leadv2-lane-status-line.sh`, wired as `statusLine`
in `.claude/settings.json`. It is simply **not visible**, because the lanes are at the far right
of a line that is too long.

Measured: rendered length **188 chars**, lane section starts at **char 89**, and the script's own
output already self-truncates mid-word (`| leadv`). Claude Code then prepends its own
`(1M context)`, `[default]`, `61% ctx`, `175t 4h52m`. On the founder's screen the visible tail is
`▶▶ bypass permissions on · 1 shell, 1 monitor` — three lanes were running and he saw none.

Verbatim, what the script emits today and the founder never sees:
```
… | lanes 3: persona-engine/ANTI-SILENCE-DELIVERY-01 worker confirmed·done 51m stale(51m silent)? | leadv
```

## Build this — and NOTHING else

Primary file: `/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/leadv2-lane-status-line.sh`
(311 lines). **It lives in the leadv2 plugin repo, not here.** Work on it in a worktree of THAT
repo; do not create a copy in persona-engine — the copy shape is forbidden.

1. **Lanes FIRST.** The line starts with lane state. Everything else follows it.
2. **Budget to the terminal width** (`COLUMNS`, falling back to `tput cols`, falling back to 80),
   and reserve the budget for lanes. Never truncate mid-word: cut on a field boundary and show a
   count of what was dropped.
3. **Quotas shrink or vanish when lanes are live.** The founder needs to know a lane went silent
   every second; he does not need `cc/cx/glm` percentages every second. Keep them only in the
   space left after lanes, abbreviated.
4. **A silent or dead lane must be the most prominent thing on the line**, not a suffix. Today's
   `stale(51m silent)?` is the right content in the wrong position.
5. `sup:OFF(retired)` is dead weight on every render — the supervisor was retired 2026-08-17.
   Remove it.

Do not add a hook, a loop, a notifier, or a Telegram door. All of those were designed and are
cancelled; see channel-verdict.md.

## Also in scope (separately proven, keep)

6. **Hook JSON schema.** `.claude/hooks/anti-silence-pulse-arm-inject.sh` and
   `…-detector.sh` must emit
   `{"hookSpecificOutput":{"hookEventName":"<ev>","additionalContext":"…"}}` and DROP the
   top-level `additionalContext` key, which the harness discards. Amend
   `tests/unit/test-anti-silence-pulse-hooks.sh:46,51` — it asserts the broken shape, which is
   why this shipped green. Amend, do not delete.
7. **Session key.** `session_id` → `basename(transcript_path .jsonl)` → **HARD FAIL** (KEYFAIL
   marker, no keyed artifact). Replace `read -r -N 8192 -t 2` with `_stdin="$(cat)"`: `-N` is
   bash 4.1+, macOS `/bin/bash` is 3.2.57 and rejects it, `|| true` swallows the error, and the
   key silently rotates. `$PPID` must never be used.

## Tests — negative controls you RUN

| Fix | Mutation (inside the function body) | Suite |
|---|---|---|
| order | move the lane field back behind the quota block | new: assert the lane field's start index is < 40 chars in a 3-lane fixture |
| width | remove the width budget | same suite: an 80-col fixture must not emit a truncated word, and must name the dropped count |
| silence | render a stale lane as a plain suffix | same suite: a lane silent > threshold must appear before any quota field |
| schema | restore the top-level `additionalContext` in `_emit` | `tests/contract/anti-silence-hook-schema.sh` |
| key | restore `_SESSION_KEY="${_sid:-${PPID:-}}"` | `tests/unit/test-anti-silence-pulse-hooks.sh` amended |

Name each mutation in the suite header, apply it INSIDE the function body in a scratch worktree,
show RED, revert, show GREEN. Paste the runs. Wire the suites into CI and prove with
`--scope changed`.

## Done means

Both lane worktrees clean of source changes (control-plane residue only), commits reported, all
five mutations shown red-then-green, and **a before/after render of the statusline at 80, 120 and
200 columns with three live lanes** — the after must show the lanes at every width.
