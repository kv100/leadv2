# CONTROL-PLANE-REVIEW-01 / F2 — arbiter review

Scope: static read of the live plugin tree only. The measured external facts below
are cited as seed facts rather than re-measured. `fdda4b32eb7c` already owns the
fact that the `cost` column is hand-authored and unmeasured; no duplicate board row
is proposed here.

## Spine 1 — `cost` has two meanings

1. **[SPINE 1] The Fable premise is false and reaches a load-bearing ranking — DEFECT.**

   Evidence: `plugins/leadv2/config/leadv2-routing.yaml:263-277` says Fable's
   `cost: 8` is below Opus because it supposedly has a separate quota ceiling and
   explicitly says that this is not a capability judgement. Seed fact **S1** proves
   the contrary live quota fact: Fable consumes `weekly_all` as well as its scoped
   bucket. The arbiter reads each matrix cell's `cost` as the base of `ecost()`
   (`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:1541-1544`) and chooses by
   that value in `_cost_key`, followed by `ok.sort(...)`
   (`.../leadv2-route-arbiter.sh:1550-1554`). Thus the false bucket premise is not
   merely stale prose: it can make Fable rank ahead of Opus while both spend the
   shared Anthropic ceiling. Concrete failure: an audit eligible for both arms
   selects Fable because 8 < 9 on a distinction S1 disproves, consuming the same
   scarce shared weekly headroom the comment claims it preserves.

   This is not a duplicate of `fdda4b32eb7c`: that row establishes that all numeric
   costs are unmeasured; this finding is the now-refuted *specific quota premise*
   encoded in one value and used by the live selector.

2. **[SPINE 1] `cheapest_capable` compares incommensurable scalars — DEFECT.**

   Evidence: the matrix calls GLM's `0.33` a credit-multiplier-derived cost (seed
   fact **S2**; the ratio rationale is in
   `plugins/leadv2/config/leadv2-routing.yaml:191-203`)
   while the Fable comment says 8 is a separate-bucket preference
   (`.../leadv2-routing.yaml:268-277`). Both become the same float in `ecost()`
   (`.../leadv2-route-arbiter.sh:1541-1544`) and the primary ordered key
   (`.../leadv2-route-arbiter.sh:1550-1553`); the output still calls the result
   `reason=cheapest_capable` (`.../leadv2-route-arbiter.sh:1823-1828`). The defect
   is therefore in the column *and* the rule, not only the comment: a numeric order
   has no stable interpretation when 0.33 is a price ratio and 8 is a policy nudge.
   Concrete failure: the caller/lead can infer 8 is roughly 24 times 0.33, although
   the code only compares two unrelated authoring conventions.

   Smallest single-meaning correction (two sentences): retain `cost` solely for one
   measured/declared price unit, and move quota preference to a separately named
   policy field evaluated only after the shared-bucket ceiling test. Until then,
   remove the disproven Fable bucket rationale rather than presenting the scalar as
   an economic comparison.

3. **[SPINE 1] The production consumer set is narrow and explicit — SOUND.**

   Evidence: the live arbiter obtains `capability_matrix` at
   `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:939`, reads `cost` only in
   `ecost()` at `:1541-1544`, and uses the result for ranking at `:1550-1554` and
   anti-stickiness equality at `:1580-1584`. The emitted word “price”/headroom
   diagnostics describe that same computed rank (`:1738-1752`); they do not invoke
   a billing API or turn `cost` into a charged amount. In the production plugin
   source reviewed, that is the live consumer path; the other hits are tests.
   Concrete consequence: correcting the matrix semantics changes arbiter ordering,
   not any separately metered charge calculation.

## Spine 2 — caller intent, parser contract, and capability

4. **[SPINE 2] `min_capability` and `max_cost` are dropped because the arbiter never reads them — DEFECT.**

   Evidence: descriptor JSON is parsed once as `d` at
   `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:458-461`. Its decision-input
   reads are: `work_kind|kind` (`:487`), `size|task_class` (`:507`), `protected`,
   `safety`, `publish`, `ui_judgment` (`:517-518`), `allowed_arms` (`:524-525`),
   `expected_hours` (`:804`), `test_only` (`:891`), `complexity`,
   `duration_class`, `complexity_source` (`:950-955`), `requested_arm` (`:1005`),
   `speakable_models` (`:1018-1019`), `requested_model` (`:1025-1030`),
   `arm_pool` and `launchable_arms` (`:1031-1034`), and task identity for history
   (`:1142`). `subtype`, `model_requested`, and `write_set_files` are only
   recorded/forecast metadata (`:1265-1267`, `:1808-1810`), not candidate filters.
   There is no read of `min_capability`, `max_cost`, or any synonymous caller
   preference in this parser. Concrete failure: `min_capability: 5` (no shown cell
   has that value; the capability-fit scale describes per-cell 1–4 at
   `.../leadv2-routing.yaml:366-389`) produces the ordinary candidate calculation,
   rather than a named no-capable-cell refusal. The earlier floor-4 replay has no
   evidentiary value because Terra is already capability 4 (seed fact **S3**);
   parser inspection settles the question without that replay.

   `fdda4b32eb7c` does not cover this: it concerns unmeasured authored rankings,
   whereas this is an accepted JSON-shaped caller constraint with no parser branch
   or refusal semantics.

