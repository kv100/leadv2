LABEL=critic-dispatch-BEAT-LOOP-ORPHANS-01-review-1788294239 SESSION_ID=28af4f3e-fa49-446d-9159-73faf1976038
--- body from: docs/handoff/dispatch-BEAT-LOOP-ORPHANS-01-review/critic.full.md ---
REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=5 medium=4 low=3

FINDING: severity=High file=plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh line=170 dimension=correctness desc=owner-check call is unguarded while the lib is sourced conditionally and every sibling call site uses `command -v` — a missing lib makes rc 127 kill the founder beat on iteration 1 (fail-closed among fail-open peers)
FINDING: severity=High file=plugins/leadv2/hooks/lib/leadv2-hook-session-kind.sh line=1 dimension=correctness desc=transcript rule `*/docs/handoff/*|*-runs/*` never matches a real worker transcript (`~/.claude/projects/<munged>/<sid>.jsonl`), so headless workers fall through to `lead` — not `unknown` — and arm loops with no journal line
FINDING: severity=High file=plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh line=1 dimension=correctness desc=case E7 asserts `~/.claude/projects/-Users-x/abc.jsonl -> lead`, enshrining the exact misclassification that produced the 53 measured orphans as expected behaviour
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-task-judge.sh line=214 dimension=design desc=census — headless `claude -p` spawners outside the four gated launchers (task-judge:214, session-runner:439) set neither LEADV2_WORKER_ARM nor LEADV2_SUBSESSION_ROLE, so mechanism 1 does not cover them
FINDING: severity=High file=docs/handoff/BEAT-LOOP-ORPHANS-01/build-attempt-1.diff line=1 dimension=correctness desc=claims-without-evidence — no report.md exists; the brief's mandated proof (suite green, NC1/NC2 pasted red, a real freepool run with clean `pgrep -f single-lead-beat-loop`) is entirely absent, and that unproven claim drives the merge decision

---

## Scope reviewed

`docs/handoff/BEAT-LOOP-ORPHANS-01/build-attempt-1.diff` (895 lines, 12 files), against
`docs/handoff/BEAT-LOOP-ORPHANS-01/brief.md` and the live worktree checkout at
`.claude/worktrees/BEAT-LOOP-ORPHANS-01`. Read-only; no source file was modified.

The change implements the two mechanisms the brief asks for:
1. a shared session-kind predicate (`plugins/leadv2/hooks/lib/leadv2-hook-session-kind.sh`, new)
   consulted by the beat hook, the beat loop, lane-pulse-watch, the backlog pump and
   `leadv2-dispatch-code.sh`;
2. an owner-liveness belt (`leadv2_loop_owner_record` / `_check`) recording owner pid +
   owner transcript at arm time and exiting when the pid is dead or the transcript is
   staler than `LEADV2_LOOP_ORPHAN_MAX_MIN` (default 30).

The shape of the fix is right. It fails on execution: the predicate's decisive rule does not
match reality, one belt call site is fail-closed where all its siblings are fail-open, the
gate covers four of at least six headless spawn paths, and the brief's evidence contract is
unfulfilled.

---

## Lens 1 — correctness

### H1. Guard asymmetry at `leadv2-single-lead-beat-loop.sh:170` (fail-closed)

The lib is sourced conditionally (`if [[ -f "$_LIB" ]]; then . "$_LIB"; fi`), so every consumer
must tolerate its absence. Census of all four belt call sites in the tree:

| site | form | behaviour if lib missing |
|---|---|---|
| `leadv2-single-lead-beat-loop.sh:118` | `if command -v leadv2_loop_owner_record …` | skipped — fail open |
| `leadv2-single-lead-beat-loop.sh:170` | `if ! leadv2_loop_owner_check "$OWNER_FILE" "beat-loop"; then` | **rc 127 → `!` true → `exit 0`** |
| `leadv2-lane-pulse-watch.sh:159` | `if command -v leadv2_loop_owner_record …` | skipped — fail open |
| `leadv2-lane-pulse-watch.sh:231` | `if command -v leadv2_loop_owner_check …` | skipped — fail open |

