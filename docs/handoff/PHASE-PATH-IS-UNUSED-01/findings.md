# PHASE-PATH-IS-UNUSED-01 — why work goes straight to BUILD, and what a cheap default needs

Diagnosis only. No code changed. All numbers below carry the command that produced them.

## 1. How often is the phase path actually taken?

Naive first pass (searching `docs/handoff/<task_id>/` for phase artifacts) undercounts badly:
phase records do not live under the founder task-id, they live under `docs/handoff/dispatch-<sig8>/phases.d/*.yaml`, where `sig8` is the first 8 hex chars of the ledger's `task_sig` (a content hash of the mission). Redone correctly against the real location (script executed this session against `~/.claude/cache/dispatch-ledger/leadv2.jsonl`, `ts>=2026-08-03`, grouped by `(task_id, task_sig[:8])`, reading `docs/handoff/dispatch-<sig8>/phases.d/{plan,gate1}.yaml`):

- 75 dispatch rows (74 unique task_ids) in the last 30 days (386 total lines in the ledger).
- **14 / 75 (19%)** have `plan.yaml` AND `gate1.yaml` both `proof: verified` — a real triad-produced `context.yaml` with `decisions:` (or non-empty `architect-prepass.md`) plus a real `.gate1-passed` sentinel from `leadv2-gate1-prompt.sh`. This is the only group that is the *designed* flow, not a workaround.
- **22 / 75 (29%)** have `plan.yaml` and/or `gate1.yaml` present but `proof: attested` — the lead ran `leadv2-phase-record.sh record <sig8> plan --artifact docs/handoff/<task>/brief.md` and `... gate1 --reason "<one line>"` by hand to satisfy the guard. This is not the plan/gate1 phases running; it is the guard being told they ran.
- **39 / 75 (52%)** have no `plan.yaml` at all — these built with no phase record present (Light-class `warn` mode, `LEADV2_REQUIRE_PHASES=0`, or dispatched before the guard covered them).
- `architect-prepass.md` non-empty: **9 / 75 (12%)**.
- `phases.d/diverge.yaml` present (Phase 1.5 used): **20 / 75 (27%)**.

Ratio: **for every 1 lane that took the real phase path, ~4.4 skipped it or faked it through the guard** (14 real vs 61 skipped-or-attested). Counting only genuine machine-verified evidence, **81% of the last 30 days' work never produced a real plan artifact or a real founder gate decision** — it produced a `--reason "one line"` CLI call or nothing.

## 2. What the dispatcher demands, and is it satisfiable before a lane starts — REPRODUCED

Read: `plugins/leadv2/scripts/leadv2-dispatch-code.sh:3971-4108` (`_phase_precondition_guard`), `plugins/leadv2/scripts/leadv2-phase-record.sh:486-529` (`_verify_artifact`), `docs/handoff/DISPATCH-PHASE-DEADLOCK-01/brief.md` + `fix-round-2.md` (the open bug report named in the mission).

