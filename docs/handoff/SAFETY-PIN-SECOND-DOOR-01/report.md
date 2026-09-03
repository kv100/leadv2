# SAFETY-PIN-SECOND-DOOR-01 — report

## Verdict

The census's literal claim (a file `leadv2-admission-class.sh` under
`plugins/leadv2/scripts/` folding risk into class while a route pin reads
`RISK_TAGS`) does not exist as described — that file lives at
`plugins/leadv2/scripts/lib/leadv2-admission-class.sh` and the "route pin" it
described is `leadv2-session-route.sh`, already fixed by
`HEAVY-TIER-VS-SAFETY-OPUS-01`. **The underlying shape was real by a
different path**: `leadv2-dispatch-code.sh`'s own worker-arm resolver
(`cmd_resolve`) is a *separate* router from `leadv2-session-route.sh` and had
no `risk_class` concept at all — the judge's `risk_class=safety_publish_payments`
only escalated `ADMISSION_CLASS` to Heavy via `lib/leadv2-admission-class.sh`'s
map. It never reached the `safety` local that gates the router's
`require_trusted` exclusion, so a task the judge flagged hard-safety, with no
caller `--safety`/`--risk-tags`, took the ordinary Heavy route with **zero**
safety-specific protection — an untrusted arm (freepool/glm) was a real,
un-excluded candidate for any task shape where Heavy's own size-based
eligibility didn't happen to already exclude it. This is a second, independent
door alongside the one `HEAVY-TIER-VS-SAFETY-OPUS-01` closed, confirmed by a
live before/after probe, not by reading.

## Evidence: live probe, resolve-only, no caller `--safety`/`--risk-tags`

