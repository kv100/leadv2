# SUPERVISOR-RESIDUE-FOLLOWUP-01 — low nits from two critic reports (~/Projects/leadv2)

Base: main 2bfbf8e (RESIDUE-SWEEP landed). Two reports feed this:
docs/handoff/dispatch-3bdeadcc-review/critic.full.md (low nits) and
docs/handoff/dispatch-9c027877-review/critic.final.md (N3). Read both first.

## Work
1. Delete the 3 orphan unregistered supervisor hook FILES (arms already removed from
   hooks.json by the sweep; grep-prove zero registrations before deleting each):
   plugins/leadv2/hooks/leadv2-supervisor-guard.sh,
   plugins/leadv2/hooks/leadv2-supervise-bash-guard.sh,
   plugins/leadv2/hooks/leadv2-supervisor-mode-reinject.sh (exact filenames may differ
   slightly — locate by grep; the critic named supervisor-guard.sh / supervise-bash-guard.sh /
   supervisor-mode-reinject.sh).
2. L3 completion: leadv2-plugin-sync.sh:519 and leadv2-status-collector.sh:104 still stamp the
   supervisor-retirement decision as 2026-08-20 — normalize to 2026-08-17 (founder order date).
3. L4: /leadv2 fanout doc entry is a notice, not a refuse-stub — make leadv2-fanout.sh refuse
   at entry with the same stub pattern the sweep used for supervise (echo refusal + exit 2,
   founder-order citation), and align the doc row.
4. T2-critic N3: in the builder-selfcheck suite, case_4_diff_golden builds its baseline via
   `git archive HEAD` — running in-worktree makes live==pre and the comparison arm tautological.
   Fix the baseline to archive the PRE-gate ref (parameterize the base ref, e.g. first commit
   before the gate file existed, or synthesize the pre-tree by removing the gate hunk) so the
   arm can actually fail again; keep the primary assertion untouched.

## Acceptance
grep-proofs quoted per deletion · affected suites green FOREGROUND solo (builder-selfcheck
suite for item 4; run-core-offline full FOREGROUND solo green) · bash -n + shellcheck -S
warning on touched scripts · COMMIT on lane branch (uncommitted exit = incident).

## Off_limits
leadv2-dispatch-product-close.sh; leadv2-dispatch-code.sh; claude-subsession.sh (live lanes
own them); hooks.json arms (already correct).

## Terminal artifact
Commit sha + raw grep/suite output + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-02e9baba" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.