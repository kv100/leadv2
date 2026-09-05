# Mission: PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01 + PHASE-PLAN-PROOF-IS-FILENAME-BASED-01

One lane, one file, two defects, two commits — parallel lanes on this file would conflict.
Constraints binding on this lane: `docs/handoff/WAVE4/shared-constraints.md` (read it first —
negative-control discipline, macOS+linux dual report, no assertion-weakening, no main commits).

## Goal
Fix `plugins/leadv2/scripts/leadv2-phase-record.sh` so (1) `record` refuses instead of silently
writing phase records into a foreign repo, and (2) the `plan` artifact proof is content-based,
not a two-name filename allowlist.

## Root cause 1 — `record` writes into whichever repo the resolved root names, unchecked
Resolution (`leadv2-phase-record.sh:152-164`, **unchanged, do not reorder**): `LEADV2_PROJECT_ROOT`
wins if set → else `PROJECT_ROOT` → else `git -C "$(pwd)" rev-parse --show-toplevel` → else `pwd`.
A conflict between the two env vars already refuses loudly on write (:155-159, exit 4) — but that
guard only fires when BOTH are set and differ. When only `LEADV2_PROJECT_ROOT` is set (this bug),
there is nothing to conflict with, so resolution succeeds silently at a root nobody validated.
Confirmed: `/Users/kostiantyn.vlasenko/Projects/persona-engine/.claude/settings.json:73` exports `"LEADV2_PROJECT_ROOT": "/Users/.../persona-engine"` in the top-level `env` block — every Bash subprocess in a persona-engine Claude Code session inherits it, including one that `cd`'d into `~/Projects/leadv2` first. No `LEADV2_*`/`LEAD_V2_*` drift — the var name matches exactly.

**Do not reorder resolution to prefer cwd.** Worktree-lane dispatches legitimately run with cwd inside a throwaway worktree while `LEADV2_PROJECT_ROOT`/`PROJECT_ROOT` correctly points at the main `leadv2` checkout that actually holds `docs/handoff/` — every real caller keeps cwd and both root vars in lockstep on purpose (`tests/test-freepool-capability-floor.sh:271-275`, `tests/test-model-select-telemetry.sh:167-171`, `tests/test-phase-gate-inversion.sh` throughout: `( cd "$REPO" && PROJECT_ROOT="$REPO" LEADV2_PROJECT_ROOT="$REPO" bash ... )`). Preferring cwd would break that pattern, not fix this one.

**What's actually missing: a permitted-root existence gate on `record`, not a different order.** `cmd_record` computes `phases_d`/`phase_file` (:742-744) then unconditionally `mkdir -p "$phases_d"` (:746) — this is the write hazard: it manufactures the target tree in whatever root resolved, with zero check that this root was ever the one this `sig8` started in. Fix: after :744 and before :746, require `[[ -d "${PHASES_DIR_BASE}/dispatch-${sig8}" ]]` (reuse `_phases_d()`, :189) — i.e. **the task's OWN `docs/handoff/dispatch-<sig8>/` must already exist under the resolved root.** Refuse (exit 4, `_log_err`, same style as :157-158) if not. This never blocks a legitimate write: `dispatch-code.sh` always creates `dispatch-<sig8>/` (context.yaml etc.) at task setup, strictly before it ever calls `record classify` — the first phase any lane records (bootstrap comment, :63-67). `record` is never the directory-creating step on the real path. Scope: `cmd_record` (write) only. `cmd_assert`/`cmd_show`/`is-bootstrap` keep today's warn-and-proceed asymmetry (:149-151) — reading a wrong/empty root already degrades harmlessly to "no records"; out of scope here.

**Real call sites** (`grep -rn "leadv2-phase-record.sh" ~/Projects/leadv2` minus `.git`):

| Caller | Lines | Passes root inline? |
|---|---|---|
| `leadv2-dispatch-code.sh` (off-limits to edit) | 7125,7173,7861,7954,8424 `record`; 4104 `assert` | No — ambient env |
| `leadv2-phase8-close.sh` | 285-286 `record close` | No — ambient env |
| `leadv2-dispatch-product-close.sh` | 2733-2734, 2887-2888, 2963-2964, 3482-3483 `record` | No — ambient env |
| `leadv2-gate1-prompt.sh` | 166 (sibling path resolve) | No — ambient env |
| Tests (`test-phase-gate-inversion.sh`, `test-freepool-capability-floor.sh:271-275`, `test-model-select-telemetry.sh:167-171`) | throughout | Yes — explicit subshell |