Line 170 is the single outlier. There is no `set -e` in this script (`set -uo pipefail`, line
39), so rc 127 is not fatal — it is *worse*: it is silently interpreted as "owner is dead", and
the founder's beat loop exits on its first iteration with no journal line distinguishing that
from a genuine dead owner. This is not a theoretical path in this repo: the plugin cache is a
separate copy of the hook tree and `claude plugin update` no-ops for directory-source
marketplaces when content changed but the version did not, so lib-present/lib-absent skew
between the checkout and the loaded plugin is a documented recurring condition here.

Fix: `if command -v leadv2_loop_owner_check >/dev/null 2>&1 && ! leadv2_loop_owner_check …`.

### H2. The transcript rule cannot fire for real workers

Predicate order: pinned `LEADV2_SESSION_KIND` → `LEADV2_WORKER_ARM=1` → non-`lead`
`LEADV2_SUBSESSION_ROLE` → transcript shape → `unknown`.

Rule 4 is:

```bash
case "$transcript" in
  */docs/handoff/*|*-runs/*) printf 'worker\n'; return 0 ;;
  *)                         printf 'lead\n';   return 0 ;;
esac
```

Claude Code writes `transcript_path` as `~/.claude/projects/<munged-cwd>/<sid>.jsonl`. For a
worker running in a lane worktree that is
`~/.claude/projects/-Users-…-leadv2--claude-worktrees-<lane>/<sid>.jsonl` — it matches neither
`*/docs/handoff/*` nor `*-runs/*`, so it takes the `*)` arm and returns **`lead`**. The `.jsonl`
files that do live under `docs/handoff/` are `*.stream.jsonl` stdout captures, which are not
what the hook receives in `transcript_path`.

Two aggravating facts, both inside this diff:

* The diff's own `_lv2_session_kind()` in `leadv2-dispatch-code.sh:4648` resolves a worker's
  transcript with `ls -t "${HOME}/.claude/projects/"*"/${_LV2_OWNER_SID}.jsonl"` — the author
  demonstrably knows worker transcripts live under `~/.claude/projects/`, which rule 4
  classifies as `lead`.
* The `*)` arm returns `lead`, not `unknown`. A wrong answer here is therefore invisible: the
  `unknown` branch is the only one that writes `loop_armed_by_unknown_session` to the arm
  journal, so this failure mode leaves no trace at all.

Net effect: mechanism 1 rests **entirely** on the env exports (rules 2–3). Any spawn path that
does not export them is ungated, and rule 4 actively converts it into a positive `lead`
classification rather than a journaled `unknown`.

### M1. `leadv2_loop_arm_journal` called on the lib-missing path

Three call sites invoke it without a `command -v` guard and outside any sourced-lib
conditional: `leadv2-single-lead-beat.sh:208`, `leadv2-dispatch-code.sh:4661` and `:4682`.
With no `set -e` this is non-fatal, but it writes `command not found` to hook stderr on every
`unknown` classification when the lib is absent — noise in the one code path whose entire
purpose is to leave a clean audit trail. `leadv2-dispatch-code.sh`'s `_lv2_session_kind` does
return early when the lib file is absent, but `_arm_lane_pulse_watch` / `_arm_single_lead_beat`
still reach the journal call with `_LV2_KIND=unknown`.

### M2. `leadv2_loop_owner_pid` matches `node` ancestors

The ancestor walk (up to 8 levels) accepts `comm` of `claude` **or `node`**. `node` is not a
harness-specific marker; any node process in the ancestry (a wrapper, an editor task runner, a
CI shim) binds the loop's declared owner to the wrong pid. The belt then measures the liveness
of something other than the session it is meant to track — in the permissive direction, since
a long-lived node parent keeps a dead session's loop alive.

### L1. `stat -f %m` is BSD-only