5. **[SPINE 2] There is no public “spend more within this tier” preference — MISSING-KNOB.**

   Evidence: the default selector chooses `(fit_bucket, ecost, utilization, arm,
   tier)` when capability fit is enabled (`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:1550-1554`), so equal-fit cells remain cost-first. The matrix gives Terra and
   Sol capability 4 but costs 4 and 7 respectively
   (`plugins/leadv2/config/leadv2-routing.yaml:258-259`), matching seed fact **S3**.
   The arbiter can understand a *hard* internal `requested_model` pin
   (`.../leadv2-route-arbiter.sh:1020-1030`), but the public dispatcher exposes
   only `--requested-arm`/`--pin-arm` and `--arm-pool`
   (`plugins/leadv2/scripts/leadv2-dispatch-code.sh:8394-8408,8440-8446`), then
   constructs an arbiter descriptor containing `requested_arm` but not
   `requested_model` (`.../leadv2-dispatch-code.sh:9510`). A pin to `codex` cannot
   choose between its Terra and Sol cells.

   Concrete failure: an operator following “use the smartest models” cannot ask
   the ordinary dispatch interface to retain capability 4 while preferring Sol over
   Terra; the only exposed hard arm pin leaves their in-arm cost ordering intact.
   This is a missing knob, not evidence that thrift is wrong: cost-first is SOUND
   as the default policy, but it is not sufficient as the only policy when an
   authorized one-off quality preference exists.

6. **[SPINE 2] Existing hard arm/pool requests fail closed rather than silently substitute — SOUND.**

   Evidence: `--requested-arm` and `--arm-pool` are validated before dispatch
   (`plugins/leadv2/scripts/leadv2-dispatch-code.sh:8549-8579`) and forwarded into
   the descriptor (`:9510`). The arbiter turns a matching `requested_model` into
   its arm only when it has a matrix cell, otherwise marks it unknown
   (`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:1025-1030`), and the
   dispatcher refuses an incapable/capped explicit request rather than silently
   taking a different arm (`plugins/leadv2/scripts/leadv2-dispatch-code.sh:9598-9608`).
   Concrete consequence: adding a genuine quality-control field should preserve
   this named-refusal contract; the existing arm-level pin is safe, merely too
   coarse for the Terra/Sol case.

7. **[SPINE 2] Capability integers are load-bearing authored inputs, not outcome-validated facts — DEFECT.**

   Evidence: the matrix declares per-cell `capability` values (including Codex
   3/4/4) at `plugins/leadv2/config/leadv2-routing.yaml:257-277` and describes the
   ordinal as the source of `fit_bucket` at `:366-375`. The arbiter converts the
   raw field to a float (or silently uses `cap_default`) at
   `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:1423-1431`, then puts the
   derived bucket before cost in the active sort at `:1550-1554`. There is no
   outcome read, calibration, or validation branch between those lines: malformed
   values are defaulted, not checked against results.

   Concrete failure: raising a cell from 3 to 4 changes which model wins complex
   work without an observed-outcome gate that could falsify the new ordinal. The
   “unmeasured” part is already covered by `fdda4b32eb7c`; the distinct defect is
   that the control path treats the number as a prerequisite for ordering while
   providing no construction-time validation mechanism.

## Spine 3 — single-arm chains and liveness

8. **[SPINE 3] A one-arm chain has an honest terminal outcome, but no same-call fallback — SOUND.**

   Evidence: the arbiter deduplicates its sorted viable cells into `chain`
   (`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:1566-1568`) and prints that
   exact list, with the winner first (`:1718-1724,1823-1845`). Thus seed fact **S3**
   (`chain=codex`) is structurally a one-element candidate list, not an omitted
   fallback token. The dispatcher adopts exactly the CSV it received
   (`plugins/leadv2/scripts/leadv2-dispatch-code.sh:2926-2940`), walks candidates,
   emits `route_fallback` only before a next candidate (`:9823-9842`), and after
   all continuation candidates fail emits `arm_advance_exhausted` and exits 4
   (`:10415-10454`). Concrete consequence: one failed Codex attempt does not
   silently fall through to an unnamed provider; it ends as a named exhausted
   dispatch. This terminal behavior is sound, but it does not make a one-arm
   availability decision resilient.