Every production caller trusts ambient env for the whole process — none scope `PROJECT_ROOT` to
the call. That's why the fix belongs at the single choke point inside `leadv2-phase-record.sh`,
not at N call sites (several off-limits anyway).

## Root cause 2 — plan-artifact proof is a filename allowlist, not content
`_verify_artifact()`'s `plan` branch (:486-516) accepts a lead-authored artifact only if it is
non-empty (`-s`, i.e. ≥1 byte — a placeholder passes today) **and** its path matches
`^(.*/)?docs/handoff/[^/]+/(brief\.md|fix-round-[0-9]+\.md)$` (:510). `continue-round-2.md` fails
the alternation and the `plan` phase is reported missing forever — the 2-round overnight stall.
The comment at :501-503 says the filename allowlist exists "so an arbitrary `--artifact` string
cannot forge plan proof" — but the actual forgery guard is the **location** scope (`[^/]+` = one
path segment = must live directly in the task's own `dispatch-<sig8>/` handoff dir, not
anywhere-in-repo); the filename choice adds no extra forgery protection, it only over-fits two
literal names.

**Prescribed rule (ONE checkable rule):** replace the name alternation with a generic leaf-name
match — `^(.*/)?docs/handoff/[^/]+/[^/]+\.md$` (still exactly one task-id segment, any `.md` name)
— **and** add a substance floor the current bare `-s` check never had: the resolved file's content
must have **≥120 non-whitespace characters AND ≥2 non-blank lines**. Two-line justification: (1)
location scope is what already stops forgery-by-arbitrary-file, so dropping the two-name allowlist
loses no protection; (2) a ≥120-char/≥2-line floor is strictly new and strictly tighter than
today's bare non-empty check, so placeholders that pass today (`TBD`, `WIP`, `N/A`, one line) will
newly fail — this is the required placeholder guard. Keep `.md`-only and the one-segment location
constraint unchanged. Also update the now-stale rationale comments at :28-30 and :498-503 to say
"location + content-substance", not "the two names" — same function, same commit, not a separate
file. **Not in scope:** the `[^/]+` task-id segment is never checked against the CALLING `sig8`
(pre-existing gap — a brief from a different task's dir would also pass today); do not fix that
here, flag it only.

## Files allowlist
- WRITE: `plugins/leadv2/scripts/leadv2-phase-record.sh` (both commits)
- WRITE: `plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh` (commit 1 negative control)
- WRITE: `plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh` (commit 2 controls)
- READ-ONLY (context, do not edit): `leadv2-dispatch-code.sh`, `leadv2-phase8-close.sh`,
  `leadv2-dispatch-product-close.sh`, `leadv2-gate1-prompt.sh`
- OFF-LIMITS (WAVE4): `leadv2-dispatch-code.sh`, `leadv2-claude-profile-select.sh`,
  `tests/known-red-suites.txt`, anything under `~/MythicalGames`, `m3` repo's `.claude/settings.json`,
  direct commits to `main`

## Steps
**Commit 1** (`PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01`): add the existence gate in `cmd_record`
between :744 and :746 as specified above; exit 4 on refusal, message names the resolved
`PROJECT_ROOT`, the `sig8`, and the missing path, and tells the operator to check
`LEADV2_PROJECT_ROOT`/`PROJECT_ROOT`/cwd (mirror :157-158's wording). No change to `cmd_assert`,
`cmd_show`, `is-bootstrap`, or the :152-164 resolution order itself.

**Commit 2** (`PHASE-PLAN-PROOF-IS-FILENAME-BASED-01`): swap the regex at :510 for the generic
leaf-name form; add the ≥120-char/≥2-line substance check on the same resolved file before
returning `_VA_STRENGTH="attested"`; update comments at :28-30 and :498-503.

## Acceptance commands
**Defect 1** — proves old behavior is gone, new refusal holds, nothing lands in the foreign repo:
```bash
cd ~/Projects/leadv2 && rm -rf "$HOME/Projects/persona-engine/docs/handoff/dispatch-deadbeef"
LEADV2_PROJECT_ROOT="$HOME/Projects/persona-engine" \
  bash plugins/leadv2/scripts/leadv2-phase-record.sh record deadbeef gate1 --reason "repro"; echo "rc=$?"
# BEFORE fix: rc=0, and this exists (the bug):
test -d "$HOME/Projects/persona-engine/docs/handoff/dispatch-deadbeef" && echo "BUG: wrote foreign repo"
# AFTER fix: rc=4 (non-zero), stderr names the missing dispatch dir, and this must NOT exist:
test ! -d "$HOME/Projects/persona-engine/docs/handoff/dispatch-deadbeef" && echo "OK: nothing created"
```

**Defect 2** — a differently-named, substantial file now satisfies `plan`; a placeholder still fails:
```bash
T=$(mktemp -d) && mkdir -p "$T/docs/handoff/TASK-CR-01"
printf 'Continuing round 2.\n\nSwitched the retry backoff from linear to exponential because the\nprior fix-round regressed under burst load. Verified locally.\n' \
  > "$T/docs/handoff/TASK-CR-01/continue-round-2.md"
printf 'TBD\n' > "$T/docs/handoff/TASK-CR-01/continue-round-3.md"
( cd "$T" && PROJECT_ROOT="$T" LEADV2_PROJECT_ROOT="$T" \
  bash ~/Projects/leadv2/plugins/leadv2/scripts/leadv2-phase-record.sh record c0ffee01 plan \
  --status done --artifact docs/handoff/TASK-CR-01/continue-round-2.md --owner test )
grep -q '^proof: attested' "$T/docs/handoff/dispatch-c0ffee01/phases.d/plan.yaml" && echo "OK: substantial file accepted"
( cd "$T" && PROJECT_ROOT="$T" LEADV2_PROJECT_ROOT="$T" \
  bash ~/Projects/leadv2/plugins/leadv2/scripts/leadv2-phase-record.sh record c0ffee02 plan \
  --status done --artifact docs/handoff/TASK-CR-01/continue-round-3.md --owner test )
grep -q '^proof: unverified' "$T/docs/handoff/dispatch-c0ffee02/phases.d/plan.yaml" && echo "OK: placeholder still rejected"
```

## Negative controls (run for real, report both exit codes macOS + linux, per shared-constraints.md)

**Control 1 (defect 1):** in `tests/test-phase-gate-inversion.sh`, add case 5c next to existing
case 5 (`:207-249`) — set only `LEADV2_PROJECT_ROOT` to a scratch repo that has never had this
`sig8` dispatched (no `dispatch-<sig8>/`), call `record`, assert rc≠0 and the directory was NOT
created. Mutation: inside `cmd_record`'s body, delete the new existence-gate `if` block (leave
`mkdir -p` unconditional again) — case 5c must go RED (rc becomes 0, directory gets created);
revert, case 5c GREEN. `run-all.sh:165` already maps `leadv2-phase-record` → this suite; no new
`EXTRA_SUITE_MAP` row needed.

**Control 2 (defect 2):** in `tests/test-phase-precondition-bootstrap.sh`, add T3c (positive:
`continue-round-2.md`-shaped file with substantial content → `proof: attested`, `plan` drops out
of `missing=`) and T3d (negative: same non-`brief`/`fix-round` name, placeholder content → stays
`unverified`, `plan` stays in `missing=`) next to existing T3/T3b (`:96-126`). Mutation: inside
`_verify_artifact`'s `plan` branch, delete the new ≥120-char/≥2-line check (keep only `-s`) — T3d
must go RED (placeholder now wrongly accepted); revert, T3c+T3d GREEN. T3b (existing, filename
`notes.md` with ~35 chars of content) must stay green untouched — it now fails on the *length*
floor instead of the *name* filter, same verdict, so it needs no edit; verify this, do not touch
its assertion. `run-all.sh:159-161` already maps this suite under `leadv2-phase-record` (and
`leadv2-dispatch-code`) — no new mapping row needed.

## Out of scope
- Reordering the :152-164 resolution precedence (would break worktree-lane dispatch).
- Any edit to `cmd_assert`, `cmd_show`, `is-bootstrap`, or the read-side warn-and-proceed path.
- Editing `leadv2-dispatch-code.sh` or any of its call sites — off-limits this wave.
- Making the `plan` regex also check the task-id segment against the calling `sig8` — real
  pre-existing gap, not this defect; leave a one-line TODO comment at :510, nothing more.
- `gate1`/`review` forgery surfaces documented at :82-102 — unrelated, unchanged.

---

**LEAD ADDENDUM — read `lead-addendum-reproduced.md` in this directory: both defects were reproduced live on 2026-09-03, and defect 2 has a ready-made two-line acceptance.**
