# ONE-LANE-WATCH-01 — report

## Scope note: LANE_WRITES is a hard boundary, not a suggestion

`LANE_WRITES` for this task is:

```
plugins/leadv2/scripts/leadv2-lane-watch-v2.sh
plugins/leadv2/scripts/tests/test-lane-watch-v2.sh
plugins/leadv2/hooks/hooks.json
plugins/leadv2/commands/leadv2.md
tests/run-all.sh
docs/handoff/ONE-LANE-WATCH-01/
```

The mission body asks for physical deletion of superseded scripts and for feeding
`leadv2-broad-status.sh` from this tool's signal. Neither `leadv2-broad-status.sh` nor any of
the other 53 census files below is in `LANE_WRITES`, and most of them are invoked from call
sites (`leadv2-dispatch-code.sh`, `leadv2-supervise.sh`, `leadv2-broad-status.sh` itself) that
are also not in `LANE_WRITES`. This repo's own standing decision is per-task worktree isolation
specifically to prevent one lane's diff from touching files another concurrent lane owns —
seven other lanes are active right now (see the `LEADV2_ACTIVE_OTHER_SESSIONS` list this
session started with). I have treated `LANE_WRITES` as authoritative and have **not** edited
anything outside it. Where the mission's ask required an out-of-scope edit, I did the
in-scope part (disarm the hook wiring; document the exact patch needed) and flagged the rest
as a named follow-up below, rather than silently doing less than asked or silently exceeding
scope. The one exception the mission itself calls out by name —
`leadv2-idle-lead-guard.sh` — was retirable entirely through `hooks.json`, which **is** in
scope, so that one is actually done, not just proposed.

## 1 — Arms itself automatically

`plugins/leadv2/hooks/hooks.json`:

- **SessionStart** (last hook in the array, after `leadv2-merged-worktree-sweep.sh`): runs
  `leadv2-lane-watch-v2.sh --arm-from-hook`. Reads `{session_id, cwd}` from stdin (same
  convention as the hook it replaces, `leadv2-idle-guard-arm.sh`), resolves the project root
  via `git -C "$cwd" rev-parse --show-toplevel`, requires `docs/leadv2/` to exist (same R6
  scoping every other leadv2 hook uses), then backgrounds one `--loop` process and records its
  pid at `~/.claude/leadv2-lane-watch/<session_id>/loop.pid`. `continueOnBlock: true`,
  `timeout: 6` — it can never block session start; every failure path in `_lw_arm` is
  best-effort (`|| true` / `|| return 0`).
- **SessionEnd** (new top-level key — verified `SessionEnd` is a supported event via
  `~/.claude/plugins/marketplaces/claude-code-plugins/.../validate-hook-schema.sh`'s
  `VALID_EVENTS` list and the openai-codex plugin's own `SessionEnd` hook, since this
  hooks.json had no `SessionEnd` key before today): runs `--disarm-from-hook`, which kills
  **only** the pid it itself recorded, and only after re-verifying via `ps -o command=` that
  the process's argv still contains this script's own basename, `--loop`, and the exact
  session id (see `_lw_is_our_loop`). It never kills by pattern-matching a lane name — that is
  the exact bug that cost the lead its own watchdog today per the mission's incident list.

**Two concurrent sessions:** state is keyed by `session_id`
(`~/.claude/leadv2-lane-watch/<session_id>/{loop.pid,reported,last_beat}`), so two sessions in
two different repos each arm their own loop, watch their own project's worktrees
(`_lw_discover_lanes` reads `<project_root>/.claude/worktrees/*`), and keep independent
`reported`/`last_beat` files. Neither can see or clear the other's dedupe state, so neither
can double-report the other's lane. Proven in the test suite's case 7 (two sessions, same
fixture lane, each reports it exactly once).

**Per-cycle cost:** one `find` + `xargs stat` over each active lane's worktree (bounded by
`-newermt '-600 minutes'`, so it only scans recently-touched files), one `stat` glob over
`~/.claude/cache/*-runs/*<lane>*` per lane, and a `read -t` on an already-open fifo fd between
cycles — zero forked `sleep` per cycle (see "fork-free wait" below). Default `POLL_SEC=60`,
default 20-minute stall threshold: for a session with N active lanes, that's ~2N subprocess
spawns (find+stat, or the xargs-batched stat) per minute, not per hook call. This is the same
order of mag101gnitude as a single `git status`, and nothing here fires on every tool call —
`FORK-STORM-KILLS-HOOKS-01`'s failure mode was orphaned `sleep` children surviving a killed
watcher; that class of leak needs no `sleep` fork here at all (below).

