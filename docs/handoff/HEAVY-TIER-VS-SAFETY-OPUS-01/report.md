# HEAVY-TIER-VS-SAFETY-OPUS-01 — Round 2 report

Lead adjudication implemented exactly as `fix-round-2.md` specifies: the hard-safety
tag pin now outranks the Heavy/Strategic think tier, with `arch` carved out.
Round 1 (`99b4f865`) was not redone; its assertions stay green.

## Change

`plugins/leadv2/scripts/leadv2-session-route.sh` — model-selection order is now:

1. `light` → light model (unchanged)
2. **tag hit on a HIGH_RISK_TAG other than `arch`** → `CLAUDE_SAFETY_MODEL`/`_EFFORT`
   (opus/high). Evaluated FIRST, so Heavy/Strategic + a hard-safety tag
   (`auth,rls,safety,publish,security`) pins opus. Still outside the config/env
   override surface, as round 1 built it.
3. `heavy|strategic` (or Heavy + arch-only tag) → think arm
   (`lib/leadv2-think-model.sh` → fable; opus fallback)
4. `_high_risk` on a non-Heavy class → safety pin (unreachable in default config;
   kept so a class-forced high-risk never falls through to SUGGESTED_MODEL)
5. `SUGGESTED_MODEL`

`arch` carve-out rationale (from the adjudication): the five hard tags name
consequences in the world; `arch` names difficulty, not consequence.
`PLANNER-MODELS-DECISION-01` deliberately pins Heavy planning/architecture to the
think tier. On a non-Heavy class, `arch` keeps round-1 behaviour (safety pin) —
asserted.

The tag-scan loop now runs unconditionally and records the matched tag
(`_risk_tag_hit`) instead of only setting a boolean; `_high_risk` semantics
(Codex/GLM/kimi bans, early-exit route emission) are unchanged.

## New assertions (plugins/leadv2/scripts/tests/test-session-route.sh)

- `Heavy + safety tag -> opus (safety outranks think tier)` — replaces round 1's
  `Heavy + safety tags stays think-tier`, which asserted the exact branch the lead
  reversed. Flipped per the adjudication, not weakened.
- `Heavy + arch tag stays think-tier (arch carve-out)` — `model=fable`.
- Plus `Standard + arch tag pins opus` (non-Heavy arch keeps round-1 behaviour).
- All round-1 assertions retained and green (suite: PASS=12 FAIL=0).

## Negative controls (both directions)

NC1 — reorder reverted (round-1 branch order, new tests kept):

```
[TEST] FAIL: Heavy + safety tag -> opus (safety outranks think tier) missing 'model=opus' in: provider=claude
[TEST] Results: PASS=11 FAIL=1
```

NC2 — `arch` carve-out dropped (`-n "$_risk_tag_hit"` without the `!= arch` guard):

```
[TEST] FAIL: Heavy + arch tag stays think-tier (arch carve-out) missing 'model=fable' in: provider=claude
[TEST] Results: PASS=11 FAIL=1
```

Both reverted → green again (PASS=12 FAIL=0).

## Platform proof (exit codes measured unpiped)

macOS (Darwin 25.5.0, bash 3.2):

```
bash plugins/leadv2/scripts/tests/test-session-route.sh
[TEST] Results: PASS=12 FAIL=0
macos-exit=0
```

Linux container (python:3.12-slim, GNU bash 5.2.37, Python 3.12.14):

```
[TEST] Results: PASS=12 FAIL=0
exit=0
```

## Census: other callers resolving safety through a class check

Grepped `plugins/leadv2/scripts` for safety→model decisions and class checks.
`CLAUDE_SAFETY_MODEL` appears only in `leadv2-session-route.sh`.

**One found second instance — flagging for the lead, not fixed here (out of
round-2 scope):** `plugins/leadv2/scripts/lib/leadv2-admission-class.sh:57-77`
(`leadv2_admission_map_class`) folds `risk_class=safety_publish_payments` into
**class Heavy** (`complexity == "complex" OR risk == "safety_publish_payments"
OR subsystems_touched >= 4 → Heavy`). The resulting Heavy class is what reaches
`leadv2-session-route.sh` as `TASK_CLASS`, while the safety-pin channel is
`RISK_TAGS` — a separate input populated from the dispatch's risk tags, not from
the judge's `risk_class`. So a task the judge classified
`safety_publish_payments` but that carries no explicit high-risk `risk_tags`
would now take the think arm (fable) instead of the safety pin. That is the same
"class-check-instead-of-tag-check" shape the lead called a bug in round 1.
Candidate fixes (lead's call): propagate `risk_class=safety_publish_payments`
into `risk_tags` at admission, or teach the route script to read the judge's
risk_class. Not done here because the admission→route contract is cross-lane
surface.

No other caller routes a model decision for safety through a class check
(`leadv2-route-arbiter.sh` uses class only for bucket flooring;
`leadv2-task-judge.sh` only produces `risk_class`, it does not route).

## Round-3 addendum (dispatch-d552b9ab): a third instance, tag-check but wrong target

Re-run of the census (same task, fresh dispatch, code already green — see below)
found a THIRD instance, of a different shape than round 2's: not a class check
standing in for a tag check, but a correctly-fired safety *tag* check that still
lands on the think tier instead of Opus.

`plugins/leadv2/scripts/leadv2-route-bandit.sh:561` and `:565`
(`cmd_select_for_workflow`, subcommand `select-for-workflow` — live, called from
`plugins/leadv2/hooks/leadv2-bandit-preflight.sh` and documented in
`skills/leadv2-plan/SKILL.md` and `skills/leadv2-review/ref/route-bandit-step0.md`,
so this is a real pre-spawn model pick, not dead code):

```
[[ "$safety" == "true" ]] && default_critic="${think_model:-sonnet}"
```

`think_model` here is the same resolver as `CLAUDE_HEAVY_MODEL`
(`lib/leadv2-think-model.sh` → fable, opus only on the resolver's own failure).
So a review/plan phase with `--safety true` picks the critic's *default* model
from the think tier, not from a safety pin — contradicting the standing rule at
`docs/model-routing.md:95`: "review/critic → Sonnet critic (Opus if
safety-touched)". Two of three now-known instances (this one and round 2's
admission-class.sh finding) both leave a safety-tagged decision on fable instead
of opus; that is the pattern the lead should weigh a systemic fix for (e.g. a
single shared "safety pins opus, no exceptions but arch" helper both scripts
call, instead of each caller re-deriving the rule).

