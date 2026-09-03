# DISPATCH-CLOSE-GATE-01 — round 2 (review said fail)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-CLOSE-GATE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh,plugins/leadv2/scripts/lib/leadv2-red-proof.sh,plugins/leadv2/scripts/tests/test-mission-writeset.sh,plugins/leadv2/scripts/tests/test-red-proof-gate.sh,tests/run-all.sh,docs/handoff/DISPATCH-CLOSE-GATE-01/

Full report: `docs/handoff/DISPATCH-CLOSE-GATE-01/review-r1.md`. Read it — it is precise and every
claim in it was produced by running the code, so do not re-litigate, fix.

**Kept, and genuinely proven — do not redo:** both libraries are real. `leadv2_writeset_missing`
and `leadv2_red_proof_has_red` / `leadv2_red_proof_unproven` each went RED under in-body mutations
applied to the production file, and — unusually good — your C1/C2 controls `sys.exit(2)` when the
mutation anchor is absent, so a zero-match is a hard failure rather than a silent skip. That is the
one thing three sibling lanes got wrong today. Keep that pattern.

The problem is that neither mechanism is connected to anything, and the extractor misses the exact
specimens it was built for.

## [Critical] Mechanism 2 is a library and a CLI verb, not a mechanism

`leadv2_red_proof_unproven` has exactly one caller: `cmd_close_gate`, reachable only by a human
typing `leadv2-dispatch-code.sh close-gate <task-id>`. Nothing on the live close path calls it, and
`leadv2-dispatch-product-close.sh` — named in the brief as *the only live close gate*, and put into
your write set for this reason — **is not touched by the diff at all**.

A verb nothing calls is not a mechanism. This is the same finding that graded defect B NOT FIXED on
the sibling lane for two rounds. Wire it into the live close so a real close is downgraded and the
`unproven` names are printed, then prove it with a real close, not a CLI invocation.

## [Critical] C1 — the wiring is invisible to the suite

Deleting **all three** `_mission_writeset_guard` call sites
(`leadv2-dispatch-code.sh:4105, 4121, 4334`) while keeping the function definition leaves the suite
at `pass=14 fail=0`. The suite tests the lib functions and the standalone `mission-writeset-check`
subcommand — neither is the live path.

Add a behavioural assertion that drives `architect_prepass` (or a harness that calls it) with a
non-covering mission and asserts it returns 1 and emits `mission_writeset_refused`. Then delete the
call site and show that assertion RED.

## [Critical] C2 — it false-positives on a real, already-correct mission

`docs/handoff/ANTI-SILENCE-STATUSLINE-01/fix-round-4.md` is the **corrected** brief; its
`LANE_WRITES` already lists `round4-red/` and `render-proof.md`. The checker refuses it:

```
rc=1
mission_writeset_refused missing=round4-red/
```

Cause: line 95 says "logs under `round4-red/`" — a bare relative fragment — and `path_re`
(`lib/leadv2-mission-writeset.sh:41`) treats any backticked token containing `/` as a required
path. The same happens on this lane's own mission (`red/` at `lane-mission.md:100`).

**Had this been live today it would have blocked a correct dispatch.** The brief's own warning:
a false positive here gets the mechanism switched off permanently. Ignore tokens that are not
repo-rooted, or resolve a fragment against the handoff dir before comparing.

## [Critical] C3 — it misses the specimens it was built for, and the fixture was written to fit

`docs/handoff/DISPATCH-PIN-CLUSTER-01/fix-round-5.md` returns `rc=0 mission_writeset_ok` — zero
required paths extracted. Two structural reasons:

1. Its real miss was **source** files (`lib/leadv2-lane-guard.sh` plus four test harnesses named in
   the body). The extractor only scans `## Done means` and two instruction phrasings, so it never
   looks where the miss was.
2. `instr_re` (`:62-66`) matches the literal `leave the logs in`. Every real mission in this repo
   writes **"Leave the RED logs in"** — the word `RED` defeats the regex. On this lane's own
   reconstructed pre-correction mission, the single most important required path
   (`docs/handoff/DISPATCH-CLOSE-GATE-01/red/`) was **not** in the missing list; the refusal was
   right for the wrong reason and its suggested correction was wrong.

And `test-mission-writeset.sh:71-75` passes only because its fixture (`MISSION_INSTR`, line 54)
uses "Also leave the logs in" — a phrasing **no mission in this repo uses**. The fixture was
written to fit the regex instead of the regex being written to fit reality.

Loosen to something like `leave .*logs? in` / `leave the .* in`, extend extraction to source paths
named as required edits, and **replace the synthetic fixture with the two real on-disk specimens**
(`fix-round-4.md` must pass; the pre-correction form of `fix-round-5.md` must be refused naming
`lib/leadv2-lane-guard.sh`).

## Rules

- The specimens are the test. Any future change to the extractor must keep the on-disk missions
  passing/refusing correctly — never adjust a fixture to match the code.
- Every fix keeps a control you RUN: mutation INSIDE the function body of the **production** file,
  RED, revert, GREEN, with a zero-match anchor treated as a hard failure. Logs in
  `docs/handoff/DISPATCH-CLOSE-GATE-01/round2-red/`.
- No `grep` against script source as an assertion; no negated command as an assertion.
- Bash 3.2.57 only.
- `git add <file> <file>`, never `git add <dir>`.
- Commit before you stop. Round 1 did not, and the lead committed for you.

## Done means

Mechanism 2 wired into the live close path in `leadv2-dispatch-product-close.sh` and proven by a
real close that prints an `unproven` name; a suite assertion that goes RED when the
`_mission_writeset_guard` call sites are deleted; `fix-round-4.md` accepted; the pre-correction
form of `fix-round-5.md` refused with `lib/leadv2-lane-guard.sh` named; the real-specimen fixtures
replacing the synthetic one; and `--scope changed` selecting both suites from a dirty tree.