### Fork-free wait — a disclosed gap, not a silent one

The mission says to use `lib/leadv2-sleep.sh` (`FORK-STORM-KILLS-HOOKS-01`'s merged fork-free
wait). **Verified it does not exist on this lane's branch**: `git ls-tree main` has
`plugins/leadv2/scripts/lib/leadv2-sleep.sh` (merge `1d17985` landed on `main`), but
`git cat-file -e HEAD:plugins/leadv2/scripts/lib/leadv2-sleep.sh` fails — this lane's `HEAD`
(`959bfba`) sits on a branch point (`merge-base HEAD main` = `10fe3d6`) two commits behind
`main`'s current tip, so the merge landed on `main` after this worktree was cut. `LANE_WRITES`
also does not include `scripts/lib/`, so the shared lib cannot be vendored in properly from
here either way.

I duplicated the same algorithm (`_lw_wait` in `leadv2-lane-watch-v2.sh`: `mkfifo` once,
`exec 9<>fifo`, `read -t SECS <&9` — a kernel timed wait with zero forked children, falling
back to `sleep` once only if the fifo cannot be created) directly in the one file `LANE_WRITES`
allows, with a comment naming the exact commit and the exact reason it's duplicated rather than
sourced. **Follow-up:** once this lane rebases past `1d17985`, delete that block and
`source lib/leadv2-sleep.sh` instead — one-line change, called out at the top of the block.

## 2 — Replace, do not add: census of the 54

Legend: **SUPERSEDED** = this tool now reports the same fact; kept alive only because deleting
the file is out of `LANE_WRITES`. **RETIRED** = actually disarmed today. **KEEP** = different
concern, correctly out of scope (enforcement, quota, statusline UI, phase-transition audit
log). **FOLLOW-UP** = genuinely overlaps and should feed off this tool's state, but its call
site is a file this lane cannot touch.

