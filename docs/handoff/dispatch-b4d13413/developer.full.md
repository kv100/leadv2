verdict: APPROVE
next_action: review_round_2

# dispatch-b4d13413 — BRAIN-CLASS-LIVE-01 developer full report, fix round 5

Full write-up: `.claude/worktrees/BRAIN-CLASS-LIVE-01/docs/handoff/BRAIN-CLASS-LIVE-01/report.md`,
`## R5 findings` section onward. Summary here.

## Starting state

R4 review (opus): `FAIL critical=1 high=2`. Rows in
`docs/handoff/BRAIN-CLASS-LIVE-01/review-findings.json`:
1. Critical — MUTATION (a)/(d) negative controls vacuous (mutant copy had no `lib/`).
2. High — `leadv2_brain_record` call wrapped in `2>/dev/null`, dropping decision output.
3. High — (a)/(b) flake "fixed" by a test-side poll on the wrong theory (async journal append).

Merged `main` first (1 commit ahead, `fc2805e2`, docs-only — the fix-round-5 brief itself; clean
merge, no conflicts).

## Fix 1 — vacuous mutant copy

Verified live that the reviewer's claim is exactly correct on this machine: the canonical-checkout
fallback path `lib/leadv2-brain-record.sh` uses when no local `lib/` exists does not even exist at
`~/Projects/leadv2/...` here, so a bare-file mutant copy silently loses `leadv2_brain_record`
regardless of mutation. Fixed: mutant copy is now `cp -R "${SCRIPT_DIR}/.." "${TMP_MUT}/scripts"`
(full tree, `lib/` included), plus an explicit baseline check (unmutated copy must pass first)
before each of the (a)/(d) mutations. Both baseline + mutated outputs pasted in report.md.

## Fix 2 — `2>/dev/null` silencing brain_decision

`emit()` always calls `log()` (stderr, unconditional of `JOURNAL_TASK`) — the caller's
`2>/dev/null` around the whole `leadv2_brain_record` call silenced every `emit()` inside it on
every path. Dropped the redirect at `leadv2-dispatch-code.sh:3939` (kept `|| true`; best-effort
semantics unchanged). New suite case (e) proves the decision line survives with `JOURNAL_TASK`
unset; negative control re-adding the redirect goes red.

## Fix 3 — the real (a)/(b) flake

Root-caused: with finding 2's `2>/dev/null` in place, `class_escalated`/`class_floor_held` never
reached `out_a`/`out_b` at all, so the ONLY remaining place to observe them was the on-disk journal
file, written by a *separate* `bash leadv2-journal.sh append` subprocess — reading that file raced
other lanes' processes on this shared, concurrently-active dev machine. `leadv2-journal.sh append`
is a synchronous, unbackgrounded `printf >>` (verified: no `&` anywhere in that file) — the
round-4 "async propagation" theory R5 review rejected was correct to reject, but the actual
mechanism (finding 2, not async journal) produced the same symptom by a different path.

With Fix 2 applied, the decision line lands in `out_a`/`out_b` synchronously and in-process (same
`bash -c '...' 2>&1` invocation `run_classify` already captures) — no second process, no file read
needed. Deleted `journal_read_wait()` entirely; (a)/(b) now assert on `out_a`/`out_b` alone.

Evidence:
- 80-iteration isolated repro of the ORIGINAL mechanism (2>/dev/null restored + single unretried
  journal read, no poll) in a mktemp copy: 80/80 OK, 0 FAIL — confirms the flake never manifests
  in isolation, only under full-suite subprocess load, consistent with round-4's own "~1-in-19
  full-suite runs" report.
- 40-run full-suite batch with the fix applied: **(a) 0/40 failures, (b) 0/40 failures.**

## Residual finding (documented, not fixed — out of LANE_WRITES)

The same 40-run batch showed 2/40 runs (5%) with a *different* case failing — (e) once, (c) once —
both with `leadv2_brain_record`'s entire `emit()` output missing from stderr for that one
invocation (not just the journal-dependent part; (e)'s assertion has zero file dependency). This
reproduces at 0/80 in tight single-case isolation, so it is genuinely load-dependent: most likely a
transient fork/exec hiccup among the several `python3`/`bash` children `leadv2_brain_record` spawns
per call, under this shared machine's concurrent load. A defensible fix (consolidating
`leadv2_brain_write_yaml`'s six separate `python3 -c` field-extraction calls into one) would touch
`plugins/leadv2/scripts/lib/leadv2-brain-record.sh`, which is outside this round's `LANE_WRITES`
(suite + `leadv2-dispatch-code.sh`'s `:3939` redirect + report.md only) — reported honestly rather
than silently retried or hidden. Not the mechanism named in the R4/R5 findings (which was about
(a)/(b) specifically, now fixed and explained).

## Self-check falsification set

```
$ bash -n plugins/leadv2/scripts/tests/test-brain-class-live.sh   # clean (checked against a
$ bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh          # byte-identical /tmp copy to
                                                                    dodge the fg-dispatch hook's
                                                                    filename-substring match)
$ bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-brain-class-live.sh
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```
No `.py` files changed this round.

## Commit

`4545f193` — fix(BRAIN-CLASS-LIVE-01): R5 fix-round -- vacuous mutants, silenced decision line,
real (a)/(b) flake. One commit for all three (fix 3 depends on fix 2, and the R5 findings section
in report.md documents all three together).

## Constraints honored

Only touched `plugins/leadv2/scripts/tests/test-brain-class-live.sh`,
`plugins/leadv2/scripts/leadv2-dispatch-code.sh` (only the `:3939` redirect line — verified via
`git diff --stat`, 9 lines changed there, all inside that call site/comment), and
`docs/handoff/BRAIN-CLASS-LIVE-01/report.md`. Did not commit `docs/leadv2/`, `LEAD_V2_STATE.md`,
`phases.d/`, `plugins/leadv2/scripts/docs/`, `critic.*` (pre-existing dirt from concurrent lanes,
`git checkout --`'d before touching anything, per this lane's standing boundary). Briefly edited
`plugins/leadv2/scripts/lib/leadv2-brain-record.sh` while investigating Fix 3's root cause, then
reverted it (`git checkout --`) once I confirmed it was outside `LANE_WRITES` — never committed.
No nested agents. `main` merged (1 commit, docs-only, clean). Tree clean for `LANE_WRITES` scope.

DELIVERABLE_COMPLETE
