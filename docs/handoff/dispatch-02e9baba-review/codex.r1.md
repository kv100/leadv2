# Adversarial review — dispatch-02e9baba

Scope reviewed: `git diff 2bfbf8e...HEAD` in
`.claude/worktrees/02e9baba` (HEAD `029c8eb`). The worktree also has unrelated
runtime/handoff changes; those were not treated as part of this diff.

## Findings

### FAIL — deleted supervisor guards remain in the live Bash hook dispatcher

`plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh` still documents and places
these deleted executables in its `MANIFEST`:

- `leadv2-supervise-bash-guard.sh`
- `leadv2-supervisor-guard.sh`

The dispatcher currently skips each entry because it uses
`[[ -x "$SCRIPT_DIR/$SCRIPT" ]] || continue`; this silently removes the former
supervisor enforcement rather than retiring the entries cleanly. This is a live
hook path, not archival documentation.

The root suite `tests/test-bash-pre-dispatch.sh` also still lists both guards as
required originals. Its observed output begins with `FAIL guard is not
executable` for each file and later reports a trace mismatch because the
dispatcher runs fewer guards. Delete the manifest/comment entries and update
the expected guard/trace fixture together, or retain compatible replacements
if their behavior was meant to survive retirement.

There is one additional historical journal reference to
`leadv2-supervisor-mode-reinject.sh` in
`docs/leadv2/tasks/dispatch-2b6c3f01/journal.md`. It is not executable wiring,
but it means a literal repository-wide retirement-reference sweep is incomplete.

### FAIL — date normalization is incomplete

Although the two edited comments now say `2026-08-17`, current HEAD still calls
the same `SUPERVISOR-DELETE-01` retirement `2026-08-19` in at least:

- `plugins/leadv2/docs/single-lead-pulse.md`
- `plugins/leadv2/hooks/leadv2-single-lead-beat.sh`
- `plugins/leadv2/scripts/leadv2-lanes-resume.sh`
- `plugins/leadv2/scripts/leadv2-lanes-snapshot.sh`
- `plugins/leadv2/scripts/tests/test-lanes-snapshot.sh`

If the intended canonical retirement date is 2026-08-17, these contradict the
newly normalized references and must be reconciled (or explicitly classified
as a different, later rename/retarget event).

### Nit — C4 is now non-tautological, but it is a brittle historical golden

The new `PRE_GATE_REF=1806b4f...` is the parent of `53d4465` and the archive
uses that fixed ref, so it no longer compares an archive of `HEAD` with the
live tree. A behavioral difference introduced after that ref can therefore
make the comparison red; this addresses the stated tautology.

However, C4 asserts byte identity of the complete generated
`review-gate.md` against an old implementation. It will red on intentional
format/output changes unrelated to the diff-lane contract, and skips in a
shallow/re-written checkout. Consider asserting the stable required fields
instead if the goal is a durable regression test. This is not the basis for
the verdict.

### Broad-status coverage

The T8b edit correctly stops requiring the deleted reinject hook while still
checking two live contract surfaces: `commands/leadv2.md` and
`docs/supervisor-role.md`. The assertion is still behavioral enough for the
specific relay-contract claim, but it did not compensate for the broken Bash
dispatcher regression described above.

## Verification performed

- Inspected the requested merge-base diff and current HEAD references.
- Searched tracked scripts, hook configuration, documentation, and tests for
  all three deleted hook names and the deleted reinject test.
- Ran `tests/test-bash-pre-dispatch.sh`; it fails due to the two missing guards
  still required by the dispatcher test.
- Checked the pinned C4 object and its relationship to the selfcheck-gate
  merge commit.

VERDICT: FAIL