`leadv2_loop_owner_check` reads transcript mtime with `stat -f %m` and falls back to `python3`.
Correct on macOS; on GNU coreutils it silently takes the python3 path, and if python3 is also
absent the staleness belt is skipped entirely (fail open). Acceptable given the fallback,
recorded for completeness.

---

## Lens 2 — tests can fail (falsification)

`plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh` (new, 356 lines) is genuinely
hermetic: it copies the real files under test into a skeleton, stubs the state-path,
pulse-beat and heartbeat seams, and runs the loops at 1 s cadence. Two mutation controls are
built in. The pid-file path it asserts on
(`.single-lead-beat-loop-$(cksum of PROJECT_ROOT).pid`) was checked against the loop's actual
naming (lines 67, 79–83) with `LEADV2_PROJECT_ROOT` / `LEADV2_SINGLE_LEAD_BEAT_LOOP_PID_DIR`
overridden — it matches, so cases B1/NC2 are not vacuous. That part is good work.

### H3. E7 asserts the defect as the contract

```bash
u_out="$(kind_of "$HOME/.claude/projects/-Users-x/abc.jsonl")"
[[ "$u_out" == "lead" ]] && ok "E7 normal project transcript -> lead" || bad "E7 got '$u_out'"
```

This is precisely the path shape of a real headless worker's transcript (H2). The suite
therefore *locks in* the misclassification: a future fix that correctly widens the predicate
to catch worktree-scoped worker transcripts will turn E7 red and read as a regression. A test
that pins the bug is worse than a missing test.

### M3. Negative gate assertions have no settle window

A4 (the positive case) observes the beat sentinel through `wait_file … 3` because "the hook's
beat trigger is a disowned background job — its sentinel lands async", as the suite's own
comment says. A1, A2 and A3 — the three cases that assert the gate *blocked* the arm — check
`! -f "$SKEL_A/state/beats.log"` immediately, with zero settle window. An unfixed gate that
arms in >0 ms passes all three.