9. **[SPINE 3] No provider/launcher liveness signal can exclude Codex before it is selected — DEFECT.**

   Evidence: before pool construction the shell gathers quota JSON and only a
   Freepool gate (`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:83-115`), and
   passes the gate result as `ROUTE_ARBITER_FREEPOOL_RC/REASON`
   (`:146-153`). The Python candidate stages are only pool, launchability, trust,
   forecast, failure memory, price ratio, and quota capping
   (`.../leadv2-route-arbiter.sh:1047-1072,1221-1243`); no Codex launcher health
   probe is passed or consulted. Failure memory is task-signature-local
   (`task_sig` at `:1142`, journal/ledger lookup at `:1144-1221`) and only removes
   an arm after recorded attributed failures exceed its threshold; it is not a
   current provider liveness check.

   Concrete failure: the missing Codex library stated in the mission can make every
   Codex launch fail while a new task signature still has no attributable history,
   so Codex remains eligible and can be returned as the sole chain member. The
   liveness entry point, if one is added, is the pre-Python shell seam beside the
   existing Freepool gate (`:96-115`) plus a typed candidate exclusion before
   `capable` is formed (`:1047-1072`); it must be provider/launcher-derived, not a
   hand-kept arm exclusion list.

   `fdda4b32eb7c` does not cover this: cost measurement cannot answer whether the
   executable launcher/library exists at selection time.

## Summary (max 800 words)

1. **[SPINE 1 — DEFECT]** Fable’s `cost: 8` encodes a now-refuted separate-bucket
   premise (`leadv2-routing.yaml:263-277`; seed fact S1), and the live arbiter
   ranks it through `ecost()`/`_cost_key` (`leadv2-route-arbiter.sh:1541-1554`).
   The Fable comment must not be treated as a quota-saving justification.

2. **[SPINE 1 — DEFECT]** The same scalar compares GLM’s price ratio with Fable’s
   policy nudge (seed fact S2; `leadv2-routing.yaml:268-277`) and calls the result
   `cheapest_capable` (`leadv2-route-arbiter.sh:1823-1828`). Separate price from
   quota-policy data; this is not a meaningful cost order today.

3. **[SPINE 1 — SOUND]** The only production behavior consuming the field is
   arbiter ranking/rotation (`leadv2-route-arbiter.sh:1541-1554,1580-1584`), not a
   billing calculation.

4. **[SPINE 2 — DEFECT]** The parser reads listed routing keys from one JSON object
   (`leadv2-route-arbiter.sh:458-525,950-1034,1142`) but not
   `min_capability`/`max_cost`; either constraint is ignored. A floor 4 replay
   cannot disprove this because Terra already satisfies it (seed fact S3).

5. **[SPINE 2 — MISSING-KNOB]** Cost remains the tie-breaker between equal-fit
   Terra and Sol (`leadv2-routing.yaml:258-259`; `leadv2-route-arbiter.sh:1550-1554`).
   The dispatcher exposes an arm pin, not a model/prefer-higher-cost control
   (`leadv2-dispatch-code.sh:8394-8446,9510`), so the founder’s one-off “smartest”
   instruction cannot be expressed within the Codex arm.

6. **[SPINE 2 — SOUND]** Existing explicit arm/pool requests validate and refuse
   rather than silently substitute (`leadv2-dispatch-code.sh:8549-8579,9598-9608`).

7. **[SPINE 2 — DEFECT]** Capability 2/3/4 is a load-bearing authored ordinal
   (`leadv2-routing.yaml:366-389`) used to choose the winner
   (`leadv2-route-arbiter.sh:1423-1431,1550-1554`) without an outcome-validation
   path. This is distinct from the board’s unmeasured-cost finding.

8. **[SPINE 3 — SOUND]** A single chain is passed exactly to dispatch and exhausts
   with a named terminal, not an invented fallback
   (`leadv2-route-arbiter.sh:1566-1568,1718-1724`; `leadv2-dispatch-code.sh:2926-2940,10415-10454`).

9. **[SPINE 3 — DEFECT]** Codex has no current liveness input in candidate
   selection; only Freepool has a gate, while failure memory is historical and
   task-local (`leadv2-route-arbiter.sh:83-115,1047-1072,1142-1243`). A launcher
   outage can therefore keep producing a singleton `codex` chain on new tasks.