| file | what it reports | verdict |
|---|---|---|
| `hooks/leadv2-idle-lead-guard.sh` | Stop-hook block on 0-queued/0-live | **RETIRED** — hooks.json wiring removed. Its condition (b) depends on `leadv2-lane-liveness.sh --all --json`, measured today returning `count_live=0` with a lane actively writing and every codex lane absent from the output — a predicate that can never see "lanes are busy," so it only ever pushes toward MORE blocking. Removing it cannot cause silent under-blocking (the risk direction the mission warns about for gates); it can only stop a spurious block. Rebuilding it on this tool's signal was considered and rejected: `_lw_run_once`'s "reported" state is per-session dedupe for *messages*, not a live yes/no "is anything alive right now" predicate a Stop hook can poll synchronously without adding a second stateful contract to an already-stateful gate — bounded risk didn't justify it in this lane's write scope. |
| `hooks/leadv2-idle-guard-arm.sh` | SessionStart arm for the above | **RETIRED** — same hooks.json edit; the file is now unreferenced from hooks.json (file itself untouched, out of `LANE_WRITES`). |
| `scripts/leadv2-lane-watch.sh` | LANE-OBSERVABILITY-02 poll-based lane watcher | **SUPERSEDED** — same job this tool does, is this tool's direct predecessor by name. Not called from `hooks.json`; call sites are in other scripts outside `LANE_WRITES`. |
| `scripts/leadv2-lane-pulse-watch.sh` | MON-PULSE-01 dispatcher-owned lane watch | **SUPERSEDED** — same liveness concern. Called from `leadv2-dispatch-code.sh` (not in `LANE_WRITES`). |
| `scripts/leadv2-lane-heartbeat.sh` | PULSE-01 durable per-task heartbeat / "uniform liveness" | **SUPERSEDED** — same concern, different name. |
| `scripts/leadv2-single-lead-beat-loop.sh` | MON-PULSE-01 part 2, default-on pulse beat loop | **SUPERSEDED** — a beat loop for single-lead mode; this tool's `LANE-BEAT` line is the same fact. |
| `hooks/leadv2-single-lead-beat.sh` | PULSE-IN-SINGLE-LEAD-01 beat hook | **FOLLOW-UP** — overlaps with `LANE-BEAT`; wired via `hooks.json` under a matcher this lane did not touch (verify before removing — did not want to change Stop/PostToolUse wiring beyond the one guard the mission named). |
| `scripts/leadv2-pulse-beat.sh` | PULSE-IN-SINGLE-LEAD-01 beat writer | **FOLLOW-UP** — same family as above. |
| `hooks/leadv2-pulse-json.sh` | PostToolUse heartbeat writer ("EYES"), fires every tool call | **FOLLOW-UP** — a per-tool-call heartbeat is a different granularity (activity, not lane-worktree-mtime) but the fact it's approximating ("is the session doing something") is a subset of what `LANE-BEAT` already reports; worth a closer look, not touched here (PostToolUse `matcher: .*`, out of caution about hook-cost regressions this repo has been burned by before). |
| `scripts/leadv2-beat-owner.sh` | BROAD-STATUS-RELAY-SCOPE-01 — who owns the relay beat | **FOLLOW-UP** — feeds `leadv2-broad-status.sh`, out of `LANE_WRITES`. |
| `scripts/leadv2-status-collector.sh` | "collect once, in code, on a schedule" — feeds status surface | **FOLLOW-UP** — candidate to read `LANE-STALL`/`LANE-BEAT` state instead of its own probes; not touched (its call sites and consumers are outside `LANE_WRITES`). |
| `scripts/leadv2-status-watch.sh` | SUPERVISOR-STATUS-SURFACE-02 watch loop | **FOLLOW-UP** — same family as above. |
| `scripts/leadv2-broad-status.sh` | the 30-minute founder status table (`dispatched=`, etc.) | **KEEP, item 4 below** — this is the founder-facing surface the mission wants fed from this tool's signal. Out of `LANE_WRITES`; exact patch given in §4. |
| `scripts/leadv2-status-render.sh` | renders the last collected snapshot, no probes | KEEP — pure renderer, different layer; feeds SwiftBar, not chat. |
| `scripts/leadv2-status-snapshot.sh` | on-demand "где мы" snapshot, file reads only | KEEP — on-demand, not a live watcher; different trigger model. |
| `scripts/leadv2-status-surface.sh` / `.5s.sh` | SwiftBar menu-bar renderer + fast-poll wrapper | KEEP — different consumer (macOS menu bar UI), not chat/session observability. |
| `scripts/leadv2-status-projects.sh` | cwd-independent project enumeration for SwiftBar | KEEP — project discovery, not lane liveness. |
| `scripts/leadv2-status.sh` | thin CLI entry sourcing `leadv2-temp.sh` | KEEP — dispatcher, not a reporting mechanism itself. |
| `scripts/leadv2-lane-status-line.sh` / `-tail.sh` | statusLine renderer (Claude Code UI element) | KEEP — different surface (the CLI status line), not this tool's chat/heartbeat output. |
| `scripts/leadv2-pulse-write.sh` / `leadv2-pulse.sh` | unconditional phase-transition journal writer | KEEP — this is an audit log of phase changes ("entered BUILD"), a different fact from "is the worktree still being written to." |
| `scripts/leadv2-outcome-watch.sh` | schedules/executes a post-deploy outcome check | KEEP — post-deploy verification, not mid-build lane liveness. |
| `scripts/leadv2-quota-status.sh` / `leadv2-token-watch.sh` | provider token/quota headroom | KEEP — quota reporting, unrelated domain. |
| `scripts/leadv2-drift-guard.sh` | 5-way parity check across plugin copies | KEEP — code-drift detection, unrelated domain. |
| `scripts/codex-guard.sh`, `leadv2-govapply-guard.sh`, `leadv2-tasks-clobber-guard.sh` | job-loss / governance-apply / tasks.yaml-clobber protection | KEEP — enforcement, explicitly out of scope ("do not touch a guard that gates correctness"). |
| `hooks/leadv2-async-question-guard.sh`, `leadv2-bg-watchdog-enforce.sh`, `leadv2-bg-watchdog-gate.sh`, `leadv2-blocker-drift-guard.sh`, `leadv2-close-ritual-guard.sh`, `leadv2-codex-direct-exec-guard.sh`, `leadv2-codex-nopoll-guard.sh`, `leadv2-continuation-guard.sh`, `leadv2-gate-artifact-guard.sh`, `leadv2-idle-notification-filter.sh`, `leadv2-lead-edit-guard.sh`, `leadv2-lead-prose-guard.sh`, `leadv2-lead-read-guard.sh`, `leadv2-memory-guard.sh`, `leadv2-model-inherit-guard.sh`, `leadv2-monitor-cap-gate.sh`, `leadv2-promise-guard.sh`, `leadv2-pulse-enforcer.sh`, `leadv2-routing-guard.sh`, `leadv2-verdict-format-guard.sh`, `leadv2-workflow-bypass-guard.sh`, `leadv2-workflow-model-guard.sh` | assorted PreToolUse/Stop/PostToolUse enforcement gates and lints | KEEP — each gates a correctness/protocol invariant (routing, edit scope, prose length, workflow discipline), none reports lane liveness. Explicitly out of scope per the mission ("this lane consolidates observability, not enforcement"). |
| `hooks/leadv2-orphan-monitor-sweep.sh` | SessionStart sweep of orphaned `Monitor`-tool process groups | KEEP — same *shape* of fix (reap your own stale kind by strict identity) but a different domain (the `Monitor` tool's child processes, not lane worktrees); this tool's `--reap-stale` is the lane-watch analogue of this same pattern, not a replacement for it. |

**Net today:** 1 file's automatic firing disabled (`leadv2-idle-lead-guard.sh` +
`leadv2-idle-guard-arm.sh`, via `hooks.json`), 4 files identified as direct, no-caveat
supersessions ready for deletion the moment a lane with write access to their call sites
(`leadv2-dispatch-code.sh`, `leadv2-supervise.sh`) runs, and 5 more flagged as likely
consolidation targets pending a closer read. That is a real, evidenced shrink, not the full
54→1 the mission's headline asks for — the honest gap is `LANE_WRITES`, not appetite.

