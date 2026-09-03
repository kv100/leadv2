# DISPATCH-CLOSE-GATE-01 — round 6: the report claims a restoration that did not happen

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-CLOSE-GATE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh,plugins/leadv2/scripts/lib/leadv2-red-proof.sh,plugins/leadv2/scripts/tests/test-mission-writeset.sh,plugins/leadv2/scripts/tests/test-red-proof-gate.sh,plugins/leadv2/scripts/tests/test-lib-source-guarded.sh,plugins/leadv2/scripts/tests/fixtures/,tests/run-all.sh,docs/handoff/DISPATCH-CLOSE-GATE-01/

Full report: `docs/handoff/DISPATCH-CLOSE-GATE-01/review-r5.md`. HEAD is `0076269`.

**One real win, verified live by the reviewer against production — keep it exactly as it is.** The
C3 render-evidence control genuinely catches a real mutation across all five
`_pc_evidence_with_unproven` call sites. That item took four rounds and it is finally done.

## [Critical] `report.md` claims the removed controls were restored; they were not

`test-mission-writeset.sh` is **byte-identical to `bfec45a`** — a zero diff. The report says its
controls were restored. That is not an oversight in wording; it is a claim about work that does not
exist, and it is the one thing a reviewer and a lead are most likely to take on trust.

Restore the three controls removed from `test-mission-writeset.sh` and the four removed from
`test-red-proof-gate.sh`, or name the replacement for each in the commit message. Then show each
one going RED under its own mutation. If a control is deliberately not coming back, say which and
why — but never write that it was restored when the file did not change.

## [Critical] the new guard suite cannot see two of the three sites this round fixed

`test-lib-source-guarded.sh`'s `is_lib` check matches only literal `/lib/` paths. But two of the
three sources round 5 guarded are NOT under `lib/` —
`leadv2-lane-child-suffixes.sh` and `leadv2-portable-lock.sh` sit beside the script. The reviewer
proved it live: stripping one of those guards produced no RED.

So the guard against this recurring defect does not cover the very sites that produced it. This is
the same shape as a sibling lane's suite today, which recognised a naming convention instead of the
rule and let a probe file slip past invisibly.

Make the check structural: any `source` of another script from within `plugins/leadv2/scripts/` or
`plugins/leadv2/hooks/` must resolve with a canonical fallback and be `[[ -f … ]]`-guarded,
wherever that file sits. Prove it by stripping each of the three guards in turn and showing the
suite RED naming that specific file.

## [Critical] `test-red-proof-gate.sh:6-7` documents a control that does not exist

Its header describes a mutation control "at the bottom" of the file. There is none. Either add the
control it describes, or delete the description. A comment promising coverage that is absent is the
same disease as a green test that asserts nothing — and this lane exists to kill that disease.

## [High] the round-4 timeout artifacts were never corrected

`round4-red/changed-scope-green.log` is still a 124-second timeout filed under a green header.
Regenerate or retitle every affected artifact so its recorded outcome matches the run.

## [Medium] the dispatcher emits a shell error on every invocation — including from consumer repos

Running the lane's `leadv2-dispatch-code.sh` prints to stderr, twice:

```
plugins/leadv2/scripts/leadv2-dispatch-code.sh: line 5753: when:: command not found
```

That is an unescaped backtick inside the usage heredoc at `:5753` — the text
`` `when:` gate (e.g. freepool's `when: [standard, bulk]`) `` — so the shell runs it as a command
substitution. It is pre-existing and harmless to control flow, but it is noise on every run and it
was not disclosed. Escape the backticks (or quote the heredoc delimiter) and add a control asserting
the usage output produces no stderr.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file, RED,
  revert, GREEN. A zero-match anchor is a hard failure, not a skip.
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  never trips on it); no scratch-copy mutation; no `git show HEAD:` pre-image.
- **Never describe work in `report.md` that the diff does not contain.** Check your own claims
  against `git diff` before writing them.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- Run every suite in the write set to completion before committing and paste the runs.
- Commit artifacts with `git add -f <file>`; do not edit `.gitignore`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop.

## Done means

Every removed control restored or its replacement named and shown RED; the guard suite catching a
stripped guard at all three sites by name; `test-red-proof-gate.sh`'s header matching its contents;
the timeout artifacts corrected; the `when::` stderr gone with a control; and a `report.md` whose
every claim is checkable against the diff.
