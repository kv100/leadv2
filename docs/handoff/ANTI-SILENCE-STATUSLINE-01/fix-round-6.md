# ANTI-SILENCE-STATUSLINE-01 — round 6 (review said fail)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-status-line.sh,plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh,plugins/leadv2/scripts/leadv2-status-surface.sh,plugins/leadv2/scripts/tests/test-statusline-readable.sh,plugins/leadv2/scripts/tests/test-status-surface.sh,tests/run-all.sh,docs/handoff/ANTI-SILENCE-STATUSLINE-01/

Full report: `docs/handoff/ANTI-SILENCE-STATUSLINE-01/review-r5.md`. HEAD is `61c0c2a`; resume.

**Won at last, after three rounds: MUT-R is RED.** Reverting the rank fix now gives 79/11 and it is
the sole delta from baseline. The founding incident — a dead lane losing its slot on the founder's
statusline — is finally protected. Keep that control exactly as it is. **F5 is genuinely fixed**
and the regenerated proof is clean.

Everything below is what still is not real.

## [Critical] `round5-red/MUT-Z.log` ships a GREEN run under a RED header

The artifact that is supposed to prove MUT-Z is caught records a passing run, labelled as if it
failed. Whatever produced that file did not check the result it was writing down.

An artifact that misreports its own outcome is worse than a missing one: it is the evidence the
next reviewer, and the lead, would have trusted. Regenerate every artifact in `round5-red/` from a
run whose exit status you assert, and make the artifact-writing step fail loudly if the run it is
recording did not actually go red.

## [Critical] MUT-Z survives, and MUT-V's control is a copy of MUT-Z's

- **MUT-Z** (tail `+N` reservation) survives at **both** candidate sites: `pass=43 fail=0`.
- **MUT-V** (tail dropped-count off-by-one) survives at
  `leadv2-lane-status-line-tail.sh:1132`, because its "control" at
  `test-statusline-readable.sh:568` is a **byte-identical copy** of MUT-Z's assertion at `:566`.

Two mutations, one assertion, neither caught. Write a distinct behavioural assertion per mutation,
apply each to production inside the function body, and show each RED individually.

## [High] `test-status-surface.sh` still grades nothing

Red at baseline (80/10, exit 1) **and** unselected by `--scope changed` from this lane. It is the
home of F4 and MUT-B. A suite that is red before any change and that CI never selects cannot
distinguish a fix from a regression. Get it green at baseline and selected from the dirty lane, and
paste both.

## [High] F5's fix has no control

Reverting the visible-width fix leaves the suite green. The fix is right; nothing holds it in place.
Add the assertion and prove it RED.

## [High] F9 is unimproved

100.1 ms tail / 83.4 ms composer children-CPU per render, against a **5.8 ms** floor. This runs on
every render of the founder's statusline. Two rounds have now reported it as addressed without the
number moving.

## [High] new — `LC_ALL=C` breaks the line at every width

Under `LC_ALL=C` the founder's line **drops the dead lane at w=20 and overflows at every width**.
None of the three scripts does any locale normalisation. The labels are Cyrillic, so a byte-oriented
locale mis-measures every one of them — and the statusline runs in whatever environment the
founder's terminal happens to have. Normalise the locale (or measure in a locale-independent way)
and add a control that runs the render under `LC_ALL=C`.

## Rules

- **An artifact must assert its own outcome.** After this round, a `roundN-red/` file that records a
  passing run is a hard failure of the round, not a nit.
- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file, RED,
  revert, GREEN; a zero-match `sed` is a hard failure, not a skip.
- One distinct assertion per mutation. Do not copy an assertion between controls.
- Bash 3.2.57 only.
- `git add <file> <file>`, never `git add <dir>`.
- Commit before you stop.

## Done means

MUT-Z and MUT-V each RED under their own distinct control; every `round5-red/` artifact regenerated
from a run whose exit status is asserted; F5 held by a control; `test-status-surface.sh` green at
baseline and selected by `--scope changed` from the dirty lane; render time near the 5.8 ms floor
rather than 100 ms; and the render correct under `LC_ALL=C` with a control that proves it.