## 3 — Helps, doesn't only report

- **Stuck → reap the stale watcher (shipped):** `--reap-stale` (also run automatically at the
  end of every `--arm-from-hook`) sweeps `~/.claude/leadv2-lane-watch/*/loop.pid`, and for any
  pid file whose recorded pid is no longer running, deletes the pidfile. It **never** touches
  a live process, and it never touches anything outside `LEADV2_LANE_WATCH_STATE_DIR` — the
  one class of "stuck" this tool can safely and automatically clear is its own dead
  bookkeeping (test suite: "reap-stale" case, plus case 8b which proves a pidfile pointing at
  a real-but-foreign process is never killed even under `--disarm-from-hook`).
- **Restart → report-and-suggest, not automatic (deliberate, per the mission's own escape
  hatch):** the `LANE-STALL` line already ends with "check and re-dispatch" — that is the
  suggestion. I did not build automatic re-dispatch. Making it safe requires (a) detecting
  uncommitted work in the lane's worktree and salvaging it before touching anything, (b) a
  bounded per-lane attempt counter durable across restarts, (c) a kill switch — three
  stateful, git-touching subsystems this lane's fixture-only, 6-file-scoped mission has no
  room to build and prove safe. Shipping a partial version of that (e.g. "restart if worktree
  is clean") would be exactly the "unbounded auto-restart" the mission forbids the moment the
  uncommitted-work check has any gap. Report-and-suggest is the honest deliverable here.

## 4 — One line the founder can read

`leadv2-broad-status.sh` cannot be edited from this lane (`LANE_WRITES` scope). The concrete
patch, for whoever picks up the follow-up: have it read
`~/.claude/leadv2-lane-watch/<session_id>/reported` and `last_beat` (or shell out to
`leadv2-lane-watch-v2.sh --once <session_id> <root>` and capture stdout) for its `dispatched=`
row instead of whatever probe currently produces `dispatched=unavailable` while four lanes are
running (the exact disagreement the mission's item 4 names). Until that lands, the founder's
table and this tool's alarm can still disagree — flagging this explicitly rather than claiming
it's fixed.

## Acceptance — fixture suite, `plugins/leadv2/scripts/tests/test-lane-watch-v2.sh`

13/13 pass. All 8 mission acceptance cases plus `--reap-stale` and an `EXTRA_SUITE_MAP`
self-check. Full raw output in `full.md`.

## Mutation proof (Rules: RED, revert, GREEN)

1. **Removed the grace-period check** (`_lw_dispatch_age_min` gate in `_lw_run_once`) →
   suite went `PASS=11 FAIL=2`, failing exactly case 4b and case 5 (the two cases that assert
   grace-period behaviour). Reverted (byte-identical `diff` against the pre-mutation copy) →
   back to `PASS=13 FAIL=0`.
2. **Neutered the worktree-mtime signal** (`_lw_newest_age_min` forced to always return `0`) →
   suite went `PASS=9 FAIL=4`, failing case 1, case 3, case 4a, and case 7 — every case that
   depends on staleness detection, case 4 included as the mission requires. Reverted → back to
   `PASS=13 FAIL=0`.

Full raw transcripts of both RED runs and both GREEN re-runs are in `full.md`.

## Bash 3.2 / self-check

`bash -n` clean on both new `.sh` files (no Python files touched — nothing to
`py_compile`). `tests/run-all.sh --scope changed` output in `full.md`.

## What I deliberately left alone

- All 53 non-retired census files — see the LANE_WRITES explanation above.
- `leadv2-broad-status.sh` wiring (item 4) — patch described, not applied (out of scope).
- Any enforcement guard — explicitly out of scope per the mission.