Same scenario run against `HEAD~1` (`9084cce6`, before this lane's fix) and
`HEAD` (`eb8a66ab`, after): a judge stub returns
`risk_class=safety_publish_payments`, the CLI invocation carries no
`--safety`/`--risk-tags`, dispatch is `--kind code --no-spawn`. Only
`safety_pin_applied`/`arm_excluded`/`route_resolved` decision lines shown
below (grepped from the raw run):

```
=== pre (HEAD~1, before this lane's fix) ===
[leadv2-dispatch-code] arm_excluded by=router arm=glm-flash task=2433c13d reason=arm_not_capable_for_size task_class=heavy when=trivial,light,standard
[leadv2-dispatch-code] arm_excluded by=router arm=freepool task=2433c13d reason=arm_not_capable_for_size task_class=heavy when=light,standard,bulk
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=codex model=gpt-5.6 tier=standard effort=high task=2433c13d reason=cheapest_capable arbiter_pick=codex util_glm=5 util_codex=5 util_claude=5 util_freepool=0 floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=complex duration_class=unknown
[leadv2-dispatch-code] route_resolved by=router router=arbiter model=codex task=2433c13d rule=none reason=cheapest_capable

=== post (HEAD, after this lane's fix) ===
[leadv2-dispatch-code] safety_pin_applied by=admission task=2433c13d reason=risk_safety_publish_payments
[leadv2-dispatch-code] arm_excluded by=router arm=freepool task=2433c13d reason=protected_path
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=codex model=gpt-5.6 tier=standard effort=high task=2433c13d reason=cheapest_capable arbiter_pick=codex util_glm=5 util_codex=5 util_claude=5 util_freepool=0 floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=complex duration_class=unknown
[leadv2-dispatch-code] route_resolved by=router router=arbiter model=codex task=2433c13d rule=none reason=cheapest_capable
```

Read the `pre` block carefully: there is **no `safety_pin_applied` line at
all**, and freepool/glm-flash are excluded only for `reason=arm_not_capable_for_size`
(an accident of `task_class=heavy`'s own `when:` eligibility list) — not
`reason=protected_path`. For a task shape where Heavy's size eligibility does
*not* already exclude the untrusted arm (or for a non-Heavy class carrying the
same risk_class), the pre-fix resolver would have handed the task to freepool
or glm with no safety-specific exclusion ever evaluated. Post-fix,
`safety_pin_applied` fires and freepool is excluded for `reason=protected_path`
regardless of size eligibility — the correct, unconditional exclusion the
census described. Both runs happen to land on the same final `arm=codex`
here (the arbiter's own cost ranking picks codex anyway in this scenario) —
the fix is not about which trusted arm wins, it is about whether an untrusted
arm was ever a live candidate.

## Fix

`plugins/leadv2/scripts/leadv2-dispatch-code.sh`'s `cmd_resolve` now folds
`ADMISSION_RISK_CLASS` (surfaced by `_admission_classify`) into the local
`safety` flag unconditionally, before any config/env override read — the same
placement `HEAVY-TIER-VS-SAFETY-OPUS-01` round 2 used for
`CLAUDE_SAFETY_MODEL`, outside the override surface. An explicit caller
`--safety` is only ever added to, never cleared. `lib/leadv2-admission-class.sh`'s
receipt gains an optional 7th tab-delimited `risk_class` field so a cache-hit
re-entry (same mission digest) can recover the signal without re-judging; old
receipts without the field read back with `risk_class=""`, never a hard
failure.

The `arch` carve-out from `HEAVY-TIER-VS-SAFETY-OPUS-01`/`fix-round-2.md` is
untouched and stays consistent by construction: that carve-out lives entirely
in `leadv2-session-route.sh`'s `RISK_TAGS`/`HIGH_RISK_TAGS` handling, a
different router with a different signal vocabulary. This fix's signal is the
judge's own three-value `risk_class` enum (`none`/`data`/`safety_publish_payments`)
— there is no `arch` value in that enum, so no second `arch` rule was
introduced.

## Test coverage

New suite `plugins/leadv2/scripts/tests/test-admission-safety-pin.sh`
(registered in `tests/run-all.sh`'s self-selecting
`plugins/leadv2/scripts/tests/` path plus an explicit `EXTRA_SUITE_MAP` row
tying it to both `leadv2-admission-class` and `leadv2-dispatch-code`):
judge-flags-safety-with-no-caller-flag fires the pin (green), `risk_class=none`
stays silent (baseline), and a mutated throwaway copy with the fold-in
stripped reopens the door (red) — asserted via a helper that accepts either
of the two live enforcement shapes the router can take per-run (arbiter path:
`arm_excluded ... reason=protected_path`; legacy-v1 fallback path:
`rule=safety_gate_publish_payments`), since both were live-observed for the
same fixed binary depending on the platform's arbiter behavior — see
"Test suite" section below. `plugins/leadv2/scripts/tests/test-admission-class.sh`
gained coverage for the `risk_class` receipt round-trip.

`test-session-route.sh` was deliberately **not** touched: it owns
`leadv2-session-route.sh`'s tag-based routing only and has no `risk_class`
concept — the census's original claim conflated the two routers, and mirroring
that conflation into the wrong test file would have hidden the actual fix
location. The new suite's own header comment states this explicitly.

## Mutation control

Ran the production `leadv2-mutation-control.sh` tool (not hand-asserted
prose) against the committed fix, mutating the unique anchor condition in
`leadv2-dispatch-code.sh` (`ADMISSION_RISK_CLASS:-}" == "safety_publish_payments"`
→ `"never_matches_anything"`) and re-running `test-admission-safety-pin.sh`:

```
$ bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
    plugins/leadv2/scripts/tests/test-admission-safety-pin.sh \
    plugins/leadv2/scripts/leadv2-dispatch-code.sh \
    's/ADMISSION_RISK_CLASS:-}" == "safety_publish_payments"/ADMISSION_RISK_CLASS:-}" == "never_matches_anything"/' \
    docs/handoff/SAFETY-PIN-SECOND-DOOR-01
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-admission-safety-pin.sh file=plugins/leadv2/scripts/leadv2-dispatch-code.sh red_line=FAIL: (green) safety_pin_applied line missing -- diff_hash=<matches this round's git diff>
$ echo $?
0
```

Artifact: `docs/handoff/SAFETY-PIN-SECOND-DOOR-01/mutation-control/*.txt`
(`baseline_rc=0`, `mutated_rc=1`, `diff_hash=` bound to `git diff <base> HEAD`
of this round, recomputed fresh after this report was committed so the hash
matches what the DoD gate itself will recompute).

## Test suite: green on macOS and in a Linux container, exit codes

macOS (host, bash 3.2 default system shell used by dispatch invocations):

```
$ bash plugins/leadv2/scripts/tests/test-admission-class.sh; echo "EXIT=$?"
SUMMARY: pass=25 fail=0
EXIT=0

$ bash plugins/leadv2/scripts/tests/test-admission-safety-pin.sh; echo "EXIT=$?"
PASS: bash syntax: dispatch
PASS: (green) judge-only safety signal, no --safety flag -- pin fires
PASS: (green) pin reaches routing enforcement, not just the admission journal
PASS: (baseline) risk_class=none -- no safety_pin_applied line
PASS: (red) with the fold-in stripped, the second door reopens -- no safety_pin_applied line
PASS: (red) no safety enforcement in routing -- exact pre-fix symptom reproduced
---
PASS=6 FAIL=0
EXIT=0
```

Linux container (`docker run debian:stable-slim`, bash 5 + git + python3
installed, repo copied in, fresh `git init` for the suites' own git
plumbing):

```
$ bash plugins/leadv2/scripts/tests/test-admission-class.sh; echo "CLASS_EXIT=$?"
SUMMARY: pass=25 fail=0
CLASS_EXIT=0

$ bash plugins/leadv2/scripts/tests/test-admission-safety-pin.sh; echo "SAFETY_EXIT=$?"
PASS: bash syntax: dispatch
PASS: (green) judge-only safety signal, no --safety flag -- pin fires
PASS: (green) pin reaches routing enforcement, not just the admission journal
PASS: (baseline) risk_class=none -- no safety_pin_applied line
PASS: (red) with the fold-in stripped, the second door reopens -- no safety_pin_applied line
PASS: (red) no safety enforcement in routing -- exact pre-fix symptom reproduced
---
PASS=6 FAIL=0
SAFETY_EXIT=0
```

Both platforms took a *different* live routing path for the same fixed
binary in this scenario (macOS resolved via the T17 arbiter and journaled
`arm_excluded ... reason=protected_path`; the Linux container's arbiter fell
back to the legacy v1 ladder — pre-existing fail-open plumbing this lane does
not touch — and resolved via `rule=safety_gate_publish_payments`). Both are
legitimate enforcement shapes for the same underlying fix; the suite's
`_safety_reached_routing` helper accepts either without weakening what it
proves (verified false on the mutated copy on both platforms too: Linux's
mutated run resolves `rule=none reason=glm_default`, macOS's mutated run
drops the `protected_path` exclusion line entirely).

## What this still does not catch

Same honest limit `leadv2-mutation-control.sh`'s own header states: the
artifact's five-line shape (`suite=`, `file=`, `baseline_rc=0`, a nonzero
`mutated_rc`, a matching `diff_hash=`) is not unforgeable — a worker could
still hand-write all five lines. It is no longer a one-line forgery, and the
`diff_hash` binds the artifact to this exact round's diff.

Also not investigated (out of scope for this lane): *why* the T17 arbiter
falls back to the legacy v1 ladder in the Linux container but not on macOS
for this scenario. That fallback is pre-existing, deliberate "fail-open on an
arbiter fault" plumbing (`leadv2-dispatch-code.sh:7574` comment) untouched by
this diff, and both fallback shapes correctly enforce the safety pin — so it
did not block this fix, but the root cause of the platform divergence itself
is unresolved and could be worth a follow-up if it turns out to affect other
arbiter-gated behavior.
