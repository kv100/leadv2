# FLEET-RUNTIME-UNATTENDED-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

Founder decision 2026-09-17. Plan: `persona-engine:docs/leadv2/FLEET-PLAN.md` (read it — the
constraints below come from there and are not negotiable in this lane).

## What this builds

The runtime that lets two lead sessions run unattended on a VPS for days. **No Claude session
supervises them.** Plain systemd + bash only: an LLM in the supervision path is a supervision
path that costs money per check and dies with a token.

Deliverables, all under `plugins/leadv2/scripts/fleet/` (new directory):

1. **`leadv2-fleet-unit.sh`** — installs/updates a systemd **user** unit per lead session,
   parameterised by repo path and lane cap. `Restart=always`. Two instances on the target host:
   `~/leadv2` cap 2, `~/pe-fleet` cap 1. Must survive ssh disconnect and host reboot
   (`loginctl enable-linger`).
2. **`leadv2-fleet-guard.sh`** — periodic (timer, not a `while true` inside the unit):
   - reaps lane worktrees whose lane reached a terminal;
   - refuses to let the fleet start a new lane below a disk floor (default 2 GB);
   - detects a stalled lane (worktree untouched N minutes) and records it.
3. **`leadv2-fleet-state.sh`** — writes and reads ONE state file. `read` prints at most five
   lines: alive/stopped + reason, lanes in flight, landed today, rows filed today, last change.
   This is the founder-facing surface; it must be readable in a single command with no jq
   gymnastics.

## Hard requirements

**Three self-stops, each with its own named reason in the state file** — a single catch-all
reason makes the next diagnosis impossible:
- disk below the floor;
- N consecutive lanes reaching a terminal without landing (default N=5);
- the weekly/5-hour quota window refuses the configured arms.

**Stop flag.** `~/.claude/leadv2-state/FLEET-STOP` is checked **between lanes**. Present → the
running lane finishes normally and no new lane is taken. It must never kill work mid-lane; a
half-merged lane is worse than a running one. Removing the file resumes without reinstall.

**Degrade, never freeze.** Claude OAuth expires on an unattended host. When the Claude arms are
unusable the fleet continues on GLM (its key is a plain file, `~/.claude/secrets/zai.env`,
`ZAI_AUTH_TOKEN`, and does not expire) and records the degrade in the state file. Silent stop on
expired Claude auth is a defect, not a safe default.

## Off limits

- Do not build a supervisor daemon or revive `leadv2-fanout.sh` / `leadv2-supervise-loop.sh` —
  retired by founder order 2026-08-17.
- Do not put a `claude` invocation anywhere in the guard or the state reader.
- `leadv2-dispatch-product-close.sh`, `leadv2-dispatch-code.sh`, `leadv2-active-registry.sh` —
  other lanes own them this session. Stay out.
- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.

## Controls — three claims, three negative controls, each RUN, outputs pasted

1. **The unit restarts a killed session.** Kill the session process; confirm systemd brings it
   back. Negative control: set `Restart=no`, confirm it stays dead.
2. **The stop flag stops between lanes, not inside one.** Touch the flag mid-lane; confirm the
   current lane reaches its own terminal AND no new lane starts. Negative control: remove the
   flag check, confirm a new lane starts anyway.
3. **The disk floor refuses a start.** Simulate free space below the floor; confirm refusal with
   the named reason. Negative control: raise the floor to 0, confirm it starts.

Apply each mutation inside the function body in the lane worktree, never a scratch copy. Assert
the mutation target string is present before running, so a control cannot rot into a permanent
green. A control that cannot fail on the unfixed code proves nothing.

## Deliverable

`docs/handoff/FLEET-RUNTIME-UNATTENDED-01/report.md` plus a guard suite
`plugins/leadv2/scripts/tests/test-fleet-runtime-guards.sh` pinning all three claims. The suite
must run on a machine without systemd (this repo's CI and the lead's macOS) — stub the unit
layer rather than skipping the case, because a suite that skips on the dev machine is a suite
nobody ever sees fail. State how CI selects it, with the selection output.