**The bug report is accurate as filed, and it is STILL live for the first call of any brand-new lane, despite two rounds of fix already merged to main** (`2a293d8b` "bootstrap probe must precede the classify write" is on `HEAD`; `99c4fc0a` round-2's own G2 assertion commit is NOT on main — the worktree branch and main have "diverged, 2 and 459 different commits each").

Reproduction, class=Standard (the CLI default when `--task-class` is omitted), `LEADV2_REQUIRE_PHASES` unset (confirmed unset in the live shell — so the guard runs in the class-derived `mode=1` enforce path for Standard/Heavy/Strategic, per `leadv2-dispatch-code.sh:3997-4012`):

```
$ LEADV2_DISPATCH_SPAWN=0 bash plugins/leadv2/scripts/leadv2-dispatch-code.sh \
    "@<scratch-brief.md>" --task-id PHASE-PATH-REPRO-01 --task-class standard --no-spawn

[leadv2-dispatch-code] dispatch_task_bound task=c6542d84 founder_task=PHASE-PATH-REPRO-01
[leadv2-dispatch-code] task_class=Standard route=phases source=flag task=c6542d84
[leadv2-dispatch-code] dispatch_classified task=c6542d84 class=product reason=conservative_default kind=unknown
[leadv2-dispatch-code] phase_precondition_refused task=c6542d84 class=Standard missing=plan,gate1 mode=1
[leadv2-dispatch-code] ERROR: dispatch refused: missing mandatory phases: plan,gate1
```

Root cause, confirmed by reading `docs/leadv2/tasks/dispatch-c6542d84/journal.md` (the run's own decision log) and by calling `is-bootstrap` before/after:

```
$ bash plugins/leadv2/scripts/leadv2-phase-record.sh assert c6542d84 --class Standard --pre-build
rc=0   # BEFORE dispatch runs: brand-new sig8 IS bootstrap, guard would admit it

# ... dispatch runs cmd_resolve, which calls:
#   bash "${PHASE_RECORD_BIN}" record "${sig8}" classify --status done   (dispatch-code.sh:6930)
# which writes phases.d/classify.yaml -- and a lane with ANY phase record is no
# longer bootstrap by definition (leadv2-phase-record.sh:1066-1071 cmd_is_bootstrap).

$ bash plugins/leadv2/scripts/leadv2-phase-record.sh is-bootstrap c6542d84
rc=1   # AFTER the same dispatch call's own classify write: no longer bootstrap

$ bash plugins/leadv2/scripts/leadv2-phase-record.sh assert c6542d84 --class Standard --pre-build
missing=plan,gate1   # now refused, in the SAME dispatch invocation that just wrote classify
```

**The dispatcher's own Phase-1 (classify) write, which happens unconditionally inside the same `cmd_resolve` call that later checks the guard, disqualifies the lane from the bootstrap admission that same call would otherwise have received.** So the very first `leadv2-dispatch-code.sh` invocation for any new Standard+ task refuses **100% of the time** — not intermittently — because bootstrap and the classify write race inside one process, and classify always wins (it runs first). This is exactly the shape in the bug report title: "the gate wants proofs only a started lane produces," except now it is worse in one respect — even the *first* call's own internal classify write is enough to trip it, before any worker is even resolved.

**Is it satisfiable?** Yes, but only via a two-call, human-authored dance — confirmed by completing it:

```
$ mkdir -p docs/handoff/PHASE-PATH-REPRO-01 && cp <brief> docs/handoff/PHASE-PATH-REPRO-01/brief.md
$ bash plugins/leadv2/scripts/leadv2-phase-record.sh record c6542d84 plan \
    --artifact docs/handoff/PHASE-PATH-REPRO-01/brief.md
$ bash plugins/leadv2/scripts/leadv2-phase-record.sh record c6542d84 gate1 --reason "scratch repro test"
$ bash plugins/leadv2/scripts/leadv2-phase-record.sh assert c6542d84 --class Standard --pre-build
rc=0   # now clears

$ LEADV2_DISPATCH_SPAWN=0 bash plugins/leadv2/scripts/leadv2-dispatch-code.sh \
    "@docs/handoff/PHASE-PATH-REPRO-01/brief.md" --task-id PHASE-PATH-REPRO-01 --task-class standard --no-spawn
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=glm-flash ...
[leadv2-dispatch-code] dispatch_rolled_back reason=no_spawn_dry_run task=c6542d84   # (no_spawn artifact only)
```

The second call proceeds. But `c6542d84` was only knowable from the FIRST call's refusal output — it is a hash of the mission content, computed inside the dispatcher, never available to the lead ahead of time. So the minimum satisfiable sequence for a brand-new Standard+ task is: **dispatch (refused, reveals sig8) → hand-write `docs/handoff/<task-id>/brief.md` if it doesn't exist yet → two `phase-record.sh record` calls (self-attested, not verified) → dispatch again.** This matches the brief's measured cost exactly: "eight hand-written-file workarounds… four dispatch attempts lost on CODEX-DETACH-01."

**Verdict on the claim: CONFIRMED, not refuted.** Round 1/round 2 of `DISPATCH-PHASE-DEADLOCK-01` made the deadlock *escapable* (attested evidence is now accepted, where before nothing was) but did not remove the guaranteed first-call refusal itself — it only shortened the workaround from 8 hand-edited files to 2 CLI calls plus one file. That is the mechanism behind the §1 number: 29% of real dispatches (22/75) carry `proof: attested`, i.e. paid exactly this toll.

Scratch reproduction artifacts (`docs/handoff/PHASE-PATH-REPRO-01/`, `docs/handoff/dispatch-c6542d84/`, `docs/leadv2/tasks/{c6542d84,dispatch-c6542d84}/`) were created and removed after the reproduction — repo left in its pre-existing state (`git status --porcelain` shows no PHASE-PATH-REPRO-01 / c6542d84 residue).

## 3. What the phase path costs when it works

Sampled the one lane in the last 30 days with fully `verified` (not attested) plan+gate1: `ANTI-SILENCE-STATUSLINE-01` (`sig8=73bc78d3`).

```
$ grep '"task_id":"ANTI-SILENCE-STATUSLINE-01"' ~/.claude/cache/dispatch-ledger/leadv2.jsonl | wc -l
22   # confirmed dispatch/arm-resolution events for this task in the ledger
$ cat docs/handoff/dispatch-73bc78d3/phases.d/{plan,gate1,classify,build}.yaml
plan:     started_at=2026-08-30T02:17:18Z  proof=verified
gate1:    started_at=2026-08-30T02:17:18Z  proof=verified
classify: started_at=2026-08-31T01:22:32Z  proof=verified   # written a full DAY after plan/gate1
build:    started_at=2026-08-31T01:23:00Z  status=running
$ ls docs/handoff/ANTI-SILENCE-STATUSLINE-01/ | grep -c fix-round
11
```

- Wall time from first ledger dispatch (`2026-08-30T02:17:49Z`) to the build phase actually starting (`2026-08-31T01:23:00Z`): **~23 hours.**
- 22 confirmed dispatch/arm-resolution events (proxy for agent spawns) across that window, alternating codex/sonnet.
- **11 fix-round files** — i.e. 11 review-and-rework cycles.

Compared against three sampled lanes that never produced a `plan.yaml` at all (no phase path, guard in warn/bypassed mode): `ADOPTION-GUARANTEES-A-PASSABLE-GATE-01` (1 fix-round), `ANTI-SILENCE-BEAT-ABORT-03` (0 fix-rounds), `CACHE-TRUTH-01` (3 fix-rounds).

**The phase-path lane did not need fewer review rounds — it needed more (11 vs 0–3 in the no-plan sample).** This is one lane, not a controlled experiment (`ANTI-SILENCE-STATUSLINE-01` also carries a documented mid-lane rescue, `DISPATCH-PIN-VIOLATED-LIVE-20260830`, visible in its own git log, which independently inflates its round count) — but it is the *only* lane in the last 30 days with a genuine verified plan+gate1 pair, so it is also the only available evidence, and the honest read is: **no lane in the last 30 days demonstrates the phase path paying for itself in fewer review rounds.** If that claim exists anywhere in this repo's self-description, it is not supported by the last 30 days of ledger data.

## 4. What would make the phase path the cheap default

Ordered by leverage, cheapest first. None of these are implemented here — this is the diagnosis, not the fix.

1. **Drop the classify-before-guard ordering, or make the guard bootstrap-check BEFORE `cmd_resolve`'s own classify write, not after.** This is the single highest-leverage change: it is the literal mechanism that makes every first dispatch of a Standard+ task refuse. `_phase_precondition_guard` (dispatch-code.sh:3984) is called after `dispatch_classified` (~line 6930) writes `phases.d/classify.yaml` in the same invocation. Moving the guard call to before that write — or having `cmd_is_bootstrap` snapshot phase-record state at process entry rather than at assert time — removes the guaranteed-refusal-on-first-call defect without touching phase semantics for anyone. This is a few-line reordering, not a design change, and it is the fix the two prior rounds (`DISPATCH-PHASE-DEADLOCK-01`) did not land: their commit landed the *attested-evidence acceptance* (the escape hatch) but not this ordering fix, which is why the reproduction above still shows the refusal on a virgin sig8.

2. **The dispatcher should generate the plan artifact itself, not demand one exist.** Right now Phase 2 (triad plan → `context.yaml`) is a separate invocation the lead must run BEFORE calling `leadv2-dispatch-code.sh`, and the guard has no way to distinguish "the lead skipped planning" from "the lead is about to plan." Concretely: when the guard would refuse for `missing=plan` on a Standard+ class AND the caller passed a brief (`@file` or `-`), the dispatcher should itself invoke the Phase-2 triad (architect + critic, codex optional per class) inline, write `docs/handoff/dispatch-<sig8>/context.yaml` with real `decisions:`, and continue — turning "you must have already planned" into "planning happens now, as part of this call." This collapses Phase 2 into Phase 4's own dispatch call instead of requiring a prior one, and it produces `proof: verified` output (a real `context.yaml`) instead of `proof: attested` self-declarations. This directly targets the 29% "attested" number in §1 — those are exactly the cases where a real plan was never produced, only asserted.

3. **Make Gate-1 a real one-line founder decision captured at the SAME call site, not a separate CLI incantation.** `leadv2-gate1-prompt.sh` exists and produces a genuine `.gate1-passed` sentinel (`proof: verified`), but nothing routes the lead there automatically — the printed remedy instead offers the `--reason` attested shortcut, which is what 22/75 lanes took. If the dispatcher, on a `missing=gate1` refusal for a Standard+ class, invoked `leadv2-gate1-prompt.sh` itself (via `ask-lead.sh`, already the existing question-proxy mechanism per the subagent protocol) instead of printing a manual remedy command, `verified` gate1 evidence would be the path of least resistance instead of `attested`.

4. **Never treat `LEADV2_REQUIRE_PHASES` unset + Light-class floor as license to skip silently.** 52% of the last 30 days (39/75) built with zero plan record. Some of that is legitimately Light-class (`warn` mode by design), but nothing in the ledger or phases.d distinguishes "Light, correctly warned-and-skipped" from "Standard+ dispatched with an env override or before the guard existed." Recommend: `phases.d` should always write a `classify.yaml` with the resolved class and the effective mode (`warn`/`1`/`0`) even when no phase is mandatory, so a future audit like this one can tell "skipped by design" from "skipped by bypass" without cross-referencing `task-class.yaml` by hand.

**Preferred shape for the fix, per the mission's stated preference:** items 1–3 all make the right path *cheaper* (fewer manual steps, generated evidence instead of demanded evidence) rather than making the wrong path more *expensive* (e.g., blocking BUILD harder). Item 1 alone removes the deadlock; items 2–3 are what convert the remaining 29% "attested" lanes into genuinely verified ones without adding lead-side friction.

## What is out of scope here (for the implementing agent to ignore)

- Any change to `LEADV2_REQUIRE_PHASES` default value itself (currently `"warn"`, overridden to `mode=1` for Standard+ by `PHASE-DISCIPLINE-01` — that override logic is not implicated in the deadlock and should not be touched incidentally).
- The review-round count / `fix-round-N.md` cadence — §3's finding is evidence, not a review-process fix target.
- `leadv2-gate1-prompt.sh` internals — cited as the correct existing mechanism, not proposed for a rewrite.
- Anything under `.claude/worktrees/` — those are live/dead lane worktrees, several mid-flight; none were touched by this diagnosis beyond read-only `git log`/`git status` probes.

## Contradiction scan (pre-finalize)

- Env var naming: `LEADV2_REQUIRE_PHASES`, `LEADV2_DISPATCH_SPAWN` — both confirmed by direct grep against `leadv2-dispatch-code.sh` and the live shell env; no drift found.
- File paths cited: all read directly this session (`plugins/leadv2/scripts/leadv2-dispatch-code.sh`, `plugins/leadv2/scripts/leadv2-phase-record.sh`, `docs/handoff/DISPATCH-PHASE-DEADLOCK-01/{brief.md,fix-round-2.md}`, `docs/handoff/dispatch-<sig8>/phases.d/*.yaml` for several live sig8s) — all exist, none marked to-create.
- No `claude -p` invocations proposed in this diagnosis — N/A.
- Concurrent access: none — this document proposes no writes; item 1–3 above touch `leadv2-dispatch-code.sh`/`leadv2-phase-record.sh`, both already flagged bug-magnets by repo history (`DISPATCH-PHASE-DEADLOCK-01` itself is round-2-and-still-incomplete evidence of that), so an implementing lane should expect the "your suite is green without your fix" trap called out in `fix-round-2.md` and must prove RED-before/GREEN-after on the real guard, not a reimplementation.
- Config contradiction check: none introduced — no new env vars proposed.

DELIVERABLE_COMPLETE
