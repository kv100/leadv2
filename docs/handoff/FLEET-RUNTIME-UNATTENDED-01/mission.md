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

---

# ROUND 2 — review failed round 1 on merit (2026-09-17)

Round 1 landed 1257 insertions and was killed by review: **2 critical, 5 high**. The work is on
`worktree-583d804d01e5`; build on it, do not restart from zero. Full verdict:
`docs/handoff/dispatch-c7527bac-review/critic.full.md`.

Three findings are not defects in the code — they mean the thing does not do what it exists for.
Fix these first and prove each:

1. **`Restart=always` undoes every controlled stop.** systemd restarts the runner after a
   deliberate stop, so the FLEET-STOP flag and all three self-stops are cosmetic: the fleet
   cannot actually be stopped. The unit and the runner need one shared model of "stopped on
   purpose" versus "crashed" — a controlled stop must exit in a way systemd does not restart.
   This is the founder-facing promise; nothing else in this lane matters if it is wrong.
2. **`--cap` is accepted, rendered into ExecStart, and ignored** (`runner.sh:46,62`). The lane
   cap is the entire reason two sessions exist rather than one. An ignored cap means unbounded
   lanes on a 4-core host.
3. **The guard falls back to `rm -rf` on a lane worktree.** Never. A reaper that can delete
   unlanded work is worse than no reaper. Use the sanctioned worktree removal path, and refuse
   rather than force when it declines.

Then the rest, in the reviewer's own words:
- **Reaping is dead code — nothing writes `.fleet-terminal`.** A loop over zero items prints
  success; that is not a reaper.
- **A real install can never run a lane:** no `Environment=` for `LEADV2_FLEET_LANE_CMD`.
- `quota_window` conflates auth expiry with quota — different states, and the plan requires
  different behaviour (degrade versus stop). Give each its own name.
- `fleet_claude_usable` is fail-closed on the credentials file, so it is wrong on macOS
  (keychain) — and macOS is where this suite runs in development.
- `landed_today` / `rows_filed_today` never roll over. `rows_filed_today` is the plan's one
  convergence indicator; a counter that never resets cannot report it.

## Tests — this is what actually failed

**Two of the three self-stops and the whole degrade path have zero tests**, the guard has none
at all, and **the Claim-2 negative control is not run by the suite, with its target-string
assertion absent.** That last one is the failure this repo has a standing rule about: a control
that is not run, or that asserts nothing, rots into a permanent green.

Every claim in the mission needs its control RUN and its output pasted. A suite that skips on
the dev machine is a suite nobody ever sees fail — stub the unit layer, do not skip the case.

---

# ROUND 3 — scope cut to four things (2026-09-17, lead)

Round 2 grew the branch to 1663 insertions and failed review with **4 critical, 4 high**. Two
rounds have now missed the same central item, so this round is deliberately narrow. **Do only
the four things below.** Everything else on the branch stays as it is; the rest of the review's
findings are being split into their own rows and are NOT yours.

Judge yourself by one question: *if I install this on the VPS right now, does the unit load,
run a lane, and stop when told?* Nothing else counts this round.

## 1. The controlled stop — asked twice, still not in the diff

`Restart=always` restarts the runner after a deliberate stop, so FLEET-STOP and all three
self-stops remain decorative. The unit and the runner need ONE shared model of "stopped on
purpose" versus "crashed": a controlled stop must exit in a way systemd does not restart
(`SuccessExitStatus` / `Restart=on-failure` with a distinct code — your choice, but pick one and
make both sides agree).

This is the founder-facing promise. If it is not in the diff, the round has failed regardless of
what else is.

## 2. The unit file does not load

- `leadv2-fleet-unit.sh:473` — `WorkingDirectory="${2}"` is a fatal unit error.
- `leadv2-fleet-unit.sh:464` — `Environment=LEADV2_FLEET_LANE_CMD=${5}` is unquoted.

Prove it by generating a unit and running `systemd-analyze verify` on it (or, where systemd is
absent, a parser stub that rejects exactly these two shapes). A unit that cannot load is not a
runtime.

## 3. A control mutation shipped in the product file

`leadv2-fleet-unit.sh:476` carries a trailing `# c1-mut:` comment which makes systemd ignore the
line. That is a negative-control marker left inside shipped code. Remove it, and make the suite
assert that no `c*-mut` marker survives in any file under `plugins/leadv2/scripts/fleet/` — a
control that can leak into the product must be caught by the suite, not by a reviewer.

## 4. The reaper still forces

`leadv2-fleet-guard.sh:78` still runs `git worktree remove --force`. Forbidden in round 2 and
still there. Use the non-forcing path and **refuse** when it declines. A reaper that can delete
unlanded work is worse than no reaper.

## Why the reviewer could not see your work

Round 2's review said: *"The diff under review is not the code that passes the suite: runner/lib
round-2 edits are [absent]"*. The review diff is built from the lane's **declared write set**, so
anything you edit outside it is invisible to the judge. The declared set for this round is
exactly: `leadv2-fleet-unit.sh`, `leadv2-fleet-guard.sh`, `leadv2-fleet-state.sh`, `runner.sh`,
`lib.sh`, `test-fleet-runtime-guards.sh`, and this row's `report.md`. **If a fix needs a file
outside that list, stop and say so in the report instead of editing it silently.**

## Controls

Two claims, both RUN, both outputs pasted:

1. A controlled stop does not get restarted by systemd. Negative control: revert to the old exit
   path and show the restart returning.
2. A generated unit passes verification. Negative control: reintroduce the unquoted
   `WorkingDirectory` and show verification failing.

Assert the mutation target string is present before each control runs. Then assert no marker
remains — see item 3.
