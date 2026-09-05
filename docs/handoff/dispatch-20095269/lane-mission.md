# STATUS-CHURN-01 — fix-round 3

**Class:** Standard fix-round. **Lane:** worktree-STATUS-CHURN-01 (resume; merge `main` FIRST).

## Why this round exists
R2 review (opus, committed-tree diff 6626410d): `verdict=FAIL high=7`. Full text:
`docs/handoff/STATUS-CHURN-01/.review-findings-dedup.tsv`. In short:

- `leadv2-status-collector.sh:129` — `set -e` inside the section subshell aborts on a non-zero cache
  helper, so the `_sc_git_compute_raw` fallback at :133 is unreachable dead code.
- `leadv2-status-collector.sh:132` — git section JSON shape is non-deterministic: 5 keys on the cache
  path (`computed_at`, `producer`) vs 3 on bypass/fallback.
- `lib/leadv2-status-cache.sh:4` — header documents a five-consumer shared-snapshot fix the diff does not
  implement; census shows ONE production call site (status-collector git facts).
- `lib/leadv2-status-cache.sh:39` — header points at a "reference shape" that does not exist; the
  compute step emits `{local_head,branch,unpushed}`.
- `tests/test-status-churn.sh:159` — the mutation control writes an executable into the SHIPPED plugin
  lib dir under a fixed name; parallel runs race it and an abnormal exit leaves a stray file in the
  canonical tree. (Standing rule since 2026-08-22: scratch/mutants go to a temp dir, never canonical.)
- `tests/test-status-churn.sh:133` — test (c) asserts on `recompute` rows whose `age_s` is the unbounded
  PRE-recompute staleness; it passes only because the fixture sleeps 3.3s.
- one more High in the tsv — read it.

## Do
1. Row per finding in `report.md` §`## R3 findings`: REAL/REFUTED + evidence command. No command = REAL.
2. Fix the code ones (fallback reachable; ONE JSON shape on every path, add the two keys as null on
   bypass/fallback; mutant into `mktemp -d`, cleaned by trap; test (c) asserts the POST-recompute age
   with a bound, no sleep-dependence).
3. Headers must describe what the diff DOES: either wire the other consumers now (then the census in the
   report shows each call site) or rewrite the header to the one consumer that exists. No aspirational docs.
4. Also fold in (founder-status is blind to lanes): `leadv2-status-collector.sh` must list dispatched
   lanes from `active.yaml` + lane worktrees, not only codex-task rows — the beat at 00:26Z/01:40Z/02:11Z
   showed 2 dead codex rows and none of 7 live lanes. Add a suite case with a fixture active.yaml row.
5. Suite + `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd; paste verdicts.

## Constraints
- LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`, `plugins/leadv2/scripts/docs/`.
- Commit on the lane, tree clean, `main` merged.

## Done when
- 7 findings each REAL→fixed or REFUTED with a command; lanes visible in the collector output with a
  pasted sample; suite green + FALSIFIABLE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-20095269" "<question>" \
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

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.