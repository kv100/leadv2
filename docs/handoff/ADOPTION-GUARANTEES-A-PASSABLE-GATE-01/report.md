# ADOPTION-GUARANTEES-A-PASSABLE-GATE-01 — report

Lane: worktree `ADOPTION-GUARANTEES-A-PASSABLE-GATE-01` (leadv2), 2026-08-31.

## What was broken

Adoption (`leadv2-repo-install.sh`) guaranteed symlinks, state, and env — but said
nothing about the phase gate's artifact paths. A lane worktree contains only what is
committed, so a repo whose `.gitignore` blankets `docs/handoff/*/*` (or
`docs/handoff/dispatch-*/*`) makes an honest gate passage physically impossible; the
lead bypasses the gate. Found live on 2026-08-31 (`getmany-followup-bot`), fixed by
hand in leadv2 `6f6b55b` and persona-engine `833e4926e` — a hand-applied fix is not
a fix. Evidence from the new fleet audit (same day):

```
bash plugins/leadv2/scripts/leadv2-repo-install.sh --check-all
  getmany-followup-bot … phase-gate committable   IGNORED — gate artifacts git-ignored; heal required
  leadv2 …             phase-gate committable   ok
  persona-engine …     phase-gate committable   ok
  platform …           phase-gate committable   ok
  respiro-ios …        phase-gate committable   ok
```

## The guarantee

`leadv2-repo-install.sh` gained section 3b, on the real adoption call path (every
`/leadv2` invocation, step 0):

- **Oracle:** `git check-ignore` on five concrete sample paths. Never a grep of
  `.gitignore` — only git knows which of layered rules wins, so a negation that is
  present but overridden reads as BROKEN, not fixed.
- **Fix:** append (never rewrite/reorder) one marker block of negations:
  `!docs/handoff/*/context.yaml`, `!docs/handoff/*/architect-prepass.md`,
  `!docs/handoff/*/.gate1-passed`, `!docs/handoff/*/brief.md`,
  `!docs/handoff/*/fix-round-*.md`. The `*` covers both id shapes the gate sees
  (`dispatch-<sig8>` and plain task ids). Idempotent: the block is appended only
  when `git check-ignore` currently ignores at least one guarded path, so an
  already-correct repo is untouched and `--quiet` prints nothing.
- **Unfixable ⇒ loud:** after appending, the paths are re-checked with git. If still
  ignored (excluded parent directory such as a bare `docs/` rule, or a
  higher-precedence ignore source), the repo is reported `UNFIXABLE` on stdout AND
  stderr and the script exits 1 — the repo does not silently look adopted while its
  gate is unpassable. `--check` reports the same as an `IGNORED` gap (exit 1).

### The guaranteed path set (derived from the consumers, named per the mission)

Read from `leadv2-phase-record.sh` (plan/gate1 verification, lines ~466-488) and the
`leadv2-dispatch-code.sh` remedy line (~3873):

| path | who requires it |
|---|---|
| `docs/handoff/dispatch-<sig8>/context.yaml` | phase gate `plan` (full) |
| `docs/handoff/dispatch-<sig8>/architect-prepass.md` | phase gate `plan` (full) |
| `docs/handoff/dispatch-<sig8>/.gate1-passed` | phase gate `gate1` |
| `docs/handoff/<task-id>/brief.md` | phase gate `plan` (attested; dispatcher reads it as the launch brief) |
| `docs/handoff/<task-id>/fix-round-N.md` | phase gate `plan` (attested; round-N instructions) |

Also observed but NOT gated (dispatcher-written, not gate-read): `docs/handoff/<task>/cost-estimate.yaml`,
`docs/handoff/dispatch-<sig8>/developer.stream.jsonl`. Left un-guaranteed on purpose — scope is the
gate's passability; widening is a one-line change in `GATE_SAMPLES`/the negation block if wanted.

## The re-runnable audit

One command answers "is every project fine?":

```
bash plugins/leadv2/scripts/leadv2-repo-install.sh --check-all
```

It walks the adoption registry (`~/.claude/leadv2-state/*/.repo-root`), runs `--check`
per repo, prints `[ADOPTED-OK]` / `[ADOPTED-BROKEN]` per repo, and exits 1 if any repo
fails. Write nothing, touches no repo. Current live result: rc=1 — `getmany-followup-bot`
is the one repo still broken, plus stale scratch-registry entries (tmp dirs from other
lanes, honestly reported BROKEN, not hidden).

## Test suite

`plugins/leadv2/scripts/tests/test-adoption-gate-passable.sh` — fixtures only
(empty canonical/agents dirs, `$TMP` state base, scoped `GIT_CONFIG_GLOBAL`; never a
real repo, never the real `~/.claude`). All assertions are `git check-ignore` /
byte-compares / exit codes; no grep of script source, no negated commands, exit code
follows FAIL count.

- **RED first** (production unmodified): `PASS=10 FAIL=7`, suite rc=1 — the 7 failures
  are exactly the missing guarantee (both blankets, round-N briefs, idempotent block,
  unfixable loudness ×3).
- **GREEN after the fix:** `PASS=17 FAIL=0`, rc=0. Acceptance 1–7 all covered
  (blanket `*/*`; blanket `dispatch-*/*`; already-correct prints nothing and changes no
  byte (`diff -r`); double-run byte-identical `.gitignore`, marker count exactly 1;
  original 4 lines survive byte-identically and first; `docs/` parent-dir exclusion ⇒
  nonzero rc + `UNFIXABLE` + `--check` nonzero; brief/fix-round committable).
- **Mutation kill:** the append line inside the production body was replaced by `:`
  on the real call path → suite `PASS=10 FAIL=7`, **rc=1** (this suite alone went red);
  reverted → green again. Output: `/tmp/mutated.out` showed the same 7 FAIL lines as
  the RED run.

`tests/run-all.sh` gained one `EXTRA_SUITE_MAP` row:
`leadv2-repo-install.sh:plugins/leadv2/scripts/tests/test-adoption-gate-passable.sh`.
Selection proven under `--scope changed` (temporary dry-run probe, removed after):

```
[SELECTED] …/plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECTED] …/tests/test-status-surface-bash32.sh
[SELECTED] …/tests/test-status-surface-single-lead.sh
[SELECTED] …/tests/test-status-surface-fast-names.sh
[SELECTED] …/plugins/leadv2/scripts/tests/test-adoption-gate-passable.sh
```

Full `--scope changed` runner result: see the lane's final chat report (run was still
in flight when this file was committed; result appended below if completed in time).

## Notes for reviewers

- `flush()` suppression extended: an UNFIXABLE repo prints even under `--quiet`.
- `--check-all` self-recurses via `${BASH_SOURCE[0]}`; Bash 3.2 only (no `mapfile`,
  heredoc loops instead of arrays under `set -u`).
- Pre-existing, NOT touched: `tests/run-all.sh` has a stray `continue"` (line ~303)
  that parses only because the quote runs on into later lines — a latent landmine for
  the `.gitignore` synthetic-stem branch. Out of this lane's scope; flagged here.
- Known baseline reds in the changed-scope runner (foreign-failure fixture,
  LANE-PLACEMENT-01, C5-registered-arm-silent) are pre-existing per memory
  `run-all-changed-preexisting-reds`; any failures in the full run need to be
  compared against that set before blaming this lane.