NC1 mitigates this for A1 only, and only because NC1 re-runs the A1 scenario *with*
`wait_file`. A2 and A3 (the transcript-shape worker cases, i.e. the ones covering H2's rule)
have no mutation control of any kind; E5/E6 cover the predicate in isolation but not the hook
wiring. The fix is one line each: reuse `wait_file … 1` and assert it returns non-zero.

### L2. Suite wall-clock

The suite spends ~30 s in real `sleep`s (B1 ~6 s, C1 ~3 s, D0 ~3 s, D1 ~6 s, NC1 ~3 s,
NC2 ~5 s, plus hook cases). In a repo where the review gate's falsifiability probe already
timed out at 60 s on this very lane, a 30 s suite registered into `tests/run-all.sh` for four
separate source files is a real budget cost. Registration itself is correct: the
`EXTRA_SUITE_MAP` hunk maps `leadv2-hook-session-kind.sh`,
`leadv2-single-lead-beat-loop.sh`, `leadv2-lane-pulse-watch.sh` and `leadv2-dispatch-code.sh`
to the new suite, so `--scope changed` will pick it up.

---

## Lens 3 — product invariant / contract

The brief's "Do NOT" list is respected: the loops' emissions and cadence are unchanged, the
lane-watcher stall rules are untouched, and nothing is killed from a hook (the hook only
`exit 0`s and stamps `.beat-owner-transcript`).

`STATE_DIR` is defined at `leadv2-single-lead-beat.sh:110–111`, before the owner-transcript
stamp at line 202 and the journal call at line 208 — that hunk is ordering-safe.

### M4. Write set exceeded

Five files outside the brief's LANE_WRITES were modified:
`plugins/leadv2/scripts/claude-subsession.sh`, `freepool-coder.sh`, `glm-coder.sh`,
`kimi-coder.sh`, and `plugins/leadv2/scripts/leadv2-dispatch-code.sh`. The launcher exports
are one line each and defensible on necessity grounds; `leadv2-dispatch-code.sh` is not — it
is the repo's highest-churn file (77 commits/90 d) and it received a new helper plus two
rewritten arming functions (~60 lines) without the founder/lead scope decision that a
LANE_WRITES expansion requires in this repo. Note that the brief's own LANE_WRITES lists two
paths that do not exist in the tree (`plugins/leadv2/hooks/leadv2-lane-watch-arm.sh`,
`plugins/leadv2/scripts/leadv2-lane-watch-v2.sh`), so the approved set was partly phantom —
that is a brief defect, not a licence to substitute a different hotspot (L3).

---

## Lens 4 — census (all instances of each defect shape)

**Shape A — unguarded belt call on a conditionally-sourced lib.** All four call sites
enumerated in H1 above; exactly one (`leadv2-single-lead-beat-loop.sh:170`) is defective.

**Shape B — undefined-function call when the lib is absent.** Three sites:
`leadv2-single-lead-beat.sh:208`, `leadv2-dispatch-code.sh:4661`, `leadv2-dispatch-code.sh:4682`
(M1). The predicate call sites are clean by contrast: `leadv2-single-lead-beat.sh:69` and
`leadv2-dispatch-code.sh:4648` both use `2>/dev/null || printf 'unknown'`, and
`leadv2-single-lead-beat-loop.sh:57`, `leadv2-lane-pulse-watch.sh:66`,
`leadv2-backlog-pump.sh:101` all sit inside `if [[ -f "$lib" ]]` blocks.

**Shape C — headless `claude` spawn without a worker marker (H4).** The diff gates four
launchers (`glm-coder.sh`, `freepool-coder.sh`, `kimi-coder.sh` via `LEADV2_WORKER_ARM=1`;
`claude-subsession.sh` via `LEADV2_SUBSESSION_ROLE`). Files under `plugins/leadv2/scripts`
that invoke a claude binary directly: `leadv2-task-judge.sh`, `leadv2-session-runner.sh`,
`leadv2-fanout.sh`, `leadv2-broad-status.sh`, `leadv2-provider-canary.sh`,
`leadv2-lane-shape.sh`, plus the four gated launchers and `leadv2-dispatch-code.sh`.
Verified ungated by reading the spawn line:

* `leadv2-task-judge.sh:51` `CLAUDE_BIN="${LEADV2_JUDGE_CLAUDE_BIN:-claude}"` →
  `:214` `"${CLAUDE_BIN}" -p "${prompt}" --model … --permission-mode bypassPermissions` — bare.
* `leadv2-session-runner.sh:144` `CLAUDE_BIN="${LEADV2_FANOUT_CLAUDE_BIN:-claude}"` →
  `:439` `"$CLAUDE_BIN" "${claude_args[@]}"` — bare. This one runs lane sessions inside
  worktrees, i.e. exactly the process shape whose orphans were measured.

Verified clean: `leadv2-review-run.sh` and `leadv2-plan-run.sh` route through
`claude-subsession.sh`. `leadv2-fanout.sh`, `leadv2-broad-status.sh`,
`leadv2-provider-canary.sh` and `leadv2-lane-shape.sh` were **not** individually verified in
this pass — UNVERIFIED: they appear in the grep for a claude binary but their spawn lines were
not read; they must be checked before the census is called complete.

Because rule 4 answers `lead` rather than `unknown` for these sessions (H2), an ungated
spawner is not merely uncovered — it is affirmatively classified as a lead.

---

## Lens 5 — claims without evidence

### H5. The brief's evidence contract is unfulfilled

The brief requires `report.md` carrying: the suite green, **both** mutation controls run with
their red output pasted, and a real freepool run after which
`pgrep -f single-lead-beat-loop` shows no loop from its worktree path. Directory listing of
`docs/handoff/BEAT-LOOP-ORPHANS-01/` at review time:

```
brief.md  build-attempt-1.diff  cost-estimate.yaml
review-hackdetect.err  review-hackdetect.md  review-mission-hackdetect.md
review-mission-opus.md  review-opus.err  review-opus.md
review-pool-resolver.err  review-run.log  task-class.yaml
```

No `report.md`. There is no artifact showing the suite was ever executed, no pasted control
output, and no `pgrep` proof that the fix actually stops orphans in a live freepool run — the
one measurement that would falsify H2 if H2 were wrong. Per the claims-without-evidence rule
this is blocking: "the controls are red and the suite is green" is the claim that drives the
merge decision, and it is carried by nothing.

Note the controls are also *structurally* self-reporting rather than red: NC1/NC2 mutate a
copy and then `ok "… control red as required"` when the mutation is caught. That is a
defensible design (self-contained mutation testing beats a pasted transcript), but it means
the suite exits 0 in both the "mutation caught" and "everything is fine" worlds — so the
pasted-red evidence the brief asks for is the only way to see the controls actually
discriminate. It is absent.

### Evidence-bearing claims that check out

The lib's header comment explicitly rules out `CLAUDE_CODE_ENTRYPOINT` as a classifier
because the interactive lead was observed running with `CLAUDE_CODE_ENTRYPOINT=sdk-cli`. That
is a probe-grounded negative claim and it is correct — a good example of the standard the rest
of the diff should meet.

---

## Findings table

| # | Sev | File:line | Dim | Summary |
|---|---|---|---|---|
| H1 | High | leadv2-single-lead-beat-loop.sh:170 | correctness | unguarded belt call, fail-closed among fail-open siblings |
| H2 | High | leadv2-hook-session-kind.sh (rule 4) | correctness | transcript rule never matches real workers; falls through to `lead`, not `unknown` |
| H3 | High | test-beat-loop-orphans.sh (E7) | correctness | test asserts the misclassification as expected behaviour |
| H4 | High | leadv2-task-judge.sh:214, leadv2-session-runner.sh:439 | design | ungated headless spawners outside the four gated launchers |
| H5 | High | docs/handoff/BEAT-LOOP-ORPHANS-01/ | correctness | report.md absent; suite/controls/pgrep evidence missing |
| M1 | Medium | leadv2-single-lead-beat.sh:208; leadv2-dispatch-code.sh:4661,4682 | correctness | `leadv2_loop_arm_journal` called when lib absent |
| M2 | Medium | leadv2-hook-session-kind.sh | correctness | owner-pid ancestor match accepts `node` — over-broad |
| M3 | Medium | test-beat-loop-orphans.sh (A1–A3) | correctness | negative gate assertions have zero settle window |
| M4 | Medium | leadv2-dispatch-code.sh + 4 launchers | design | five files outside LANE_WRITES, incl. the 77-commit/90d hotspot |
| L1 | Low | leadv2-hook-session-kind.sh | correctness | `stat -f %m` BSD-only (python3 fallback present) |
| L2 | Low | test-beat-loop-orphans.sh | perf | ~30 s of real sleeps in a 60 s-budget gate context |
| L3 | Low | brief.md LANE_WRITES | design | names two files that do not exist in the tree |

Totals: critical=0, high=5 (H1–H5), medium=4 (M1–M4), low=3 (L1–L3).

## What would make this pass

1. Guard line 170 like its three siblings.
2. Rewrite rule 4: match the worker shape that actually exists
   (`~/.claude/projects/*worktrees*`, or better, classify from the resolved cwd/worktree
   rather than the transcript string), and make the fallback arm `unknown`, never `lead`.
3. Flip E7 to assert the corrected behaviour; add settle-window assertions to A1–A3 and a
   mutation control for the transcript-shape cases.
4. Gate `leadv2-task-judge.sh` and `leadv2-session-runner.sh` (and finish verifying the four
   unchecked spawners).
5. Produce `report.md` with the suite run, both controls' output, and the live freepool
   `pgrep` proof.

DELIVERABLE_COMPLETE