Not fixed here — same reasoning as round 2's admission-class.sh finding:
`leadv2-route-bandit.sh` is a shared plan/review pre-spawn chooser with its own
test suite (`tests/test-leadv2-route-bandit.sh`) and live callers in two skills;
changing its default without updating those together is cross-lane surface, and
this task's brief scopes the *fix* to `leadv2-session-route.sh`'s two failing
assertions, not to every caller the census turns up. Flagging for the lead.

## Round-4 addendum (dispatch-d552b9ab): tool-generated mutation-control artifact

Round 2/3's negative controls (NC1/NC2 above) were hand-run prose: a manual
edit, a manual suite run, a manual revert. `leadv2-mutation-control.sh` (a
sibling tool added since round 3, `WORKER-DOD-GATE-01`) exists specifically so
a mutation-control claim is mechanically checkable instead of asserted — this
addendum re-derives NC1 through it, on a scratch copy of the lane (the lane's
own `leadv2-session-route.sh` is never touched by the tool):

```
$ bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
    plugins/leadv2/scripts/tests/test-session-route.sh \
    plugins/leadv2/scripts/leadv2-session-route.sh \
    '234s/!= "arch"/== "arch"/' \
    docs/handoff/HEAVY-TIER-VS-SAFETY-OPUS-01
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-session-route.sh file=plugins/leadv2/scripts/leadv2-session-route.sh red_line=[TEST] FAIL: Heavy + safety tag -> opus (safety outranks think tier) missing 'model=opus' in: provider=claude diff_hash=d3615b239d9506b8cd70db912917bd0db3b82bb28474e3413c4deaa46f5615a1
```

Artifact written to `mutation-control/20260903T193221Z-21638.txt`:

```
suite=plugins/leadv2/scripts/tests/test-session-route.sh
file=plugins/leadv2/scripts/leadv2-session-route.sh
anchor=234s/!= "arch"/== "arch"/
baseline_rc=0
mutated_rc=1
red_line=[TEST] FAIL: Heavy + safety tag -> opus (safety outranks think tier) missing 'model=opus' in: provider=claude
diff_hash=d3615b239d9506b8cd70db912917bd0db3b82bb28474e3413c4deaa46f5615a1
```

The mutation (line 234 of `leadv2-session-route.sh`: flip `!= "arch"` to
`== "arch"`) is the round-2 reorder's exact inverse: it makes the safety-pin
branch match ONLY on `arch` instead of every non-arch hard tag, so a
Heavy+safety-tagged task falls through to the think-tier branch (fable)
instead of pinning opus — same failure shape as `main` at `06ed55fb`. Baseline
green (`baseline_rc=0`), mutant red (`mutated_rc=1`) on the exact assertion the
brief names. `git status` confirms the lane's own file is untouched by the
tool (it mutates a `mktemp -d` scratch clone, never `git worktree add`, per
the tool's own header comment).

Re-ran the Linux proof fresh for this dispatch, glibc image (matches round-2's
`python:3.12-slim`, GNU bash 5.2.37, GNU coreutils — not the `bash:5.2`
Alpine/musl image, which fails this suite for an unrelated reason: BusyBox
coreutils incompatibility in the test harness's own stub setup, not a
routing defect):

```
$ docker run --rm -v "$(pwd)/plugins/leadv2/scripts:/scripts:ro" python:3.12-slim bash -c '...'
GNU bash, version 5.2.37(1)-release (aarch64-unknown-linux-gnu)
[TEST] Results: PASS=12 FAIL=0
exit=0
```

No routing code changed in this dispatch — round 2's fix (`74f4cfcc`) stands
as-is; this addendum only strengthens the evidence trail per the DoD gate's
own "mutation-control claim must be backed by a `leadv2-mutation-control.sh`
artifact, not asserted prose" rule.

## Self-check

- `bash -n leadv2-session-route.sh` ok; `bash -n tests/test-session-route.sh` ok
  (SYNTAX-OK pasted above in transcript; both clean).
- No Python files changed (no `py_compile` needed).
- Changed-scope runner: this lane's changed scope is the route script + its
  suite; the suite itself is the changed-scope test (12/12 green on both
  platforms, above). `tests/run-all.sh --scope changed` was not run: core-offline
  alone exceeds 10 min (see run-all-changed-scope-runtime memory) and no other
  suite's inputs changed; negative controls above cover the regression surface.
