verdict: APPROVE
next_action: review_round_2

# HANDOFF-ARTIFACTS-ALLOWLIST-IS-NAME-BASED-01 — round 2

## What changed and why

`.gitignore` round 1's allowlist (`!docs/handoff/*/report.md`, `!docs/handoff/*/brief*.md`,
`!docs/handoff/*/*.full.md`, `!docs/handoff/*/*.summary.md`, plus further down
`!docs/handoff/*/fix-round*.md`, `!docs/handoff/*/continue-round*.md`,
`!docs/handoff/*/architect-prepass.md`, `!docs/handoff/*/divergence.md`) enumerated NAMES.
`report-e4-round.md`, `fix-round-1.md`, `mission-close.md` are lane documents like any other
but none of the eight enumerated names matched them (`fix-round-1.md` happens to match
`fix-round*.md` already — asserted anyway per below), so a new kind of document was invisible
to `git add` the day it was first written.

Fix: collapsed the eight per-name `.md` negations into one extension-scoped rule,
`!docs/handoff/*/*.md`, directly under the blanket `docs/handoff/*/*` ignore. Non-document
siblings keep their own, untouched exceptions:
- `!docs/handoff/*/round*-red` (directory, not a document)
- `!docs/handoff/*/context.yaml` and `!docs/handoff/*/.gate1-passed` (structured lead/gate
  state, not authored prose — see "context.yaml was NOT touched" below)

Full diff of the two files is in commit `da64ac0e` (see `git diff --stat` below).

## context.yaml was NOT touched — a conflict I'm flagging, not silently resolving

The mission's mirror text names `context.yaml` alongside `scratch.txt` as a sibling that
"must stay ignored." I verified this is already, deliberately, NOT the case in the current
`.gitignore` — and changing it would reintroduce a real, named incident:

```
$ git log -p --follow -- .gitignore | grep -n -B5 "context.yaml" | tail -10
commit 6f6b55b45f57a56645b919a6e3115a35c9641308
Author: t <t@t.example>
Date:   Mon Aug 31 19:33:48 2026 +0300

    fix(gitignore): the phase gate demanded artifacts .gitignore forbade committing (fix-round-N, context.yaml, architect-prepass.md, .gate1-passed)
```

```
$ git ls-files docs/handoff/ | grep -c context.yaml
50
```

`context.yaml` is currently tracked (50 files across real lanes) because a prior incident
(the phase gate requires it committed). Empirically, on the unmodified pre-existing
`.gitignore` (before my change), `context.yaml` already stages with a plain `git add`
(no -f) — see the probe below run against a copy of the ORIGINAL `.gitignore`:

```
$ cd /tmp/gitignore-probe && git add docs/handoff/FIXTURE-ID/context.yaml docs/handoff/FIXTURE-ID/scratch.txt ...
The following paths are ignored by one of your .gitignore files:
docs/handoff/FIXTURE-ID/mission-close.md
docs/handoff/FIXTURE-ID/report-e4-round.md
docs/handoff/FIXTURE-ID/scratch.txt
hint: Use -f if you really want to add them.
$ git diff --cached --name-only
docs/handoff/FIXTURE-ID/context.yaml
docs/handoff/FIXTURE-ID/fix-round-1.md
```

