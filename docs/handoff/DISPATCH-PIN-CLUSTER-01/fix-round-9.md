# DISPATCH-PIN-CLUSTER-01 — round 9: the new suite prints RED and exits 0

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-PIN-CLUSTER-01`

LANE_WRITES: plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh,plugins/leadv2/scripts/lib/leadv2-admission-class.sh,plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,tests/run-all.sh,docs/handoff/DISPATCH-PIN-CLUSTER-01/

HEAD is `252da1f` — round 8, which I committed after the codex worker's 5-minute cap killed it
with the work uncommitted. Main is `42d3232`; rebase onto it first.

**Round 8 did real work and it stays.** All four changed files are `bash -n` clean;
`test-dirty-lane-never-lands.sh` passes with the terminal funnel, the dirty-death pin, the
non-transitive `pass_unlanded` and the rollback switch all asserted; and
`test-lane-placement-pin.sh` went **27/0, up from 24/3** — M7-1 from round 7 is closed.

## [Critical] `test-consumer-symlink-farm.sh` passes with the fix removed

I deleted the canonical fallback at `leadv2-dispatch-product-close.sh:45` and re-ran the suite:

```
RED control: leadv2-dispatch-product-close.sh (canonical fallback unreachable, rc=0)
PASS: all four consumer-farm loaders resolve via canonical fallback
suite rc=0
```

The `RED control:` lines are printed, not asserted — they do not fail the run, so the suite cannot
distinguish a working tree from a broken one. This is the same defect the PULSE lane's round-4
suite was failed for tonight: green with the fix removed is a failed control, not a passing test.

Make each `RED control:` line an assertion that sets the exit code. Then prove it, all four pasted:
strip the canonical fallback from **each** of the four loaders in turn, show the suite RED naming
that specific loader and exiting non-zero, restore, show GREEN and a clean `git diff --stat`.

Position-independence still applies — the same lesson the CLOSE-GATE lane learned twice: an
assertion must look for its own `file:line` in the findings, not compare against the first finding
or against an exact set, so an unrelated violation elsewhere cannot flip it.

## [Critical] one loader is genuinely broken right now

On an **unmutated** tree the suite already prints:

```
RED control: lib/leadv2-admission-class.sh (canonical fallback unreachable, rc=1)
```

So `lib/leadv2-admission-class.sh` does not resolve through the canonical fallback today, and the
suite passes anyway. Fix the loader. Then confirm the same consumer-farm reproduction the round-7
reviewer used — a real 204-link farm with no `lib/` — resolves it, and show the suite RED when you
strip it again.

## [High] carried from round 8, unverified: the close gate must fail CLOSED

Round 8 claims a fail-closed close gate. Because the suite above is non-diagnostic, that claim is
not yet evidence. Demonstrate it directly, both directions pasted:

- lib absent from BOTH roots + a dirty lane ⇒ the terminal is **not** `landed`, and the named error
  it does emit;
- lib present + a clean lane ⇒ `landed` as normal.

## [Medium] `tests/run-all.sh` must be reconciled with main

Main carries HOOK-OUTPUT-CAP's state-file-bounded last-checked-SHA selection, DISPATCH-CLOSE-GATE's
widened `scripts/*.sh|scripts/lib/*.sh|hooks/*.sh` glob, the `freepool-arm.yaml` stem case and
several `EXTRA_SUITE_MAP` rows. Keep main's block, re-apply this lane's rows on top, and add a row
for `test-consumer-symlink-farm.sh` so CI selects it. Prove with `--scope changed`.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the production function body, RED, revert,
  GREEN, clean `git diff --stat`. **A suite that stays green with the fix removed is a failed
  control.** A printed `RED control:` line that does not change the exit code is not an assertion.
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  never trips on it); no scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is
  not evidence.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop — and if you are running
  short, commit what works rather than leaving it on disk; two rounds have been lost that way today.

## Done means

Four strip-and-restore controls that each fail the suite by exit code naming their own loader, a
working `lib/leadv2-admission-class.sh`, the fail-closed close gate demonstrated both ways, and a
reconciled `tests/run-all.sh` that selects the new suite.
