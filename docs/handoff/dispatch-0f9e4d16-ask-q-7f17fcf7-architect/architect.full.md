# architect — ask-timeout decision (dispatch-0f9e4d16, q-7f17fcf7)

## Question
Outcome files carry no arm / work_kind / complexity, so they cannot be joined to selection
telemetry. Lane asks to make a minimal producer change to
`plugins/leadv2/scripts/leadv2-lane-outcome.sh` (outside LANE_WRITES) so an outcome record is
appended keyed by dispatch task + concrete model.

## Evidence (live checkout, this worktree base)
- `plugins/leadv2/scripts/leadv2-lane-outcome.sh` exists, 7340 bytes, executable.
- `grep -n 'arm\|work_kind\|complexity\|model'` over that file → **zero hits**. The producer has
  no notion of any join key.
- Its three sinks all key on `RUN_DIR` only and carry the same five fields:
  - L186-191 `outcome_sentinel`: `outcome= bound= work= next= at=`
  - L194-195 `progress.log`: `LEADV2_LANE_OUTCOME outcome= bound= work= next=`
  - L198-201 `meta.yaml`: `outcome:`, `outcome_bound:`, `outcome_next:`
  No dispatch task id, no model, in any of them.

## Decision
Option **b**. Option (a) is not a conservative choice here, it is a null one: with no join key at
the source, a read-only ledger does not "begin empty and fill up" — it begins empty and *stays*
empty, because nothing downstream can ever attribute an outcome to an arm. The whole
ARM-CAPABILITY-FROM-OUTCOMES capability would ship inert and read green, which is exactly the
lying-green failure the verify gate exists to prevent. The missing field is the feature.

DECISION_OPTION: b
RATIONALE: outcome records carry no join key at all (grep: zero arm/model/task hits), so a read-only ledger under option (a) can never fill — the producer field IS the capability.

## Scope of the authorization (binding on the implementing lane)
The write-set expansion is for this file and this purpose only:

| Constraint | Requirement |
|---|---|
| File | `plugins/leadv2/scripts/leadv2-lane-outcome.sh` — added to LANE_WRITES, nothing else |
| Change shape | **Additive only.** Append new keys; never rename, reorder or drop `outcome`/`bound`/`work`/`next`/`at`. Existing readers parse by key and must stay green. |
| New keys | `task` (dispatch task id), `model` (the concrete model actually used, not the alias/tier), plus `work_kind` and `complexity` **only if already resolvable in scope** — do not add a new resolution path to get them |
| Missing values | Emit the key with an explicit empty/`unknown` value; never omit the key and never fail the run. Every new emission keeps the existing `|| true` fail-open posture — outcome classification must not become a new death mode. |
| Sinks | Same three sinks, same order. Do not introduce a fourth artifact in this change. |
| Ledger | The consumer stays read-only and tolerant of records lacking the new keys (historical runs). |
| stdout | L203 `echo "${OUTCOME}"` is a contract with callers — must remain the sole stdout line. |

## Risks / mitigations
1. **Parser breakage in existing readers** — mitigation: additive keys only, appended after the
   existing ones; any reader doing positional parsing must be identified before merge (grep for
   `outcome_sentinel` and `LEADV2_LANE_OUTCOME` consumers).
2. **Alias vs concrete model drift** — recording a tier alias makes the arm join meaningless.
   Record the concrete model id resolved at dispatch; if only the alias is in scope, record both.
3. **New failure surface in a death-path script** — this script runs on lane death. Any new
   lookup must be `|| true`-guarded and must not extend the critical path.
4. **Retro-fill temptation** — do not backfill historical runs by guessing arms from paths. The
   ledger starts thin and grows forward; a fabricated history poisons the capability it feeds.
5. **Write-set precedent** — this authorization does not generalize. A later lane wanting another
   out-of-set producer file must ask again.

## Out of scope
Selection-telemetry schema changes, ledger consumer design, arm-selection policy, backfill of
existing outcome artifacts, any other file in `plugins/leadv2/scripts/`.

DELIVERABLE_COMPLETE