`context.yaml` staged without `-f` even before my change — because `!docs/handoff/*/context.yaml`
already un-ignores it. Forcing it back to "ignored" would mean deleting that line, which is
exactly the 2026-08-31 incident this repo already fixed once ("the phase gate demanded
artifacts .gitignore forbade committing"). Per the mission's own instruction ("If your change
contradicts a comment, you are probably about to reintroduce the incident — say so in your
deliverable instead of silently deleting the comment"), I left `!docs/handoff/*/context.yaml`
and `!docs/handoff/*/.gate1-passed` untouched and built the mirror assertion (check 6) around
siblings that were never carved out: `scratch.txt`, a stray tarball, and an editor `.swp`
backup — all of which genuinely stay ignored under both the old and new `.gitignore`. This is
documented inline in both `.gitignore` and the test file.

## Files touched (LANE_WRITES only)

```
$ git diff --stat
 .gitignore                                         | 39 +++++++++++++----
 .../tests/test-handoff-artifacts-tracked.sh        | 51 ++++++++++++++++++++++
 2 files changed, 81 insertions(+), 9 deletions(-)
```

No touch to `docs/leadv2/`, `docs/LEAD_V2_STATE.md`, or `docs/handoff/dispatch-nw*` — confirmed
by the stat above (only the two LANE_WRITES files appear).

## tests/run-all.sh registration (confirmed, not touched)

```
$ grep -n "handoff-artifacts-tracked" tests/run-all.sh
294:gitignore:plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh
```
Already registered under the `gitignore` group; `tests/run-all.sh` was not edited.

## Self-check

```
$ bash -n plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh && echo "bash -n OK"
bash -n OK
```
No Python files changed this round (`.gitignore` and a `.sh` test only) — `py_compile` N/A.

## Ten consecutive suite runs (post-fix, post-commit)

```
run 1 rc=0 :: test-handoff-artifacts-tracked: 8 passed, 0 failed
run 2 rc=0 :: test-handoff-artifacts-tracked: 8 passed, 0 failed
run 3 rc=0 :: test-handoff-artifacts-tracked: 8 passed, 0 failed
run 4 rc=0 :: test-handoff-artifacts-tracked: 8 passed, 0 failed
run 5 rc=0 :: test-handoff-artifacts-tracked: 8 passed, 0 failed
run 6 rc=0 :: test-handoff-artifacts-tracked: 8 passed, 0 failed
run 7 rc=0 :: test-handoff-artifacts-tracked: 8 passed, 0 failed
run 8 rc=0 :: test-handoff-artifacts-tracked: 8 passed, 0 failed
run 9 rc=0 :: test-handoff-artifacts-tracked: 8 passed, 0 failed
run 10 rc=0 :: test-handoff-artifacts-tracked: 8 passed, 0 failed
```

Full per-check listing for one of the ten runs (all PASS):
```
PASS: 1: roundN-red/ artifact staged by plain git add (no -f)
PASS: 2: report.md + brief.md staged by plain git add (no -f)
PASS: 3a: transient dispatch.log still matched by check-ignore
PASS: 3b: plain git add is a no-op on ignored dispatch.log
PASS: 4: deleting a tracked proof artifact shows in git status
PASS: RED control: pre-fix blanket-ignore mutation blocks roundN-red git add (control fires, exit code moves)
PASS: 5: never-enumerated lane document names (report-e4-round.md, fix-round-1.md, mission-close.md) staged by plain git add (no -f)
PASS: 6: non-document siblings (scratch.txt, stray-artifact.tar.gz, report.md.swp) stay ignored by plain git add
test-handoff-artifacts-tracked: 8 passed, 0 failed
```

(Checks 1-4 + the RED control are round 1's, unmodified. Checks 5 and 6 are new this round.)

## Negative controls — via leadv2-mutation-control.sh (read first for calling convention)

Usage confirmed from the script itself: `leadv2-mutation-control.sh <suite> <file> <sed-or-patch> [task_dir]`,
exit 0 = mutant applied and suite went red as required, exit 1 = mutant_survived (invalid control),
exit 2 = control_not_applied (anchor/baseline/no-op problem).

### Control (a): revert allowlist to the name-based form → lane-document case (check 5) goes red

Anchor: `s#^!docs/handoff/\*/\*\.md$#!docs/handoff/*/report.md#` applied to `.gitignore`
(replaces the blanket `!docs/handoff/*/*.md` with a single old-style name, `report.md` only —
the pre-fix, name-enumerated shape).

```
$ bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
    plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh \
    .gitignore \
    's#^!docs/handoff/\*/\*\.md$#!docs/handoff/*/report.md#' \
    docs/handoff/dispatch-e3cec9b5
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh file=.gitignore red_line=FAIL: 2: report.md/brief.md not staged (git add said: The following paths are ignored by one of your .gitignore files: diff_hash=84044cd51a066a7f7fb317171d7dc9dbff4dc31a9c5e0f5e0a2131b04c19032f lane_diff_hash=17f1988d3b5b5064effbc95377f8486b55ea9e7976feb1591fcdd0a141cb0408
rc=0
```
`baseline_rc=0` (embedded in the artifact, suite was green pre-mutation), `mutated_rc=1`
(from the artifact's `mutated_rc=` field, matching the printed `rc=0` for the *control tool
itself*, which means "control applied correctly and suite went red").

Direct (non-tool-wrapped) reproduction, showing the full per-check output including check 5
specifically going red (the tool's `red_line` only surfaces the FIRST match, which was check 2;
check 5 is confirmed red in the same run below):
```
PASS: 1: roundN-red/ artifact staged by plain git add (no -f)
FAIL: 2: report.md/brief.md not staged (git add said: The following paths are ignored by one of your .gitignore files:
docs/handoff/FIXTURE-ID/brief.md
hint: Use -f if you really want to add them.
hint: Disable this message with "git config set advice.addIgnoredFile false"; staged: docs/handoff/FIXTURE-ID/report.md)
PASS: 3a: transient dispatch.log still matched by check-ignore
PASS: 3b: plain git add is a no-op on ignored dispatch.log
PASS: 4: deleting a tracked proof artifact shows in git status
PASS: RED control: pre-fix blanket-ignore mutation blocks roundN-red git add (control fires, exit code moves)
FAIL: 5: a never-enumerated lane document was not staged (git add said: The following paths are ignored by one of your .gitignore files:
docs/handoff/FIXTURE-ID/fix-round-1.md
docs/handoff/FIXTURE-ID/mission-close.md
docs/handoff/FIXTURE-ID/report-e4-round.md
hint: Use -f if you really want to add them.
hint: Disable this message with "git config set advice.addIgnoredFile false"; staged: )
PASS: 6: non-document siblings (scratch.txt, stray-artifact.tar.gz, report.md.swp) stay ignored by plain git add
test-handoff-artifacts-tracked: 6 passed, 2 failed
rc=1
```
Pair: `baseline_rc=0` / `mutated_rc=1`. Red line (check 5, the lane-document case): `FAIL: 5: a
never-enumerated lane document was not staged (... fix-round-1.md, mission-close.md,
report-e4-round.md ...)`. `.gitignore` was restored byte-for-byte to the committed state
afterward (`diff .gitignore /tmp/gitignore.orig.bak` → no output, confirmed clean).

### Control (b): widen to `!docs/handoff/*/*` → the mirror (check 6) goes red — this is the round's deliverable control

Anchor: `s#^!docs/handoff/\*/\*\.md$#!docs/handoff/*/*#` applied to `.gitignore` (blanket
un-ignore of everything in the lane directory, the "just widen it" trap the mission warns
against).

```
$ bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
    plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh \
    .gitignore \
    's#^!docs/handoff/\*/\*\.md$#!docs/handoff/*/*#' \
    docs/handoff/dispatch-e3cec9b5
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh file=.gitignore red_line=FAIL: 3a: dispatch.log is NOT ignored (churn would flood git status) diff_hash=e17c0c5b6230b6f5f178af31a1d4a046feaaf3f7a2a067a9946ab3d67a7c82d7 lane_diff_hash=17f1988d3b5b5064effbc95377f8486b55ea9e7976feb1591fcdd0a141cb0408
rc=0
```
`baseline_rc=0` / `mutated_rc=1` (tool rc=0 = "correctly reddened"). Direct reproduction
showing check 6 (the mirror, this round's deliverable) specifically going red in the same run:
```
PASS: 1: roundN-red/ artifact staged by plain git add (no -f)
PASS: 2: report.md + brief.md staged by plain git add (no -f)
FAIL: 3a: dispatch.log is NOT ignored (churn would flood git status)
FAIL: 3b: dispatch.log got staged despite the ignore rule
PASS: 4: deleting a tracked proof artifact shows in git status
PASS: RED control: pre-fix blanket-ignore mutation blocks roundN-red git add (control fires, exit code moves)
PASS: 5: never-enumerated lane document names (report-e4-round.md, fix-round-1.md, mission-close.md) staged by plain git add (no -f)
FAIL: 6: a non-document sibling got staged despite not being a lane document (staged: docs/handoff/FIXTURE-ID/report.md.swp
docs/handoff/FIXTURE-ID/scratch.txt
docs/handoff/FIXTURE-ID/stray-artifact.tar.gz)
test-handoff-artifacts-tracked: 5 passed, 3 failed
rc=1
```
Pair: `baseline_rc=0` / `mutated_rc=1`. Red line (check 6, the mirror — proves the scoped
`!docs/handoff/*/*.md` rule is not equivalent to a blanket `!docs/handoff/*/*` unblind):
`FAIL: 6: a non-document sibling got staged despite not being a lane document (staged:
docs/handoff/FIXTURE-ID/report.md.swp docs/handoff/FIXTURE-ID/scratch.txt
docs/handoff/FIXTURE-ID/stray-artifact.tar.gz)`. `.gitignore` restored byte-for-byte afterward
(diff against `/tmp/gitignore.orig2.bak` → no output).

Neither control crashed the suite (no stack trace / no JSONDecodeError) — both produced a
normal `FAIL:` assertion line and a non-zero suite exit code, which is what the mission
requires ("A mutant that reddens the suite by CRASHING it ... is not a control").

## Commit

```
$ git log --oneline -1
da64ac0e fix(handoff): allowlist lane documents by extension, not by enumerated name
```
Working tree is clean and matches this commit (`git status --short` empty after final restore).

## What I deliberately left alone

- `tests/run-all.sh` — not touched, confirmed already registers the suite (grep above).
- `leadv2-dispatch-code.sh`, `leadv2-active-registry.sh` — not read or touched (held by other
  sessions, per mission constraint).
- `!docs/handoff/*/context.yaml` and `!docs/handoff/*/.gate1-passed` — not folded into the new
  `*.md` rule and not removed; see the "context.yaml was NOT touched" section above for why the
  mission's literal mirror wording (context.yaml "must stay ignored") cannot be satisfied without
  reintroducing the 2026-08-31 gate-commit incident, and why I built the mirror assertion around
  `scratch.txt` / a stray tarball / an editor backup instead.
- `docs/handoff/dispatch-*-review-*.md` (root-level review artifact rule) — untouched, unrelated
  scope (root of `docs/handoff/`, not inside a lane directory).
- Round 1's checks 1-4 and its RED control — untouched, per "do not redo round 1."

DELIVERABLE_COMPLETE
